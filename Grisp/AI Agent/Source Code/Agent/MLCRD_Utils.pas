unit MLCRD_Utils;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.JSON,
  MLCRD_Types;

function EnsureRange(const Value, Min, Max: Double): Double;
function EscapeJSON(const S: string): string;

// JSON Serialization helpers
function CandidateToJSON(const C: TCandidate): string;
function CritiqueToJSON(const Cr: TCritique): string;
function RepairToJSON(const R: TRepair): string;
function CapabilityRequestToJSON(const Req: TCapabilityRequest): string;
function TestProgramToJSON(const T: TTestProgram): string;
function DebugFeedbackToJSON(const D: TDebugFeedback): string;
function ScoreToJSON(const S: TScore): string;
function PeerInfoToJSON(const P: TPeerInfo): string;
function DecisionToJSON(const Dec: TDecision): string;
function ProtocolTraceToJSON(const Trace: TProtocolTrace): string;

// JSON Deserialization helpers
function JSONToCandidate(const JSONStr: string): TCandidate;
function JSONToCritique(const JSONStr: string): TCritique;
function JSONToRepair(const JSONStr: string): TRepair;
function JSONToCapabilityRequest(const JSONStr: string): TCapabilityRequest;
function JSONToTestProgram(const JSONStr: string): TTestProgram;
function JSONToDebugFeedback(const JSONStr: string): TDebugFeedback;
function JSONToScore(const JSONStr: string): TScore;

implementation

function EnsureRange(const Value, Min, Max: Double): Double;
begin
  if Value < Min then Exit(Min);
  if Value > Max then Exit(Max);
  Result := Value;
end;

function EscapeJSON(const S: string): string;
var
  SB: TStringBuilder;
  I: Integer;
  C: Char;
begin
  SB := TStringBuilder.Create;
  try
    for I := 1 to Length(S) do
    begin
      C := S[I];
      case C of
        '"': SB.Append('\"');
        '\': SB.Append('\\');
        #8: SB.Append('\b');
        #9: SB.Append('\t');
        #10: SB.Append('\n');
        #12: SB.Append('\f');
        #13: SB.Append('\r');
      else
        if (Ord(C) < 32) then
          SB.Append(Format('\u%.4x', [Ord(C)]))
        else
          SB.Append(C);
      end;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function CandidateToJSON(const C: TCandidate): string;
begin
  Result := Format('{"peer":"%s","content":"%s","timestamp":"%s"}',
    [EscapeJSON(C.PeerName), EscapeJSON(C.Content), FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', C.TimestampUtc)]);
end;

function CritiqueToJSON(const Cr: TCritique): string;
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('{"from_peer":"' + EscapeJSON(Cr.FromPeer) + '",');
    SB.Append('"target_peer":"' + EscapeJSON(Cr.TargetPeer) + '",');
    SB.Append('"issues":[');
    for I := 0 to High(Cr.Issues) do
    begin
      if I > 0 then SB.Append(',');
      SB.Append('"' + EscapeJSON(Cr.Issues[I]) + '"');
    end;
    SB.Append('],');
    SB.Append('"suggested_fix":"' + EscapeJSON(Cr.SuggestedFix) + '",');
    SB.Append('"confidence":' + FloatToStr(Cr.Confidence, TFormatSettings.Invariant) + '}');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function RepairToJSON(const R: TRepair): string;
var
  SB: TStringBuilder;
  I: Integer;
  Pair: TPair<string, string>;
  First: Boolean;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('{"from_peer":"' + EscapeJSON(R.FromPeer) + '",');
    SB.Append('"target_peer":"' + EscapeJSON(R.TargetPeer) + '",');
    SB.Append('"original":"' + EscapeJSON(R.Original) + '",');
    SB.Append('"content":"' + EscapeJSON(R.Content) + '",');
    SB.Append('"language":"' + EscapeJSON(R.Language) + '",');
    SB.Append('"critiques":[');
    for I := 0 to High(R.Critiques) do
    begin
      if I > 0 then SB.Append(',');
      SB.Append(CritiqueToJSON(R.Critiques[I]));
    end;
    SB.Append('],');
    SB.Append('"metadata":{');
    First := True;
    if Assigned(R.Metadata) then
      for Pair in R.Metadata do
      begin
        if not First then SB.Append(',');
        SB.Append('"' + EscapeJSON(Pair.Key) + '":"' + EscapeJSON(Pair.Value) + '"');
        First := False;
      end;
    SB.Append('}}');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function CapabilityRequestToJSON(const Req: TCapabilityRequest): string;
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('{"from_peer":"' + EscapeJSON(Req.FromPeer) + '",');
    SB.Append('"target_peer":"' + EscapeJSON(Req.TargetPeer) + '",');
    SB.Append('"capabilities":[');
    for I := 0 to High(Req.Capabilities) do
    begin
      if I > 0 then SB.Append(',');
      SB.Append('"' + EscapeJSON(Req.Capabilities[I]) + '"');
    end;
    SB.Append('],');
    SB.Append('"reason":"' + EscapeJSON(Req.Reason) + '",');
    SB.Append('"confidence":' + FloatToStr(Req.Confidence, TFormatSettings.Invariant) + '}');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TestProgramToJSON(const T: TTestProgram): string;
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('{"from_peer":"' + EscapeJSON(T.FromPeer) + '",');
    SB.Append('"target_peer":"' + EscapeJSON(T.TargetPeer) + '",');
    SB.Append('"language":"' + EscapeJSON(T.Language) + '",');
    SB.Append('"purpose":"' + EscapeJSON(T.Purpose) + '",');
    SB.Append('"code":"' + EscapeJSON(T.Code) + '",');
    SB.Append('"hints":[');
    for I := 0 to High(T.Hints) do
    begin
      if I > 0 then SB.Append(',');
      SB.Append('"' + EscapeJSON(T.Hints[I]) + '"');
    end;
    SB.Append(']}');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function DebugFeedbackToJSON(const D: TDebugFeedback): string;
begin
  Result := Format('{"syntax_ok":%s,"semantic_ok":%s,"compile_ok":%s,"runtime_ok":%s,' +
    '"crash_count":%d,"timeout_count":%d,"breakpoint_hits":%d,"breakpoint_violations":%d,' +
    '"stack_trace":"%s","variable_dump":"%s","diagnostics":"%s","test_output":"%s",' +
    '"test_exit_code":%d,"test_passed":%s,"elapsed_ms":%d}',
    [BoolToStr(D.SyntaxOK, True).ToLower, BoolToStr(D.SemanticOK, True).ToLower,
     BoolToStr(D.CompileOK, True).ToLower, BoolToStr(D.RuntimeOK, True).ToLower,
     D.CrashCount, D.TimeoutCount, D.BreakpointHits, D.BreakpointViolations,
     EscapeJSON(D.StackTrace), EscapeJSON(D.VariableDump), EscapeJSON(D.Diagnostics),
     EscapeJSON(D.TestOutput), D.TestExitCode, BoolToStr(D.TestPassed, True).ToLower, D.ElapsedMs]);
end;

function ScoreToJSON(const S: TScore): string;
begin
  Result := Format('{"from_peer":"%s","target_peer":"%s","repair_peer":"%s",' +
    '"score_value":%s,"confidence":%s,"external":%s,"reason":"%s"}',
    [EscapeJSON(S.FromPeer), EscapeJSON(S.TargetPeer), EscapeJSON(S.RepairPeer),
     FloatToStr(S.ScoreValue, TFormatSettings.Invariant),
     FloatToStr(S.Confidence, TFormatSettings.Invariant),
     DebugFeedbackToJSON(S.External), EscapeJSON(S.Reason)]);
end;

function PeerInfoToJSON(const P: TPeerInfo): string;
begin
  Result := Format('{"name":"%s","reliability":%s,"chosen_count":%d,' +
    '"failed_tests":%d,"grisp_rejects":%d,"successful_repairs":%d,"spurious_debug_requests":%d}',
    [EscapeJSON(P.Name), FloatToStr(P.Reliability, TFormatSettings.Invariant),
     P.ChosenCount, P.FailedTests, P.GrispRejects, P.SuccessfulRepairs, P.SpuriousDebugRequests]);
end;

function DecisionToJSON(const Dec: TDecision): string;
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('{"target_peer":"' + EscapeJSON(Dec.TargetPeer) + '",');
    SB.Append('"chosen_repair_peer":"' + EscapeJSON(Dec.ChosenRepairPeer) + '",');
    SB.Append('"final_content":"' + EscapeJSON(Dec.FinalContent) + '",');
    SB.Append('"final_score":' + FloatToStr(Dec.FinalScore, TFormatSettings.Invariant) + ',');
    SB.Append('"evidence_scores":[');
    for I := 0 to High(Dec.EvidenceScores) do
    begin
      if I > 0 then SB.Append(',');
      SB.Append(ScoreToJSON(Dec.EvidenceScores[I]));
    end;
    SB.Append('],');
    SB.Append('"evidence_debug":[');
    for I := 0 to High(Dec.EvidenceDebug) do
    begin
      if I > 0 then SB.Append(',');
      SB.Append(DebugFeedbackToJSON(Dec.EvidenceDebug[I]));
    end;
    SB.Append(']}');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function ProtocolTraceToJSON(const Trace: TProtocolTrace): string;
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('{');
    SB.Append('"task_prompt":"' + EscapeJSON(Trace.TaskPrompt) + '",');
    SB.Append('"started_utc":"' + FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', Trace.StartedUtc) + '",');
    SB.Append('"finished_utc":"' + FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', Trace.FinishedUtc) + '",');

    SB.Append('"candidates":[');
    for I := 0 to High(Trace.Candidates) do
    begin
      if I > 0 then SB.Append(',');
      SB.Append(CandidateToJSON(Trace.Candidates[I]));
    end;
    SB.Append('],');

    SB.Append('"critiques":[');
    for I := 0 to High(Trace.Critiques) do
    begin
      if I > 0 then SB.Append(',');
      SB.Append(CritiqueToJSON(Trace.Critiques[I]));
    end;
    SB.Append('],');

    SB.Append('"repairs":[');
    for I := 0 to High(Trace.Repairs) do
    begin
      if I > 0 then SB.Append(',');
      SB.Append(RepairToJSON(Trace.Repairs[I]));
    end;
    SB.Append('],');

    SB.Append('"capability_requests":[');
    for I := 0 to High(Trace.CapabilityRequests) do
    begin
      if I > 0 then SB.Append(',');
      SB.Append(CapabilityRequestToJSON(Trace.CapabilityRequests[I]));
    end;
    SB.Append('],');

    SB.Append('"activated_capabilities":[');
    for I := 0 to High(Trace.ActivatedCapabilities) do
    begin
      if I > 0 then SB.Append(',');
      SB.Append('"' + EscapeJSON(Trace.ActivatedCapabilities[I]) + '"');
    end;
    SB.Append('],');

    SB.Append('"test_programs":[');
    for I := 0 to High(Trace.TestPrograms) do
    begin
      if I > 0 then SB.Append(',');
      SB.Append(TestProgramToJSON(Trace.TestPrograms[I]));
    end;
    SB.Append('],');

    SB.Append('"test_results":[');
    for I := 0 to High(Trace.TestResults) do
    begin
      if I > 0 then SB.Append(',');
      SB.Append(DebugFeedbackToJSON(Trace.TestResults[I]));
    end;
    SB.Append('],');

    SB.Append('"scores":[');
    for I := 0 to High(Trace.Scores) do
    begin
      if I > 0 then SB.Append(',');
      SB.Append(ScoreToJSON(Trace.Scores[I]));
    end;
    SB.Append('],');

    SB.Append('"decisions":[');
    for I := 0 to High(Trace.Decisions) do
    begin
      if I > 0 then SB.Append(',');
      SB.Append(DecisionToJSON(Trace.Decisions[I]));
    end;
    SB.Append('],');

    SB.Append('"chosen_final_plan":"' + EscapeJSON(Trace.ChosenFinalPlan) + '",');
    SB.Append('"grisp_accepted":' + BoolToStr(Trace.GrispAccepted, True).ToLower + ',');
    SB.Append('"grisp_diagnostics":"' + EscapeJSON(Trace.GrispDiagnostics) + '",');
    SB.Append('"execution_output":"' + EscapeJSON(Trace.ExecutionOutput) + '",');

    SB.Append('"peer_infos_before":[');
    for I := 0 to High(Trace.PeerInfosBefore) do
    begin
      if I > 0 then SB.Append(',');
      SB.Append(PeerInfoToJSON(Trace.PeerInfosBefore[I]));
    end;
    SB.Append('],');

    SB.Append('"peer_infos_after":[');
    for I := 0 to High(Trace.PeerInfosAfter) do
    begin
      if I > 0 then SB.Append(',');
      SB.Append(PeerInfoToJSON(Trace.PeerInfosAfter[I]));
    end;
    SB.Append(']');

    SB.Append('}');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Deserialization helpers using System.JSON

function JSONToCandidate(const JSONStr: string): TCandidate;
var
  Val: TJSONValue;
  Obj: TJSONObject;
begin
  Result := Default(TCandidate);
  Val := TJSONObject.ParseJSONValue(JSONStr);
  if Assigned(Val) and (Val is TJSONObject) then
  begin
    Obj := Val as TJSONObject;
    try
      if Obj.FindValue('peer') <> nil then
        Result.PeerName := Obj.GetValue('peer').Value;
      if Obj.FindValue('content') <> nil then
        Result.Content := Obj.GetValue('content').Value;
      Result.TimestampUtc := Now;
    finally
      Obj.Free;
    end;
  end;
end;

function JSONToCritique(const JSONStr: string): TCritique;
var
  Val: TJSONValue;
  Obj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  Result := Default(TCritique);
  Val := TJSONObject.ParseJSONValue(JSONStr);
  if Assigned(Val) and (Val is TJSONObject) then
  begin
    Obj := Val as TJSONObject;
    try
      if Obj.FindValue('from_peer') <> nil then
        Result.FromPeer := Obj.GetValue('from_peer').Value;
      if Obj.FindValue('target_peer') <> nil then
        Result.TargetPeer := Obj.GetValue('target_peer').Value;
      if Obj.FindValue('suggested_fix') <> nil then
        Result.SuggestedFix := Obj.GetValue('suggested_fix').Value;
      if Obj.FindValue('confidence') <> nil then
        Result.Confidence := StrToFloatDef(Obj.GetValue('confidence').Value, 1.0);

      if (Obj.FindValue('issues') <> nil) and (Obj.GetValue('issues') is TJSONArray) then
      begin
        Arr := Obj.GetValue('issues') as TJSONArray;
        SetLength(Result.Issues, Arr.Count);
        for I := 0 to Arr.Count - 1 do
          Result.Issues[I] := Arr.Items[I].Value;
      end;
    finally
      Obj.Free;
    end;
  end;
end;

function JSONToRepair(const JSONStr: string): TRepair;
var
  Val: TJSONValue;
  Obj: TJSONObject;
begin
  Result := Default(TRepair);
  Result.Metadata := TDictionary<string, string>.Create;
  Val := TJSONObject.ParseJSONValue(JSONStr);
  if Assigned(Val) and (Val is TJSONObject) then
  begin
    Obj := Val as TJSONObject;
    try
      if Obj.FindValue('from_peer') <> nil then
        Result.FromPeer := Obj.GetValue('from_peer').Value;
      if Obj.FindValue('target_peer') <> nil then
        Result.TargetPeer := Obj.GetValue('target_peer').Value;
      if Obj.FindValue('original') <> nil then
        Result.Original := Obj.GetValue('original').Value;
      if Obj.FindValue('content') <> nil then
        Result.Content := Obj.GetValue('content').Value;
      if Obj.FindValue('language') <> nil then
        Result.Language := Obj.GetValue('language').Value
      else
        Result.Language := 'text';
    finally
      Obj.Free;
    end;
  end;
end;

function JSONToCapabilityRequest(const JSONStr: string): TCapabilityRequest;
var
  Val: TJSONValue;
  Obj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  Result := Default(TCapabilityRequest);
  Val := TJSONObject.ParseJSONValue(JSONStr);
  if Assigned(Val) and (Val is TJSONObject) then
  begin
    Obj := Val as TJSONObject;
    try
      if Obj.FindValue('from_peer') <> nil then
        Result.FromPeer := Obj.GetValue('from_peer').Value;
      if Obj.FindValue('target_peer') <> nil then
        Result.TargetPeer := Obj.GetValue('target_peer').Value;
      if Obj.FindValue('reason') <> nil then
        Result.Reason := Obj.GetValue('reason').Value;
      if Obj.FindValue('confidence') <> nil then
        Result.Confidence := StrToFloatDef(Obj.GetValue('confidence').Value, 1.0);

      if (Obj.FindValue('capabilities') <> nil) and (Obj.GetValue('capabilities') is TJSONArray) then
      begin
        Arr := Obj.GetValue('capabilities') as TJSONArray;
        SetLength(Result.Capabilities, Arr.Count);
        for I := 0 to Arr.Count - 1 do
          Result.Capabilities[I] := Arr.Items[I].Value;
      end;
    finally
      Obj.Free;
    end;
  end;
end;

function JSONToTestProgram(const JSONStr: string): TTestProgram;
var
  Val: TJSONValue;
  Obj: TJSONObject;
begin
  Result := Default(TTestProgram);
  Val := TJSONObject.ParseJSONValue(JSONStr);
  if Assigned(Val) and (Val is TJSONObject) then
  begin
    Obj := Val as TJSONObject;
    try
      if Obj.FindValue('from_peer') <> nil then
        Result.FromPeer := Obj.GetValue('from_peer').Value;
      if Obj.FindValue('target_peer') <> nil then
        Result.TargetPeer := Obj.GetValue('target_peer').Value;
      if Obj.FindValue('language') <> nil then
        Result.Language := Obj.GetValue('language').Value;
      if Obj.FindValue('purpose') <> nil then
        Result.Purpose := Obj.GetValue('purpose').Value;
      if Obj.FindValue('code') <> nil then
        Result.Code := Obj.GetValue('code').Value;
    finally
      Obj.Free;
    end;
  end;
end;

function JSONToDebugFeedback(const JSONStr: string): TDebugFeedback;
var
  Val: TJSONValue;
  Obj: TJSONObject;
begin
  Result := Default(TDebugFeedback);
  Val := TJSONObject.ParseJSONValue(JSONStr);
  if Assigned(Val) and (Val is TJSONObject) then
  begin
    Obj := Val as TJSONObject;
    try
      Result.SyntaxOK := (Obj.FindValue('syntax_ok') <> nil) and (Obj.GetValue('syntax_ok').Value = 'true');
      Result.SemanticOK := (Obj.FindValue('semantic_ok') <> nil) and (Obj.GetValue('semantic_ok').Value = 'true');
      Result.CompileOK := (Obj.FindValue('compile_ok') <> nil) and (Obj.GetValue('compile_ok').Value = 'true');
      Result.RuntimeOK := (Obj.FindValue('runtime_ok') <> nil) and (Obj.GetValue('runtime_ok').Value = 'true');
      if Obj.FindValue('crash_count') <> nil then
        Result.CrashCount := StrToIntDef(Obj.GetValue('crash_count').Value, 0);
      if Obj.FindValue('diagnostics') <> nil then
        Result.Diagnostics := Obj.GetValue('diagnostics').Value;
      if Obj.FindValue('test_output') <> nil then
        Result.TestOutput := Obj.GetValue('test_output').Value;
      if Obj.FindValue('test_exit_code') <> nil then
        Result.TestExitCode := StrToIntDef(Obj.GetValue('test_exit_code').Value, 0);
      Result.TestPassed := (Obj.FindValue('test_passed') <> nil) and (Obj.GetValue('test_passed').Value = 'true');
    finally
      Obj.Free;
    end;
  end;
end;

function JSONToScore(const JSONStr: string): TScore;
var
  Val, ExtVal: TJSONValue;
  Obj: TJSONObject;
begin
  Result := Default(TScore);
  Val := TJSONObject.ParseJSONValue(JSONStr);
  if Assigned(Val) and (Val is TJSONObject) then
  begin
    Obj := Val as TJSONObject;
    try
      if Obj.FindValue('from_peer') <> nil then
        Result.FromPeer := Obj.GetValue('from_peer').Value;
      if Obj.FindValue('target_peer') <> nil then
        Result.TargetPeer := Obj.GetValue('target_peer').Value;
      if Obj.FindValue('repair_peer') <> nil then
        Result.RepairPeer := Obj.GetValue('repair_peer').Value;
      if Obj.FindValue('score_value') <> nil then
        Result.ScoreValue := StrToFloatDef(Obj.GetValue('score_value').Value, 0.5);
      if Obj.FindValue('confidence') <> nil then
        Result.Confidence := StrToFloatDef(Obj.GetValue('confidence').Value, 1.0);
      if Obj.FindValue('reason') <> nil then
        Result.Reason := Obj.GetValue('reason').Value;

      ExtVal := Obj.FindValue('external');
      if Assigned(ExtVal) then
        Result.External := JSONToDebugFeedback(ExtVal.ToJSON);
    finally
      Obj.Free;
    end;
  end;
end;

end.
