unit unit_GrispStrategy_version_001;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  unit_GrispGraph_version_001,
  unit_GrispPattern_version_001,
  unit_GrispRewrite_version_001;

type
  TStrategyKind = (skRule, skSequence, skRepeat, skTry, skChoice, skPhase);

  TStrategy = class
  public
    Kind: TStrategyKind;
    RuleName: string;
    Phase: Integer;
    Strategies: TList<TStrategy>;
    constructor Create(AKind: TStrategyKind);
    destructor Destroy; override;
  end;

  TGrispStrategyEngine = class
  private
    FGraph: TGGraph;
    FMatcher: TGrispPatternMatcher;
    FRewriter: TGrispRewriter;
    FStrategies: TDictionary<string, TStrategy>;
    FTrace: TStrings;
    FMaxSteps: Integer;
    function ExecuteStrategy(Strategy: TStrategy; var Steps: Integer): Boolean;
    function FindRule(const RuleName: string): TGNode;
  public
    constructor Create(Graph: TGGraph);
    destructor Destroy; override;
    procedure AddStrategy(const Name: string; Strategy: TStrategy);
    function Execute(const StrategyName: string; MaxSteps: Integer = 1000): Integer;
    property Trace: TStrings read FTrace write FTrace;
  end;

implementation

{ TStrategy }

constructor TStrategy.Create(AKind: TStrategyKind);
begin
  inherited Create;
  Kind := AKind;
  Strategies := TList<TStrategy>.Create;
  Phase := 0;
end;

destructor TStrategy.Destroy;
begin
  Strategies.Free;
  inherited Destroy;
end;

{ TGrispStrategyEngine }

constructor TGrispStrategyEngine.Create(Graph: TGGraph);
begin
  inherited Create;
  FGraph := Graph;
  FMatcher := TGrispPatternMatcher.Create(Graph);
  FRewriter := TGrispRewriter.Create(Graph);
  FStrategies := TDictionary<string, TStrategy>.Create;
  FMaxSteps := 1000;
end;

destructor TGrispStrategyEngine.Destroy;
var
  Strategy: TStrategy;
begin
  for Strategy in FStrategies.Values do
    Strategy.Free;
  FStrategies.Free;
  FRewriter.Free;
  FMatcher.Free;
  inherited Destroy;
end;

function TGrispStrategyEngine.FindRule(const RuleName: string): TGNode;
var
  Node: TGNode;
begin
  for Node in FGraph.Rules do
    if SameText(Node.Name, RuleName) then
      Exit(Node);
  Result := nil;
end;

function TGrispStrategyEngine.ExecuteStrategy(Strategy: TStrategy; var Steps: Integer): Boolean;
var
  SubStrategy: TStrategy;
  Rule: TGNode;
  Applied: Integer;
  Changed: Boolean;
  OldPhase: Integer;
begin
  Result := False;

  if Steps >= FMaxSteps then
    Exit;

  case Strategy.Kind of
    skRule:
      begin
        Rule := FindRule(Strategy.RuleName);
        if Assigned(Rule) then
        begin
          FMatcher.SetCurrentRule(Rule);
          Applied := FRewriter.ApplyAllMatches(Rule, FMatcher, FTrace);
          if Applied > 0 then
          begin
            Inc(Steps, Applied);
            Result := True;
          end;
        end;
      end;

    skRepeat:
      begin
        repeat
          Changed := False;
          for SubStrategy in Strategy.Strategies do
          begin
            if ExecuteStrategy(SubStrategy, Steps) then
              Changed := True;
            if Steps >= FMaxSteps then
              Break;
          end;
        until (not Changed) or (Steps >= FMaxSteps);
        Result := Changed;
      end;

    skSequence:
      for SubStrategy in Strategy.Strategies do
      begin
        if ExecuteStrategy(SubStrategy, Steps) then
          Result := True;
        if Steps >= FMaxSteps then
          Break;
      end;

    skTry:
      for SubStrategy in Strategy.Strategies do
      begin
        if ExecuteStrategy(SubStrategy, Steps) then
        begin
          Result := True;
          Break;
        end;
      end;

    skChoice:
      for SubStrategy in Strategy.Strategies do
      begin
        if ExecuteStrategy(SubStrategy, Steps) then
          Result := True;
        if Steps >= FMaxSteps then
          Break;
      end;

    skPhase:
      begin
        OldPhase := FMatcher.FCurrentPhase;
        try
          FMatcher.SetPhase(Strategy.Phase);
          for SubStrategy in Strategy.Strategies do
          begin
            if ExecuteStrategy(SubStrategy, Steps) then
              Result := True;
            if Steps >= FMaxSteps then
              Break;
          end;
        finally
          FMatcher.SetPhase(OldPhase);
        end;
      end;
  end;
end;

procedure TGrispStrategyEngine.AddStrategy(const Name: string; Strategy: TStrategy);
begin
  FStrategies.AddOrSetValue(Name, Strategy);
end;

function TGrispStrategyEngine.Execute(const StrategyName: string; MaxSteps: Integer): Integer;
var
  Strategy: TStrategy;
  Steps: Integer;
begin
  Result := 0;
  FMaxSteps := MaxSteps;
  if not FStrategies.TryGetValue(StrategyName, Strategy) then
    Exit;

  Steps := 0;
  ExecuteStrategy(Strategy, Steps);
  Result := Steps;
end;

end.
