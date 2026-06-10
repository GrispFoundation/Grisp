unit unit_Runtime_TGrispRuntimeEngine_version_001;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  unit_Graph_TGrispGraph_version_001,
  unit_Graph_TGrispEdge_TGrispNode_version_001,
  unit_Core_TGrispValueBase_version_001,           // Added for TGrispValue
  unit_Pattern_TGrispPatternMatcher_version_001,
  unit_Rewrite_TGrispRewriter_version_001,
  unit_Runtime_TGrispRuntimeConfig_version_001;

type
  TGrispRuntimeEngine = class
  private
    FGraph: TGrispGraph;
    FMatcher: TGrispPatternMatcher;
    FRewriter: TGrispRewriter;
    FTrace: TStrings;
    FConfig: TGrispRuntimeConfig;
    FTotalSteps: Integer;

    function GetRulePhase(Rule: TGrispNode): Integer;
    procedure LogTrace(const Msg: string);
    procedure EnsureMatcherRewriter;

  public
    constructor Create(Graph: TGrispGraph);
    destructor Destroy; override;

    function Run(MaxSteps: Integer = 0): Integer; overload;
    function RunWithTrace(Trace: TStrings; MaxSteps: Integer = 0): Integer;
    function RunWithPhases(MaxPhases: Integer = 0; MaxStepsPerPhase: Integer = 0): Integer;
    function RunWithPhasesAndTrace(Trace: TStrings; MaxPhases: Integer = 0; MaxStepsPerPhase: Integer = 0): Integer;
    function RunUntilStable(MaxSteps: Integer = 0): Integer;

    procedure Reset;
    procedure SetConfig(const Config: TGrispRuntimeConfig);

    property TotalSteps: Integer read FTotalSteps;
    property Config: TGrispRuntimeConfig read FConfig;
  end;

implementation

constructor TGrispRuntimeEngine.Create(Graph: TGrispGraph);
begin
  inherited Create;
  FGraph := Graph;
  FConfig.SetDefaults;
  FTotalSteps := 0;
  FMatcher := nil;
  FRewriter := nil;
end;

destructor TGrispRuntimeEngine.Destroy;
begin
  FreeAndNil(FRewriter);
  FreeAndNil(FMatcher);
  inherited Destroy;
end;

procedure TGrispRuntimeEngine.EnsureMatcherRewriter;
begin
  if FMatcher = nil then
    FMatcher := TGrispPatternMatcher.Create(FGraph);
  if FRewriter = nil then
    FRewriter := TGrispRewriter.Create(FGraph);
end;

procedure TGrispRuntimeEngine.LogTrace(const Msg: string);
begin
  if FConfig.TraceEnabled and Assigned(FTrace) then
    FTrace.Add(Msg);
end;

function TGrispRuntimeEngine.GetRulePhase(Rule: TGrispNode): Integer;
var
  PhaseAttr: TGrispValue;
begin
  Result := 0;
  if Rule.HasAttribute('phase') then
  begin
    PhaseAttr := Rule.GetValueAttribute('phase');
    if (PhaseAttr <> nil) and (PhaseAttr.Kind = gvkNumber) then
      Result := Trunc(PhaseAttr.NumberValue);
  end;
end;

procedure TGrispRuntimeEngine.Reset;
begin
  FTotalSteps := 0;
  if FConfig.AutoCleanup then
  begin
    FreeAndNil(FRewriter);
    FreeAndNil(FMatcher);
  end;
end;

procedure TGrispRuntimeEngine.SetConfig(const Config: TGrispRuntimeConfig);
begin
  FConfig := Config;
end;

function TGrispRuntimeEngine.Run(MaxSteps: Integer): Integer;
var
  Steps: Integer;
  ActualMaxSteps: Integer;
begin
  Result := 0;
  if FGraph = nil then Exit;

  ActualMaxSteps := MaxSteps;
  if ActualMaxSteps = 0 then
    ActualMaxSteps := FConfig.MaxSteps;

  EnsureMatcherRewriter;

  Steps := 0;
  try
    Result := RunWithTrace(nil, ActualMaxSteps);
  finally
    FTotalSteps := Steps;
  end;
end;

function TGrispRuntimeEngine.RunWithTrace(Trace: TStrings; MaxSteps: Integer): Integer;
var
  Step: Integer;
  Changed: Boolean;
  Rule: TGrispNode;
  Applied: Integer;
  ActualMaxSteps: Integer;
  i: Integer;
begin
  Result := 0;
  if FGraph = nil then Exit;

  FTrace := Trace;
  ActualMaxSteps := MaxSteps;
  if ActualMaxSteps = 0 then
    ActualMaxSteps := FConfig.MaxSteps;

  EnsureMatcherRewriter;

  Step := 0;
  try
    repeat
      Changed := False;

      for i := 0 to FGraph.Rules.Count - 1 do
      begin
        Rule := FGraph.Rules[i];
        FMatcher.SetCurrentRule(Rule);
        Applied := FRewriter.ApplyAllMatches(Rule, FMatcher, FTrace);

        if Applied > 0 then
        begin
          Inc(Step, Applied);
          Changed := True;

          LogTrace(Format('Step %d: applied %s (%d matches)', [Step, Rule.Name, Applied]));

          if Step >= ActualMaxSteps then
            Break;
        end;
      end;

    until (not Changed) or (Step >= ActualMaxSteps);

    Result := Step;
  finally
    FTrace := nil;
    if FConfig.AutoCleanup then
    begin
      FreeAndNil(FRewriter);
      FreeAndNil(FMatcher);
    end;
  end;
end;

function TGrispRuntimeEngine.RunWithPhases(MaxPhases: Integer; MaxStepsPerPhase: Integer): Integer;
begin
  Result := RunWithPhasesAndTrace(nil, MaxPhases, MaxStepsPerPhase);
end;

function TGrispRuntimeEngine.RunWithPhasesAndTrace(Trace: TStrings; MaxPhases: Integer; MaxStepsPerPhase: Integer): Integer;
var
  Phase: Integer;
  PhaseSteps: Integer;
  Changed: Boolean;
  Rule: TGrispNode;
  Applied: Integer;
  RulePhase: Integer;
  TotalSteps: Integer;
  ActualMaxPhases: Integer;
  ActualMaxStepsPerPhase: Integer;
  i: Integer;
begin
  Result := 0;
  TotalSteps := 0;

  if FGraph = nil then Exit;

  FTrace := Trace;
  ActualMaxPhases := MaxPhases;
  if ActualMaxPhases = 0 then
    ActualMaxPhases := FConfig.MaxPhases;

  ActualMaxStepsPerPhase := MaxStepsPerPhase;
  if ActualMaxStepsPerPhase = 0 then
	ActualMaxStepsPerPhase := FConfig.MaxStepsPerPhase;

  EnsureMatcherRewriter;

  try
    for Phase := 1 to ActualMaxPhases do
    begin
      LogTrace(Format('========== PHASE %d ==========', [Phase]));
      PhaseSteps := 0;

      repeat
        Changed := False;

        for i := 0 to FGraph.Rules.Count - 1 do
        begin
          Rule := FGraph.Rules[i];
          RulePhase := GetRulePhase(Rule);

          if (RulePhase = 0) or (RulePhase = Phase) then
          begin
            FMatcher.SetCurrentRule(Rule);
            Applied := FRewriter.ApplyAllMatches(Rule, FMatcher, FTrace);

            if Applied > 0 then
            begin
              Inc(PhaseSteps, Applied);
              Changed := True;

              LogTrace(Format('  Phase %d, Step %d: %s (%d matches)',
                       [Phase, PhaseSteps, Rule.Name, Applied]));

              if PhaseSteps >= ActualMaxStepsPerPhase then
                Break;
            end;
          end;
        end;

        if PhaseSteps >= ActualMaxStepsPerPhase then
          Break;

      until not Changed;

      LogTrace(Format('Phase %d complete after %d steps', [Phase, PhaseSteps]));
      Inc(TotalSteps, PhaseSteps);

      if PhaseSteps = 0 then
        Break;
    end;

    Result := TotalSteps;

  finally
    FTrace := nil;
    if FConfig.AutoCleanup then
    begin
      FreeAndNil(FRewriter);
      FreeAndNil(FMatcher);
    end;
  end;
end;

function TGrispRuntimeEngine.RunUntilStable(MaxSteps: Integer): Integer;
begin
  Result := Run(MaxSteps);
end;

end.
