unit unit_Parser_TGrispUnifiedParser_version_001;

interface

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  unit_Token_TGrispTokenKind_version_001,
  unit_Token_TGrispToken_version_001,
  unit_Lexer_TGrispLexer_version_001,
  unit_Graph_TGrispGraph_version_001,
  unit_Graph_TGrispEdge_TGrispNode_version_001,
  unit_Core_TGrispValueBase_version_001,
  unit_Core_TGrispExpression_version_001,
  unit_Core_TGrispExpressionEvaluator_version_001,
  unit_Core_TGrispType_version_001,
  unit_Strategy_TGrispStrategyKind_version_001,
  unit_Strategy_TGrispStrategy_version_001,
  unit_Strategy_TGrispStrategyEngine_version_001;

type
  EGrispParseError = class(Exception);

  TGrispUnifiedParser = class
  private
    FLexer: TGrispLexer;
    FCurrent: TGrispToken;
    FGraph: TGrispGraph;
    FStrategyEngine: TGrispStrategyEngine;
    FAnonId: Integer;

    procedure Advance;
    procedure Expect(AKind: TGrispTokenKind; const Msg: string);

    function ParseTypeName: string;
    function InnerArrayType(const ATypeName: string): string;
    function ParseType: TGrispType;

    function ParseValue(const ATypeName: string): TGrispValue;
    procedure ParseNodeBody(ANode: TGrispNode);

    function ParseExpr: TGrispExpression;
    function ParseOrExpr: TGrispExpression;
    function ParseAndExpr: TGrispExpression;
    function ParseCompareExpr: TGrispExpression;
    function ParseAddExpr: TGrispExpression;
    function ParseMulExpr: TGrispExpression;
    function ParseUnaryExpr: TGrispExpression;
    function ParsePrimaryExpr: TGrispExpression;
    function ExprToValue(Expr: TGrispExpression): TGrispValue;

    function ParseStrategy: TGrispStrategy;

    function EdgeExists(ASource, ATarget: TGrispNode; const ALabel: string): Boolean;
    procedure RegisterEdgesForNode(ANode: TGrispNode);
    procedure RegisterEdgesForAllNodes;

  public
    constructor Create(const ASource: string; AGraph: TGrispGraph);
    destructor Destroy; override;

    procedure ParseNodeDecl;
    procedure ParseTypeDecl;
    procedure ParseStrategyDecl;
    procedure ParseFile;
  end;

implementation

{ TGrispUnifiedParser }

constructor TGrispUnifiedParser.Create(const ASource: string; AGraph: TGrispGraph);
begin
  inherited Create;
  FLexer := TGrispLexer.Create(ASource);
  FGraph := AGraph;
  FStrategyEngine := TGrispStrategyEngine.Create(AGraph);
  FAnonId := 0;
  Advance;
end;

destructor TGrispUnifiedParser.Destroy;
begin
  FStrategyEngine.Free;
  FLexer.Free;
  inherited Destroy;
end;

procedure TGrispUnifiedParser.Advance;
begin
  FCurrent := FLexer.NextToken;
end;

procedure TGrispUnifiedParser.Expect(AKind: TGrispTokenKind; const Msg: string);
begin
  if FCurrent.Kind <> AKind then
    raise EGrispParseError.CreateFmt('%s at line %d col %d', [Msg, FCurrent.Line, FCurrent.Column]);
  Advance;
end;

function TGrispUnifiedParser.ParseTypeName: string;
var
  Inner: string;
begin
  Result := FCurrent.Lexeme;
  Advance;
  if SameText(Result, 'array') then
  begin
    Expect(tkLess, '"<" expected');
    Inner := FCurrent.Lexeme;
    Advance;
    Expect(tkGreater, '">" expected');
    Result := 'array<' + Inner + '>';
  end;
end;

function TGrispUnifiedParser.InnerArrayType(const ATypeName: string): string;
begin
  Result := Copy(ATypeName, 7, Length(ATypeName) - 7);
  if (Length(Result) > 0) and (Result[Length(Result)] = '>') then
    SetLength(Result, Length(Result) - 1);
end;

function TGrispUnifiedParser.ParseType: TGrispType;
var
  InnerType: TGrispType;
begin
  if SameText(FCurrent.Lexeme, 'number') then
  begin
    Result := TGrispType.Create(gtkNumber);
    Advance;
  end
  else if SameText(FCurrent.Lexeme, 'string') then
  begin
    Result := TGrispType.Create(gtkString);
    Advance;
  end
  else if SameText(FCurrent.Lexeme, 'boolean') then
  begin
    Result := TGrispType.Create(gtkBoolean);
    Advance;
  end
  else if SameText(FCurrent.Lexeme, 'identifier') then
  begin
    Result := TGrispType.Create(gtkIdentifier);
    Advance;
  end
  else if SameText(FCurrent.Lexeme, 'nil') then
  begin
    Result := TGrispType.Create(gtkNil);
    Advance;
  end
  else if SameText(FCurrent.Lexeme, 'array') then
  begin
    Advance;
    Expect(tkLess, '"<" expected');
    InnerType := ParseType;
    Result := TGrispType.Create(gtkArray);
    Result.ElementType := InnerType;
    Expect(tkGreater, '">" expected');
  end
  else if FCurrent.Kind = tkIdentifier then
  begin
    Result := TGrispType.Create(gtkNode);
    Result.NodeTypeName := FCurrent.Lexeme;
    Advance;
  end
  else
    raise EGrispParseError.Create('Type expected');
end;

function TGrispUnifiedParser.ParseValue(const ATypeName: string): TGrispValue;
var
  S: string;
  D: Double;
  Node: TGrispNode;
  InnerType: string;
begin
  // Pattern variable support: bare identifier for scalar types
  if FCurrent.Kind = tkIdentifier then
  begin

	if not SameText(ATypeName, 'node') and not StartsText('array<', ATypeName) then
	begin
	  Result := TGrispValue.Create(gvkIdentifier);
	  Result.IdentifierValue := FCurrent.Lexeme;
	  Advance;
	  Exit;
	end;

  end;

  if StartsText('array<', ATypeName) then
  begin
    InnerType := InnerArrayType(ATypeName);
    Expect(tkLBracket, '"[" expected');
    Result := TGrispValue.Create(gvkArray);
    while (FCurrent.Kind <> tkRBracket) and (FCurrent.Kind <> tkEOF) do
    begin
      Result.ArrayValue.Add(ParseValue(InnerType));
      if FCurrent.Kind = tkComma then Advance else Break;
    end;
    Expect(tkRBracket, '"]" expected');
    Exit;
  end;

  if SameText(ATypeName, 'number') then
  begin
    if FCurrent.Kind <> tkNumber then raise EGrispParseError.Create('number expected');
    D := StrToFloat(FCurrent.Lexeme);
    Advance;
    Result := TGrispValue.Create(gvkNumber);
    Result.NumberValue := D;
    Exit;
  end;

  if SameText(ATypeName, 'string') then
  begin
    if FCurrent.Kind <> tkString then raise EGrispParseError.Create('string expected');
    S := FCurrent.Lexeme;
    Advance;
    if (Length(S) >= 2) and CharInSet(S[1], ['''', '"']) then
      S := Copy(S, 2, Length(S) - 2);
    Result := TGrispValue.Create(gvkString);
    Result.StringValue := S;
    Exit;
  end;

  if SameText(ATypeName, 'boolean') then
  begin
    if FCurrent.Kind <> tkBoolean then raise EGrispParseError.Create('boolean expected');
    Result := TGrispValue.Create(gvkBoolean);
    Result.BoolValue := SameText(FCurrent.Lexeme, 'true');
    Advance;
    Exit;
  end;

  if SameText(ATypeName, 'identifier') then
  begin
    if not (FCurrent.Kind in [tkIdentifier, tkKeywordNode, tkKeywordArray]) then
      raise EGrispParseError.Create('identifier expected');
    Result := TGrispValue.Create(gvkIdentifier);
    Result.IdentifierValue := FCurrent.Lexeme;
    Advance;
    Exit;
  end;

  if SameText(ATypeName, 'node') then
  begin
	Expect(tkLBrace, '"{" expected');
	Inc(FAnonId);
	Node := FGraph.AddNode('#' + IntToStr(FAnonId), 'pattern');
	ParseNodeBody(Node);
	Expect(tkRBrace, '"}" expected');
	Result := TGrispValue.Create(gvkNode);
	Result.SetNodeReference(Node.Id, Node.Name);
	Exit;
  end;

  raise EGrispParseError.CreateFmt('Unknown type "%s"', [ATypeName]);
end;

procedure TGrispUnifiedParser.ParseNodeBody(ANode: TGrispNode);
var
  Key, TypeName: string;
  Value: TGrispValue;
begin
  while (FCurrent.Kind <> tkRBrace) and (FCurrent.Kind <> tkEOF) and
        (FCurrent.Kind <> tkKeywordWhere) do
  begin
    if not (FCurrent.Kind in [tkIdentifier, tkKeywordNode, tkKeywordArray]) then
      raise EGrispParseError.CreateFmt('Attribute name expected at %d:%d', [FCurrent.Line, FCurrent.Column]);
    Key := FCurrent.Lexeme;
    Advance;
    Expect(tkColon, '":" expected');
    TypeName := ParseTypeName;
    Expect(tkEquals, '"=" expected');
    Value := ParseValue(TypeName);
    ANode.SetValueAttribute(Key, Value);
    if FCurrent.Kind = tkSemicolon then
      Advance;
  end;
end;

function TGrispUnifiedParser.ExprToValue(Expr: TGrispExpression): TGrispValue;
begin
  Result := TGrispValue.Create(gvkExpression);
  Result.ExpressionValue := Expr;
end;

function TGrispUnifiedParser.ParseExpr: TGrispExpression;
begin
  Result := ParseOrExpr;
end;

function TGrispUnifiedParser.ParseOrExpr: TGrispExpression;
var
  Left, Right: TGrispExpression;
begin
  Left := ParseAndExpr;
  while FCurrent.Kind = tkKeywordOr do
  begin
    Advance;
    Right := ParseAndExpr;
    Result := TGrispExpression.Create(gekBinary);
    Result.OperatorSymbol := 'or';
    Result.Left := Left;
    Result.Right := Right;
    Left := Result;
  end;
  Result := Left;
end;

function TGrispUnifiedParser.ParseAndExpr: TGrispExpression;
var
  Left, Right: TGrispExpression;
begin
  Left := ParseCompareExpr;
  while FCurrent.Kind = tkKeywordAnd do
  begin
    Advance;
	Right := ParseCompareExpr;
    Result := TGrispExpression.Create(gekBinary);
    Result.OperatorSymbol := 'and';
    Result.Left := Left;
    Result.Right := Right;
    Left := Result;
  end;
  Result := Left;
end;

function TGrispUnifiedParser.ParseCompareExpr: TGrispExpression;
var
  Left, Right: TGrispExpression;
  Op: string;
begin
  Left := ParseAddExpr;
  while FCurrent.Kind in [tkEquals, tkNotEqual, tkLess, tkGreater, tkLessEqual, tkGreaterEqual] do
  begin
    Op := FCurrent.Lexeme;
    Advance;
    Right := ParseAddExpr;
    Result := TGrispExpression.Create(gekBinary);
    Result.OperatorSymbol := Op;
    Result.Left := Left;
    Result.Right := Right;
    Left := Result;
  end;
  Result := Left;
end;

function TGrispUnifiedParser.ParseAddExpr: TGrispExpression;
var
  Left, Right: TGrispExpression;
  Op: string;
begin
  Left := ParseMulExpr;
  while (FCurrent.Kind = tkOperator) and ((FCurrent.Lexeme = '+') or (FCurrent.Lexeme = '-')) do
  begin
    Op := FCurrent.Lexeme;
    Advance;
    Right := ParseMulExpr;
    Result := TGrispExpression.Create(gekBinary);
    Result.OperatorSymbol := Op;
    Result.Left := Left;
    Result.Right := Right;
    Left := Result;
  end;
  Result := Left;
end;

function TGrispUnifiedParser.ParseMulExpr: TGrispExpression;
var
  Left, Right: TGrispExpression;
  Op: string;
begin
  Left := ParseUnaryExpr;
  while ((FCurrent.Kind = tkOperator) and ((FCurrent.Lexeme = '*') or (FCurrent.Lexeme = '/'))) or
        (FCurrent.Kind = tkKeywordMod) do
  begin
    Op := FCurrent.Lexeme;
    Advance;
    Right := ParseUnaryExpr;
    Result := TGrispExpression.Create(gekBinary);
    Result.OperatorSymbol := Op;
    Result.Left := Left;
    Result.Right := Right;
    Left := Result;
  end;
  Result := Left;
end;

function TGrispUnifiedParser.ParseUnaryExpr: TGrispExpression;
begin
  if FCurrent.Kind = tkKeywordNot then
  begin
    Advance;
    Result := TGrispExpression.Create(gekUnary);
    Result.OperatorSymbol := 'not';
    Result.Left := ParseUnaryExpr;
    Exit;
  end;
  if (FCurrent.Kind = tkOperator) and (FCurrent.Lexeme = '-') then
  begin
    Advance;
    Result := TGrispExpression.Create(gekUnary);
    Result.OperatorSymbol := '-';
    Result.Left := ParseUnaryExpr;
    Exit;
  end;
  Result := ParsePrimaryExpr;
end;

function TGrispUnifiedParser.ParsePrimaryExpr: TGrispExpression;
var
  Name: string;
begin
  if FCurrent.Kind = tkNumber then
  begin
    Result := TGrispExpression.Create(gekLiteral);
    Result.Value := TGrispValue.Create(gvkNumber);
    TGrispValue(Result.Value).NumberValue := StrToFloat(FCurrent.Lexeme);
    Advance;
    Exit;
  end;
  if FCurrent.Kind = tkBoolean then
  begin
    Result := TGrispExpression.Create(gekLiteral);
    Result.Value := TGrispValue.Create(gvkBoolean);
    TGrispValue(Result.Value).BoolValue := SameText(FCurrent.Lexeme, 'true');
    Advance;
    Exit;
  end;
  if FCurrent.Kind = tkIdentifier then
  begin
    Name := FCurrent.Lexeme;
    Advance;
    if FCurrent.Kind = tkLParen then
    begin
      Result := TGrispExpression.Create(gekCall);
      Result.Name := Name;
      Advance;
      while (FCurrent.Kind <> tkRParen) and (FCurrent.Kind <> tkEOF) do
      begin
        Result.Arguments.Add(ParseExpr);
        if FCurrent.Kind = tkComma then Advance else Break;
      end;
      Expect(tkRParen, '")" expected');
      Exit;
    end
    else
    begin
      Result := TGrispExpression.Create(gekVariable);
      Result.Name := Name;
      Exit;
    end;
  end;
  if FCurrent.Kind = tkLParen then
  begin
    Advance;
    Result := ParseExpr;
    Expect(tkRParen, '")" expected');
    Exit;
  end;
  raise EGrispParseError.Create('Expression expected');
end;

function TGrispUnifiedParser.ParseStrategy: TGrispStrategy;
begin
  if FCurrent.Kind = tkKeywordRepeat then
  begin
    Advance;
    Expect(tkLParen, '"(" expected');
    Result := TGrispStrategy.Create(gskRepeat);
    while FCurrent.Kind <> tkRParen do
    begin
      Result.Strategies.Add(ParseStrategy);
      if FCurrent.Kind = tkComma then Advance;
    end;
    Expect(tkRParen, '")" expected');
  end
  else if FCurrent.Kind = tkKeywordTry then
  begin
    Advance;
    Expect(tkLParen, '"(" expected');
    Result := TGrispStrategy.Create(gskTry);
    while FCurrent.Kind <> tkRParen do
    begin
      Result.Strategies.Add(ParseStrategy);
      if FCurrent.Kind = tkComma then Advance;
    end;
    Expect(tkRParen, '")" expected');
  end
  else if FCurrent.Kind = tkKeywordChoice then
  begin
    Advance;
    Expect(tkLParen, '"(" expected');
    Result := TGrispStrategy.Create(gskChoice);
    while FCurrent.Kind <> tkRParen do
    begin
      Result.Strategies.Add(ParseStrategy);
      if FCurrent.Kind = tkComma then Advance;
    end;
    Expect(tkRParen, '")" expected');
  end
  else if (FCurrent.Kind = tkKeywordPhase) or ((FCurrent.Kind = tkIdentifier) and SameText(FCurrent.Lexeme, 'phase')) then
  begin
    if FCurrent.Kind = tkIdentifier then Advance;
    Expect(tkLParen, '"(" expected');
    Result := TGrispStrategy.Create(gskPhase);
    if FCurrent.Kind = tkNumber then
    begin
      Result.Phase := Trunc(StrToFloat(FCurrent.Lexeme));
      Advance;
    end;
    while FCurrent.Kind <> tkRParen do
    begin
      Result.Strategies.Add(ParseStrategy);
      if FCurrent.Kind = tkComma then Advance;
    end;
    Expect(tkRParen, '")" expected');
  end
  else if FCurrent.Kind = tkIdentifier then
  begin
    Result := TGrispStrategy.Create(gskRule);
    Result.RuleName := FCurrent.Lexeme;
    Advance;
  end
  else
    raise EGrispParseError.Create('Strategy expected');
end;

function TGrispUnifiedParser.EdgeExists(ASource, ATarget: TGrispNode; const ALabel: string): Boolean;
var
  E: TGrispEdge;
begin
  for E in FGraph.Edges do
    if (E.Source = ASource) and (E.Target = ATarget) and SameText(E.LabelName, ALabel) then
      Exit(True);
  Result := False;
end;

procedure TGrispUnifiedParser.RegisterEdgesForNode(ANode: TGrispNode);
var
  Key: string;
  Val: TGrispValue;
  Target: TGrispNode;
  Elem: TGrispValue;
  NodeId: Integer;
  NodeName: string;
begin
  for Key in ANode.GetAttributeKeys do
  begin
    Val := ANode.GetValueAttribute(Key);
    if Val = nil then Continue;
    case Val.Kind of
      gvkNode:
        begin
          Val.GetNodeReference(NodeId, NodeName);
          Target := FGraph.FindNode(NodeName);
          if Assigned(Target) and not EdgeExists(ANode, Target, Key) then
            FGraph.AddEdge(ANode, Target, Key, '');
        end;
      gvkIdentifier:
        begin
          Target := FGraph.FindNode(Val.IdentifierValue);
          if Assigned(Target) and not EdgeExists(ANode, Target, Key) then
            FGraph.AddEdge(ANode, Target, Key, '');
        end;
      gvkArray:
        for Elem in Val.ArrayValue do
        begin
          if Elem.Kind = gvkNode then
          begin
            Elem.GetNodeReference(NodeId, NodeName);
            Target := FGraph.FindNode(NodeName);
            if Assigned(Target) and not EdgeExists(ANode, Target, Key) then
              FGraph.AddEdge(ANode, Target, Key, '');
          end
          else if Elem.Kind = gvkIdentifier then
          begin
            Target := FGraph.FindNode(Elem.IdentifierValue);
            if Assigned(Target) and not EdgeExists(ANode, Target, Key) then
              FGraph.AddEdge(ANode, Target, Key, '');
          end;
        end;
    end;
  end;
end;

procedure TGrispUnifiedParser.RegisterEdgesForAllNodes;
var
  Node: TGrispNode;
begin
  for Node in FGraph.Nodes do
    RegisterEdgesForNode(Node);
end;

procedure TGrispUnifiedParser.ParseNodeDecl;
var
  NodeName: string;
  Node: TGrispNode;
  WhereExpr: TGrispExpression;
  TempExpr: TGrispExpression;
  PhaseNum: Double;
begin
  Expect(tkKeywordNode, '"node" expected');
  NodeName := FCurrent.Lexeme;
  Expect(tkIdentifier, 'name expected');
  Node := FGraph.AddNode(NodeName, 'node');

  if StartsText('rule.', NodeName) then
    FGraph.RegisterRule(Node);

  // Parse optional phase declaration
  if (FCurrent.Kind = tkKeywordPhase) or ((FCurrent.Kind = tkIdentifier) and SameText(FCurrent.Lexeme, 'phase')) then
  begin
    if FCurrent.Kind = tkIdentifier then Advance;
    if FCurrent.Kind = tkNumber then
    begin
      PhaseNum := StrToFloat(FCurrent.Lexeme);
      Node.SetValueAttribute('phase', TGrispValue.Create(gvkNumber));
      Node.GetValueAttribute('phase').NumberValue := PhaseNum;
      Advance;
    end;
  end;

  Expect(tkLBrace, '{ expected');
  ParseNodeBody(Node);

  // Parse optional temp section
  if (FCurrent.Kind = tkKeywordTemp) or ((FCurrent.Kind = tkIdentifier) and SameText(FCurrent.Lexeme, 'temp')) then
  begin
    if FCurrent.Kind = tkIdentifier then Advance;
    Expect(tkEquals, '"=" expected');
    TempExpr := ParseExpr;
    Node.SetValueAttribute('temp', ExprToValue(TempExpr));
  end;

  if FCurrent.Kind = tkKeywordWhere then
  begin
    Advance;
    WhereExpr := ParseExpr;
    Node.SetValueAttribute('where', ExprToValue(WhereExpr));
  end;

  Expect(tkRBrace, '} expected');
end;

procedure TGrispUnifiedParser.ParseTypeDecl;
var
  TypeName: string;
  Typ: TGrispType;
begin
  Expect(tkKeywordType, '"type" expected');
  TypeName := FCurrent.Lexeme;
  Expect(tkIdentifier, 'name expected');
  Expect(tkEquals, '"=" expected');
  Typ := ParseType;
  FGraph.AddType(TypeName, Typ);
end;

procedure TGrispUnifiedParser.ParseStrategyDecl;
var
  StrategyName: string;
  Strat: TGrispStrategy;
begin
  Expect(tkKeywordStrategy, '"strategy" expected');
  StrategyName := FCurrent.Lexeme;
  Expect(tkIdentifier, 'name expected');
  Expect(tkEquals, '"=" expected');
  Strat := ParseStrategy;
  FStrategyEngine.AddStrategy(StrategyName, Strat);
end;

procedure TGrispUnifiedParser.ParseFile;
begin
  while FCurrent.Kind <> tkEOF do
  begin
    case FCurrent.Kind of
      tkKeywordNode:
        ParseNodeDecl;
      tkKeywordType:
        ParseTypeDecl;
      tkKeywordStrategy:
        ParseStrategyDecl;
      else
        raise EGrispParseError.Create('Expected node, type, or strategy declaration');
    end;
  end;
  RegisterEdgesForAllNodes;
end;

end.
