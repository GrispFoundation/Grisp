unit unit_GrispParser_version_001;

interface

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  unit_GrispTokens_version_001,
  unit_GrispLexer_version_001,
  unit_GrispGraph_version_001,
  unit_GrispStrategy_version_001;

type
  EGrispParseError = class(Exception);

  TGrispParser = class
  private
    FLexer: TGrispLexer;
    FCurrent: TToken;
    FGraph: TGGraph;
    FStrategyEngine: TGrispStrategyEngine;
    FAnonId: Integer;
    procedure Advance;
    procedure Expect(AKind: TTokenKind; const Msg: string);
    procedure ParseNodeDecl;
    procedure ParseNodeBody(ANode: TGNode);
    procedure ParseTypeDecl;
    procedure ParseStrategyDecl;
    function ParseStrategy: TStrategy;
    function ParseType: TGrispType;
    function ParseTypeName: string;
    function ParseValue(const ATypeName: string): TGValue;
    function ParseExpr: TGrispExpression;
    function ParseOrExpr: TGrispExpression;
    function ParseAndExpr: TGrispExpression;
    function ParseCompareExpr: TGrispExpression;
    function ParseAddExpr: TGrispExpression;
    function ParseMulExpr: TGrispExpression;
    function ParseUnaryExpr: TGrispExpression;
    function ParsePrimaryExpr: TGrispExpression;
    function ExprToValue(Expr: TGrispExpression): TGValue;
    function InnerArrayType(const ATypeName: string): string;
    procedure RegisterEdgesForNode(ANode: TGNode);
    procedure RegisterEdgesForAllNodes;
    function EdgeExists(ASource, ATarget: TGNode; const ALabel: string): Boolean;
  public
    constructor Create(const ASource: string; AGraph: TGGraph);
    destructor Destroy; override;
    procedure ParseFile;
  end;

implementation

constructor TGrispParser.Create(const ASource: string; AGraph: TGGraph);
begin
  inherited Create;
  FLexer := TGrispLexer.Create(ASource);
  FGraph := AGraph;
  FStrategyEngine := TGrispStrategyEngine.Create(AGraph);
  FAnonId := 0;
  Advance;
end;

destructor TGrispParser.Destroy;
begin
  FStrategyEngine.Free;
  FLexer.Free;
  inherited Destroy;
end;

procedure TGrispParser.Advance;
begin
  FCurrent := FLexer.NextToken;
end;

procedure TGrispParser.Expect(AKind: TTokenKind; const Msg: string);
begin
  if FCurrent.Kind <> AKind then
    raise EGrispParseError.CreateFmt('%s at line %d col %d', [Msg, FCurrent.Line, FCurrent.Column]);
  Advance;
end;

procedure TGrispParser.ParseNodeDecl;
var
  NodeName: string;
  Node: TGNode;
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
    if FCurrent.Kind = tkIdentifier then Advance;  // consume 'phase'
    if FCurrent.Kind = tkNumber then
    begin
      PhaseNum := StrToFloat(FCurrent.Lexeme);
      Node.SetAttribute('phase', TGValue.Create(vkNumber));
      Node.GetAttribute('phase').NumberValue := PhaseNum;
      Advance;
    end;
  end;

  Expect(tkLBrace, '{ expected');
  ParseNodeBody(Node);

  // Parse optional temp section
  if (FCurrent.Kind = tkKeywordTemp) or ((FCurrent.Kind = tkIdentifier) and SameText(FCurrent.Lexeme, 'temp')) then
  begin
    if FCurrent.Kind = tkIdentifier then Advance;  // consume 'temp'
    Expect(tkEquals, '"=" expected');
    TempExpr := ParseExpr;
    Node.SetAttribute('temp', ExprToValue(TempExpr));
  end;

  if FCurrent.Kind = tkKeywordWhere then
  begin
    Advance;
    WhereExpr := ParseExpr;
    Node.SetAttribute('where', ExprToValue(WhereExpr));
  end;

  Expect(tkRBrace, '} expected');
end;

procedure TGrispParser.ParseNodeBody(ANode: TGNode);
var
  Key, TypeName: string;
  Value: TGValue;
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
    ANode.SetAttribute(Key, Value);
    if FCurrent.Kind = tkSemicolon then
      Advance;
  end;
end;

procedure TGrispParser.ParseTypeDecl;
var
  TypeName: string;
  Typ: TGrispType;
begin
  Expect(tkKeywordType, '"type" expected');
  TypeName := FCurrent.Lexeme;
  Expect(tkIdentifier, 'name expected');
  Expect(tkEquals, '"=" expected');
  Typ := ParseType;
  FGraph.Types.AddOrSetValue(TypeName, Typ);
end;

function TGrispParser.ParseType: TGrispType;
var
  InnerType: TGrispType;
begin
  if SameText(FCurrent.Lexeme, 'number') then
  begin
    Result := TGrispType.Create(tpNumber);
    Advance;
  end
  else if SameText(FCurrent.Lexeme, 'string') then
  begin
    Result := TGrispType.Create(tpString);
    Advance;
  end
  else if SameText(FCurrent.Lexeme, 'boolean') then
  begin
    Result := TGrispType.Create(tpBoolean);
    Advance;
  end
  else if SameText(FCurrent.Lexeme, 'identifier') then
  begin
    Result := TGrispType.Create(tpIdentifier);
    Advance;
  end
  else if SameText(FCurrent.Lexeme, 'nil') then
  begin
    Result := TGrispType.Create(tpNil);
    Advance;
  end
  else if SameText(FCurrent.Lexeme, 'array') then
  begin
    Advance;
    Expect(tkLess, '"<" expected');
    InnerType := ParseType;
    Result := TGrispType.Create(tpArray);
    Result.ElementType := InnerType;
    Expect(tkGreater, '">" expected');
  end
  else if FCurrent.Kind = tkIdentifier then
  begin
    Result := TGrispType.Create(tpNode);
    Result.NodeType := FCurrent.Lexeme;
    Advance;
  end
  else
    raise EGrispParseError.Create('Type expected');
end;

procedure TGrispParser.ParseStrategyDecl;
var
  StrategyName: string;
  Strat: TStrategy;
begin
  Expect(tkKeywordStrategy, '"strategy" expected');
  StrategyName := FCurrent.Lexeme;
  Expect(tkIdentifier, 'name expected');
  Expect(tkEquals, '"=" expected');
  Strat := ParseStrategy;
  FStrategyEngine.AddStrategy(StrategyName, Strat);
end;

function TGrispParser.ParseStrategy: TStrategy;
var
  Strat: TStrategy;
begin
  if FCurrent.Kind = tkKeywordRepeat then
  begin
    Advance;
    Expect(tkLParen, '"(" expected');
    Result := TStrategy.Create(skRepeat);
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
    Result := TStrategy.Create(skTry);
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
    Result := TStrategy.Create(skChoice);
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
    Result := TStrategy.Create(skPhase);
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
    Result := TStrategy.Create(skRule);
    Result.RuleName := FCurrent.Lexeme;
    Advance;
  end
  else
    raise EGrispParseError.Create('Strategy expected');
end;

function TGrispParser.ParseTypeName: string;
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

function TGrispParser.InnerArrayType(const ATypeName: string): string;
begin
  Result := Copy(ATypeName, 7, Length(ATypeName) - 7);
  if (Length(Result) > 0) and (Result[Length(Result)] = '>') then
    SetLength(Result, Length(Result) - 1);
end;

function TGrispParser.ParseValue(const ATypeName: string): TGValue;
var
  S: string;
  D: Double;
  Node: TGNode;
  InnerType: string;
begin
  // Pattern variable support: bare identifier for scalar types
  if FCurrent.Kind = tkIdentifier then
  begin
    if not SameText(ATypeName, 'node') and not StartsText('array<', ATypeName) then
    begin
      Result := TGValue.Create(vkIdentifier);
      Result.IdentifierValue := FCurrent.Lexeme;
      Advance;
      Exit;
    end;
  end;

  if StartsText('array<', ATypeName) then
  begin
    InnerType := InnerArrayType(ATypeName);
    Expect(tkLBracket, '"[" expected');
    Result := TGValue.Create(vkArray);
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
    Result := TGValue.Create(vkNumber);
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
    Result := TGValue.Create(vkString);
    Result.StringValue := S;
    Exit;
  end;
  if SameText(ATypeName, 'boolean') then
  begin
    if FCurrent.Kind <> tkBoolean then raise EGrispParseError.Create('boolean expected');
    Result := TGValue.Create(vkBoolean);
    Result.BoolValue := SameText(FCurrent.Lexeme, 'true');
    Advance;
    Exit;
  end;
  if SameText(ATypeName, 'identifier') then
  begin
    if not (FCurrent.Kind in [tkIdentifier, tkKeywordNode, tkKeywordArray]) then
      raise EGrispParseError.Create('identifier expected');
    Result := TGValue.Create(vkIdentifier);
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
    Result := TGValue.Create(vkNode);
    Result.NodeValue := Node;
    Exit;
  end;
  raise EGrispParseError.CreateFmt('Unknown type "%s"', [ATypeName]);
end;

function TGrispParser.ExprToValue(Expr: TGrispExpression): TGValue;
begin
  Result := TGValue.Create(vkExpression);
  Result.ExpressionValue := Expr;
end;

function TGrispParser.ParseExpr: TGrispExpression;
begin
  Result := ParseOrExpr;
end;

function TGrispParser.ParseOrExpr: TGrispExpression;
var
  Left, Right: TGrispExpression;
begin
  Left := ParseAndExpr;
  while FCurrent.Kind = tkKeywordOr do
  begin
    Advance;
    Right := ParseAndExpr;
    Result := TGrispExpression.Create(ekBinary);
    Result.OperatorSymbol := 'or';
    Result.Left := Left;
    Result.Right := Right;
    Left := Result;
  end;
  Result := Left;
end;

function TGrispParser.ParseAndExpr: TGrispExpression;
var
  Left, Right: TGrispExpression;
begin
  Left := ParseCompareExpr;
  while FCurrent.Kind = tkKeywordAnd do
  begin
    Advance;
    Right := ParseCompareExpr;
    Result := TGrispExpression.Create(ekBinary);
    Result.OperatorSymbol := 'and';
    Result.Left := Left;
    Result.Right := Right;
    Left := Result;
  end;
  Result := Left;
end;

function TGrispParser.ParseCompareExpr: TGrispExpression;
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
    Result := TGrispExpression.Create(ekBinary);
    Result.OperatorSymbol := Op;
    Result.Left := Left;
    Result.Right := Right;
    Left := Result;
  end;
  Result := Left;
end;

function TGrispParser.ParseAddExpr: TGrispExpression;
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
    Result := TGrispExpression.Create(ekBinary);
    Result.OperatorSymbol := Op;
    Result.Left := Left;
    Result.Right := Right;
    Left := Result;
  end;
  Result := Left;
end;

function TGrispParser.ParseMulExpr: TGrispExpression;
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
    Result := TGrispExpression.Create(ekBinary);
    Result.OperatorSymbol := Op;
    Result.Left := Left;
    Result.Right := Right;
    Left := Result;
  end;
  Result := Left;
end;

function TGrispParser.ParseUnaryExpr: TGrispExpression;
begin
  if FCurrent.Kind = tkKeywordNot then
  begin
    Advance;
    Result := TGrispExpression.Create(ekUnary);
    Result.OperatorSymbol := 'not';
    Result.Left := ParseUnaryExpr;
    Exit;
  end;
  if (FCurrent.Kind = tkOperator) and (FCurrent.Lexeme = '-') then
  begin
    Advance;
    Result := TGrispExpression.Create(ekUnary);
    Result.OperatorSymbol := '-';
    Result.Left := ParseUnaryExpr;
    Exit;
  end;
  Result := ParsePrimaryExpr;
end;

function TGrispParser.ParsePrimaryExpr: TGrispExpression;
var
  Name: string;
begin
  if FCurrent.Kind = tkNumber then
  begin
    Result := TGrispExpression.Create(ekLiteral);
    Result.Value := TGValue.Create(vkNumber);
    TGValue(Result.Value).NumberValue := StrToFloat(FCurrent.Lexeme);
    Advance;
    Exit;
  end;
  if FCurrent.Kind = tkBoolean then
  begin
    Result := TGrispExpression.Create(ekLiteral);
    Result.Value := TGValue.Create(vkBoolean);
    TGValue(Result.Value).BoolValue := SameText(FCurrent.Lexeme, 'true');
    Advance;
    Exit;
  end;
  if FCurrent.Kind = tkIdentifier then
  begin
    Name := FCurrent.Lexeme;
    Advance;
    if FCurrent.Kind = tkLParen then
    begin
      Result := TGrispExpression.Create(ekCall);
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
      Result := TGrispExpression.Create(ekVariable);
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

function TGrispParser.EdgeExists(ASource, ATarget: TGNode; const ALabel: string): Boolean;
var
  E: TGEdge;
begin
  for E in FGraph.Edges do
    if (E.Source = ASource) and (E.Target = ATarget) and SameText(E.LabelName, ALabel) then
      Exit(True);
  Result := False;
end;

procedure TGrispParser.RegisterEdgesForNode(ANode: TGNode);
var
  Key: string;
  Val: TGValue;
  Target: TGNode;
  Elem: TGValue;
begin
  for Key in ANode.Attributes.Keys do
  begin
    Val := ANode.GetAttribute(Key);
    if Val = nil then Continue;
    case Val.Kind of
      vkNode:
        if Assigned(Val.NodeValue) and not EdgeExists(ANode, Val.NodeValue, Key) then
          FGraph.AddEdge(ANode, Val.NodeValue, Key, '');
      vkIdentifier:
        begin
          Target := FGraph.FindNode(Val.IdentifierValue);
          if Assigned(Target) and not EdgeExists(ANode, Target, Key) then
            FGraph.AddEdge(ANode, Target, Key, '');
        end;
      vkArray:
        for Elem in Val.ArrayValue do
        begin
          if Elem.Kind = vkNode then
          begin
            if Assigned(Elem.NodeValue) and not EdgeExists(ANode, Elem.NodeValue, Key) then
              FGraph.AddEdge(ANode, Elem.NodeValue, Key, '');
          end
          else if Elem.Kind = vkIdentifier then
          begin
            Target := FGraph.FindNode(Elem.IdentifierValue);
            if Assigned(Target) and not EdgeExists(ANode, Target, Key) then
              FGraph.AddEdge(ANode, Target, Key, '');
          end;
        end;
    end;
  end;
end;

procedure TGrispParser.RegisterEdgesForAllNodes;
var
  Node: TGNode;
begin
  for Node in FGraph.Nodes do
    RegisterEdgesForNode(Node);
end;

procedure TGrispParser.ParseFile;
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
