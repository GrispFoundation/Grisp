unit MLCRD_Algorithms;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Math,
  MLCRD_Types, MLCRD_Utils;

const
  DEFAULT_ALPHA = 0.5; // Weight for subjective LLM score
  DEFAULT_BETA  = 0.5; // Weight for objective external ground truth (compiler/runtime/tests)

  // External debug component weights
  W_SYNTAX     = 0.10;
  W_SEMANTIC   = 0.10;
  W_COMPILE    = 0.20;
  W_RUNTIME    = 0.20;
  W_TESTPASS   = 0.30;
  W_CRASH      = 0.05;
  W_TIMEOUT    = 0.03;
  W_BREAKVIOL  = 0.02;

  // Reliability adjustment deltas
  DELTA_POS_SUCCESS   = 0.025; // Chosen repair passes all tests and is accepted by GRISP
  DELTA_POS_TEST      = 0.020; // Peer wrote a useful test that uncovered an edge case
  DELTA_NEG_CRASH     = 0.040; // Peer's repair crashed or caused memory violations
  DELTA_NEG_TEST_FAIL = 0.030; // Peer's repair failed test verification
  DELTA_NEG_GRISP     = 0.035; // Peer supported a plan rejected by GRISP security kernel
  DELTA_NEG_NOISE_REQ = 0.015; // Peer requested deep debugging unnecessarily on trivial code

function ComputeExternalScore(const D: TDebugFeedback): Double;
function GetPeerReliabilityFromArray(const PeerName: string; const PeerInfos: TArray<TPeerInfo>): Double;
function AggregateRepairScore(const Repair: TRepair; const Scores: TArray<TScore>;
  const PeerInfos: TArray<TPeerInfo>; const Alpha: Double = DEFAULT_ALPHA;
  const Beta: Double = DEFAULT_BETA): Double;

function NegotiateCapabilities(const Requests: TArray<TCapabilityRequest>;
  Threshold: Integer = 1; const TaskPrompt: string = ''): TArray<string>;

procedure UpdatePeerReliability(const PeerName: string; var PeerInfos: TList<TPeerInfo>;
  const Scores: TArray<TScore>; const ExecDebug: TDebugFeedback; const GrispAccepted: Boolean;
  const RequestedCaps: TArray<TCapabilityRequest>);

procedure UpdateAllPeerReliabilities(var PeerInfos: TList<TPeerInfo>;
  const Scores: TArray<TScore>; const ExecDebug: TDebugFeedback; const GrispAccepted: Boolean;
  const RequestedCaps: TArray<TCapabilityRequest>);

implementation

function ComputeExternalScore(const D: TDebugFeedback): Double;
var
  Score: Double;
begin
  Score := 0.0;

  if D.SyntaxOK then Score := Score + W_SYNTAX;
  if D.SemanticOK then Score := Score + W_SEMANTIC;
  if D.CompileOK then Score := Score + W_COMPILE;
  if D.RuntimeOK then Score := Score + W_RUNTIME;
  if D.TestPassed then Score := Score + W_TESTPASS;

  Score := Score - (W_CRASH * D.CrashCount);
  Score := Score - (W_TIMEOUT * D.TimeoutCount);
  Score := Score - (W_BREAKVIOL * D.BreakpointViolations);

  Result := EnsureRange(Score, 0.0, 1.0);
end;

function GetPeerReliabilityFromArray(const PeerName: string; const PeerInfos: TArray<TPeerInfo>): Double;
var
  P: TPeerInfo;
begin
  for P in PeerInfos do
    if SameText(P.Name, PeerName) then
      Exit(P.Reliability);
  Result := 1.0;
end;

function AggregateRepairScore(const Repair: TRepair; const Scores: TArray<TScore>;
  const PeerInfos: TArray<TPeerInfo>; const Alpha, Beta: Double): Double;
var
  S: TScore;
  R: Double;
  Ext: Double;
  TotalWeight: Double;
  SumContrib: Double;
begin
  SumContrib := 0.0;
  TotalWeight := 0.0;

  for S in Scores do
  begin
    if SameText(S.TargetPeer, Repair.TargetPeer) and SameText(S.RepairPeer, Repair.FromPeer) then
    begin
      R := GetPeerReliabilityFromArray(S.FromPeer, PeerInfos);
      Ext := ComputeExternalScore(S.External);

      // Subjective LLM confidence-weighted score + Objective external score
      SumContrib := SumContrib + R * (Alpha * (S.ScoreValue * S.Confidence) + Beta * Ext);
      TotalWeight := TotalWeight + R;
    end;
  end;

  if TotalWeight > 0.0001 then
    Result := SumContrib / TotalWeight
  else
    Result := 0.0;
end;

function NegotiateCapabilities(const Requests: TArray<TCapabilityRequest>;
  Threshold: Integer; const TaskPrompt: string): TArray<string>;
var
  CapCounts: TDictionary<string, Integer>;
  Req: TCapabilityRequest;
  Cap: string;
  ResultList: TList<string>;
  LowPrompt: string;
  IsHighRiskTask: Boolean;
begin
  CapCounts := TDictionary<string, Integer>.Create;
  ResultList := TList<string>.Create;
  try
    LowPrompt := LowerCase(TaskPrompt);
    IsHighRiskTask := LowPrompt.Contains('pointer') or LowPrompt.Contains('memory') or
      LowPrompt.Contains('concurrency') or LowPrompt.Contains('overflow') or
      LowPrompt.Contains('segfault') or LowPrompt.Contains('security') or
      LowPrompt.Contains('divide by zero') or LowPrompt.Contains('division');

    for Req in Requests do
    begin
      for Cap in Req.Capabilities do
      begin
        if not CapCounts.ContainsKey(Cap) then
          CapCounts.Add(Cap, 1)
        else
          CapCounts[Cap] := CapCounts[Cap] + 1;
      end;
    end;

    for Cap in CapCounts.Keys do
    begin
      // Threshold check or risk keyword override
      if (CapCounts[Cap] >= Threshold) or IsHighRiskTask then
      begin
        if not ResultList.Contains(Cap) then
          ResultList.Add(Cap);
      end;
    end;

    Result := ResultList.ToArray;
  finally
    CapCounts.Free;
    ResultList.Free;
  end;
end;

procedure UpdatePeerReliability(const PeerName: string; var PeerInfos: TList<TPeerInfo>;
  const Scores: TArray<TScore>; const ExecDebug: TDebugFeedback; const GrispAccepted: Boolean;
  const RequestedCaps: TArray<TCapabilityRequest>);
var
  I: Integer;
  Info: TPeerInfo;
  FoundBadExternal: Boolean;
  PeerRequestedCaps: Boolean;
  S: TScore;
  Req: TCapabilityRequest;
begin
  for I := 0 to PeerInfos.Count - 1 do
  begin
    if SameText(PeerInfos[I].Name, PeerName) then
    begin
      Info := PeerInfos[I];
      FoundBadExternal := False;

      // 1. Check external validation outcomes for this peer's repairs/scores
      for S in Scores do
      begin
        if SameText(S.FromPeer, PeerName) or SameText(S.RepairPeer, PeerName) then
        begin
          if (not S.External.CompileOK) or (not S.External.RuntimeOK) or
             (S.External.CrashCount > 0) or (not S.External.TestPassed) then
          begin
            FoundBadExternal := True;
            Break;
          end;
        end;
      end;

      // 2. Check capability request justification
      PeerRequestedCaps := False;
      for Req in RequestedCaps do
      begin
        if SameText(Req.FromPeer, PeerName) and (Length(Req.Capabilities) > 0) then
        begin
          PeerRequestedCaps := True;
          Break;
        end;
      end;

      // Apply positive adjustments
      if GrispAccepted and (not FoundBadExternal) and ExecDebug.RuntimeOK then
      begin
        Info.Reliability := Min(1.0, Info.Reliability + DELTA_POS_SUCCESS);
        Inc(Info.SuccessfulRepairs);
      end;

      // Apply negative adjustments
      if not GrispAccepted then
      begin
        Info.Reliability := Max(0.0, Info.Reliability - DELTA_NEG_GRISP);
        Inc(Info.GrispRejects);
      end;

      if FoundBadExternal or (ExecDebug.CrashCount > 0) then
      begin
        Info.Reliability := Max(0.0, Info.Reliability - DELTA_NEG_CRASH);
        Inc(Info.FailedTests);
      end;

      if PeerRequestedCaps and (not FoundBadExternal) and GrispAccepted then
      begin
        // If peer requested debugging on a completely clean run without issues, apply small noise penalty
        Info.Reliability := Max(0.0, Info.Reliability - DELTA_NEG_NOISE_REQ);
        Inc(Info.SpuriousDebugRequests);
      end;

      PeerInfos[I] := Info;
      Exit;
    end;
  end;
end;

procedure UpdateAllPeerReliabilities(var PeerInfos: TList<TPeerInfo>;
  const Scores: TArray<TScore>; const ExecDebug: TDebugFeedback; const GrispAccepted: Boolean;
  const RequestedCaps: TArray<TCapabilityRequest>);
var
  I: Integer;
  PName: string;
begin
  for I := 0 to PeerInfos.Count - 1 do
  begin
    PName := PeerInfos[I].Name;
    UpdatePeerReliability(PName, PeerInfos, Scores, ExecDebug, GrispAccepted, RequestedCaps);
  end;
end;

end.
