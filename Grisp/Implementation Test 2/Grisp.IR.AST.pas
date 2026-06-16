unit Grisp.Runtime.Engine;

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  Grisp.Core.Types,
  Grisp.Core.Counters,
  Grisp.Core.Ordering,
  Grisp.Core.Graph,
  Grisp.Core.Expr,
  Grisp.IR.AST;

type
  TMatchKey = record
    RuleId: UTF8String;
    BindingsJson: UTF8String;
  end;

  TMatch = record
    Key: TMatchKey;
    Age: Int64;
    Rule: TRule;
    Bindings: TEnv;
    LetValues: TEnv;
    ReadTrace: TReadSet;
  end;

  TReadKind = (rkNodeExistence, rkFieldRead, rkEdgeExistence, rkAdjacency,
               rkExtent, rkEdgeType, rkPredicateVersion, rkOrderingVersion,
               rkEdgePredicateVersion, rkEdgeOrderingVersion);

  TReadEntry = record
    Kind: TReadKind;
    case Byte of
      0: (Node: TNodeId);
      1: (NodeField: record Node: TNodeId; Field: UTF8String end);
      2: (Edge: TEdgeId);
      3: (Adjacency: record Node: TNodeId; Edge: TEdgeId; IsOutgoing: Boolean end);
      4: (ExtentType: UTF8String);
      5: (EdgeTypeName: UTF8String);
      6: (Predicate: record Typ: UTF8String; Field: UTF8String end);
      7: (Ordering: record Typ: UTF8String; Field: UTF8String end);
      8: (EdgePredicate: record Typ: UTF8String; Field: UTF8String end);
      9: (EdgeOrdering: record Typ: UTF8String; Field: UTF8String end);
  end;

  TReadSet = TArray<TReadEntry>;

  TPrimitiveActionKind = (pakCreateNode, pakCreateEdge, pakUpdateFieldNode,
                          pakUpdateFieldEdge, pakDeleteEdge, pakDeleteNode,
                          pakEmitEvent);

  TPrimitiveAction = record
    Kind: TPrimitiveActionKind;
    case Byte of
      0: (CreateNode: record VarName: UTF8String; NodeType: UTF8String; Fields: TFieldMap end);
      1: (CreateEdge: record VarName: UTF8String; EdgeType: UTF8String; Src, Tgt: TValue; Fields: TFieldMap end);
      2: (UpdateFieldNode: record NodeId: TNodeId; Field: UTF8String; NewValue: TValue end);
      3: (UpdateFieldEdge: record EdgeId: TEdgeId; Field: UTF8String; NewValue: TValue end);
      4: (DeleteEdgeId: TEdgeId);
      5: (DeleteNodeId: TNodeId);
      6: (EmitEvent: record EventType: UTF8String; Payload: TArray<TValue> end);
  end;

  TPrimitiveActionList = TArray<TPrimitiveAction>;

  TState = record
    G: TGraph;
    C: TCounters;
	T: Int64;
    MPrev: TDictionary<TMatchKey, Int64>;
  end;

  TEngine = record
    IR: TIRRoot;
    State: TState;
    CurrentMatches: TArray<TMatch>;
    SelectedMatch: TMatch;
    PlannedTrace: TPrimitiveActionList;
    PlannedReadSet: TReadSet;
  end;

procedure DoTick(var Engine: TEngine);
procedure Discover(var Engine: TEngine);
function Select(var Engine: TEngine): Boolean;
procedure Plan(var Engine: TEngine);
function Commit(var Engine: TEngine): Boolean;
function Step(var Engine: TEngine): Boolean;

function ComputeAge(const Key: TMatchKey; const MPrev: TDictionary<TMatchKey, Int64>): Int64;
function Score(const Match: TMatch): Int64;
function ValidateReadSet(const ReadSet: TReadSet; const BeforeState: TState): Boolean;
function ApplyTrace(const Trace: TPrimitiveActionList; var G: TGraph; var C: TCounters): Boolean;
function WouldAnyCounterOverflow(const Trace: TPrimitiveActionList; const C: TCounters): Boolean;

implementation

function ComputeAge(const Key: TMatchKey; const MPrev: TDictionary<TMatchKey, Int64>): Int64;
var
  OldAge: Int64;
begin
  if MPrev.TryGetValue(Key, OldAge) then
  begin
    if OldAge = High(Int64) then
      RaiseCounterOverflow;
    Result := OldAge + 1;
  end
  else
    Result := 0;
end;

function Score(const Match: TMatch): Int64;
begin
  Result := CheckedAdd(
    CheckedMul(Match.Rule.BasePriority, Match.Rule.PriorityScale),
    CheckedMul(Match.Age, Match.Rule.FairnessScale));
end;

function ValidateReadSet(const ReadSet: TReadSet; const BeforeState: TState): Boolean;
begin
  // Stub – always true for now
  Result := True;
end;

function ApplyTrace(const Trace: TPrimitiveActionList; var G: TGraph; var C: TCounters): Boolean;
begin
  // Stub – no mutation
  Result := True;
end;

function WouldAnyCounterOverflow(const Trace: TPrimitiveActionList; const C: TCounters): Boolean;
begin
  // Stub – always false
  Result := False;
end;

procedure DoTick(var Engine: TEngine);
begin
  if not CheckedInc(Engine.State.C.TickCounter) then
    RaiseCounterOverflow;
  Inc(Engine.State.T);
end;

procedure Discover(var Engine: TEngine);
begin
  // Stub – empty match set
  SetLength(Engine.CurrentMatches, 0);
end;

function Select(var Engine: TEngine): Boolean;
begin
  Result := Length(Engine.CurrentMatches) > 0;
  if Result then
    Engine.SelectedMatch := Engine.CurrentMatches[0];
end;

procedure Plan(var Engine: TEngine);
begin
  // Stub – empty trace
  SetLength(Engine.PlannedTrace, 0);
  SetLength(Engine.PlannedReadSet, 0);
end;

function Commit(var Engine: TEngine): Boolean;
begin
  if not ValidateReadSet(Engine.PlannedReadSet, Engine.State) then
    Exit(False);
  if WouldAnyCounterOverflow(Engine.PlannedTrace, Engine.State.C) then
    RaiseCounterOverflow;
  if not ApplyTrace(Engine.PlannedTrace, Engine.State.G, Engine.State.C) then
    Exit(False);
  // Update MPrev with all current matches
  var NewMPrev := TDictionary<TMatchKey, Int64>.Create;
  for var m in Engine.CurrentMatches do
    NewMPrev.Add(m.Key, m.Age);
  Engine.State.MPrev.Free;
  Engine.State.MPrev := NewMPrev;
  Result := True;
end;

function Step(var Engine: TEngine): Boolean;
begin
  try
    DoTick(Engine);
    Discover(Engine);
    if not Select(Engine) then
      Exit(True);
    Plan(Engine);
    if not Commit(Engine) then
      Exit(True);
    Result := True;
  except
    on E: Exception do
    begin
      // Fatal error – re-raise for runner to catch
      raise;
    end;
  end;
end;

end.
