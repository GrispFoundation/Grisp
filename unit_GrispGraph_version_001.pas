unit unit_GrispGraph_version_001;

interface

uses
  System.SysUtils,
  System.Math,
  System.Generics.Collections;

type
  TGValueKind = (
    vkNumber,
    vkString,
    vkBoolean,
    vkIdentifier,
    vkArray,
    vkNode,
    vkExpression
  );

  TGNode = class;

  TGrispExpressionKind = (
    ekLiteral,
    ekVariable,
    ekUnary,
    ekBinary,
    ekCall
  );

  TGrispExpression = class
  public
    Kind: TGrispExpressionKind;
    Value: TObject; // will be TGValue, declared after TGValue
    Name: string;
    OperatorSymbol: string;
    Left: TGrispExpression;
    Right: TGrispExpression;
    Arguments: TObjectList<TGrispExpression>;
    constructor Create(AKind: TGrispExpressionKind);
    destructor Destroy; override;
  end;

  TGValue = class
  public
    Kind: TGValueKind;
    NumberValue: Double;
    StringValue: string;
    BoolValue: Boolean;
    IdentifierValue: string;
    ArrayValue: TObjectList<TGValue>;
    NodeValue: TGNode;
    ExpressionValue: TGrispExpression;
    constructor Create(AKind: TGValueKind);
    destructor Destroy; override;
    function Clone: TGValue;
    function ToString: string; override;
  end;

  TGrispExpressionEvaluator = class
  private
    class function EvaluateLiteral(Expression: TGrispExpression): TGValue; static;
    class function EvaluateVariable(Expression: TGrispExpression; Bindings: TDictionary<string, TGValue>): TGValue; static;
    class function EvaluateUnary(Expression: TGrispExpression; Bindings: TDictionary<string, TGValue>): TGValue; static;
    class function EvaluateBinary(Expression: TGrispExpression; Bindings: TDictionary<string, TGValue>): TGValue; static;
    class function EvaluateCall(Expression: TGrispExpression; Bindings: TDictionary<string, TGValue>): TGValue; static;
    class function RequireNumber(Value: TGValue; const Context: string): Double; static;
    class function RequireBoolean(Value: TGValue; const Context: string): Boolean; static;
    class procedure EnsureArgumentCount(Expression: TGrispExpression; Expected: Integer); static;
  public
    class function Evaluate(Expression: TGrispExpression; Bindings: TDictionary<string, TGValue>): TGValue;
  end;

  TGEdge = class
  public
    LabelName: string;
    EdgeType: string;
    Source: TGNode;
    Target: TGNode;
    constructor Create(ASource: TGNode; ATarget: TGNode; const ALabel: string; const AEdgeType: string);
  end;

  TGNode = class
  public
    Id: Integer;
    Name: string;
    NodeType: string;
    Attributes: TObjectDictionary<string, TGValue>;
    Outgoing: TObjectList<TGEdge>;
    constructor Create(AId: Integer; const AName: string; const ANodeType: string);
    destructor Destroy; override;
    function GetAttribute(const Key: string): TGValue;
    procedure SetAttribute(const Key: string; AValue: TGValue);
    function ToString: string; override;
  end;

  TGGraph = class
  private
    FNextId: Integer;
  public
    Nodes: TObjectList<TGNode>;
    Edges: TObjectList<TGEdge>;
    NodeIndex: TObjectDictionary<string, TGNode>;
    Rules: TObjectList<TGNode>;
    constructor Create;
    destructor Destroy; override;
    function AddNode(const AName: string; const ANodeType: string): TGNode;
    function AddEdge(ASource: TGNode; ATarget: TGNode; const ALabel: string; const AEdgeType: string = ''): TGEdge;
    function FindNode(const AName: string): TGNode;
    procedure RegisterRule(ANode: TGNode);
    function ToDOT: string;
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
  if Assigned(Value) then
    TGValue(Value).Free;
  inherited Destroy;
end;

{ TGValue }

constructor TGValue.Create(AKind: TGValueKind);
begin
  inherited Create;
  Kind := AKind;
  if Kind = vkArray then
    ArrayValue := TObjectList<TGValue>.Create(True);
end;

destructor TGValue.Destroy;
begin
  if Assigned(ArrayValue) then
    ArrayValue.Free;
  if Assigned(ExpressionValue) then
    ExpressionValue.Free;
  inherited Destroy;
end;

function TGValue.Clone: TGValue;
var
  E: TGValue;
begin
  Result := TGValue.Create(Kind);
  Result.NumberValue := NumberValue;
  Result.StringValue := StringValue;
  Result.BoolValue := BoolValue;
  Result.IdentifierValue := IdentifierValue;
  Result.NodeValue := NodeValue;
  if Kind = vkArray then
    for E in ArrayValue do
      Result.ArrayValue.Add(E.Clone);
  if Kind = vkExpression then
    if Assigned(ExpressionValue) then
      Result.ExpressionValue := ExpressionValue; // shallow, expressions immutable
end;

function TGValue.ToString: string;
begin
  case Kind of
    vkNumber:
      Result := FloatToStr(NumberValue);
    vkString:
      Result := '"' + StringValue + '"';
    vkBoolean:
      Result := BoolToStr(BoolValue, True);
    vkIdentifier:
      Result := IdentifierValue;
    vkArray:
      Result := '[...]';
    vkNode:
      if Assigned(NodeValue) then
        Result := Format('node(%d)', [NodeValue.Id])
      else
        Result := 'node(nil)';
    vkExpression:
      Result := '<expr>';
  else
    Result := 'nil';
  end;
end;

{ TGrispExpressionEvaluator }

class function TGrispExpressionEvaluator.Evaluate(Expression: TGrispExpression; Bindings: TDictionary<string, TGValue>): TGValue;
begin
  if Expression = nil then
    Exit(nil);
  case Expression.Kind of
    ekLiteral:  Result := EvaluateLiteral(Expression);
    ekVariable: Result := EvaluateVariable(Expression, Bindings);
    ekUnary:    Result := EvaluateUnary(Expression, Bindings);
    ekBinary:   Result := EvaluateBinary(Expression, Bindings);
    ekCall:     Result := EvaluateCall(Expression, Bindings);
  else
    Result := nil;
  end;
end;

class function TGrispExpressionEvaluator.EvaluateLiteral(Expression: TGrispExpression): TGValue;
begin
  if Assigned(Expression.Value) then
    Result := TGValue(Expression.Value).Clone
  else
    Result := nil;
end;

class function TGrispExpressionEvaluator.EvaluateVariable(Expression: TGrispExpression; Bindings: TDictionary<string, TGValue>): TGValue;
var
  BoundValue: TGValue;
begin
  if not Assigned(Bindings) then
    raise Exception.Create('No variable bindings supplied');
  if Bindings.TryGetValue(Expression.Name, BoundValue) then
    Result := BoundValue.Clone
  else
    raise Exception.CreateFmt('Unbound variable "%s"', [Expression.Name]);
end;

class function TGrispExpressionEvaluator.EvaluateUnary(Expression: TGrispExpression; Bindings: TDictionary<string, TGValue>): TGValue;
var
  Operand: TGValue;
begin
  Operand := Evaluate(Expression.Left, Bindings);
  try
    if SameText(Expression.OperatorSymbol, 'not') then
    begin
      Result := TGValue.Create(vkBoolean);
      Result.BoolValue := not RequireBoolean(Operand, 'not');
      Exit;
    end;
    if Expression.OperatorSymbol = '-' then
    begin
      Result := TGValue.Create(vkNumber);
      Result.NumberValue := -RequireNumber(Operand, 'unary -');
      Exit;
    end;
    raise Exception.CreateFmt('Unknown unary operator "%s"', [Expression.OperatorSymbol]);
  finally
    Operand.Free;
  end;
end;

class function TGrispExpressionEvaluator.EvaluateBinary(Expression: TGrispExpression; Bindings: TDictionary<string, TGValue>): TGValue;
var
  LeftValue, RightValue: TGValue;
  RightNumber: Double;
  LeftBool, RightBool: Boolean;
begin
  LeftValue := Evaluate(Expression.Left, Bindings);
  RightValue := Evaluate(Expression.Right, Bindings);
  try
    if Expression.OperatorSymbol = '+' then
    begin
      Result := TGValue.Create(vkNumber);
      Result.NumberValue := RequireNumber(LeftValue, '+') + RequireNumber(RightValue, '+');
      Exit;
    end;
    if Expression.OperatorSymbol = '-' then
    begin
      Result := TGValue.Create(vkNumber);
      Result.NumberValue := RequireNumber(LeftValue, '-') - RequireNumber(RightValue, '-');
      Exit;
    end;
    if Expression.OperatorSymbol = '*' then
    begin
      Result := TGValue.Create(vkNumber);
      Result.NumberValue := RequireNumber(LeftValue, '*') * RequireNumber(RightValue, '*');
      Exit;
    end;
    if Expression.OperatorSymbol = '/' then
    begin
      RightNumber := RequireNumber(RightValue, '/');
      if RightNumber = 0 then
        raise Exception.Create('Division by zero');
      Result := TGValue.Create(vkNumber);
      Result.NumberValue := RequireNumber(LeftValue, '/') / RightNumber;
      Exit;
    end;
    if SameText(Expression.OperatorSymbol, 'mod') then
    begin
      Result := TGValue.Create(vkNumber);
      Result.NumberValue := Trunc(RequireNumber(LeftValue, 'mod')) mod Trunc(RequireNumber(RightValue, 'mod'));
      Exit;
    end;
    if Expression.OperatorSymbol = '=' then
    begin
      Result := TGValue.Create(vkBoolean);
      Result.BoolValue := RequireNumber(LeftValue, '=') = RequireNumber(RightValue, '=');
      Exit;
    end;
    if Expression.OperatorSymbol = '<>' then
    begin
      Result := TGValue.Create(vkBoolean);
      Result.BoolValue := RequireNumber(LeftValue, '<>') <> RequireNumber(RightValue, '<>');
      Exit;
    end;
    if Expression.OperatorSymbol = '<' then
    begin
      Result := TGValue.Create(vkBoolean);
      Result.BoolValue := RequireNumber(LeftValue, '<') < RequireNumber(RightValue, '<');
      Exit;
    end;
    if Expression.OperatorSymbol = '>' then
    begin
      Result := TGValue.Create(vkBoolean);
      Result.BoolValue := RequireNumber(LeftValue, '>') > RequireNumber(RightValue, '>');
      Exit;
    end;
    if Expression.OperatorSymbol = '<=' then
    begin
      Result := TGValue.Create(vkBoolean);
      Result.BoolValue := RequireNumber(LeftValue, '<=') <= RequireNumber(RightValue, '<=');
      Exit;
    end;
    if Expression.OperatorSymbol = '>=' then
    begin
      Result := TGValue.Create(vkBoolean);
      Result.BoolValue := RequireNumber(LeftValue, '>=') >= RequireNumber(RightValue, '>=');
      Exit;
    end;
    if SameText(Expression.OperatorSymbol, 'and') then
    begin
      LeftBool := RequireBoolean(LeftValue, 'and');
      RightBool := RequireBoolean(RightValue, 'and');
      Result := TGValue.Create(vkBoolean);
      Result.BoolValue := LeftBool and RightBool;
      Exit;
    end;
    if SameText(Expression.OperatorSymbol, 'or') then
    begin
      LeftBool := RequireBoolean(LeftValue, 'or');
      RightBool := RequireBoolean(RightValue, 'or');
      Result := TGValue.Create(vkBoolean);
      Result.BoolValue := LeftBool or RightBool;
      Exit;
    end;
    raise Exception.CreateFmt('Unknown binary operator "%s"', [Expression.OperatorSymbol]);
  finally
    LeftValue.Free;
    RightValue.Free;
  end;
end;

class function TGrispExpressionEvaluator.EvaluateCall(Expression: TGrispExpression; Bindings: TDictionary<string, TGValue>): TGValue;
var
  Arg0, Arg1, Arg2: TGValue;
  N0, N1, N2: Double;
begin
  if SameText(Expression.Name, 'min') then
  begin
    EnsureArgumentCount(Expression, 2);
    Arg0 := Evaluate(Expression.Arguments[0], Bindings);
    Arg1 := Evaluate(Expression.Arguments[1], Bindings);
    try
      Result := TGValue.Create(vkNumber);
      Result.NumberValue := Min(RequireNumber(Arg0, 'min'), RequireNumber(Arg1, 'min'));
    finally
      Arg0.Free;
      Arg1.Free;
    end;
    Exit;
  end;
  if SameText(Expression.Name, 'max') then
  begin
    EnsureArgumentCount(Expression, 2);
    Arg0 := Evaluate(Expression.Arguments[0], Bindings);
    Arg1 := Evaluate(Expression.Arguments[1], Bindings);
    try
      Result := TGValue.Create(vkNumber);
      Result.NumberValue := Max(RequireNumber(Arg0, 'max'), RequireNumber(Arg1, 'max'));
    finally
      Arg0.Free;
      Arg1.Free;
    end;
    Exit;
  end;
  if SameText(Expression.Name, 'mid') then
  begin
    EnsureArgumentCount(Expression, 3);
    Arg0 := Evaluate(Expression.Arguments[0], Bindings);
    Arg1 := Evaluate(Expression.Arguments[1], Bindings);
    Arg2 := Evaluate(Expression.Arguments[2], Bindings);
    try
      N0 := RequireNumber(Arg0, 'mid');
      N1 := RequireNumber(Arg1, 'mid');
      N2 := RequireNumber(Arg2, 'mid');
      Result := TGValue.Create(vkNumber);
      Result.NumberValue := N0 + N1 + N2 - Min(Min(N0, N1), N2) - Max(Max(N0, N1), N2);
    finally
      Arg0.Free;
      Arg1.Free;
      Arg2.Free;
    end;
    Exit;
  end;
  raise Exception.CreateFmt('Unknown function "%s"', [Expression.Name]);
end;

class function TGrispExpressionEvaluator.RequireNumber(Value: TGValue; const Context: string): Double;
begin
  if not Assigned(Value) or (Value.Kind <> vkNumber) then
    raise Exception.CreateFmt('Operator "%s" requires number operands', [Context]);
  Result := Value.NumberValue;
end;

class function TGrispExpressionEvaluator.RequireBoolean(Value: TGValue; const Context: string): Boolean;
begin
  if not Assigned(Value) or (Value.Kind <> vkBoolean) then
    raise Exception.CreateFmt('Operator "%s" requires boolean operands', [Context]);
  Result := Value.BoolValue;
end;

class procedure TGrispExpressionEvaluator.EnsureArgumentCount(Expression: TGrispExpression; Expected: Integer);
begin
  if Expression.Arguments.Count <> Expected then
    raise Exception.CreateFmt('Function "%s" expects %d arguments, got %d',
      [Expression.Name, Expected, Expression.Arguments.Count]);
end;

{ TGEdge }

constructor TGEdge.Create(ASource: TGNode; ATarget: TGNode; const ALabel: string; const AEdgeType: string);
begin
  inherited Create;
  Source := ASource;
  Target := ATarget;
  LabelName := ALabel;
  EdgeType := AEdgeType;
end;

{ TGNode }

constructor TGNode.Create(AId: Integer; const AName: string; const ANodeType: string);
begin
  inherited Create;
  Id := AId;
  Name := AName;
  NodeType := ANodeType;
  Attributes := TObjectDictionary<string, TGValue>.Create([doOwnsValues]);
  Outgoing := TObjectList<TGEdge>.Create(False);
end;

destructor TGNode.Destroy;
begin
  Outgoing.Free;
  Attributes.Free;
  inherited Destroy;
end;

function TGNode.GetAttribute(const Key: string): TGValue;
begin
  if not Attributes.TryGetValue(Key, Result) then
    Result := nil;
end;

procedure TGNode.SetAttribute(const Key: string; AValue: TGValue);
begin
  Attributes.AddOrSetValue(Key, AValue);
end;

function TGNode.ToString: string;
begin
  Result := Format('Node %d "%s"', [Id, Name]);
end;

{ TGGraph }

constructor TGGraph.Create;
begin
  inherited Create;
  Nodes := TObjectList<TGNode>.Create(True);
  Edges := TObjectList<TGEdge>.Create(True);
  NodeIndex := TObjectDictionary<string, TGNode>.Create;
  Rules := TObjectList<TGNode>.Create(False);
  FNextId := 1;
end;

destructor TGGraph.Destroy;
begin
  Rules.Free;
  NodeIndex.Free;
  Edges.Free;
  Nodes.Free;
  inherited Destroy;
end;

function TGGraph.AddNode(const AName: string; const ANodeType: string): TGNode;
begin
  if (AName <> '') and NodeIndex.ContainsKey(AName) then
    raise Exception.CreateFmt('Duplicate node name "%s"', [AName]);
  Result := TGNode.Create(FNextId, AName, ANodeType);
  Inc(FNextId);
  Nodes.Add(Result);
  if AName <> '' then
    NodeIndex.Add(AName, Result);
end;

function TGGraph.AddEdge(ASource: TGNode; ATarget: TGNode; const ALabel: string; const AEdgeType: string): TGEdge;
begin
  Result := TGEdge.Create(ASource, ATarget, ALabel, AEdgeType);
  Edges.Add(Result);
  if Assigned(ASource) then
    ASource.Outgoing.Add(Result);
end;

function TGGraph.FindNode(const AName: string): TGNode;
begin
  if not NodeIndex.TryGetValue(AName, Result) then
    Result := nil;
end;

procedure TGGraph.RegisterRule(ANode: TGNode);
begin
  if Rules.IndexOf(ANode) < 0 then
    Rules.Add(ANode);
end;

function TGGraph.ToDOT: string;
var
  N: TGNode;
  E: TGEdge;
begin
  Result := 'digraph G {' + #10;
  for N in Nodes do
    Result := Result + Format(' %d [label="%s"];', [N.Id, N.Name]) + #10;
  for E in Edges do
    if Assigned(E.Source) and Assigned(E.Target) then
      Result := Result + Format(' %d -> %d [label="%s"];', [E.Source.Id, E.Target.Id, E.LabelName]) + #10;
  Result := Result + '}';
end;

end.

