unit unit_GrispRuntime_version_001;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  unit_GrispGraph_version_001,
  unit_GrispPattern_version_001,
  unit_GrispRewrite_version_001;

type
  TRuntimeConfig = record
    MaxSteps: Integer;
    MaxPhases: Integer;
    TraceEnabled: Boolean;
    PhaseMode: Boolean;  // Enable phase-based execution
  end;

  TGrispRuntime = class
  private
    class var FConfig: TRuntimeConfig;
    class function GetRulePhase(Rule: TGNode): Integer;
  public
    class procedure Initialize;
    class procedure Configure(const Config: TRuntimeConfig);
    class function Run(Graph: TGGraph; MaxSteps: Integer = 1000; Trace: TStrings = nil): Integer;
    class function RunWithPhases(Graph: TGGraph; MaxPhases: Integer = 10; MaxStepsPerPhase: Integer = 100; Trace: TStrings = nil): Integer;
  end;

implementation

class procedure TGrispRuntime.Initialize;
begin
  FConfig.MaxSteps := 1000;
  FConfig.MaxPhases := 10;
  FConfig.TraceEnabled := False;
  FConfig.PhaseMode := False;
end;

class procedure TGrispRuntime.Configure(const Config: TRuntimeConfig);
begin
  FConfig := Config;
end;

class function TGrispRuntime.GetRulePhase(Rule: TGNode): Integer;
var
  PhaseAttr: TGValue;
begin
  Result := 0;  // Default phase (always execute)
  if Rule.HasAttribute('phase') then
  begin
    PhaseAttr := Rule.GetAttribute('phase');
    if (PhaseAttr <> nil) and (PhaseAttr.Kind = vkNumber) then
      Result := Trunc(PhaseAttr.NumberValue);
  end;
end;

class function TGrispRuntime.Run(Graph: TGGraph; MaxSteps: Integer; Trace: TStrings): Integer;
var
  Matcher: TGrispPatternMatcher;
  Rewriter: TGrispRewriter;
  Step: Integer;
  Changed: Boolean;
  Rule: TGNode;
  Applied: Integer;
begin
  Result := 0;
  if Graph = nil then
    Exit;

  Matcher := TGrispPatternMatcher.Create(Graph);
  Rewriter := TGrispRewriter.Create(Graph);
  try
    Step := 0;
    repeat
      Changed := False;

      for Rule in Graph.Rules do
      begin
        // In non-phase mode, execute all rules
        // In phase mode, only execute rules with phase=0 or phase matching current phase
        // (Phase mode requires external phase tracking)
        Matcher.SetCurrentRule(Rule);
        Applied := Rewriter.ApplyAllMatches(Rule, Matcher, Trace);

        if Applied > 0 then
        begin
          Inc(Step, Applied);
          Changed := True;

          if Assigned(Trace) then
            Trace.Add(Format('Step %d: applied %s (%d matches)', [Step, Rule.Name, Applied]));

          if Step >= MaxSteps then
            Break;
        end;
      end;

    until (not Changed) or (Step >= MaxSteps);

    Result := Step;
  finally
    Rewriter.Free;
    Matcher.Free;
  end;
end;

class function TGrispRuntime.RunWithPhases(Graph: TGGraph; MaxPhases: Integer; MaxStepsPerPhase: Integer; Trace: TStrings): Integer;
var
  Phase: Integer;
  Matcher: TGrispPatternMatcher;
  Rewriter: TGrispRewriter;
  PhaseSteps: Integer;
  Changed: Boolean;
  Rule: TGNode;
  Applied: Integer;
  RulePhase: Integer;
  TotalSteps: Integer;
begin
  Result := 0;
  TotalSteps := 0;

  if Graph = nil then
    Exit;

  Matcher := TGrispPatternMatcher.Create(Graph);
  Rewriter := TGrispRewriter.Create(Graph);
  try
    for Phase := 1 to MaxPhases do
    begin
      if Assigned(Trace) then
        Trace.Add(Format('========== PHASE %d ==========', [Phase]));

      PhaseSteps := 0;

      repeat
        Changed := False;

        for Rule in Graph.Rules do
        begin
          RulePhase := GetRulePhase(Rule);

          // Execute rules that belong to this phase OR have no phase (phase=0)
          if (RulePhase = 0) or (RulePhase = Phase) then
          begin
            Matcher.SetCurrentRule(Rule);
            Applied := Rewriter.ApplyAllMatches(Rule, Matcher, Trace);

            if Applied > 0 then
            begin
              Inc(PhaseSteps, Applied);
              Changed := True;

              if Assigned(Trace) then
                Trace.Add(Format('  Phase %d, Step %d: %s (%d matches)', [Phase, PhaseSteps, Rule.Name, Applied]));

              if PhaseSteps >= MaxStepsPerPhase then
                Break;
            end;
          end;
        end;

        if PhaseSteps >= MaxStepsPerPhase then
          Break;

      until not Changed;

      if Assigned(Trace) then
        Trace.Add(Format('Phase %d complete after %d steps', [Phase, PhaseSteps]));

      Inc(TotalSteps, PhaseSteps);

      // Stop if no rules executed in this phase
      if PhaseSteps = 0 then
        Break;
    end;

    Result := TotalSteps;

  finally
    Rewriter.Free;
    Matcher.Free;
  end;
end;

initialization
  TGrispRuntime.Initialize;
end.
