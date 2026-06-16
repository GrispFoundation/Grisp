unit Grisp.Runtime.Engine;

interface

uses
  System.Generics.Collections,
  Grisp.Core.Types,
  Grisp.Core.Counters,
  Grisp.Core.Ordering,
  Grisp.Core.Graph,      // provides GetIncidentEdgesSorted etc.
  Grisp.Core.Expr,       // provides TEnv, EvalExpr
  Grisp.IR.AST;          // provides TRule, TIRRoot

type
  // MatchKey as defined in §2.6 – serialized to canonical JSON for ordering
  TMatchKey = record
    RuleId: UTF8String;
    BindingsJson: UTF8String;   // Canonical JSON of (rule_id, bindings)
  end;

  // A single match from DISCOVER
  TMatch = record
    Key: TMatchKey;
    Age: Int64;
    Rule: TRule;
    Bindings: TEnv;              // variable -> value (only pattern bindings)
    LetValues: TEnv;             // let bindings evaluated (diagnostic)
    ReadTrace: TReadSet;         // see below
  end;

  // Read set elements – each is a tagged union of possible reads
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

  // Primitive actions produced by PLAN (ordered sequence)
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

  // Main engine state
  TEngine = record
    IR: TIRRoot;
    State: TState;    // defined below
    // Internal fields for current tick (not persisted across ticks)
    CurrentMatches: TArray<TMatch>;
    SelectedMatch: TMatch;
    PlannedTrace: TPrimitiveActionList;
    PlannedReadSet: TReadSet;
  end;

  TState = record
    G: TGraph;
    C: TCounters;
    T: Int64;               // current tick number
    MPrev: TDictionary<TMatchKey, Int64>;  // age map
  end;

// SOS transitions
procedure DoTick(var Engine: TEngine);   // Rule 1
procedure Discover(var Engine: TEngine); // Rule 2
function Select(var Engine: TEngine): Boolean;  // Rule 3, returns False if no match
procedure Plan(var Engine: TEngine);     // Rule 4
function Commit(var Engine: TEngine): Boolean; // Rule 5, returns False if match discarded (non‑fatal)
function Step(var Engine: TEngine): Boolean;   // Executes one full tick; returns False on fatal error

// Helper functions
function ComputeAge(const Key: TMatchKey; const MPrev: TDictionary<TMatchKey, Int64>): Int64;
function Score(const Match: TMatch): Int64;   // uses rule priorities and age
function ValidateReadSet(const ReadSet: TReadSet; const BeforeState: TState): Boolean;
function ApplyTrace(const Trace: TPrimitiveActionList; var G: TGraph; var C: TCounters): Boolean;
function WouldAnyCounterOverflow(const Trace: TPrimitiveActionList; const C: TCounters): Boolean;

implementation

end.
