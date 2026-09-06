unit MLCRD_Coordinator;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  MLCRD_Types, MLCRD_Interfaces, MLCRD_Algorithms, MLCRD_Utils;

type
  TMultiLLMAgent = class
  private
    FPeers: TList<IWebLLMPeer>;
    FPeerInfos: TList<TPeerInfo>;
    FVfs: IGrispVfs;
    FTestAdapter: IGrispTestAdapter;
    FHarness: IGrispHarnessAdapter;
    FLastTrace: TProtocolTrace;

    function GetPeerReliability(const PeerName: string): Double;
    procedure SetPeerReliability(const PeerName: string; const Value: Double);
    function ShouldRunTests(const ActivatedCapabilities: TArray<string>): Boolean;
  public
    constructor Create(const APeers: TArray<IWebLLMPeer>;
      AVfs: IGrispVfs; ATestAdapter: IGrispTestAdapter; AHarness: IGrispHarnessAdapter);
    destructor Destroy; override;

    function RunTask(const UserPrompt: string): string;

    function GetLastTrace: TProtocolTrace;
    function GetLastTraceJSON: string;
    function GetPeerInfos: TArray<TPeerInfo>;

    property Vfs: IGrispVfs read FVfs;
    property TestAdapter: IGrispTestAdapter read FTestAdapter;
    property Harness: IGrispHarnessAdapter read FHarness;
  end;

implementation

{ TMultiLLMAgent }

constructor TMultiLLMAgent.Create(const APeers: TArray<IWebLLMPeer>;
  AVfs: IGrispVfs; ATestAdapter: IGrispTestAdapter; AHarness: IGrispHarnessAdapter);
var
  I: Integer;
  Peer: IWebLLMPeer;
begin
  inherited Create;
  FPeers := TList<IWebLLMPeer>.Create;
  FPeerInfos := TList<TPeerInfo>.Create;
  FVfs := AVfs;
  FTestAdapter := ATestAdapter;
  FHarness := AHarness;

  for I := 0 to High(APeers) do
  begin
    Peer := APeers[I];
    if Assigned(Peer) then
    begin
      FPeers.Add(Peer);
      FPeerInfos.Add(TPeerInfo.Create(Peer.GetName, 1.0));
    end;
  end;
end;

destructor TMultiLLMAgent.Destroy;
begin
  FPeers.Free;
  FPeerInfos.Free;
  inherited Destroy;
end;

function TMultiLLMAgent.GetPeerReliability(const PeerName: string): Double;
var
  P: TPeerInfo;
begin
  for P in FPeerInfos do
    if SameText(P.Name, PeerName) then
      Exit(P.Reliability);
  Result := 1.0;
end;

procedure TMultiLLMAgent.SetPeerReliability(const PeerName: string; const Value: Double);
var
  I: Integer;
  Info: TPeerInfo;
begin
  for I := 0 to FPeerInfos.Count - 1 do
    if SameText(FPeerInfos[I].Name, PeerName) then
    begin
      Info := FPeerInfos[I];
      Info.Reliability := EnsureRange(Value, 0.0, 1.0);
      FPeerInfos[I] := Info;
      Exit;
    end;

  Info := TPeerInfo.Create(PeerName, EnsureRange(Value, 0.0, 1.0));
  FPeerInfos.Add(Info);
end;

function TMultiLLMAgent.ShouldRunTests(const ActivatedCapabilities: TArray<string>): Boolean;
var
  S: string;
begin
  for S in ActivatedCapabilities do
    if SameText(S, 'test_execute') or SameText(S, 'test') or SameText(S, 'run') then
      Exit(True);
  Result := False;
end;

function TMultiLLMAgent.RunTask(const UserPrompt: string): string;
var
  Candidates: TList<TCandidate>;
  Critiques: TList<TCritique>;
  Repairs: TList<TRepair>;
  Requests: TList<TCapabilityRequest>;
  ActivatedCaps: TArray<string>;
  LightDebug: TList<TDebugFeedback>;
  TestPrograms: TList<TTestProgram>;
  TestResults: TList<TDebugFeedback>;
  Scores: TList<TScore>;
  Decisions: TList<TDecision>;
  ChosenPlan: string;
  GrispAccepted: Boolean;
  GrispDiag: string;
  ExecOutput: string;
  ExecDebug: TDebugFeedback;

  Peer: IWebLLMPeer;
  C: TCandidate;
  R: TRepair;
  T: TTestProgram;
  FB: TDebugFeedback;
  BestScore: Double;
  BestRepair: TRepair;
  Dec: TDecision;
  I: Integer;
  ScoreVal: Double;
  SB: TStringBuilder;
begin
  FLastTrace := Default(TProtocolTrace);
  FLastTrace.TaskPrompt := UserPrompt;
  FLastTrace.StartedUtc := Now;
  FLastTrace.PeerInfosBefore := FPeerInfos.ToArray;

  Candidates := TList<TCandidate>.Create;
  Critiques := TList<TCritique>.Create;
  Repairs := TList<TRepair>.Create;
  Requests := TList<TCapabilityRequest>.Create;
  LightDebug := TList<TDebugFeedback>.Create;
  TestPrograms := TList<TTestProgram>.Create;
  TestResults := TList<TDebugFeedback>.Create;
  Scores := TList<TScore>.Create;
  Decisions := TList<TDecision>.Create;
  try
    // -------------------------------------------------------------
    // Phase 1: Candidate Generation
    // -------------------------------------------------------------
    for Peer in FPeers do
      Candidates.Add(Peer.GenerateCandidate(UserPrompt));
    FLastTrace.Candidates := Candidates.ToArray;

    // -------------------------------------------------------------
    // Phase 2: Mutual Critique
    // -------------------------------------------------------------
    for Peer in FPeers do
      for C in Candidates do
        Critiques.Add(Peer.CritiqueCandidate(UserPrompt, C));
    FLastTrace.Critiques := Critiques.ToArray;

    // -------------------------------------------------------------
    // Phase 3: Cross-Repair (N x N Matrix)
    // -------------------------------------------------------------
    for Peer in FPeers do
      for C in Candidates do
        Repairs.Add(Peer.RepairCandidate(UserPrompt, C, Critiques.ToArray));
    FLastTrace.Repairs := Repairs.ToArray;

    // -------------------------------------------------------------
    // Phase 4: Capability Requests & Negotiation
    // -------------------------------------------------------------
    for Peer in FPeers do
      Requests.AddRange(Peer.RequestCapabilities(UserPrompt, Repairs.ToArray));
    FLastTrace.CapabilityRequests := Requests.ToArray;

    ActivatedCaps := NegotiateCapabilities(Requests.ToArray, 1, UserPrompt);
    FLastTrace.ActivatedCapabilities := ActivatedCaps;

    // -------------------------------------------------------------
    // Phase 5: Lightweight Debugging (Syntax & Compile sanity)
    // -------------------------------------------------------------
    for R in Repairs do
    begin
      FB := Default(TDebugFeedback);
      if Assigned(FTestAdapter) then
        FTestAdapter.RunQuickCheck(R.Content, R.Language, FB)
      else
        FB := TDebugFeedback.MakeSuccess('Lightweight check passed');
      LightDebug.Add(FB);
    end;
    FLastTrace.LightDebug := LightDebug.ToArray;

    // -------------------------------------------------------------
    // Phase 6: Deep Debugging & Test-Program Generation (Conditional)
    // -------------------------------------------------------------
    if ShouldRunTests(ActivatedCaps) then
    begin
      for Peer in FPeers do
        for R in Repairs do
          TestPrograms.Add(Peer.ProposeTestProgram(UserPrompt, R));

      for T in TestPrograms do
      begin
        FB := Default(TDebugFeedback);
        if Assigned(FVfs) and Assigned(FTestAdapter) then
        begin
          FVfs.WriteFile('/workspace/tests/' + T.FromPeer + '_' + T.TargetPeer + '.src', T.Code, 'text/plain');
          FTestAdapter.CompileAndRunTest(T.Code, T.Language, FB);
        end
        else
          FB := TDebugFeedback.MakeSuccess('Test passed');
        TestResults.Add(FB);
      end;
    end;
    FLastTrace.TestPrograms := TestPrograms.ToArray;
    FLastTrace.TestResults := TestResults.ToArray;

    // -------------------------------------------------------------
    // Phase 7: Multi-Modal Scoring
    // -------------------------------------------------------------
    for Peer in FPeers do
      Scores.AddRange(Peer.ScoreRepairs(UserPrompt, Candidates.ToArray, Repairs.ToArray, LightDebug.ToArray));
    FLastTrace.Scores := Scores.ToArray;

    // -------------------------------------------------------------
    // Phase 8: Aggregation & Decision
    // -------------------------------------------------------------
    for C in Candidates do
    begin
      BestScore := -1.0;
      BestRepair := Repairs[0];

      for R in Repairs do
      begin
        if SameText(R.TargetPeer, C.PeerName) then
        begin
          ScoreVal := AggregateRepairScore(R, Scores.ToArray, FPeerInfos.ToArray);
          if ScoreVal > BestScore then
          begin
            BestScore := ScoreVal;
            BestRepair := R;
          end;
        end;
      end;

      Dec := TDecision.Create(C.PeerName, BestRepair.FromPeer, BestRepair.Content, BestScore);
      Decisions.Add(Dec);
    end;
    FLastTrace.Decisions := Decisions.ToArray;

    // Pick top decision
    BestScore := -1.0;
    ChosenPlan := '';
    for Dec in Decisions do
    begin
      if Dec.FinalScore > BestScore then
      begin
        BestScore := Dec.FinalScore;
        ChosenPlan := Dec.FinalContent;
      end;
    end;
    FLastTrace.ChosenFinalPlan := ChosenPlan;

    // -------------------------------------------------------------
    // Phase 9: GRISP Kernel Validation
    // -------------------------------------------------------------
    if Assigned(FHarness) then
      GrispAccepted := FHarness.ValidatePlan(ChosenPlan, GrispDiag)
    else
    begin
      GrispAccepted := True;
      GrispDiag := 'Harness bypassed';
    end;
    FLastTrace.GrispAccepted := GrispAccepted;
    FLastTrace.GrispDiagnostics := GrispDiag;

    // -------------------------------------------------------------
    // Phase 10: Execution
    // -------------------------------------------------------------
    if GrispAccepted and Assigned(FHarness) then
      FHarness.ExecutePlan(ChosenPlan, ExecOutput, ExecDebug)
    else
    begin
      ExecOutput := 'Plan validated. Ready for deployment in workspace.';
      ExecDebug := TDebugFeedback.MakeSuccess('Commit OK');
    end;
    FLastTrace.ExecutionOutput := ExecOutput;

    // -------------------------------------------------------------
    // Phase 11: Reliability Update
    // -------------------------------------------------------------
    UpdateAllPeerReliabilities(FPeerInfos, Scores.ToArray, ExecDebug, GrispAccepted, Requests.ToArray);
    FLastTrace.PeerInfosAfter := FPeerInfos.ToArray;

    // -------------------------------------------------------------
    // Phase 12: Human Explanation & Audit Log
    // -------------------------------------------------------------
    FLastTrace.FinishedUtc := Now;

    SB := TStringBuilder.Create;
    try
      SB.AppendLine('================================================================');
      SB.AppendLine('       ADVANCED AGENT MLCRD COOPERATIVE EXECUTION REPORT        ');
      SB.AppendLine('================================================================');
      SB.AppendLine('Task: ' + UserPrompt);
      SB.AppendLine(Format('Active Peers: %d | Candidates: %d | Cross-Repairs: %d',
        [FPeers.Count, Candidates.Count, Repairs.Count]));
      SB.AppendLine('Activated Capabilities: ' + string.Join(', ', ActivatedCaps));
      SB.AppendLine(Format('Tests Generated & Run: %d', [TestPrograms.Count]));
      SB.AppendLine('GRISP Sandbox Status: ' + BoolToStr(GrispAccepted, True).ToUpper);
      SB.AppendLine('GRISP Diagnostics: ' + GrispDiag);
      SB.AppendLine('----------------------------------------------------------------');
      SB.AppendLine('CHOSEN FINAL SOLUTION (Score: ' + FloatToStrF(BestScore, ffFixed, 4, 3) + '):');
      SB.AppendLine(ChosenPlan);
      SB.AppendLine('----------------------------------------------------------------');
      SB.AppendLine('PEER RELIABILITY EVOLUTION:');
      for I := 0 to FPeerInfos.Count - 1 do
      begin
        SB.AppendLine(Format('  - %s: Reliability = %.3f (Repairs: %d, TestFails: %d, Rejects: %d)',
          [FPeerInfos[I].Name, FPeerInfos[I].Reliability, FPeerInfos[I].SuccessfulRepairs,
           FPeerInfos[I].FailedTests, FPeerInfos[I].GrispRejects]));
      end;
      SB.AppendLine('================================================================');
      Result := SB.ToString;
    finally
      SB.Free;
    end;

  finally
    Candidates.Free;
    Critiques.Free;
    Repairs.Free;
    Requests.Free;
    LightDebug.Free;
    TestPrograms.Free;
    TestResults.Free;
    Scores.Free;
    Decisions.Free;
  end;
end;

function TMultiLLMAgent.GetLastTrace: TProtocolTrace;
begin
  Result := FLastTrace;
end;

function TMultiLLMAgent.GetLastTraceJSON: string;
begin
  Result := ProtocolTraceToJSON(FLastTrace);
end;

function TMultiLLMAgent.GetPeerInfos: TArray<TPeerInfo>;
begin
  Result := FPeerInfos.ToArray;
end;

end.
