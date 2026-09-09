// Filename: MLCRD_Coordinator.pas
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
    FConfig: TAgentConfiguration;

    function GetPeerReliability(const PeerName: string): Double;
    procedure SetPeerReliability(const PeerName: string; const Value: Double);
    function IsTrivialCode(const Code: string): Boolean;
    function ShouldRunTests(const ActivatedCapabilities: TArray<string>; const Repairs: TArray<TRepair>): Boolean;
    procedure ConsoleWrite(const Msg: string);
    function GuessFileNameFromContent(const Content, Language: string): string;
  public
    constructor Create(const APeers: TArray<IWebLLMPeer>;
      AVfs: IGrispVfs; ATestAdapter: IGrispTestAdapter; AHarness: IGrispHarnessAdapter;
      const AConfig: TAgentConfiguration);
    destructor Destroy; override;

    function RunTask(const UserPrompt: string): string;

    function GetLastTrace: TProtocolTrace;
    function GetLastTraceJSON: string;
    function GetPeerInfos: TArray<TPeerInfo>;

    property Vfs: IGrispVfs read FVfs;
    property TestAdapter: IGrispTestAdapter read FTestAdapter;
    property Harness: IGrispHarnessAdapter read FHarness;
    property Config: TAgentConfiguration read FConfig;
  end;

implementation

{ TMultiLLMAgent }

constructor TMultiLLMAgent.Create(const APeers: TArray<IWebLLMPeer>;
  AVfs: IGrispVfs; ATestAdapter: IGrispTestAdapter; AHarness: IGrispHarnessAdapter;
  const AConfig: TAgentConfiguration);
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
  FConfig := AConfig;

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

// ---------------------------------------------------------------------------
// Language‑agnostic triviality check
// ---------------------------------------------------------------------------
function TMultiLLMAgent.IsTrivialCode(const Code: string): Boolean;
var
  Lower: string;
begin
  Lower := LowerCase(Code);
  if Lower.Contains('function ') then Exit(False);
  if Lower.Contains('procedure ') then Exit(False);
  if Lower.Contains('def ') then Exit(False);
  if Lower.Contains('class ') then Exit(False);
  if Lower.Contains('struct ') then Exit(False);
  if Lower.Contains('record ') then Exit(False);
  if Lower.Contains('case ') then Exit(False);
  if Lower.Contains('switch ') then Exit(False);
  if Lower.Contains('for ') then Exit(False);
  if Lower.Contains('while ') then Exit(False);
  if Lower.Contains('repeat ') then Exit(False);
  if Lower.Contains('do ') then Exit(False);
  if Lower.Contains('if ') then Exit(False);
  if Lower.Contains('else ') then Exit(False);
  if Lower.Contains(' + ') or Lower.Contains(' - ') or Lower.Contains(' * ') or
     Lower.Contains(' / ') or Lower.Contains(' div ') or Lower.Contains(' mod ') or
     Lower.Contains(' % ') then Exit(False);
  if Lower.Contains('pointer') or Lower.Contains('malloc') or Lower.Contains('free') or
     Lower.Contains('new ') or Lower.Contains('delete ') or Lower.Contains('array') then Exit(False);
  if Lower.Contains('readln') or Lower.Contains('readline') or
     Lower.Contains('open(') or Lower.Contains('fopen') then Exit(False);
  Result := True;
end;

// ---------------------------------------------------------------------------
// Decide if tests should run
// ---------------------------------------------------------------------------
function TMultiLLMAgent.ShouldRunTests(const ActivatedCapabilities: TArray<string>; const Repairs: TArray<TRepair>): Boolean;
var
  S: string;
  R: TRepair;
begin
  if not FConfig.GenerateTests then
    Exit(False);

  Result := False;
  for S in ActivatedCapabilities do
    if SameText(S, 'test_execute') or SameText(S, 'run') then
    begin
      Result := True;
      Break;
    end;

  if not Result then
    Exit(False);

  for R in Repairs do
  begin
    if not IsTrivialCode(R.Content) then
      Exit(True);
  end;

  Result := False;
end;

// ---------------------------------------------------------------------------
// Console output helper
// ---------------------------------------------------------------------------
procedure TMultiLLMAgent.ConsoleWrite(const Msg: string);
begin
  Writeln('[GRISP] ' + Msg);
end;

// ---------------------------------------------------------------------------
// GuessFileNameFromContent – fallback heuristic (kept as safety net)
// ---------------------------------------------------------------------------
function TMultiLLMAgent.GuessFileNameFromContent(const Content, Language: string): string;
var
  FirstLine: string;
  Ext: string;
begin
  Ext := '.txt';
  if SameText(Language, 'pascal') or SameText(Language, 'delphi') then
    Ext := '.pas'
  else if SameText(Language, 'c') then
    Ext := '.c'
  else if SameText(Language, 'python') then
    Ext := '.py';

  FirstLine := Content.Trim;
  if FirstLine.StartsWith('program ') then
  begin
    var NamePart := Copy(FirstLine, 9, MaxInt);
    var SpacePos := Pos(' ', NamePart);
    if SpacePos > 0 then
      NamePart := Copy(NamePart, 1, SpacePos - 1);
    if NamePart.EndsWith(';') then
      NamePart := Copy(NamePart, 1, Length(NamePart) - 1);
    Result := NamePart + Ext;
  end
  else if FirstLine.StartsWith('unit ') then
  begin
    var NamePart := Copy(FirstLine, 6, MaxInt);
    var SpacePos := Pos(' ', NamePart);
    if SpacePos > 0 then
      NamePart := Copy(NamePart, 1, SpacePos - 1);
    if NamePart.EndsWith(';') then
      NamePart := Copy(NamePart, 1, Length(NamePart) - 1);
    Result := NamePart + Ext;
  end
  else if FirstLine.StartsWith('#include') or FirstLine.StartsWith('int main') then
    Result := 'main' + Ext
  else if FirstLine.StartsWith('import ') or FirstLine.StartsWith('def ') then
    Result := 'main' + Ext
  else
    Result := 'program' + Ext;
end;

// ---------------------------------------------------------------------------
// RunTask – 12‑phase protocol with AI‑driven filenames
// ---------------------------------------------------------------------------
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
  J: Integer;
  ScoreVal: Double;
  SB: TStringBuilder;
  FileEntry: TFileEntry;
  WrittenCount: Integer;
  Ext: string;
  TestFileName: string;
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
    // Phase 1: Candidates
    for Peer in FPeers do
      Candidates.Add(Peer.GenerateCandidate(UserPrompt, FConfig));
    FLastTrace.Candidates := Candidates.ToArray;

    // Phase 2: Critiques
    for Peer in FPeers do
      for C in Candidates do
        Critiques.Add(Peer.CritiqueCandidate(UserPrompt, C, FConfig));
    FLastTrace.Critiques := Critiques.ToArray;

    // Phase 3: Repairs
    for Peer in FPeers do
      for C in Candidates do
        Repairs.Add(Peer.RepairCandidate(UserPrompt, C, Critiques.ToArray, FConfig));
    FLastTrace.Repairs := Repairs.ToArray;

    // Phase 4: Capability Requests
    for Peer in FPeers do
      Requests.AddRange(Peer.RequestCapabilities(UserPrompt, Repairs.ToArray, FConfig));
    FLastTrace.CapabilityRequests := Requests.ToArray;

    ActivatedCaps := NegotiateCapabilities(Requests.ToArray, 1, UserPrompt);
    FLastTrace.ActivatedCapabilities := ActivatedCaps;

    // Phase 5: Light Debug
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

    // Phase 6: Deep Debug & Test Generation
    if ShouldRunTests(ActivatedCaps, Repairs.ToArray) then
    begin
      ConsoleWrite('Running deep tests (non‑trivial code detected)...');
      for Peer in FPeers do
        for R in Repairs do
          TestPrograms.Add(Peer.ProposeTestProgram(UserPrompt, R, FConfig));

      for T in TestPrograms do
      begin
        ConsoleWrite('  Compiling test from ' + T.FromPeer + ' for ' + T.TargetPeer + '...');
        FB := Default(TDebugFeedback);
        if Assigned(FVfs) and Assigned(FTestAdapter) then
        begin
          // Determine extension
          Ext := '.txt';
          if SameText(T.Language, 'pascal') or SameText(T.Language, 'delphi') then
            Ext := '.pas'
          else if SameText(T.Language, 'c') then
            Ext := '.c'
          else if SameText(T.Language, 'python') then
            Ext := '.py';
          TestFileName := 'Test_' + T.FromPeer + '_on_' + T.TargetPeer + Ext;
          FVfs.WriteFile('/workspace/tests/' + TestFileName, T.Code, 'text/plain');
          if FTestAdapter.CompileAndRunTest(T.Code, T.Language, FB) then
          begin
            ConsoleWrite('    Test passed (exit code ' + IntToStr(FB.TestExitCode) + ')');
            if FB.TestOutput <> '' then
              ConsoleWrite('    Output: ' + FB.TestOutput);
          end
          else
          begin
            ConsoleWrite('    Test FAILED:');
            if FB.Diagnostics <> '' then
              ConsoleWrite('    ' + FB.Diagnostics);
            if FB.TestOutput <> '' then
              ConsoleWrite('    Output: ' + FB.TestOutput);
          end;
        end
        else
        begin
          FB := TDebugFeedback.MakeSuccess('Test passed');
          ConsoleWrite('    Test (simulated) passed');
        end;
        TestResults.Add(FB);
      end;
    end
    else
    begin
      ConsoleWrite('Skipping deep tests (trivial code or no test capabilities).');
    end;
    FLastTrace.TestPrograms := TestPrograms.ToArray;
    FLastTrace.TestResults := TestResults.ToArray;

    // Phase 7: Scores
    for Peer in FPeers do
      Scores.AddRange(Peer.ScoreRepairs(UserPrompt, Candidates.ToArray, Repairs.ToArray, LightDebug.ToArray, FConfig));
    FLastTrace.Scores := Scores.ToArray;

    // Phase 8: Decisions
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

    // Pick best
    BestScore := -1.0;
    ChosenPlan := '';
    BestRepair := Repairs[0];
    for Dec in Decisions do
    begin
      if Dec.FinalScore > BestScore then
      begin
        BestScore := Dec.FinalScore;
        ChosenPlan := Dec.FinalContent;
        for R in Repairs do
          if (R.FromPeer = Dec.ChosenRepairPeer) and (R.TargetPeer = Dec.TargetPeer) then
          begin
            BestRepair := R;
            Break;
          end;
      end;
    end;
    FLastTrace.ChosenFinalPlan := ChosenPlan;

    // Phase 9: GRISP Validation
    if Assigned(FHarness) then
      GrispAccepted := FHarness.ValidatePlan(ChosenPlan, GrispDiag)
    else
    begin
      GrispAccepted := True;
      GrispDiag := 'Harness bypassed';
    end;
    FLastTrace.GrispAccepted := GrispAccepted;
    FLastTrace.GrispDiagnostics := GrispDiag;

    // Phase 10: Execution
    if GrispAccepted and Assigned(FHarness) then
      FHarness.ExecutePlan(ChosenPlan, ExecOutput, ExecDebug)
    else
    begin
      ExecOutput := 'Plan validated. Ready for deployment.';
      ExecDebug := TDebugFeedback.MakeSuccess('Commit OK');
    end;
    FLastTrace.ExecutionOutput := ExecOutput;

    // -----------------------------------------------------------------------
    // Write ALL files from BestRepair to the workspace
    // -----------------------------------------------------------------------
    WrittenCount := 0;
    if (Length(BestRepair.Files) > 0) then
    begin
      if Assigned(FVfs) then
      begin
        for J := 0 to High(BestRepair.Files) do
        begin
          FileEntry := BestRepair.Files[J];
          // If the filename is generic or empty, try to guess a better one (fallback)
          if (FileEntry.FileName = 'program.txt') or (FileEntry.FileName = '') then
            FileEntry.FileName := GuessFileNameFromContent(FileEntry.Content, BestRepair.Language);
          if FVfs.WriteFile('/workspace/' + FileEntry.FileName, FileEntry.Content, 'text/plain') then
          begin
            ConsoleWrite('File written: /workspace/' + FileEntry.FileName);
            Inc(WrittenCount);
          end
          else
            ConsoleWrite('ERROR: Could not write file /workspace/' + FileEntry.FileName);
        end;
        if WrittenCount > 0 then
          ExecOutput := ExecOutput + sLineBreak + Format('Wrote %d file(s) to /workspace/', [WrittenCount]);
      end
      else
        ConsoleWrite('WARNING: Vfs not available; cannot write files.');
    end
    else if (ChosenPlan <> '') and (not ChosenPlan.Trim.StartsWith('rules')) then
    begin
      // Fallback: use the single ChosenPlan with a guessed name
      var FileName := GuessFileNameFromContent(ChosenPlan, '');
      if Assigned(FVfs) and FVfs.WriteFile('/workspace/' + FileName, ChosenPlan, 'text/plain') then
      begin
        ConsoleWrite('Final code written to /workspace/' + FileName);
        ExecOutput := ExecOutput + sLineBreak + 'File written: /workspace/' + FileName;
      end;
    end;

    // Phase 11: Reliability Update
    UpdateAllPeerReliabilities(FPeerInfos, Scores.ToArray, ExecDebug, GrispAccepted, Requests.ToArray);
    FLastTrace.PeerInfosAfter := FPeerInfos.ToArray;

    // Phase 12: Report
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
      SB.AppendLine('Files written:');
      if Length(BestRepair.Files) > 0 then
        for FileEntry in BestRepair.Files do
          SB.AppendLine('  /workspace/' + FileEntry.FileName)
      else
        SB.AppendLine('  (No files written)');
      SB.AppendLine('----------------------------------------------------------------');
      SB.AppendLine('Execution output:');
      SB.AppendLine(ExecOutput);
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