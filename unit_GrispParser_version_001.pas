unit unit_GrispParser_version_001;

interface

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  unit_GrispTokens_version_001,
  unit_GrispLexer_version_001,
  unit_GrispGraph_version_001;

type
  EGrispParseError = class(Exception);

  TGrispParser = class
  private
    FLexer: TGrispLexer;
    FCurrent: TToken;
    FGraph: TGGraph;
    procedure Advance;
    procedure Expect(AKind: TTokenKind; const Msg: string);
    procedure ParseNodeDecl;
    procedure ParseNodeBody(ANode: TGNode);
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
  public
    constructor Create(const ASource: string);
    destructor Destroy; override;
    function Parse: TGGraph;
  end;

implementation

constructor TGrispParser.Create(const ASource: string);
begin
  inherited Create;
  FLexer := TGrispLexer.Create(ASource);
  FGraph := TGGraph.Create;
  Advance;
end;

destructor TGrispParser.Destroy;
begin
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
  begin
    raise EGrispParseError.CreateFmt('%s at line %d col %d', [Msg, FCurrent.Line, FCurrent.Column]);
  end;
  Advance;
end;

procedure TGrispParser.ParseNodeDecl;
var
  NodeName: string;
  Node: TGNode;
  WhereExpr: TGrispExpression;
begin
  Expect(tkKeywordNode, '"node" expected');
  NodeName := FCurrent.Lexeme;
  Expect(tkIdentifier, 'name expected');
  Node := FGraph.AddNode(NodeName, 'node');
  if StartsText('rule.', NodeName) then
  begin
    FGraph.RegisterRule(Node);
  end;
  Expect(tkLBrace, '{ expected');
  ParseNodeBody(Node);
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
  Key: string;
  TypeName: string;
  Value: TGValue;
begin
  while (FCurrent.Kind <> tkRBrace) and (FCurrent.Kind <> tkEOF) do
  begin
    if not (FCurrent.Kind in [tkIdentifier, tkKeywordNode, tkKeywordArray]) then
    begin
      raise EGrispParseError.CreateFmt('Attribute name expected at %d:%d', [FCurrent.Line, FCurrent.Column]);
    end;
    Key := FCurrent.Lexeme;
    Advance;
    Expect(tkColon, '":" expected');
    TypeName := ParseTypeName;
    Expect(tkEquals, '"=" expected');
    Value := ParseValue(TypeName);
    ANode.SetAttribute(Key, Value);
  end;
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
  begin
    SetLength(Result, Length(Result) - 1);
  end;
end;

function TGrispParser.ParseValue(const ATypeName: string): TGValue;
var
  S: string;
  D: Double;
  Node: TGNode;
  InnerType: string;
begin
  if StartsText('array<', ATypeName) then
  begin
    InnerType := InnerArrayType(ATypeName);
    Expect(tkLBracket, '"[" expected');
    Result := TGValue.Create(vkArray);
    while FCurrent.Kind <> tkRBracket do
    begin
      Result.ArrayValue.Add(ParseValue(InnerType));
      if FCurrent.Kind = tkComma then
      begin
        Advance;
      end
      else
      begin
        Break;
      end;
    end;
    Expect(tkRBracket, '"]" expected');
    Exit;
  end;

  if SameText(ATypeName, 'number') then
  begin
    if FCurrent.Kind <> tkNumber then
    begin
      raise EGrispParseError.Create('number expected');
    end;
    D := StrToFloat(FCurrent.Lexeme);
    Advance;
    Result := TGValue.Create(vkNumber);
    Result.NumberValue := D;
    Exit;
  end;
  if SameText(ATypeName, 'string') then
  begin
    if FCurrent.Kind <> tkString then
    begin
      raise EGrispParseError.Create('string expected');
    end;
    S := FCurrent.Lexeme;
    Advance;
    if (Length(S) >= 2) and CharInSet(S[1], ['''', '"']) then
    begin
      S := Copy(S, 2, Length(S) - 2);
    end;
    Result := TGValue.Create(vkString);
    Result.StringValue := S;
    Exit;
  end;
  if SameText(ATypeName, 'boolean') then
  begin
    if FCurrent.Kind <> tkBoolean then
    begin
      raise EGrispParseError.Create('boolean expected');
    end;
    Result := TGValue.Create(vkBoolean);
    Result.BoolValue := SameText(FCurrent.Lexeme, 'true');
    Advance;
    Exit;
  end;
  if SameText(ATypeName, 'identifier') then
  begin
    if not (FCurrent.Kind in [tkIdentifier, tkKeywordNode, tkKeywordArray]) then
    begin
      raise EGrispParseError.Create('identifier expected');
    end;
    Result := TGValue.Create(vkIdentifier);
    Result.IdentifierValue := FCurrent.Lexeme;
    Advance;
    Exit;
  end;
  if SameText(ATypeName, 'node') then
  begin
    Expect(tkLBrace, '"{" expected');
    Node := FGraph.AddNode('', 'node');
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
  Left: TGrispExpression;
  Right: TGrispExpression;
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
  Left: TGrispExpression;
  Right: TGrispExpression;
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
  Left: TGrispExpression;
  Right: TGrispExpression;
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
  Left: TGrispExpression;
  Right: TGrispExpression;
  Op: string;
begin
  Left := ParseMulExpr;
  while (FCurrent.Lexeme = '+') or (FCurrent.Lexeme = '-') do
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
  Left: TGrispExpression;
  Right: TGrispExpression;
  Op: string;
begin
  Left := ParseUnaryExpr;
  while (FCurrent.Lexeme = '*') or (FCurrent.Lexeme = '/') or (FCurrent.Kind = tkKeywordMod) do
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
  if FCurrent.Lexeme = '-' then
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
      while FCurrent.Kind <> tkRParen do
      begin
        Result.Arguments.Add(ParseExpr);
        if FCurrent.Kind = tkComma then
        begin
          Advance;
        end;
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
    if Val = nil then
    begin
      Continue;
    end;
    case Val.Kind of
      vkNode:
        begin
          if Assigned(Val.NodeValue) then
          begin
            FGraph.AddEdge(ANode, Val.NodeValue, Key);
          end;
        end;
      vkIdentifier:
        begin
          Target := FGraph.FindNode(Val.IdentifierValue);
          if Assigned(Target) then
          begin
            FGraph.AddEdge(ANode, Target, Key);
          end;
        end;
      vkArray:
        begin
          for Elem in Val.ArrayValue do
          begin
            if Elem.Kind = vkNode then
            begin
              if Assigned(Elem.NodeValue) then
              begin
                FGraph.AddEdge(ANode, Elem.NodeValue, Key);
              end;
            end
            else
            begin
              if Elem.Kind = vkIdentifier then
              begin
                Target := FGraph.FindNode(Elem.IdentifierValue);
                if Assigned(Target) then
                begin
                  FGraph.AddEdge(ANode, Target, Key);
                end;
              end;
            end;
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
  begin
    RegisterEdgesForNode(Node);
  end;
end;

function TGrispParser.Parse: TGGraph;
begin
  while FCurrent.Kind <> tkEOF do
  begin
    ParseNodeDecl;
  end;
  RegisterEdgesForAllNodes;
  Result := FGraph;
end;

end.
