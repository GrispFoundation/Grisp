unit unit_Parser_TGrispParserBase_version_001;

interface

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  unit_Token_TGrispTokenKind_version_001,
  unit_Token_TGrispToken_version_001,
  unit_Lexer_TGrispLexer_version_001,
  unit_Graph_TGrispGraph_version_001,
  unit_Core_TGrispExpression_version_001,
  unit_Core_TGrispValueBase_version_001;

type
  EGrispParseError = class(Exception);

  TGrispParserBase = class
  protected
    FLexer: TGrispLexer;
    FCurrent: TGrispToken;
    FGraph: TGrispGraph;
    FAnonId: Integer;
    FOwnsLexer: Boolean;

    procedure Advance;
    procedure Expect(AKind: TGrispTokenKind; const Msg: string);
    function ParseTypeName: string;
    function InnerArrayType(const ATypeName: string): string;
    function ParseExpr: TGrispExpression;
    function ParseOrExpr: TGrispExpression;
    function ParseAndExpr: TGrispExpression;
    function ParseCompareExpr: TGrispExpression;
    function ParseAddExpr: TGrispExpression;
    function ParseMulExpr: TGrispExpression;
    function ParseUnaryExpr: TGrispExpression;
    function ParsePrimaryExpr: TGrispExpression;
    function ExprToValue(Expr: TGrispExpression): TGrispValue;
  public
    constructor Create(const ASource: string; AGraph: TGrispGraph);
    constructor CreateShared(Parent: TGrispParserBase); virtual;
    destructor Destroy; override;
    procedure ParseFile; virtual;
  end;

implementation

constructor TGrispParserBase.Create(const ASource: string; AGraph: TGrispGraph);
begin
  inherited Create;
  FLexer := TGrispLexer.Create(ASource);
  FGraph := AGraph;
  FAnonId := 0;
  FOwnsLexer := True;
  Advance;
end;

constructor TGrispParserBase.CreateShared(Parent: TGrispParserBase);
begin
  inherited Create;
  FLexer := Parent.FLexer;
  FCurrent := Parent.FCurrent;
  FGraph := Parent.FGraph;
  FAnonId := Parent.FAnonId;
  FOwnsLexer := False;
  // DON'T call Advance() - token stream is already positioned
end;

destructor TGrispParserBase.Destroy;
begin
  if FOwnsLexer then
    FLexer.Free;
  inherited Destroy;
end;

procedure TGrispParserBase.Advance;
begin
  FCurrent := FLexer.NextToken;
end;

procedure TGrispParserBase.Expect(AKind: TGrispTokenKind; const Msg: string);
begin
  if FCurrent.Kind <> AKind then
    raise EGrispParseError.CreateFmt('%s at line %d col %d', [Msg, FCurrent.Line, FCurrent.Column]);
  Advance;
end;

function TGrispParserBase.ParseTypeName: string;
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

function TGrispParserBase.InnerArrayType(const ATypeName: string): string;
begin
  Result := Copy(ATypeName, 7, Length(ATypeName) - 7);
  if (Length(Result) > 0) and (Result[Length(Result)] = '>') then
    SetLength(Result, Length(Result) - 1);
end;

function TGrispParserBase.ExprToValue(Expr: TGrispExpression): TGrispValue;
begin
  Result := TGrispValue.Create(gvkExpression);
  Result.ExpressionValue := Expr;
end;

function TGrispParserBase.ParseExpr: TGrispExpression;
begin
  Result := ParseOrExpr;
end;

function TGrispParserBase.ParseOrExpr: TGrispExpression;
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

function TGrispParserBase.ParseAndExpr: TGrispExpression;
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

function TGrispParserBase.ParseCompareExpr: TGrispExpression;
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

function TGrispParserBase.ParseAddExpr: TGrispExpression;
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

function TGrispParserBase.ParseMulExpr: TGrispExpression;
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

function TGrispParserBase.ParseUnaryExpr: TGrispExpression;
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

function TGrispParserBase.ParsePrimaryExpr: TGrispExpression;
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

procedure TGrispParserBase.ParseFile;
begin
  // To be overridden by descendant
end;

end.
