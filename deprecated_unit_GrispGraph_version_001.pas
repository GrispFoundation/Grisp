unit unit_GrispGraph_version_001;

interface

uses
  System.SysUtils,
  System.Math,
  System.Generics.Collections;

type
  TGrispValueKind = (
    gvkNumber,
    gvkString,
    gvkBoolean,
    gvkIdentifier,
    gvkArray,
    gvkNode,
    gvkExpression
  );

  TGrispNode = class;
  TGrispType = class;

  TGrispExpressionKind = (
    gekLiteral,
    gekVariable,
    gekUnary,
    gekBinary,
    gekCall
  );

  TGrispExpression = class
  public
    Kind: TGrispExpressionKind;
    Value: TObject; // TGrispValue
    Name: string;
    OperatorSymbol: string;
    Left: TGrispExpression;
    Right: TGrispExpression;
    Arguments: TObjectList<TGrispExpression>;
    constructor Create(AKind: TGrispExpressionKind);
    destructor Destroy; override;
    function Clone: TGrispExpression;
  end;

  TGrispValue = class
  public
    Kind: TGrispValueKind;
    NumberValue: Double;
    StringValue: string;
    BoolValue: Boolean;
    IdentifierValue: string;
    ArrayValue: TObjectList<TGrispValue>;
    NodeValue: TGrispNode;
    ExpressionValue: TGrispExpression;
    constructor Create(AKind: TGrispValueKind);
    destructor Destroy; override;
    function Clone: TGrispValue;
    function ToString: string; override;
  end;

  TGrispTypeKind = (
    gtkNumber,
    gtkString,
    gtkBoolean,
    gtkIdentifier,
    gtkNode,
    gtkArray,
    gtkNil
  );

  TGrispType = class
  public
    Kind: TGrispTypeKind;
    ElementType: TGrispType;
    NodeTypeName: string;
    constructor Create(AKind: TGrispTypeKind);
    destructor Destroy; override;
    function Matches(Value: TGrispValue): Boolean;
    function ToString: string; override;
  end;

  TGrispExpressionEvaluator = class
  private
    class function EvaluateLiteral(Expression: TGrispExpression): TGrispValue; static;
    class function EvaluateVariable(Expression: TGrispExpression; Bindings: TDictionary<string, TGrispValue>): TGrispValue; static;
    class function EvaluateUnary(Expression: TGrispExpression; Bindings: TDictionary<string, TGrispValue>): TGrispValue; static;
    class function EvaluateBinary(Expression: TGrispExpression; Bindings: TDictionary<string, TGrispValue>): TGrispValue; static;
    class function EvaluateCall(Expression: TGrispExpression; Bindings: TDictionary<string, TGrispValue>): TGrispValue; static;
    class function RequireNumber(Value: TGrispValue; const Context: string): Double; static;
    class function RequireBoolean(Value: TGrispValue; const Context: string): Boolean; static;
    class procedure EnsureArgumentCount(Expression: TGrispExpression; Expected: Integer); static;
  public
    class function Evaluate(Expression: TGrispExpression; Bindings: TDictionary<string, TGrispValue>): TGrispValue;
  end;

  TGrispEdge = class
  public
    LabelName: string;
    EdgeType: string;
    Source: TGrispNode;
    Target: TGrispNode;
    constructor Create(ASource: TGrispNode; ATarget: TGrispNode; const ALabel: string; const AEdgeType: string);
  end;

  TGrispNode = class
  private
    FAttributes: TObjectDictionary<string, TGrispValue>;
    FOutgoing: TObjectList<TGrispEdge>;
    FIncoming: TObjectList<TGrispEdge>;
    FMarked: Boolean;
  public
    Id: Integer;
    Name: string;
    NodeType: string;
    constructor Create(AId: Integer; const AName: string; const ANodeType: string);
    destructor Destroy; override;

    // Attribute operations
    function GetAttribute(const Key: string): TGrispValue;
    procedure SetAttribute(const Key: string; AValue: TGrispValue);
    procedure RemoveAttribute(const Key: string);
    function HasAttribute(const Key: string): Boolean;
    function GetNumber(const Key: string; Default: Double = 0): Double;
    function GetIdentifier(const Key: string): string;

    // Edge operations
    property Outgoing: TObjectList<TGrispEdge> read FOutgoing;
    property Incoming: TObjectList<TGrispEdge> read FIncoming;

    // Mark and sweep support
    property Marked: Boolean read FMarked write FMarked;

    procedure AddOutgoingEdge(Edge: TGrispEdge);
    procedure AddIncomingEdge(Edge: TGrispEdge);
    procedure RemoveOutgoingEdge(Edge: TGrispEdge);
    procedure RemoveIncomingEdge(Edge: TGrispEdge);

    function ToString: string; override;
  end;

  TGrispGraph = class
  private
    FNextId: Integer;
    FNodes: TObjectList<TGrispNode>;
    FEdges: TObjectList<TGrispEdge>;
    FNodeIndex: TObjectDictionary<string, TGrispNode>;
    FRules: TObjectList<TGrispNode>;
    FTypes: TObjectDictionary<string, TGrispType>;
    FModified: Boolean;

    procedure MarkReachable(Node: TGrispNode);
    procedure SweepUnmarked;
  public
    constructor Create;
    destructor Destroy; override;

    // Node operations
    function AddNode(const AName: string; const ANodeType: string): TGrispNode;
    function FindNode(const AName: string): TGrispNode;
    procedure RemoveNode(Node: TGrispNode);
    procedure RemoveNodeByName(const AName: string);

    // Edge operations
    function AddEdge(ASource: TGrispNode; ATarget: TGrispNode; const ALabel: string; const AEdgeType: string = ''): TGrispEdge;
    procedure RemoveEdge(Edge: TGrispEdge);
    procedure RemoveEdgesBetween(Source, Target: TGrispNode; const ALabel: string = '');

    // Rule operations
    procedure RegisterRule(ANode: TGrispNode);
    property Rules: TObjectList<TGrispNode> read FRules;

    // Type operations
    procedure AddType(const Name: string; TypeObj: TGrispType);
    function FindType(const Name: string): TGrispType;
    property Types: TObjectDictionary<string, TGrispType> read FTypes;

    // Graph operations
    property Nodes: TObjectList<TGrispNode> read FNodes;
    property Edges: TObjectList<TGrispEdge> read FEdges;
    property NodeIndex: TObjectDictionary<string, TGrispNode> read FNodeIndex;

    // Maintenance
    procedure RegisterEdgesFromIdentifiers;
    procedure GarbageCollect;
    function GetNodesByType(const ANodeType: string): TArray<TGrispNode>;
    function GetNodesByAttribute(const Key: string; Value: TGrispValue): TList<TGrispNode>;

    // Export
    function ToDOT: string;
    function ToJSON: string;

    property Modified: Boolean read FModified write FModified;
  end;

implementation

{ TGrispExpression }

constructor TGrispExpression.Create(AKind: TGrispExpressionKind);
begin
  inherited Create;
  Kind := AKind;
  Arguments := TObjectList<TGrispExpression>.Create(True);
end;

destructor TGrispExpression.Destroy;
begin
  Arguments.Free;
  Left.Free;
  Right.Free;
  Value.Free;
  inherited Destroy;
end;

function TGrispExpression.Clone: TGrispExpression;
var Arg: TGrispExpression;
begin
  Result := TGrispExpression.Create(Kind);
  Result.Name := Name;
  Result.OperatorSymbol := OperatorSymbol;
  if Assigned(Value) then
    Result.Value := TGrispValue(Value).Clone;
  if Assigned(Left) then
    Result.Left := Left.Clone;
  if Assigned(Right) then
    Result.Right := Right.Clone;
  for Arg in Arguments do
    Result.Arguments.Add(Arg.Clone);
end;

{ TGrispValue }

constructor TGrispValue.Create(AKind: TGrispValueKind);
begin
  inherited Create;
  Kind := AKind;
  if Kind = gvkArray then
    ArrayValue := TObjectList<TGrispValue>.Create(True);
end;

destructor TGrispValue.Destroy;
begin
  ArrayValue.Free;
  ExpressionValue.Free;
  inherited Destroy;
end;

function TGrispValue.Clone: TGrispValue;
var E: TGrispValue;
begin
  Result := TGrispValue.Create(Kind);
  Result.NumberValue := NumberValue;
  Result.StringValue := StringValue;
  Result.BoolValue := BoolValue;
  Result.IdentifierValue := IdentifierValue;
  Result.NodeValue := NodeValue;
  if Kind = gvkArray then
    for E in ArrayValue do
      Result.ArrayValue.Add(E.Clone);
  if Kind = gvkExpression then
    if Assigned(ExpressionValue) then
      Result.ExpressionValue := ExpressionValue.Clone;
end;

function TGrispValue.ToString: string;
begin
  case Kind of
    gvkNumber: Result := FloatToStr(NumberValue);
    gvkString: Result := '"' + StringValue + '"';
    gvkBoolean: Result := BoolToStr(BoolValue, True);
    gvkIdentifier: Result := IdentifierValue;
    gvkArray: Result := '[...]';
    gvkNode:
      if Assigned(NodeValue) then
        Result := Format('node(%d:%s)', [NodeValue.Id, NodeValue.Name])
      else
        Result := 'node(nil)';
    gvkExpression: Result := '<expr>';
  else
    Result := 'nil';
  end;
end;

{ TGrispType }

constructor TGrispType.Create(AKind: TGrispTypeKind);
begin
  inherited Create;
  Kind := AKind;
  ElementType := nil;
  NodeTypeName := '';
end;

destructor TGrispType.Destroy;
begin
  ElementType.Free;
  inherited Destroy;
end;

function TGrispType.Matches(Value: TGrispValue): Boolean;
begin
  Result := False;
  if Value = nil then Exit;

  case Kind of
    gtkNumber: Result := Value.Kind = gvkNumber;
    gtkString: Result := Value.Kind = gvkString;
    gtkBoolean: Result := Value.Kind = gvkBoolean;
    gtkIdentifier: Result := Value.Kind = gvkIdentifier;
    gtkNil: Result := Value = nil;
    gtkNode:
      Result := (Value.Kind = gvkNode) and
                (Assigned(Value.NodeValue)) and
                ((NodeTypeName = '') or (Value.NodeValue.NodeType = NodeTypeName));
    gtkArray:
      begin
        if Value.Kind <> gvkArray then Exit;
        if ElementType = nil then
          Result := True
        else
        begin
          Result := True;
          for var E in Value.ArrayValue do
            if not ElementType.Matches(E) then
            begin
              Result := False;
              Break;
            end;
        end;
      end;
  end;
end;

function TGrispType.ToString: string;
begin
  case Kind of
    gtkNumber: Result := 'number';
    gtkString: Result := 'string';
    gtkBoolean: Result := 'boolean';
    gtkIdentifier: Result := 'identifier';
    gtkNil: Result := 'nil';
    gtkNode:
      if NodeTypeName <> '' then
        Result := 'node<' + NodeTypeName + '>'
      else
        Result := 'node';
    gtkArray:
      if ElementType <> nil then
        Result := 'array<' + ElementType.ToString + '>'
      else
        Result := 'array';
  end;
end;

{ TGrispExpressionEvaluator }

class function TGrispExpressionEvaluator.Evaluate(Expression: TGrispExpression; Bindings: TDictionary<string, TGrispValue>): TGrispValue;
begin
  if Expression = nil then Exit(nil);
  case Expression.Kind of
    gekLiteral: Result := EvaluateLiteral(Expression);
    gekVariable: Result := EvaluateVariable(Expression, Bindings);
    gekUnary: Result := EvaluateUnary(Expression, Bindings);
    gekBinary: Result := EvaluateBinary(Expression, Bindings);
    gekCall: Result := EvaluateCall(Expression, Bindings);
  else
    Result := nil;
  end;
end;

class function TGrispExpressionEvaluator.EvaluateLiteral(Expression: TGrispExpression): TGrispValue;
begin
  if Assigned(Expression.Value) then
    Result := TGrispValue(Expression.Value).Clone
  else
    Result := nil;
end;

class function TGrispExpressionEvaluator.EvaluateVariable(Expression: TGrispExpression; Bindings: TDictionary<string, TGrispValue>): TGrispValue;
var BoundValue: TGrispValue;
begin
  if not Assigned(Bindings) then
    raise Exception.Create('No variable bindings supplied');
  if Bindings.TryGetValue(Expression.Name, BoundValue) then
    Result := BoundValue.Clone
  else
    raise Exception.CreateFmt('Unbound variable "%s"', [Expression.Name]);
end;

class function TGrispExpressionEvaluator.EvaluateUnary(Expression: TGrispExpression; Bindings: TDictionary<string, TGrispValue>): TGrispValue;
var Operand: TGrispValue;
begin
  Operand := Evaluate(Expression.Left, Bindings);
  try
    if SameText(Expression.OperatorSymbol, 'not') then
    begin
      Result := TGrispValue.Create(gvkBoolean);
      Result.BoolValue := not RequireBoolean(Operand, 'not');
      Exit;
    end;
    if Expression.OperatorSymbol = '-' then
    begin
      Result := TGrispValue.Create(gvkNumber);
      Result.NumberValue := -RequireNumber(Operand, 'unary -');
      Exit;
    end;
    raise Exception.CreateFmt('Unknown unary operator "%s"', [Expression.OperatorSymbol]);
  finally
    Operand.Free;
  end;
end;

class function TGrispExpressionEvaluator.EvaluateBinary(Expression: TGrispExpression; Bindings: TDictionary<string, TGrispValue>): TGrispValue;
var LeftValue, RightValue: TGrispValue; RightNumber: Double; LeftBool, RightBool: Boolean;
begin
  LeftValue := Evaluate(Expression.Left, Bindings);
  RightValue := Evaluate(Expression.Right, Bindings);
  try
    if Expression.OperatorSymbol = '+' then
    begin
      Result := TGrispValue.Create(gvkNumber);
      Result.NumberValue := RequireNumber(LeftValue, '+') + RequireNumber(RightValue, '+');
      Exit;
    end;
    if Expression.OperatorSymbol = '-' then
    begin
      Result := TGrispValue.Create(gvkNumber);
      Result.NumberValue := RequireNumber(LeftValue, '-') - RequireNumber(RightValue, '-');
      Exit;
    end;
    if Expression.OperatorSymbol = '*' then
    begin
      Result := TGrispValue.Create(gvkNumber);
      Result.NumberValue := RequireNumber(LeftValue, '*') * RequireNumber(RightValue, '*');
      Exit;
    end;
    if Expression.OperatorSymbol = '/' then
    begin
      RightNumber := RequireNumber(RightValue, '/');
      if RightNumber = 0 then raise Exception.Create('Division by zero');
      Result := TGrispValue.Create(gvkNumber);
      Result.NumberValue := RequireNumber(LeftValue, '/') / RightNumber;
      Exit;
    end;
    if SameText(Expression.OperatorSymbol, 'mod') then
    begin
      Result := TGrispValue.Create(gvkNumber);
      Result.NumberValue := Trunc(RequireNumber(LeftValue, 'mod')) mod Trunc(RequireNumber(RightValue, 'mod'));
      Exit;
    end;
    if Expression.OperatorSymbol = '=' then
    begin
      Result := TGrispValue.Create(gvkBoolean);
      Result.BoolValue := RequireNumber(LeftValue, '=') = RequireNumber(RightValue, '=');
      Exit;
    end;
    if Expression.OperatorSymbol = '<>' then
    begin
      Result := TGrispValue.Create(gvkBoolean);
      Result.BoolValue := RequireNumber(LeftValue, '<>') <> RequireNumber(RightValue, '<>');
      Exit;
    end;
    if Expression.OperatorSymbol = '<' then
    begin
      Result := TGrispValue.Create(gvkBoolean);
      Result.BoolValue := RequireNumber(LeftValue, '<') < RequireNumber(RightValue, '<');
      Exit;
    end;
    if Expression.OperatorSymbol = '>' then
    begin
      Result := TGrispValue.Create(gvkBoolean);
      Result.BoolValue := RequireNumber(LeftValue, '>') > RequireNumber(RightValue, '>');
      Exit;
    end;
    if Expression.OperatorSymbol = '<=' then
    begin
      Result := TGrispValue.Create(gvkBoolean);
      Result.BoolValue := RequireNumber(LeftValue, '<=') <= RequireNumber(RightValue, '<=');
      Exit;
    end;
    if Expression.OperatorSymbol = '>=' then
    begin
      Result := TGrispValue.Create(gvkBoolean);
      Result.BoolValue := RequireNumber(LeftValue, '>=') >= RequireNumber(RightValue, '>=');
      Exit;
    end;
    if SameText(Expression.OperatorSymbol, 'and') then
    begin
      LeftBool := RequireBoolean(LeftValue, 'and');
      RightBool := RequireBoolean(RightValue, 'and');
      Result := TGrispValue.Create(gvkBoolean);
      Result.BoolValue := LeftBool and RightBool;
      Exit;
    end;
    if SameText(Expression.OperatorSymbol, 'or') then
    begin
      LeftBool := RequireBoolean(LeftValue, 'or');
      RightBool := RequireBoolean(RightValue, 'or');
      Result := TGrispValue.Create(gvkBoolean);
      Result.BoolValue := LeftBool or RightBool;
      Exit;
    end;
    raise Exception.CreateFmt('Unknown binary operator "%s"', [Expression.OperatorSymbol]);
  finally
    LeftValue.Free;
    RightValue.Free;
  end;
end;

class function TGrispExpressionEvaluator.EvaluateCall(Expression: TGrispExpression; Bindings: TDictionary<string, TGrispValue>): TGrispValue;
var Arg0, Arg1, Arg2: TGrispValue; N0, N1, N2: Double;
begin
  if SameText(Expression.Name, 'min') then
  begin
    EnsureArgumentCount(Expression, 2);
    Arg0 := Evaluate(Expression.Arguments[0], Bindings);
    Arg1 := Evaluate(Expression.Arguments[1], Bindings);
    try
      Result := TGrispValue.Create(gvkNumber);
      Result.NumberValue := Min(RequireNumber(Arg0, 'min'), RequireNumber(Arg1, 'min'));
    finally Arg0.Free; Arg1.Free; end;
    Exit;
  end;
  if SameText(Expression.Name, 'max') then
  begin
    EnsureArgumentCount(Expression, 2);
    Arg0 := Evaluate(Expression.Arguments[0], Bindings);
    Arg1 := Evaluate(Expression.Arguments[1], Bindings);
    try
      Result := TGrispValue.Create(gvkNumber);
      Result.NumberValue := Max(RequireNumber(Arg0, 'max'), RequireNumber(Arg1, 'max'));
    finally Arg0.Free; Arg1.Free; end;
    Exit;
  end;
  if SameText(Expression.Name, 'mid') then
  begin
    EnsureArgumentCount(Expression, 3);
    Arg0 := Evaluate(Expression.Arguments[0], Bindings);
    Arg1 := Evaluate(Expression.Arguments[1], Bindings);
    Arg2 := Evaluate(Expression.Arguments[2], Bindings);
    try
      N0 := RequireNumber(Arg0, 'mid'); N1 := RequireNumber(Arg1, 'mid'); N2 := RequireNumber(Arg2, 'mid');
      Result := TGrispValue.Create(gvkNumber);
      Result.NumberValue := N0 + N1 + N2 - Min(Min(N0, N1), N2) - Max(Max(N0, N1), N2);
    finally Arg0.Free; Arg1.Free; Arg2.Free; end;
    Exit;
  end;
  raise Exception.CreateFmt('Unknown function "%s"', [Expression.Name]);
end;

class function TGrispExpressionEvaluator.RequireNumber(Value: TGrispValue; const Context: string): Double;
begin
  if not Assigned(Value) or (Value.Kind <> gvkNumber) then
    raise Exception.CreateFmt('Operator "%s" requires number operands', [Context]);
  Result := Value.NumberValue;
end;

class function TGrispExpressionEvaluator.RequireBoolean(Value: TGrispValue; const Context: string): Boolean;
begin
  if not Assigned(Value) or (Value.Kind <> gvkBoolean) then
    raise Exception.CreateFmt('Operator "%s" requires boolean operands', [Context]);
  Result := Value.BoolValue;
end;

class procedure TGrispExpressionEvaluator.EnsureArgumentCount(Expression: TGrispExpression; Expected: Integer);
begin
  if Expression.Arguments.Count <> Expected then
    raise Exception.CreateFmt('Function "%s" expects %d arguments, got %d',
      [Expression.Name, Expected, Expression.Arguments.Count]);
end;

{ TGrispEdge }

constructor TGrispEdge.Create(ASource: TGrispNode; ATarget: TGrispNode; const ALabel: string; const AEdgeType: string);
begin
  inherited Create;
  Source := ASource;
  Target := ATarget;
  LabelName := ALabel;
  EdgeType := AEdgeType;
end;

{ TGrispNode }

constructor TGrispNode.Create(AId: Integer; const AName: string; const ANodeType: string);
begin
  inherited Create;
  Id := AId;
  Name := AName;
  NodeType := ANodeType;
  FAttributes := TObjectDictionary<string, TGrispValue>.Create([doOwnsValues]);
  FOutgoing := TObjectList<TGrispEdge>.Create(False);
  FIncoming := TObjectList<TGrispEdge>.Create(False);
  FMarked := False;
end;

destructor TGrispNode.Destroy;
begin
  FIncoming.Free;
  FOutgoing.Free;
  FAttributes.Free;
  inherited Destroy;
end;

function TGrispNode.GetAttribute(const Key: string): TGrispValue;
begin
  if not FAttributes.TryGetValue(Key, Result) then Result := nil;
end;

procedure TGrispNode.SetAttribute(const Key: string; AValue: TGrispValue);
begin
  FAttributes.AddOrSetValue(Key, AValue);
end;

procedure TGrispNode.RemoveAttribute(const Key: string);
begin
  FAttributes.Remove(Key);
end;

function TGrispNode.HasAttribute(const Key: string): Boolean;
begin
  Result := FAttributes.ContainsKey(Key);
end;

function TGrispNode.GetNumber(const Key: string; Default: Double): Double;
var V: TGrispValue;
begin
  V := GetAttribute(Key);
  if Assigned(V) and (V.Kind = gvkNumber) then Exit(V.NumberValue);
  Result := Default;
end;

function TGrispNode.GetIdentifier(const Key: string): string;
var V: TGrispValue;
begin
  V := GetAttribute(Key);
  if Assigned(V) and (V.Kind = gvkIdentifier) then Exit(V.IdentifierValue);
  Result := '';
end;

procedure TGrispNode.AddOutgoingEdge(Edge: TGrispEdge);
begin
  FOutgoing.Add(Edge);
end;

procedure TGrispNode.AddIncomingEdge(Edge: TGrispEdge);
begin
  FIncoming.Add(Edge);
end;

procedure TGrispNode.RemoveOutgoingEdge(Edge: TGrispEdge);
begin
  FOutgoing.Remove(Edge);
end;

procedure TGrispNode.RemoveIncomingEdge(Edge: TGrispEdge);
begin
  FIncoming.Remove(Edge);
end;

function TGrispNode.ToString: string;
begin
  Result := Format('Node %d "%s" [%s]', [Id, Name, NodeType]);
end;

{ TGrispGraph }

constructor TGrispGraph.Create;
begin
  inherited Create;
  FNodes := TObjectList<TGrispNode>.Create(True);
  FEdges := TObjectList<TGrispEdge>.Create(True);
  FNodeIndex := TObjectDictionary<string, TGrispNode>.Create;
  FRules := TObjectList<TGrispNode>.Create(False);
  FTypes := TObjectDictionary<string, TGrispType>.Create([doOwnsValues]);
  FNextId := 1;
  FModified := False;
end;

destructor TGrispGraph.Destroy;
begin
  FRules.Free;
  FTypes.Free;
  FNodeIndex.Free;
  FEdges.Free;
  FNodes.Free;
  inherited Destroy;
end;

function TGrispGraph.AddNode(const AName: string; const ANodeType: string): TGrispNode;
begin
  if (AName <> '') and FNodeIndex.ContainsKey(AName) then
    raise Exception.CreateFmt('Duplicate node name "%s"', [AName]);
  Result := TGrispNode.Create(FNextId, AName, ANodeType);
  Inc(FNextId);
  FNodes.Add(Result);
  if AName <> '' then FNodeIndex.Add(AName, Result);
  FModified := True;
end;

procedure TGrispGraph.RemoveNode(Node: TGrispNode);
var
  i: Integer;
begin
  if Node = nil then Exit;

  // Remove all outgoing edges
  for i := Node.Outgoing.Count - 1 downto 0 do
    RemoveEdge(Node.Outgoing[i]);

  // Remove all incoming edges
  for i := Node.Incoming.Count - 1 downto 0 do
    RemoveEdge(Node.Incoming[i]);

  // Remove from index
  if Node.Name <> '' then
    FNodeIndex.Remove(Node.Name);

  // Remove from rules list
  FRules.Remove(Node);

  // Remove from nodes list
  FNodes.Remove(Node);
  FModified := True;
end;

procedure TGrispGraph.RemoveNodeByName(const AName: string);
var
  Node: TGrispNode;
begin
  Node := FindNode(AName);
  if Node <> nil then
    RemoveNode(Node);
end;

function TGrispGraph.FindNode(const AName: string): TGrispNode;
begin
  if not FNodeIndex.TryGetValue(AName, Result) then Result := nil;
end;

function TGrispGraph.AddEdge(ASource: TGrispNode; ATarget: TGrispNode; const ALabel: string; const AEdgeType: string): TGrispEdge;
var
  E: TGrispEdge;
begin
  // Check for existing edge
  for E in FEdges do
    if (E.Source = ASource) and (E.Target = ATarget) and SameText(E.LabelName, ALabel) then
      Exit(E);

  Result := TGrispEdge.Create(ASource, ATarget, ALabel, AEdgeType);
  FEdges.Add(Result);
  if Assigned(ASource) then ASource.AddOutgoingEdge(Result);
  if Assigned(ATarget) then ATarget.AddIncomingEdge(Result);
  FModified := True;
end;

procedure TGrispGraph.RemoveEdge(Edge: TGrispEdge);
begin
  if Edge = nil then Exit;

  if Assigned(Edge.Source) then
    Edge.Source.RemoveOutgoingEdge(Edge);
  if Assigned(Edge.Target) then
    Edge.Target.RemoveIncomingEdge(Edge);

  FEdges.Remove(Edge);
  Edge.Free;
  FModified := True;
end;

procedure TGrispGraph.RemoveEdgesBetween(Source, Target: TGrispNode; const ALabel: string);
var
  Edge: TGrispEdge;
  i: Integer;
begin
  for i := FEdges.Count - 1 downto 0 do
  begin
    Edge := FEdges[i];
    if (Edge.Source = Source) and (Edge.Target = Target) then
      if (ALabel = '') or SameText(Edge.LabelName, ALabel) then
        RemoveEdge(Edge);
  end;
end;

procedure TGrispGraph.RegisterRule(ANode: TGrispNode);
begin
  if FRules.IndexOf(ANode) < 0 then
    FRules.Add(ANode);
end;

procedure TGrispGraph.AddType(const Name: string; TypeObj: TGrispType);
begin
  FTypes.AddOrSetValue(Name, TypeObj);
end;

function TGrispGraph.FindType(const Name: string): TGrispType;
begin
  if not FTypes.TryGetValue(Name, Result) then Result := nil;
end;

procedure TGrispGraph.RegisterEdgesFromIdentifiers;
var N: TGrispNode; Key: string; Val: TGrispValue; Target: TGrispNode;
begin
  for N in FNodes do
    for Key in N.FAttributes.Keys do
    begin
      Val := N.GetAttribute(Key);
      if Assigned(Val) and (Val.Kind = gvkIdentifier) then
      begin
        Target := FindNode(Val.IdentifierValue);
        if Assigned(Target) then
          AddEdge(N, Target, Key, 'ref');
      end;
    end;
  FModified := True;
end;

procedure TGrispGraph.MarkReachable(Node: TGrispNode);
var
  Edge: TGrispEdge;
begin
  if (Node = nil) or Node.Marked then Exit;

  Node.Marked := True;
  for Edge in Node.Outgoing do
    MarkReachable(Edge.Target);
  for Edge in Node.Incoming do
    MarkReachable(Edge.Source);
end;

procedure TGrispGraph.SweepUnmarked;
var
  Node: TGrispNode;
  i: Integer;
begin
  for i := FNodes.Count - 1 downto 0 do
  begin
    Node := FNodes[i];
    if not Node.Marked then
      RemoveNode(Node)
    else
      Node.Marked := False;  // Reset for next collection
  end;
end;

procedure TGrispGraph.GarbageCollect;
var
  Root: TGrispNode;
  Key: string;
  Val: TGrispValue;
  Target: TGrispNode;
begin
  // Mark all rules and their reachable nodes
  for Root in FRules do
    MarkReachable(Root);

  // Also mark any node referenced by name in rules
  for Root in FRules do
  begin
    for Key in Root.FAttributes.Keys do
    begin
      Val := Root.GetAttribute(Key);
      if (Val <> nil) and (Val.Kind = gvkIdentifier) then
      begin
        Target := FindNode(Val.IdentifierValue);
        if Target <> nil then
          MarkReachable(Target);
      end;
    end;
  end;

  // Remove unmarked nodes
  SweepUnmarked;
  FModified := True;
end;

function TGrispGraph.GetNodesByType(const ANodeType: string): TArray<TGrispNode>;
var N: TGrispNode; List: TList<TGrispNode>;
begin
  List := TList<TGrispNode>.Create;
  try
    for N in FNodes do
      if SameText(N.NodeType, ANodeType) then List.Add(N);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function TGrispGraph.GetNodesByAttribute(const Key: string; Value: TGrispValue): TList<TGrispNode>;
var
  Node: TGrispNode;
  Attr: TGrispValue;
begin
  Result := TList<TGrispNode>.Create;
  for Node in FNodes do
  begin
    Attr := Node.GetAttribute(Key);
    if Attr <> nil then
    begin
      if Value = nil then
        Result.Add(Node)
      else if Attr.Kind = Value.Kind then
      begin
        case Attr.Kind of
          gvkNumber:
            if Attr.NumberValue = Value.NumberValue then Result.Add(Node);
          gvkString:
            if Attr.StringValue = Value.StringValue then Result.Add(Node);
          gvkBoolean:
            if Attr.BoolValue = Value.BoolValue then Result.Add(Node);
          gvkIdentifier:
            if Attr.IdentifierValue = Value.IdentifierValue then Result.Add(Node);
        end;
      end;
    end;
  end;
end;

function TGrispGraph.ToDOT: string;
var N: TGrispNode; E: TGrispEdge;
begin
  Result := 'digraph G {' + sLineBreak;
  for N in FNodes do
    Result := Result + Format('  %d [label="%s"];', [N.Id, N.Name]) + sLineBreak;
  for E in FEdges do
    if Assigned(E.Source) and Assigned(E.Target) then
      Result := Result + Format('  %d -> %d [label="%s"];', [E.Source.Id, E.Target.Id, E.LabelName]) + sLineBreak;
  Result := Result + '}' + sLineBreak;
end;

function TGrispGraph.ToJSON: string;
var
  N: TGrispNode;
  E: TGrispEdge;
  First: Boolean;
begin
  Result := '{' + sLineBreak;
  Result := Result + '  "nodes": [' + sLineBreak;

  First := True;
  for N in FNodes do
  begin
    if not First then Result := Result + ',' + sLineBreak;
    First := False;
    Result := Result + Format('    {"id": %d, "name": "%s", "type": "%s"}', [N.Id, N.Name, N.NodeType]);
  end;

  Result := Result + sLineBreak + '  ],' + sLineBreak;
  Result := Result + '  "edges": [' + sLineBreak;

  First := True;
  for E in FEdges do
  begin
    if not First then Result := Result + ',' + sLineBreak;
    First := False;
    Result := Result + Format('    {"source": %d, "target": %d, "label": "%s"}', [E.Source.Id, E.Target.Id, E.LabelName]);
  end;

  Result := Result + sLineBreak + '  ]' + sLineBreak;
  Result := Result + '}' + sLineBreak;
end;

end.
