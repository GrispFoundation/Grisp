unit unit_Strategy_TGrispStrategyBuilder_version_001;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.TypInfo,
  unit_Strategy_TGrispStrategyKind_version_001,
  unit_Strategy_TGrispStrategy_version_001,
  unit_Debug_TGrispDebug_version_001;

type
  TGrispStrategyBuilder = class
  private
    FStrategies: TList<TGrispStrategy>;
    FDebugEnabled: Boolean;

    procedure Debug(const Msg: string);
    procedure DebugStrategy(const Prefix: string; S: TGrispStrategy; Indent: Integer = 0);
    procedure DebugStack(const Stack: TList<TGrispStrategy>; const Operation: string);
    procedure DumpStrategyList(const Prefix: string);
  public
    constructor Create;
    destructor Destroy; override;

    procedure EnableDebug;
    procedure DisableDebug;

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
  FDebugEnabled := False;
end;

destructor TGrispStrategyBuilder.Destroy;
begin
  Clear;
  FStrategies.Free;
  inherited Destroy;
end;

procedure TGrispStrategyBuilder.EnableDebug;
begin
  FDebugEnabled := True;
  TGrispDebug.Enable;
  Debug('=== Original StrategyBuilder DEBUG ENABLED ===');
end;

procedure TGrispStrategyBuilder.DisableDebug;
begin
  Debug('=== Original StrategyBuilder DEBUG DISABLED ===');
  FDebugEnabled := False;
end;

procedure TGrispStrategyBuilder.Debug(const Msg: string);
begin
  if FDebugEnabled then
    TGrispDebug.Log('[OrigBuilder] ' + Msg);
end;

procedure TGrispStrategyBuilder.DebugStrategy(const Prefix: string; S: TGrispStrategy; Indent: Integer = 0);
var
  IndentStr: string;
  i: Integer;
begin
  if not FDebugEnabled then Exit;

  IndentStr := StringOfChar(' ', Indent * 2);
  if S = nil then
  begin
    Debug(Format('%s%sNIL Strategy', [IndentStr, Prefix]));
    Exit;
  end;

  case S.Kind of
    gskRule:
      Debug(Format('%s%sRule: %s', [IndentStr, Prefix, S.RuleName]));
    gskSequence:
      Debug(Format('%s%sSequence (%d children)', [IndentStr, Prefix, S.Strategies.Count]));
    gskRepeat:
      Debug(Format('%s%sRepeat (%d children)', [IndentStr, Prefix, S.Strategies.Count]));
    gskTry:
      Debug(Format('%s%sTry (%d children)', [IndentStr, Prefix, S.Strategies.Count]));
    gskChoice:
      Debug(Format('%s%sChoice (%d children)', [IndentStr, Prefix, S.Strategies.Count]));
    gskPhase:
      Debug(Format('%s%sPhase %d (%d children)', [IndentStr, Prefix, S.Phase, S.Strategies.Count]));
  end;

  for i := 0 to S.Strategies.Count - 1 do
    DebugStrategy('  child', S.Strategies[i], Indent + 1);
end;

procedure TGrispStrategyBuilder.DebugStack(const Stack: TList<TGrispStrategy>; const Operation: string);
var
  i: Integer;
  S: TGrispStrategy;
begin
  if not FDebugEnabled then Exit;

  Debug(Format('Stack %s - Count: %d', [Operation, Stack.Count]));
  for i := 0 to Stack.Count - 1 do
  begin
    S := Stack[i];
    if S <> nil then
      Debug(Format('  Stack[%d]: %s', [i, GetEnumName(TypeInfo(TGrispStrategyKind), Ord(S.Kind))]))
    else
      Debug(Format('  Stack[%d]: NIL', [i]));
  end;
end;

procedure TGrispStrategyBuilder.DumpStrategyList(const Prefix: string);
var
  i: Integer;
  S: TGrispStrategy;
begin
  if not FDebugEnabled then Exit;

  Debug(Format('%s FStrategies has %d items:', [Prefix, FStrategies.Count]));
  for i := 0 to FStrategies.Count - 1 do
  begin
    S := FStrategies[i];
    if S <> nil then
      DebugStrategy(Format('  [%d] ', [i]), S)
    else
      Debug(Format('  [%d] NIL', [i]));
  end;
end;

procedure TGrispStrategyBuilder.Clear;
var
  Strategy: TGrispStrategy;
begin
  Debug('Clear called');
  for Strategy in FStrategies do
  begin
    if FDebugEnabled then
      Debug(Format('  Freeing strategy: %s', [GetEnumName(TypeInfo(TGrispStrategyKind), Ord(Strategy.Kind))]));
    Strategy.Free;
  end;
  FStrategies.Clear;
  DumpStrategyList('After Clear');
end;

function TGrispStrategyBuilder.Rule(const RuleName: string): TGrispStrategyBuilder;
var
  Strategy: TGrispStrategy;
begin
  Strategy := TGrispStrategy.Create(gskRule);
  Strategy.RuleName := RuleName;
  FStrategies.Add(Strategy);
  Debug(Format('Rule added: %s (total strategies: %d)', [RuleName, FStrategies.Count]));
  DumpStrategyList('After Rule');
  Result := Self;
end;

function TGrispStrategyBuilder.Sequence: TGrispStrategyBuilder;
var
  Strategy: TGrispStrategy;
begin
  Strategy := TGrispStrategy.Create(gskSequence);
  FStrategies.Add(Strategy);
  Debug(Format('Sequence added (total strategies: %d)', [FStrategies.Count]));
  DumpStrategyList('After Sequence');
  Result := Self;
end;

function TGrispStrategyBuilder.RepeatStrategy: TGrispStrategyBuilder;
var
  Strategy: TGrispStrategy;
begin
  Strategy := TGrispStrategy.Create(gskRepeat);
  FStrategies.Add(Strategy);
  Debug(Format('Repeat added (total strategies: %d)', [FStrategies.Count]));
  DumpStrategyList('After Repeat');
  Result := Self;
end;

function TGrispStrategyBuilder.TryStrategy: TGrispStrategyBuilder;
var
  Strategy: TGrispStrategy;
begin
  Strategy := TGrispStrategy.Create(gskTry);
  FStrategies.Add(Strategy);
  Debug(Format('Try added (total strategies: %d)', [FStrategies.Count]));
  DumpStrategyList('After Try');
  Result := Self;
end;

function TGrispStrategyBuilder.Choice: TGrispStrategyBuilder;
var
  Strategy: TGrispStrategy;
begin
  Strategy := TGrispStrategy.Create(gskChoice);
  FStrategies.Add(Strategy);
  Debug(Format('Choice added (total strategies: %d)', [FStrategies.Count]));
  DumpStrategyList('After Choice');
  Result := Self;
end;

function TGrispStrategyBuilder.Phase(PhaseNum: Integer): TGrispStrategyBuilder;
var
  Strategy: TGrispStrategy;
begin
  Strategy := TGrispStrategy.Create(gskPhase);
  Strategy.Phase := PhaseNum;
  FStrategies.Add(Strategy);
  Debug(Format('Phase %d added (total strategies: %d)', [PhaseNum, FStrategies.Count]));
  DumpStrategyList('After Phase');
  Result := Self;
end;

function TGrispStrategyBuilder.Add(const Strategy: TGrispStrategy): TGrispStrategyBuilder;
begin
  FStrategies.Add(Strategy);
  Debug(Format('Strategy added (total strategies: %d)', [FStrategies.Count]));
  DumpStrategyList('After Add');
  Result := Self;
end;

function TGrispStrategyBuilder.Build: TGrispStrategy;
var
  i: Integer;
  Current, Parent: TGrispStrategy;
  Stack: TList<TGrispStrategy>;
begin
  Debug('=== BUILD START ===');
  DumpStrategyList('Before Build');

  if FStrategies.Count = 0 then
  begin
    Debug('ERROR: No strategies to build');
    raise Exception.Create('No strategies to build');
  end;

  Debug(Format('Cloning first strategy (index 0):', []));
  DebugStrategy('  Source', FStrategies[0]);
  Result := FStrategies[0].Clone;
  DebugStrategy('  Cloned', Result);

  Stack := TList<TGrispStrategy>.Create;
  try
    Stack.Add(Result);
    DebugStack(Stack, 'After adding root');

    Debug(Format('Processing %d remaining strategies...', [FStrategies.Count - 1]));

    for i := 1 to FStrategies.Count - 1 do
    begin
      Debug(Format('--- Loop iteration %d ---', [i]));
      Current := FStrategies[i];
      DebugStrategy('Current strategy', Current);

      DebugStack(Stack, 'Before accessing parent');

      // CRITICAL: This is where the crash happens if Stack is empty
      if Stack.Count = 0 then
      begin
        Debug('!!! CRITICAL ERROR: Stack is empty! Cannot get parent. !!!');
        Debug('This is the cause of the "List index out of bounds (-1)" crash');
        raise Exception.Create('Stack underflow - no parent available');
      end;

      Parent := Stack[Stack.Count - 1];
      DebugStrategy('Parent strategy', Parent);

      Debug(Format('Current.Kind = %s', [GetEnumName(TypeInfo(TGrispStrategyKind), Ord(Current.Kind))]));

      if Current.Kind in [gskSequence, gskRepeat, gskTry, gskChoice, gskPhase] then
      begin
        Debug('  Current is composite - adding as child and pushing to stack');
        var ClonedCurrent := Current.Clone;
        Parent.Strategies.Add(ClonedCurrent);
        Stack.Add(ClonedCurrent);
        Debug(Format('  Added composite to parent. Parent now has %d children', [Parent.Strategies.Count]));
        DebugStack(Stack, 'After push');
      end
      else
      begin
        Debug('  Current is leaf (Rule) - adding as child');
        Parent.Strategies.Add(Current.Clone);
        Debug(Format('  Added leaf to parent. Parent now has %d children', [Parent.Strategies.Count]));

        Debug('  Popping stack while top has children...');
        while (Stack.Count > 0) and (Stack[Stack.Count - 1].Strategies.Count > 0) do
        begin
          Debug(Format('    Popping: Stack[%d] (has %d children)',
            [Stack.Count - 1, Stack[Stack.Count - 1].Strategies.Count]));
          Stack.Delete(Stack.Count - 1);
          DebugStack(Stack, 'After pop');
        end;

        if Stack.Count = 0 then
          Debug('  WARNING: Stack is now empty! Next iteration will crash!');
      end;
    end;

    Debug('=== BUILD SUCCESSFUL ===');
    DebugStrategy('Final result', Result);

  finally
    Debug('Cleaning up stack');
    Stack.Free;
  end;
end;

end.
