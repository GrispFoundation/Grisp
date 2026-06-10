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
    FRoot: TGrispStrategy;
    FCurrentParent: TGrispStrategy;
    FScopeStack: TStack<TGrispStrategy>;
    FDebugEnabled: Boolean;

    procedure Debug(const Msg: string);
    procedure DebugEnter(const Method: string);
    procedure DebugExit(const Method: string);
    procedure DumpStrategy(Strategy: TGrispStrategy; Indent: Integer = 0);
    procedure DumpState(const Prefix: string);

    procedure AddStrategy(Strategy: TGrispStrategy);
	procedure WrapLastStrategy(Kind: TGrispStrategyKind; PhaseNum: Integer = 0);
  public
    constructor Create;
    destructor Destroy; override;

    procedure EnableDebug;
    procedure DisableDebug;

    function Rule(const RuleName: string): TGrispStrategyBuilder;
    function Sequence: TGrispStrategyBuilder;
    function EndScope: TGrispStrategyBuilder;
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
  FRoot := nil;
  FCurrentParent := nil;
  FScopeStack := TStack<TGrispStrategy>.Create;
  FDebugEnabled := False;
end;

destructor TGrispStrategyBuilder.Destroy;
begin
  Clear;
  FScopeStack.Free;
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

procedure TGrispStrategyBuilder.DumpState(const Prefix: string);
begin
  if not FDebugEnabled then Exit;
  Debug(Format('%s Root: %s, CurrentParent: %s, ScopeStack depth: %d', [
    Prefix,
    BoolToStr(FRoot <> nil, True),
    BoolToStr(FCurrentParent <> nil, True),
    FScopeStack.Count
  ]));
  if FRoot <> nil then
    DumpStrategy(FRoot, 1);
end;

procedure TGrispStrategyBuilder.Clear;
begin
  DebugEnter('Clear');
  FRoot.Free;
  FRoot := nil;
  FCurrentParent := nil;
  FScopeStack.Clear;
  DumpState('After Clear');
  DebugExit('Clear');
end;

procedure TGrispStrategyBuilder.AddStrategy(Strategy: TGrispStrategy);
begin
  if FRoot = nil then
  begin
    FRoot := Strategy;
    FCurrentParent := Strategy;
    Debug('Added as root');
  end
  else if (FRoot.Kind = gskRule) and (FCurrentParent = FRoot) then
  begin
    // Multiple root rules - wrap in sequence
    Debug('Multiple root rules detected - wrapping in sequence');
    var NewSequence := TGrispStrategy.Create(gskSequence);
    NewSequence.Strategies.Add(FRoot);
    NewSequence.Strategies.Add(Strategy);
    FRoot := NewSequence;
    FCurrentParent := NewSequence;
    Debug('Created sequence with both rules');
  end
  else if FCurrentParent <> nil then
  begin
    FCurrentParent.Strategies.Add(Strategy);
    Debug(Format('Added to parent %s', [GetEnumName(TypeInfo(TGrispStrategyKind), Ord(FCurrentParent.Kind))]));
  end
  else
  begin
    Debug('ERROR: No current parent for strategy');
    Strategy.Free;
    raise Exception.Create('No current parent for strategy');
  end;
end;

procedure TGrispStrategyBuilder.WrapLastStrategy(Kind: TGrispStrategyKind; PhaseNum: Integer = 0);
var
  Last: TGrispStrategy;
  Wrapper: TGrispStrategy;
begin
  Debug(Format('Wrapping last strategy with %s', [GetEnumName(TypeInfo(TGrispStrategyKind), Ord(Kind))]));

  if FRoot = nil then
  begin
    case Kind of
      gskRepeat:
        raise Exception.Create('RepeatStrategy requires a preceding strategy');
      gskTry:
        raise Exception.Create('TryStrategy requires a preceding strategy');
      gskChoice:
        raise Exception.Create('Choice requires a preceding strategy');
      gskPhase:
        raise Exception.Create('Phase requires a preceding strategy');
    else
      raise Exception.Create('No strategy to wrap');
    end;
  end;

  // If current parent has children, wrap the last child
  if (FCurrentParent <> nil) and (FCurrentParent.Strategies.Count > 0) then
  begin
    Last := FCurrentParent.Strategies.Last;
    Debug(Format('Wrapping child strategy: %s', [GetEnumName(TypeInfo(TGrispStrategyKind), Ord(Last.Kind))]));

    Wrapper := TGrispStrategy.Create(Kind);
    if Kind = gskPhase then
      Wrapper.Phase := PhaseNum;
    Wrapper.Strategies.Add(Last);

    FCurrentParent.Strategies.Delete(FCurrentParent.Strategies.Count - 1);
    FCurrentParent.Strategies.Add(Wrapper);
    Debug('Created wrapper and replaced child');
  end
  // Otherwise, wrap the root itself
  else if FRoot <> nil then
  begin
    Debug('Wrapping root strategy');
    Last := FRoot;
    Debug(Format('Root strategy: %s', [GetEnumName(TypeInfo(TGrispStrategyKind), Ord(Last.Kind))]));

    Wrapper := TGrispStrategy.Create(Kind);
    if Kind = gskPhase then
      Wrapper.Phase := PhaseNum;
    Wrapper.Strategies.Add(Last);

    FRoot := Wrapper;
    FCurrentParent := Wrapper;
    Debug('Created wrapper and replaced root');
  end
  else
  begin
    // This case should never be reached because FRoot is checked above
    raise Exception.Create('No strategy to wrap');
  end;
end;

function TGrispStrategyBuilder.Rule(const RuleName: string): TGrispStrategyBuilder;
var
  Strategy: TGrispStrategy;
begin
  DebugEnter('Rule');
  Debug(Format('Adding rule: %s', [RuleName]));
  Strategy := TGrispStrategy.Create(gskRule);
  Strategy.RuleName := RuleName;
  AddStrategy(Strategy);
  DumpState('After Rule');
  DebugExit('Rule');
  Result := Self;
end;

function TGrispStrategyBuilder.Sequence: TGrispStrategyBuilder;
var
  Strategy: TGrispStrategy;
begin
  DebugEnter('Sequence');
  Debug('Adding sequence - opening new scope');

  Strategy := TGrispStrategy.Create(gskSequence);

  FScopeStack.Push(FCurrentParent);

  if FRoot = nil then
  begin
    FRoot := Strategy;
    FCurrentParent := Strategy;
    Debug('Sequence is root');
  end
  else if FCurrentParent <> nil then
  begin
    FCurrentParent.Strategies.Add(Strategy);
    FCurrentParent := Strategy;
    Debug('Sequence added as child and becomes current parent');
  end
  else
  begin
    Debug('ERROR: Cannot add sequence - no context');
    Strategy.Free;
    raise Exception.Create('Cannot add sequence - no context');
  end;

  DumpState('After Sequence');
  DebugExit('Sequence');
  Result := Self;
end;

function TGrispStrategyBuilder.EndScope: TGrispStrategyBuilder;
begin
  DebugEnter('EndScope');

  if FScopeStack.Count = 0 then
  begin
    Debug('ERROR: EndScope called with no open scope');
    raise Exception.Create('EndScope called with no open scope');
  end;

  FCurrentParent := FScopeStack.Pop;
  Debug('Closed scope');
  DumpState('After EndScope');
  DebugExit('EndScope');
  Result := Self;
end;

function TGrispStrategyBuilder.RepeatStrategy: TGrispStrategyBuilder;
begin
  DebugEnter('RepeatStrategy');
  WrapLastStrategy(gskRepeat);
  DumpState('After RepeatStrategy');
  DebugExit('RepeatStrategy');
  Result := Self;
end;

function TGrispStrategyBuilder.TryStrategy: TGrispStrategyBuilder;
begin
  DebugEnter('TryStrategy');
  WrapLastStrategy(gskTry);
  DumpState('After TryStrategy');
  DebugExit('TryStrategy');
  Result := Self;
end;

function TGrispStrategyBuilder.Choice: TGrispStrategyBuilder;
begin
  DebugEnter('Choice');
  WrapLastStrategy(gskChoice);
  DumpState('After Choice');
  DebugExit('Choice');
  Result := Self;
end;

function TGrispStrategyBuilder.Phase(PhaseNum: Integer): TGrispStrategyBuilder;
begin
  DebugEnter('Phase');
  Debug(Format('Phase number: %d', [PhaseNum]));
  WrapLastStrategy(gskPhase, PhaseNum);
  DumpState('After Phase');
  DebugExit('Phase');
  Result := Self;
end;

function TGrispStrategyBuilder.Build: TGrispStrategy;
begin
  DebugEnter('Build');
  DumpState('Before Build');

  if FRoot = nil then
  begin
	Debug('ERROR: No strategies to build');
	raise Exception.Create('No strategies to build');
  end;

  if FScopeStack.Count > 0 then
  begin
    Debug('WARNING: Unclosed scopes exist');
	while FScopeStack.Count > 0 do
	  EndScope;
  end;

  Result := FRoot;
  FRoot := nil;
  FCurrentParent := nil;
  FScopeStack.Clear;

  Debug('Final strategy tree:');
  DumpStrategy(Result, 1);

  DebugExit('Build');
end;

end.
