unit unit_Strategy_TGrispStrategyBuilder_version_001;

interface

uses
  System.SysUtils,                              // Added for Exception
  System.Generics.Collections,
  unit_Strategy_TGrispStrategyKind_version_001,
  unit_Strategy_TGrispStrategy_version_001;

type
  TGrispStrategyBuilder = class
  private
    FStrategies: TList<TGrispStrategy>;
  public
    constructor Create;
    destructor Destroy; override;

    function Rule(const RuleName: string): TGrispStrategyBuilder;
    function Sequence: TGrispStrategyBuilder;
    function RepeatStrategy: TGrispStrategyBuilder;
    function TryStrategy: TGrispStrategyBuilder;
    function Choice: TGrispStrategyBuilder;
    function Phase(PhaseNum: Integer): TGrispStrategyBuilder;
    function Add(const Strategy: TGrispStrategy): TGrispStrategyBuilder;

    function Build: TGrispStrategy;
    procedure Clear;
  end;

implementation

constructor TGrispStrategyBuilder.Create;
begin
  inherited Create;
  FStrategies := TList<TGrispStrategy>.Create;
end;

destructor TGrispStrategyBuilder.Destroy;
begin
  Clear;
  FStrategies.Free;
  inherited Destroy;
end;

function TGrispStrategyBuilder.Rule(const RuleName: string): TGrispStrategyBuilder;
var
  Strategy: TGrispStrategy;
begin
  Strategy := TGrispStrategy.Create(gskRule);
  Strategy.RuleName := RuleName;
  FStrategies.Add(Strategy);
  Result := Self;
end;

function TGrispStrategyBuilder.Sequence: TGrispStrategyBuilder;
begin
  FStrategies.Add(TGrispStrategy.Create(gskSequence));
  Result := Self;
end;

function TGrispStrategyBuilder.RepeatStrategy: TGrispStrategyBuilder;
begin
  FStrategies.Add(TGrispStrategy.Create(gskRepeat));
  Result := Self;
end;

function TGrispStrategyBuilder.TryStrategy: TGrispStrategyBuilder;
begin
  FStrategies.Add(TGrispStrategy.Create(gskTry));
  Result := Self;
end;

function TGrispStrategyBuilder.Choice: TGrispStrategyBuilder;
begin
  FStrategies.Add(TGrispStrategy.Create(gskChoice));
  Result := Self;
end;

function TGrispStrategyBuilder.Phase(PhaseNum: Integer): TGrispStrategyBuilder;
var
  Strategy: TGrispStrategy;
begin
  Strategy := TGrispStrategy.Create(gskPhase);
  Strategy.Phase := PhaseNum;
  FStrategies.Add(Strategy);
  Result := Self;
end;

function TGrispStrategyBuilder.Add(const Strategy: TGrispStrategy): TGrispStrategyBuilder;
begin
  FStrategies.Add(Strategy);
  Result := Self;
end;

function TGrispStrategyBuilder.Build: TGrispStrategy;
var
  i: Integer;
  Strategy, Current, Parent: TGrispStrategy;
  Stack: TList<TGrispStrategy>;
begin
  if FStrategies.Count = 0 then
    raise Exception.Create('No strategies to build');

  Result := FStrategies[0].Clone;
  Stack := TList<TGrispStrategy>.Create;
  try
    Stack.Add(Result);

    for i := 1 to FStrategies.Count - 1 do
    begin
      Current := FStrategies[i];
      Parent := Stack[Stack.Count - 1];

      if Current.Kind in [gskSequence, gskRepeat, gskTry, gskChoice, gskPhase] then
      begin
        Parent.Strategies.Add(Current.Clone);
        Stack.Add(Parent.Strategies[Parent.Strategies.Count - 1]);
      end
      else
      begin
        Parent.Strategies.Add(Current.Clone);
        while (Stack.Count > 0) and (Stack[Stack.Count - 1].Strategies.Count > 0) do
          Stack.Delete(Stack.Count - 1);
      end;
    end;
  finally
    Stack.Free;
  end;
end;

procedure TGrispStrategyBuilder.Clear;
var
  Strategy: TGrispStrategy;
begin
  for Strategy in FStrategies do
    Strategy.Free;
  FStrategies.Clear;
end;

end.
