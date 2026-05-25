unit unit_Parser_TGrispNodeParser_version_001;

interface

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  unit_Token_TGrispTokenKind_version_001,      // Changed
  unit_Token_TGrispToken_version_001,          // Changed
  unit_Lexer_TGrispLexer_version_001,          // Changed
  unit_Graph_TGrispGraph_version_001,
  unit_Graph_TGrispEdge_TGrispNode_version_001, // Added for TGrispNode
  unit_Core_TGrispValueBase_version_001,       // Added for TGrispValue
  unit_Core_TGrispExpression_version_001,      // Added for TGrispExpression
  unit_Parser_TGrispParserBase_version_001;

type
  TGrispNodeParser = class(TGrispParserBase)
  private
    function ParseValue(const ATypeName: string): TGrispValue;
    procedure ParseNodeBody(ANode: TGrispNode);
    function EdgeExists(ASource, ATarget: TGrispNode; const ALabel: string): Boolean;
    procedure RegisterEdgesForNode(ANode: TGrispNode);
    procedure RegisterEdgesForAllNodes;
  public
    procedure ParseNodeDecl;
    procedure ParseFile; override;
  end;

implementation

function TGrispNodeParser.ParseValue(const ATypeName: string): TGrispValue;
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
    // Store node reference by ID and Name
    Result.SetNodeReference(Node.Id, Node.Name);
    Exit;
  end;

  raise EGrispParseError.CreateFmt('Unknown type "%s"', [ATypeName]);
end;

procedure TGrispNodeParser.ParseNodeBody(ANode: TGrispNode);
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
	ANode.SetValueAttribute(Key, Value);  // Changed: use SetValueAttribute
	if FCurrent.Kind = tkSemicolon then
	  Advance;
  end;
end;

function TGrispNodeParser.EdgeExists(ASource, ATarget: TGrispNode; const ALabel: string): Boolean;
var
  E: TGrispEdge;
begin
  for E in FGraph.Edges do
	if (E.Source = ASource) and (E.Target = ATarget) and SameText(E.LabelName, ALabel) then
	  Exit(True);
  Result := False;
end;

procedure TGrispNodeParser.RegisterEdgesForNode(ANode: TGrispNode);
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

procedure TGrispNodeParser.RegisterEdgesForAllNodes;
var
  Node: TGrispNode;
begin
  for Node in FGraph.Nodes do
    RegisterEdgesForNode(Node);
end;

procedure TGrispNodeParser.ParseNodeDecl;
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

procedure TGrispNodeParser.ParseFile;
begin
  while FCurrent.Kind <> tkEOF do
  begin
    case FCurrent.Kind of
      tkKeywordNode:
        ParseNodeDecl;
      tkKeywordType, tkKeywordStrategy:
        // Skip type and strategy declarations - handled by other parsers
        Advance;
      else
        raise EGrispParseError.Create('Expected node declaration');
    end;
  end;
  RegisterEdgesForAllNodes;
end;

end.
