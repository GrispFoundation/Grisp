unit unit_Parser_TGrispUnifiedParser_version_001;

interface

uses
  System.SysUtils,
  System.StrUtils,
  System.TypInfo,
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
  unit_Debug_TGrispDebug_version_001;  // Remove StrategyEngine from uses

type
  EGrispParseError = class(Exception);

  TGrispUnifiedParser = class
  private
    FLexer: TGrispLexer;
    FCurrent: TGrispToken;
    FGraph: TGrispGraph;
    FAnonId: Integer;
    FDebugEnabled: Boolean;

    procedure Debug(const Msg: string);
    procedure DebugEnter(const Method: string);
    procedure DebugExit(const Method: string);
    procedure DebugToken(const Prefix: string);
    procedure DebugValue(const Prefix: string; const Value: TGrispValue);
    procedure DebugNode(const Prefix: string; const Node: TGrispNode);
    procedure DebugAttribute(const Prefix: string; const Key: string; const Value: TGrispValue);

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

    procedure EnableDebug;
    procedure DisableDebug;

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
  FDebugEnabled := False;
  FLexer := TGrispLexer.Create(ASource);
  FGraph := AGraph;
  FAnonId := 0;
  Advance;
  Debug('Parser created');
end;

destructor TGrispUnifiedParser.Destroy;
begin
  Debug('Parser destroyed');
  FLexer.Free;
  inherited Destroy;
end;

procedure TGrispUnifiedParser.EnableDebug;
begin
  FDebugEnabled := True;
  TGrispDebug.Enable;
  Debug('Debug enabled');
end;

procedure TGrispUnifiedParser.DisableDebug;
begin
  Debug('Debug disabled');
  FDebugEnabled := False;
  TGrispDebug.Disable;
end;

procedure TGrispUnifiedParser.Debug(const Msg: string);
begin
  if FDebugEnabled then
    TGrispDebug.Log(Msg);
end;

procedure TGrispUnifiedParser.DebugEnter(const Method: string);
begin
  if FDebugEnabled then
    TGrispDebug.LogEnter(Method);
end;

procedure TGrispUnifiedParser.DebugExit(const Method: string);
begin
  if FDebugEnabled then
    TGrispDebug.LogExit(Method);
end;

procedure TGrispUnifiedParser.DebugToken(const Prefix: string);
begin
  if FDebugEnabled then
    TGrispDebug.LogToken(Prefix, FCurrent);
end;

procedure TGrispUnifiedParser.DebugValue(const Prefix: string; const Value: TGrispValue);
begin
  if FDebugEnabled then
    TGrispDebug.LogValue(Prefix, Value);
end;

procedure TGrispUnifiedParser.DebugNode(const Prefix: string; const Node: TGrispNode);
begin
  if FDebugEnabled then
    TGrispDebug.LogNode(Prefix, Node);
end;

procedure TGrispUnifiedParser.DebugAttribute(const Prefix: string; const Key: string; const Value: TGrispValue);
begin
  if not FDebugEnabled then Exit;
  Debug(Format('%s Attribute: %s = %s', [Prefix, Key, Value.ToString]));
end;

procedure TGrispUnifiedParser.Advance;
begin
  DebugToken('Advance from');
  FCurrent := FLexer.NextToken;
  DebugToken('Advance to');
end;

procedure TGrispUnifiedParser.Expect(AKind: TGrispTokenKind; const Msg: string);
begin
  Debug(Format('Expect: %s, Current: %s',
    [GetEnumName(TypeInfo(TGrispTokenKind), Ord(AKind)),
     GetEnumName(TypeInfo(TGrispTokenKind), Ord(FCurrent.Kind))]));
  if FCurrent.Kind <> AKind then
    raise EGrispParseError.CreateFmt('%s at line %d col %d', [Msg, FCurrent.Line, FCurrent.Column]);
  Advance;
end;

function TGrispUnifiedParser.ParseTypeName: string;
var
  Inner: string;
begin
  DebugEnter('ParseTypeName');
  DebugToken('Start');
  Result := FCurrent.Lexeme;
  Debug('Type name: ' + Result);
  Advance;
  if SameText(Result, 'array') then
  begin
    Debug('Parsing array type');
    Expect(tkLess, '"<" expected');
    Inner := FCurrent.Lexeme;
    Debug('Inner type: ' + Inner);
    Advance;
    Expect(tkGreater, '">" expected');
    Result := 'array<' + Inner + '>';
    Debug('Array type: ' + Result);
  end;
  DebugExit('ParseTypeName');
end;

function TGrispUnifiedParser.InnerArrayType(const ATypeName: string): string;
begin
  DebugEnter('InnerArrayType');
  Debug('ATypeName: ' + ATypeName);
  Result := Copy(ATypeName, 7, Length(ATypeName) - 7);
  if (Length(Result) > 0) and (Result[Length(Result)] = '>') then
    SetLength(Result, Length(Result) - 1);
  Debug('Result: ' + Result);
  DebugExit('InnerArrayType');
end;

function TGrispUnifiedParser.ParseType: TGrispType;
var
  InnerType: TGrispType;
begin
  DebugEnter('ParseType');
  DebugToken('Start');

  if SameText(FCurrent.Lexeme, 'number') then
  begin
    Debug('Type: number');
    Result := TGrispType.Create(gtkNumber);
    Advance;
  end
  else if SameText(FCurrent.Lexeme, 'string') then
  begin
    Debug('Type: string');
    Result := TGrispType.Create(gtkString);
    Advance;
  end
  else if SameText(FCurrent.Lexeme, 'boolean') then
  begin
    Debug('Type: boolean');
    Result := TGrispType.Create(gtkBoolean);
    Advance;
  end
  else if SameText(FCurrent.Lexeme, 'identifier') then
  begin
    Debug('Type: identifier');
    Result := TGrispType.Create(gtkIdentifier);
    Advance;
  end
  else if SameText(FCurrent.Lexeme, 'nil') then
  begin
    Debug('Type: nil');
    Result := TGrispType.Create(gtkNil);
    Advance;
  end
  else if SameText(FCurrent.Lexeme, 'array') then
  begin
    Debug('Type: array');
    Advance;
    Expect(tkLess, '"<" expected');
    InnerType := ParseType;
    Result := TGrispType.Create(gtkArray);
    Result.ElementType := InnerType;
    Expect(tkGreater, '">" expected');
  end
  else if FCurrent.Kind = tkIdentifier then
  begin
    Debug('Type: node<' + FCurrent.Lexeme + '>');
    Result := TGrispType.Create(gtkNode);
    Result.NodeTypeName := FCurrent.Lexeme;
    Advance;
  end
  else
    raise EGrispParseError.Create('Type expected');

  DebugExit('ParseType');
end;

function TGrispUnifiedParser.ParseValue(const ATypeName: string): TGrispValue;
var
  S: string;
  D: Double;
  Node: TGrispNode;
  InnerType: string;
begin
  DebugEnter('ParseValue');
  Debug('ATypeName: ' + ATypeName);
  DebugToken('Start');

  // Pattern variable support: bare identifier for scalar types
  if FCurrent.Kind = tkIdentifier then
  begin
    if not SameText(ATypeName, 'node') and not StartsText('array<', ATypeName) then
    begin
      Debug('Pattern variable: ' + FCurrent.Lexeme);
      Result := TGrispValue.Create(gvkIdentifier);
      Result.IdentifierValue := FCurrent.Lexeme;
      Advance;
      DebugValue('Created', Result);
      DebugExit('ParseValue');
      Exit;
    end;
  end;

  if StartsText('array<', ATypeName) then
  begin
    Debug('Parsing array value');
    InnerType := InnerArrayType(ATypeName);
    Expect(tkLBracket, '"[" expected');
    Result := TGrispValue.Create(gvkArray);
    while (FCurrent.Kind <> tkRBracket) and (FCurrent.Kind <> tkEOF) do
    begin
      Debug('Adding array element');
      Result.ArrayValue.Add(ParseValue(InnerType));
      if FCurrent.Kind = tkComma then Advance else Break;
    end;
    Expect(tkRBracket, '"]" expected');
    DebugValue('Created array', Result);
    DebugExit('ParseValue');
    Exit;
  end;

  if SameText(ATypeName, 'number') then
  begin
    Debug('Parsing number');
    if FCurrent.Kind <> tkNumber then raise EGrispParseError.Create('number expected');
    D := StrToFloat(FCurrent.Lexeme);
    Advance;
    Result := TGrispValue.Create(gvkNumber);
    Result.NumberValue := D;
    DebugValue('Created number', Result);
    DebugExit('ParseValue');
    Exit;
  end;

  if SameText(ATypeName, 'string') then
  begin
    Debug('Parsing string');
    if FCurrent.Kind <> tkString then raise EGrispParseError.Create('string expected');
    S := FCurrent.Lexeme;
    Advance;
    if (Length(S) >= 2) and CharInSet(S[1], ['''', '"']) then
      S := Copy(S, 2, Length(S) - 2);
    Result := TGrispValue.Create(gvkString);
    Result.StringValue := S;
    DebugValue('Created string', Result);
    DebugExit('ParseValue');
    Exit;
  end;

  if SameText(ATypeName, 'boolean') then
  begin
    Debug('Parsing boolean');
    if FCurrent.Kind <> tkBoolean then raise EGrispParseError.Create('boolean expected');
    Result := TGrispValue.Create(gvkBoolean);
    Result.BoolValue := SameText(FCurrent.Lexeme, 'true');
    Advance;
    DebugValue('Created boolean', Result);
    DebugExit('ParseValue');
    Exit;
  end;

  if SameText(ATypeName, 'identifier') then
  begin
    Debug('Parsing identifier');
    if not (FCurrent.Kind in [tkIdentifier, tkKeywordNode, tkKeywordArray]) then
      raise EGrispParseError.Create('identifier expected');
    Result := TGrispValue.Create(gvkIdentifier);
    Result.IdentifierValue := FCurrent.Lexeme;
    Advance;
    DebugValue('Created identifier', Result);
    DebugExit('ParseValue');
    Exit;
  end;

  if SameText(ATypeName, 'node') then
  begin
    Debug('Parsing node value');

    // Case 1: Inline node literal
    if FCurrent.Kind = tkLBrace then
    begin
      Debug('Inline node literal');
      Expect(tkLBrace, '"{" expected');
      Inc(FAnonId);
      Node := FGraph.AddNode('#' + IntToStr(FAnonId), 'pattern');
      DebugNode('Created nested node', Node);
      ParseNodeBody(Node);
      Expect(tkRBrace, '"}" expected');
      Result := TGrispValue.Create(gvkNode);
      Result.SetNodeReference(Node.Id, Node.Name);
      DebugValue('Created node reference', Result);
      DebugExit('ParseValue');
      Exit;
    end;

    // Case 2: Reference to existing node by identifier
    if FCurrent.Kind = tkIdentifier then
    begin
      Debug('Node reference: ' + FCurrent.Lexeme);
      Result := TGrispValue.Create(gvkIdentifier);
      Result.IdentifierValue := FCurrent.Lexeme;
      Advance;
      DebugValue('Created node reference', Result);
      DebugExit('ParseValue');
      Exit;
    end;

    raise EGrispParseError.Create('"{" or identifier expected for node value');
  end;

  Debug('Unknown type: ' + ATypeName);
  raise EGrispParseError.CreateFmt('Unknown type "%s"', [ATypeName]);
end;

procedure TGrispUnifiedParser.ParseNodeBody(ANode: TGrispNode);
var
  Key, TypeName: string;
  Value: TGrispValue;
  AttrCount: Integer;
begin
  DebugEnter('ParseNodeBody');
  DebugNode('For node', ANode);
  AttrCount := 0;

  while (FCurrent.Kind <> tkRBrace) and (FCurrent.Kind <> tkEOF) and
        (FCurrent.Kind <> tkKeywordWhere) do
  begin
    Debug('Parsing attribute #' + IntToStr(AttrCount + 1));
    DebugToken('Attribute start');

    if not (FCurrent.Kind in [tkIdentifier, tkKeywordNode, tkKeywordArray]) then
      raise EGrispParseError.CreateFmt('Attribute name expected at %d:%d', [FCurrent.Line, FCurrent.Column]);

    Key := FCurrent.Lexeme;
    Debug('Key: ' + Key);
    Advance;

    Expect(tkColon, '":" expected');
    TypeName := ParseTypeName;
    Debug('TypeName: ' + TypeName);

    Expect(tkEquals, '"=" expected');
    Value := ParseValue(TypeName);

    DebugAttribute('Setting', Key, Value);
    ANode.SetValueAttribute(Key, Value);
    Inc(AttrCount);

    if FCurrent.Kind = tkSemicolon then
    begin
      Debug('Semicolon separator');
      Advance;
    end;
  end;

  Debug(Format('ParseNodeBody complete: %d attributes', [AttrCount]));
  DebugExit('ParseNodeBody');
end;

function TGrispUnifiedParser.ExprToValue(Expr: TGrispExpression): TGrispValue;
begin
  DebugEnter('ExprToValue');
  Result := TGrispValue.Create(gvkExpression);
  Result.ExpressionValue := Expr;
  DebugValue('Created', Result);
  DebugExit('ExprToValue');
end;

function TGrispUnifiedParser.ParseExpr: TGrispExpression;
begin
  DebugEnter('ParseExpr');
  Result := ParseOrExpr;
  DebugExit('ParseExpr');
end;

function TGrispUnifiedParser.ParseOrExpr: TGrispExpression;
var
  Left, Right: TGrispExpression;
begin
  DebugEnter('ParseOrExpr');
  Left := ParseAndExpr;
  while FCurrent.Kind = tkKeywordOr do
  begin
    Debug('OR operator found');
    Advance;
    Right := ParseAndExpr;
    Result := TGrispExpression.Create(gekBinary);
    Result.OperatorSymbol := 'or';
    Result.Left := Left;
    Result.Right := Right;
    Left := Result;
  end;
  Result := Left;
  DebugExit('ParseOrExpr');
end;

function TGrispUnifiedParser.ParseAndExpr: TGrispExpression;
var
  Left, Right: TGrispExpression;
begin
  DebugEnter('ParseAndExpr');
  Left := ParseCompareExpr;
  while FCurrent.Kind = tkKeywordAnd do
  begin
    Debug('AND operator found');
    Advance;
    Right := ParseCompareExpr;
    Result := TGrispExpression.Create(gekBinary);
    Result.OperatorSymbol := 'and';
    Result.Left := Left;
    Result.Right := Right;
    Left := Result;
  end;
  Result := Left;
  DebugExit('ParseAndExpr');
end;

function TGrispUnifiedParser.ParseCompareExpr: TGrispExpression;
var
  Left, Right: TGrispExpression;
  Op: string;
begin
  DebugEnter('ParseCompareExpr');
  Left := ParseAddExpr;
  while FCurrent.Kind in [tkEquals, tkNotEqual, tkLess, tkGreater, tkLessEqual, tkGreaterEqual] do
  begin
    Op := FCurrent.Lexeme;
    Debug('Compare operator: ' + Op);
    Advance;
    Right := ParseAddExpr;
    Result := TGrispExpression.Create(gekBinary);
    Result.OperatorSymbol := Op;
    Result.Left := Left;
    Result.Right := Right;
    Left := Result;
  end;
  Result := Left;
  DebugExit('ParseCompareExpr');
end;

function TGrispUnifiedParser.ParseAddExpr: TGrispExpression;
var
  Left, Right: TGrispExpression;
  Op: string;
begin
  DebugEnter('ParseAddExpr');
  Left := ParseMulExpr;
  while (FCurrent.Kind = tkOperator) and ((FCurrent.Lexeme = '+') or (FCurrent.Lexeme = '-')) do
  begin
    Op := FCurrent.Lexeme;
    Debug('Add operator: ' + Op);
    Advance;
    Right := ParseMulExpr;
    Result := TGrispExpression.Create(gekBinary);
    Result.OperatorSymbol := Op;
    Result.Left := Left;
    Result.Right := Right;
    Left := Result;
  end;
  Result := Left;
  DebugExit('ParseAddExpr');
end;

function TGrispUnifiedParser.ParseMulExpr: TGrispExpression;
var
  Left, Right: TGrispExpression;
  Op: string;
begin
  DebugEnter('ParseMulExpr');
  Left := ParseUnaryExpr;
  while ((FCurrent.Kind = tkOperator) and ((FCurrent.Lexeme = '*') or (FCurrent.Lexeme = '/'))) or
        (FCurrent.Kind = tkKeywordMod) do
  begin
    Op := FCurrent.Lexeme;
    Debug('Mul operator: ' + Op);
    Advance;
    Right := ParseUnaryExpr;
    Result := TGrispExpression.Create(gekBinary);
    Result.OperatorSymbol := Op;
    Result.Left := Left;
    Result.Right := Right;
    Left := Result;
  end;
  Result := Left;
  DebugExit('ParseMulExpr');
end;

function TGrispUnifiedParser.ParseUnaryExpr: TGrispExpression;
begin
  DebugEnter('ParseUnaryExpr');
  if FCurrent.Kind = tkKeywordNot then
  begin
    Debug('NOT operator');
    Advance;
    Result := TGrispExpression.Create(gekUnary);
    Result.OperatorSymbol := 'not';
    Result.Left := ParseUnaryExpr;
    DebugExit('ParseUnaryExpr');
    Exit;
  end;
  if (FCurrent.Kind = tkOperator) and (FCurrent.Lexeme = '-') then
  begin
    Debug('Unary minus');
    Advance;
    Result := TGrispExpression.Create(gekUnary);
    Result.OperatorSymbol := '-';
    Result.Left := ParseUnaryExpr;
    DebugExit('ParseUnaryExpr');
    Exit;
  end;
  Result := ParsePrimaryExpr;
  DebugExit('ParseUnaryExpr');
end;

function TGrispUnifiedParser.ParsePrimaryExpr: TGrispExpression;
var
  Name: string;
begin
  DebugEnter('ParsePrimaryExpr');
  DebugToken('Start');

  if FCurrent.Kind = tkNumber then
  begin
    Debug('Number literal');
    Result := TGrispExpression.Create(gekLiteral);
    Result.Value := TGrispValue.Create(gvkNumber);
    TGrispValue(Result.Value).NumberValue := StrToFloat(FCurrent.Lexeme);
    Advance;
    DebugExit('ParsePrimaryExpr');
    Exit;
  end;

  if FCurrent.Kind = tkBoolean then
  begin
    Debug('Boolean literal');
    Result := TGrispExpression.Create(gekLiteral);
    Result.Value := TGrispValue.Create(gvkBoolean);
    TGrispValue(Result.Value).BoolValue := SameText(FCurrent.Lexeme, 'true');
    Advance;
    DebugExit('ParsePrimaryExpr');
    Exit;
  end;

  if FCurrent.Kind = tkIdentifier then
  begin
    Name := FCurrent.Lexeme;
    Debug('Identifier: ' + Name);
    Advance;
    if FCurrent.Kind = tkLParen then
    begin
      Debug('Function call: ' + Name);
      Result := TGrispExpression.Create(gekCall);
      Result.Name := Name;
      Advance;
      while (FCurrent.Kind <> tkRParen) and (FCurrent.Kind <> tkEOF) do
      begin
        Result.Arguments.Add(ParseExpr);
        if FCurrent.Kind = tkComma then Advance else Break;
      end;
      Expect(tkRParen, '")" expected');
      DebugExit('ParsePrimaryExpr');
      Exit;
    end
    else
    begin
      Debug('Variable: ' + Name);
      Result := TGrispExpression.Create(gekVariable);
      Result.Name := Name;
      DebugExit('ParsePrimaryExpr');
      Exit;
    end;
  end;

  if FCurrent.Kind = tkLParen then
  begin
    Debug('Parenthesized expression');
    Advance;
    Result := ParseExpr;
    Expect(tkRParen, '")" expected');
    DebugExit('ParsePrimaryExpr');
    Exit;
  end;

  raise EGrispParseError.Create('Expression expected');
end;

function TGrispUnifiedParser.ParseStrategy: TGrispStrategy;
begin
  DebugEnter('ParseStrategy');
  DebugToken('Start');

  if FCurrent.Kind = tkKeywordRepeat then
  begin
    Debug('Strategy: repeat');
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
    Debug('Strategy: try');
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
    Debug('Strategy: choice');
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
    Debug('Strategy: phase');
    if FCurrent.Kind = tkIdentifier then Advance;
    Expect(tkLParen, '"(" expected');
    Result := TGrispStrategy.Create(gskPhase);
    if FCurrent.Kind = tkNumber then
    begin
      Result.Phase := Trunc(StrToFloat(FCurrent.Lexeme));
      Debug('Phase number: ' + IntToStr(Result.Phase));
      Advance;
      // FIX: Consume comma if present
      if FCurrent.Kind = tkComma then
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
    Debug('Strategy: rule - ' + FCurrent.Lexeme);
    Result := TGrispStrategy.Create(gskRule);
    Result.RuleName := FCurrent.Lexeme;
    Advance;
  end
  else
    raise EGrispParseError.Create('Strategy expected');

  DebugExit('ParseStrategy');
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
  DebugEnter('RegisterEdgesForNode');
  DebugNode('For node', ANode);

  for Key in ANode.GetAttributeKeys do
  begin
    Val := ANode.GetValueAttribute(Key);
    if Val = nil then Continue;

    Debug('Processing edge for key: ' + Key);

    case Val.Kind of
      gvkNode:
        begin
          Val.GetNodeReference(NodeId, NodeName);
          // Find by ID first, then by name as fallback
          Target := nil;
          for var Node in FGraph.Nodes do
            if Node.Id = NodeId then
            begin
              Target := Node;
              Break;
            end;
          // Fallback to name lookup if ID not found
          if Target = nil then
            Target := FGraph.FindNode(NodeName);

          if Assigned(Target) and not EdgeExists(ANode, Target, Key) then
          begin
            Debug(Format('Adding edge: %s -%s-> %s (ID: %d)', [ANode.Name, Key, Target.Name, Target.Id]));
            FGraph.AddEdge(ANode, Target, Key, '');
          end
          else if Target = nil then
            Debug(Format('Target node not found: ID=%d, Name=%s', [NodeId, NodeName]));
        end;
      gvkIdentifier:
        begin
          Target := FGraph.FindNode(Val.IdentifierValue);
          if Assigned(Target) and not EdgeExists(ANode, Target, Key) then
          begin
            Debug(Format('Adding edge: %s -%s-> %s', [ANode.Name, Key, Target.Name]));
            FGraph.AddEdge(ANode, Target, Key, '');
          end;
        end;
      gvkArray:
        for Elem in Val.ArrayValue do
        begin
          if Elem.Kind = gvkNode then
          begin
            Elem.GetNodeReference(NodeId, NodeName);
            // Find by ID
            Target := nil;
            for var Node in FGraph.Nodes do
              if Node.Id = NodeId then
              begin
                Target := Node;
                Break;
              end;
            if Target = nil then
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

  DebugExit('RegisterEdgesForNode');
end;

procedure TGrispUnifiedParser.RegisterEdgesForAllNodes;
var
  Node: TGrispNode;
begin
  DebugEnter('RegisterEdgesForAllNodes');
  Debug('Total nodes: ' + IntToStr(FGraph.Nodes.Count));

  for Node in FGraph.Nodes do
    RegisterEdgesForNode(Node);

  DebugExit('RegisterEdgesForAllNodes');
end;

procedure TGrispUnifiedParser.ParseNodeDecl;
var
  NodeName: string;
  Node: TGrispNode;
  WhereExpr: TGrispExpression;
  TempExpr: TGrispExpression;
  PhaseNum: Double;
begin
  DebugEnter('ParseNodeDecl');
  DebugToken('Start');

  Expect(tkKeywordNode, '"node" expected');
  NodeName := FCurrent.Lexeme;
  Debug('Node name: ' + NodeName);
  Expect(tkIdentifier, 'name expected');
  Node := FGraph.AddNode(NodeName, 'node');
  DebugNode('Created node', Node);

  if StartsText('rule.', NodeName) then
  begin
    Debug('Registering as rule');
    FGraph.RegisterRule(Node);
  end;

  // Parse optional phase declaration
  if (FCurrent.Kind = tkKeywordPhase) or ((FCurrent.Kind = tkIdentifier) and SameText(FCurrent.Lexeme, 'phase')) then
  begin
    Debug('Parsing phase declaration');
    if FCurrent.Kind = tkIdentifier then Advance;
    if FCurrent.Kind = tkNumber then
    begin
      PhaseNum := StrToFloat(FCurrent.Lexeme);
      Debug('Phase number: ' + FloatToStr(PhaseNum));
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
    Debug('Parsing temp section');
    if FCurrent.Kind = tkIdentifier then Advance;
    Expect(tkEquals, '"=" expected');
    TempExpr := ParseExpr;
    Node.SetValueAttribute('temp', ExprToValue(TempExpr));
  end;

  if FCurrent.Kind = tkKeywordWhere then
  begin
    Debug('Parsing where clause');
    Advance;
    WhereExpr := ParseExpr;
    Node.SetValueAttribute('where', ExprToValue(WhereExpr));
  end;

  DebugToken('Before closing brace');
  Expect(tkRBrace, '} expected');
  DebugToken('After closing brace');

  DebugExit('ParseNodeDecl');
end;

procedure TGrispUnifiedParser.ParseTypeDecl;
var
  TypeName: string;
  Typ: TGrispType;
begin
  DebugEnter('ParseTypeDecl');
  DebugToken('Start');

  Expect(tkKeywordType, '"type" expected');
  TypeName := FCurrent.Lexeme;
  Debug('Type name: ' + TypeName);
  Expect(tkIdentifier, 'name expected');
  Expect(tkEquals, '"=" expected');
  Typ := ParseType;
  FGraph.AddType(TypeName, Typ);
  Debug('Type added to graph');

  DebugExit('ParseTypeDecl');
end;

procedure TGrispUnifiedParser.ParseStrategyDecl;
var
  StrategyName: string;
  Strat: TGrispStrategy;
begin
  DebugEnter('ParseStrategyDecl');
  DebugToken('Start');

  Expect(tkKeywordStrategy, '"strategy" expected');
  StrategyName := FCurrent.Lexeme;
  Debug('Strategy name: ' + StrategyName);
  Expect(tkIdentifier, 'name expected');
  Expect(tkEquals, '"=" expected');
  Strat := ParseStrategy;
  // Store strategy directly on the graph
  FGraph.AddStrategy(StrategyName, Strat);
  Debug('Strategy added to graph');

  DebugExit('ParseStrategyDecl');
end;

procedure TGrispUnifiedParser.ParseFile;
var
  DeclCount: Integer;
begin
  DebugEnter('ParseFile');
  Debug('Starting parse');
  DeclCount := 0;

  while FCurrent.Kind <> tkEOF do
  begin
    Debug(Format('Declaration #%d', [DeclCount + 1]));
    DebugToken('Current token');

    case FCurrent.Kind of
      tkKeywordNode:
        begin
          Debug('Found node declaration');
          ParseNodeDecl;
          Inc(DeclCount);
        end;
      tkKeywordType:
        begin
          Debug('Found type declaration');
          ParseTypeDecl;
          Inc(DeclCount);
        end;
      tkKeywordStrategy:
        begin
          Debug('Found strategy declaration');
          ParseStrategyDecl;
          Inc(DeclCount);
        end;
      else
        raise EGrispParseError.Create('Expected node, type, or strategy declaration');
    end;
  end;

  Debug(Format('Parse complete: %d declarations', [DeclCount]));
  RegisterEdgesForAllNodes;
  DebugExit('ParseFile');
end;

end.
