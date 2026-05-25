unit unit_Strategy_TGrispStrategyEngine_version_001;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  unit_Graph_TGrispGraph_version_001,
  unit_Graph_TGrispEdge_TGrispNode_version_001,  // ADDED: for TGrispNode
  unit_Pattern_TGrispPatternMatcher_version_001,
  unit_Rewrite_TGrispRewriter_version_001,
  unit_Strategy_TGrispStrategyKind_version_001,
  unit_Strategy_TGrispStrategy_version_001;

type
  TGrispStrategyEngine = class
  private
    FGraph: TGrispGraph;
    FMatcher: TGrispPatternMatcher;
    FRewriter: TGrispRewriter;
    FStrategies: TDictionary<string, TGrispStrategy>;
    FTrace: TStrings;
    FMaxSteps: Integer;
    FCurrentSteps: Integer;

    function ExecuteStrategy(Strategy: TGrispStrategy): Boolean;
    function FindRule(const RuleName: string): TGrispNode;
    procedure ResetSteps;
  public
    constructor Create(Graph: TGrispGraph);
    destructor Destroy; override;

    procedure AddStrategy(const Name: string; Strategy: TGrispStrategy);
    function Execute(const StrategyName: string; MaxSteps: Integer = 1000): Integer;
    function ExecuteWithTrace(const StrategyName: string; Trace: TStrings; MaxSteps: Integer = 1000): Integer;

    property Trace: TStrings read FTrace write FTrace;
    property MaxSteps: Integer read FMaxSteps write FMaxSteps;
  end;

implementation

constructor TGrispStrategyEngine.Create(Graph: TGrispGraph);
begin
  inherited Create;
  FGraph := Graph;
  FMatcher := TGrispPatternMatcher.Create(Graph);
  FRewriter := TGrispRewriter.Create(Graph);
  FStrategies := TDictionary<string, TGrispStrategy>.Create;
  FMaxSteps := 1000;
  FCurrentSteps := 0;
end;

destructor TGrispStrategyEngine.Destroy;
var
  Strategy: TGrispStrategy;
begin
  for Strategy in FStrategies.Values do
    Strategy.Free;
  FStrategies.Free;
  FRewriter.Free;
  FMatcher.Free;
  inherited Destroy;
end;

function TGrispStrategyEngine.FindRule(const RuleName: string): TGrispNode;
var
  Node: TGrispNode;
  i: Integer;
begin
  Result := nil;
  for i := 0 to FGraph.Rules.Count - 1 do
  begin
    Node := FGraph.Rules[i];
    if SameText(Node.Name, RuleName) then
      Exit(Node);
  end;
end;

procedure TGrispStrategyEngine.ResetSteps;
begin
  FCurrentSteps := 0;
end;

function TGrispStrategyEngine.ExecuteStrategy(Strategy: TGrispStrategy): Boolean;
var
  SubStrategy: TGrispStrategy;
  Rule: TGrispNode;
  Applied: Integer;
  Changed: Boolean;
  OldPhase: Integer;
  i: Integer;
begin
  Result := False;

  if FCurrentSteps >= FMaxSteps then
    Exit;

  case Strategy.Kind of
    gskRule:
      begin
        Rule := FindRule(Strategy.RuleName);
        if Assigned(Rule) then
        begin
          FMatcher.SetCurrentRule(Rule);
          Applied := FRewriter.ApplyAllMatches(Rule, FMatcher, FTrace);
          if Applied > 0 then
          begin
            Inc(FCurrentSteps, Applied);
            Result := True;
          end;
        end;
      end;

    gskRepeat:
      begin
        repeat
          Changed := False;
          for i := 0 to Strategy.Strategies.Count - 1 do
          begin
            SubStrategy := Strategy.Strategies[i];
            if ExecuteStrategy(SubStrategy) then
              Changed := True;
            if FCurrentSteps >= FMaxSteps then
              Break;
          end;
        until (not Changed) or (FCurrentSteps >= FMaxSteps);
        Result := Changed;
      end;

    gskSequence:
      begin
        for i := 0 to Strategy.Strategies.Count - 1 do
        begin
          SubStrategy := Strategy.Strategies[i];
          if ExecuteStrategy(SubStrategy) then
            Result := True;
          if FCurrentSteps >= FMaxSteps then
            Break;
        end;
      end;

    gskTry:
      begin
        for i := 0 to Strategy.Strategies.Count - 1 do
        begin
          SubStrategy := Strategy.Strategies[i];
          if ExecuteStrategy(SubStrategy) then
          begin
            Result := True;
            Break;
		  end;
        end;
      end;

    gskChoice:
      begin
        for i := 0 to Strategy.Strategies.Count - 1 do
        begin
          SubStrategy := Strategy.Strategies[i];
          if ExecuteStrategy(SubStrategy) then
            Result := True;
          if FCurrentSteps >= FMaxSteps then
            Break;
        end;
      end;

    gskPhase:
      begin
        OldPhase := FMatcher.CurrentPhase;
        try
          FMatcher.SetPhase(Strategy.Phase);
          for i := 0 to Strategy.Strategies.Count - 1 do
          begin
            SubStrategy := Strategy.Strategies[i];
            if ExecuteStrategy(SubStrategy) then
              Result := True;
            if FCurrentSteps >= FMaxSteps then
              Break;
          end;
        finally
          FMatcher.SetPhase(OldPhase);
        end;
      end;
  end;
end;

procedure TGrispStrategyEngine.AddStrategy(const Name: string; Strategy: TGrispStrategy);
begin
  FStrategies.AddOrSetValue(Name, Strategy);
end;

function TGrispStrategyEngine.Execute(const StrategyName: string; MaxSteps: Integer): Integer;
var
  Strategy: TGrispStrategy;
begin
  Result := 0;
  FMaxSteps := MaxSteps;
  ResetSteps;

  if not FStrategies.TryGetValue(StrategyName, Strategy) then
    Exit;

  ExecuteStrategy(Strategy);
  Result := FCurrentSteps;
end;

function TGrispStrategyEngine.ExecuteWithTrace(const StrategyName: string; Trace: TStrings; MaxSteps: Integer): Integer;
begin
  FTrace := Trace;
  try
    Result := Execute(StrategyName, MaxSteps);
  finally
    FTrace := nil;
  end;
end;

end.
