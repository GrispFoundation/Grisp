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
    procedure DebugEnter(const Method: string);
    procedure DebugExit(const Method: string);
    procedure DumpStrategyList(const Prefix: string);
    procedure DumpStrategy(Strategy: TGrispStrategy; Indent: Integer = 0);
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
  Debug('=== Fixed StrategyBuilder DEBUG ENABLED ===');
end;

procedure TGrispStrategyBuilder.DisableDebug;
begin
  Debug('=== Fixed StrategyBuilder DEBUG DISABLED ===');
  FDebugEnabled := False;
end;

procedure TGrispStrategyBuilder.Debug(const Msg: string);
begin
  if FDebugEnabled then
    TGrispDebug.Log('[FixedBuilder] ' + Msg);
end;

procedure TGrispStrategyBuilder.DebugEnter(const Method: string);
begin
  if FDebugEnabled then
    TGrispDebug.LogEnter('[FixedBuilder] ' + Method);
end;

procedure TGrispStrategyBuilder.DebugExit(const Method: string);
begin
  if FDebugEnabled then
    TGrispDebug.LogExit('[FixedBuilder] ' + Method);
end;

procedure TGrispStrategyBuilder.DumpStrategy(Strategy: TGrispStrategy; Indent: Integer = 0);
var
  i: Integer;
  IndentStr: string;
begin
  if not FDebugEnabled then Exit;

  IndentStr := StringOfChar(' ', Indent * 2);
  case Strategy.Kind of
    gskRule:
      Debug(Format('%sRule: %s', [IndentStr, Strategy.RuleName]));
    gskSequence:
      begin
        Debug(Format('%sSequence (%d children)', [IndentStr, Strategy.Strategies.Count]));
        for i := 0 to Strategy.Strategies.Count - 1 do
          DumpStrategy(Strategy.Strategies[i], Indent + 1);
      end;
    gskRepeat:
      begin
        Debug(Format('%sRepeat (%d children)', [IndentStr, Strategy.Strategies.Count]));
        for i := 0 to Strategy.Strategies.Count - 1 do
          DumpStrategy(Strategy.Strategies[i], Indent + 1);
      end;
    gskTry:
      begin
        Debug(Format('%sTry (%d children)', [IndentStr, Strategy.Strategies.Count]));
        for i := 0 to Strategy.Strategies.Count - 1 do
          DumpStrategy(Strategy.Strategies[i], Indent + 1);
      end;
    gskChoice:
      begin
        Debug(Format('%sChoice (%d children)', [IndentStr, Strategy.Strategies.Count]));
        for i := 0 to Strategy.Strategies.Count - 1 do
          DumpStrategy(Strategy.Strategies[i], Indent + 1);
      end;
    gskPhase:
      begin
        Debug(Format('%sPhase %d (%d children)', [IndentStr, Strategy.Phase, Strategy.Strategies.Count]));
        for i := 0 to Strategy.Strategies.Count - 1 do
          DumpStrategy(Strategy.Strategies[i], Indent + 1);
      end;
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
      DumpStrategy(S, 1)
    else
      Debug(Format('  [%d] NIL', [i]));
  end;
end;

procedure TGrispStrategyBuilder.Clear;
begin
  DebugEnter('Clear');
  for var S in FStrategies do
    S.Free;
  FStrategies.Clear;
  DumpStrategyList('After Clear');
  DebugExit('Clear');
end;

function TGrispStrategyBuilder.Rule(const RuleName: string): TGrispStrategyBuilder;
var
  Strategy: TGrispStrategy;
begin
  DebugEnter('Rule');
  Debug(Format('Adding rule: %s', [RuleName]));
  Strategy := TGrispStrategy.Create(gskRule);
  Strategy.RuleName := RuleName;
  FStrategies.Add(Strategy);
  DumpStrategyList('After Rule');
  DebugExit('Rule');
  Result := Self;
end;

function TGrispStrategyBuilder.Sequence: TGrispStrategyBuilder;
begin
  DebugEnter('Sequence');
  Debug('Adding sequence');
  FStrategies.Add(TGrispStrategy.Create(gskSequence));
  DumpStrategyList('After Sequence');
  DebugExit('Sequence');
  Result := Self;
end;

function TGrispStrategyBuilder.RepeatStrategy: TGrispStrategyBuilder;
var
  LastIdx: Integer;
  Last: TGrispStrategy;
  Wrapper: TGrispStrategy;
begin
  DebugEnter('RepeatStrategy');

  if FStrategies.Count = 0 then
  begin
    Debug('ERROR: RepeatStrategy requires a preceding strategy');
    raise Exception.Create('RepeatStrategy requires a preceding strategy');
  end;

  LastIdx := FStrategies.Count - 1;
  Last := FStrategies[LastIdx];
  Debug(Format('Wrapping strategy at index %d: %s', [LastIdx,
    GetEnumName(TypeInfo(TGrispStrategyKind), Ord(Last.Kind))]));

  Wrapper := TGrispStrategy.Create(gskRepeat);
  Wrapper.Strategies.Add(Last);

  FStrategies[LastIdx] := Wrapper;
  Debug('Created Repeat wrapper and replaced original');
  DumpStrategyList('After RepeatStrategy');

  DebugExit('RepeatStrategy');
  Result := Self;
end;

function TGrispStrategyBuilder.TryStrategy: TGrispStrategyBuilder;
var
  LastIdx: Integer;
  Last: TGrispStrategy;
  Wrapper: TGrispStrategy;
begin
  DebugEnter('TryStrategy');

  if FStrategies.Count = 0 then
  begin
    Debug('ERROR: TryStrategy requires a preceding strategy');
    raise Exception.Create('TryStrategy requires a preceding strategy');
  end;

  LastIdx := FStrategies.Count - 1;
  Last := FStrategies[LastIdx];
  Debug(Format('Wrapping strategy at index %d: %s', [LastIdx,
    GetEnumName(TypeInfo(TGrispStrategyKind), Ord(Last.Kind))]));

  Wrapper := TGrispStrategy.Create(gskTry);
  Wrapper.Strategies.Add(Last);

  FStrategies[LastIdx] := Wrapper;
  Debug('Created Try wrapper and replaced original');
  DumpStrategyList('After TryStrategy');

  DebugExit('TryStrategy');
  Result := Self;
end;

function TGrispStrategyBuilder.Choice: TGrispStrategyBuilder;
var
  LastIdx: Integer;
  Last: TGrispStrategy;
  Wrapper: TGrispStrategy;
begin
  DebugEnter('Choice');

  if FStrategies.Count = 0 then
  begin
    Debug('ERROR: Choice requires a preceding strategy');
    raise Exception.Create('Choice requires a preceding strategy');
  end;

  LastIdx := FStrategies.Count - 1;
  Last := FStrategies[LastIdx];
  Debug(Format('Wrapping strategy at index %d: %s', [LastIdx,
    GetEnumName(TypeInfo(TGrispStrategyKind), Ord(Last.Kind))]));

  Wrapper := TGrispStrategy.Create(gskChoice);
  Wrapper.Strategies.Add(Last);

  FStrategies[LastIdx] := Wrapper;
  Debug('Created Choice wrapper and replaced original');
  DumpStrategyList('After Choice');

  DebugExit('Choice');
  Result := Self;
end;

function TGrispStrategyBuilder.Phase(PhaseNum: Integer): TGrispStrategyBuilder;
var
  LastIdx: Integer;
  Last: TGrispStrategy;
  Wrapper: TGrispStrategy;
begin
  DebugEnter('Phase');
  Debug(Format('Phase number: %d', [PhaseNum]));

  if FStrategies.Count = 0 then
  begin
    Debug('ERROR: Phase requires a preceding strategy');
    raise Exception.Create('Phase requires a preceding strategy');
  end;

  LastIdx := FStrategies.Count - 1;
  Last := FStrategies[LastIdx];
  Debug(Format('Wrapping strategy at index %d: %s', [LastIdx,
    GetEnumName(TypeInfo(TGrispStrategyKind), Ord(Last.Kind))]));

  Wrapper := TGrispStrategy.Create(gskPhase);
  Wrapper.Phase := PhaseNum;
  Wrapper.Strategies.Add(Last);

  FStrategies[LastIdx] := Wrapper;
  Debug('Created Phase wrapper and replaced original');
  DumpStrategyList('After Phase');

  DebugExit('Phase');
  Result := Self;
end;

function TGrispStrategyBuilder.Build: TGrispStrategy;
begin
  DebugEnter('Build');
  DumpStrategyList('Before Build');

  if FStrategies.Count = 0 then
  begin
    Debug('ERROR: No strategies to build');
    raise Exception.Create('No strategies to build');
  end;

  if FStrategies.Count = 1 then
  begin
    Result := FStrategies[0];
    Debug(Format('Single strategy result: %s', [
      GetEnumName(TypeInfo(TGrispStrategyKind), Ord(Result.Kind))]));
    FStrategies.Clear;
  end
  else
  begin
    Debug(Format('Multiple strategies (%d) - wrapping in Sequence', [FStrategies.Count]));
    Result := TGrispStrategy.Create(gskSequence);
    for var S in FStrategies do
      Result.Strategies.Add(S);
    FStrategies.Clear;
    Debug('Created Sequence with all strategies');
  end;

  Debug('Final strategy tree:');
  DumpStrategy(Result, 1);

  DebugExit('Build');
end;

end.
