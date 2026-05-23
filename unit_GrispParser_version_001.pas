unit unit_GrispParser_version_001;

interface

uses
  System.SysUtils,
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
  public
    constructor Create(const ASource: string);
    destructor Destroy; override;

    function Parse: TGGraph;
  end;

implementation

{ TGrispParser }

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
  inherited;
end;

procedure TGrispParser.Advance;
begin
  FCurrent := FLexer.NextToken;
end;

procedure TGrispParser.Expect(AKind: TTokenKind; const Msg: string);
begin
  if FCurrent.Kind <> AKind then
    raise EGrispParseError.CreateFmt('%s at line %d, col %d (found "%s")',
      [Msg, FCurrent.Line, FCurrent.Column, FCurrent.Lexeme]);
  Advance;
end;

procedure TGrispParser.ParseNodeDecl;
var
  NodeName: string;
  Node: TGNode;
begin
  Expect(tkKeywordNode, '"node" expected');
  if (FCurrent.Kind <> tkIdentifier) and (FCurrent.Kind <> tkKeywordNode) and (FCurrent.Kind <> tkKeywordArray) then
    raise EGrispParseError.CreateFmt('Node name expected, but found "%s" at line %d, col %d',
      [FCurrent.Lexeme, FCurrent.Line, FCurrent.Column]);
  
  NodeName := FCurrent.Lexeme;
  Advance;

  Node := FGraph.AddNode(NodeName, 'node');

  // Register rule if its name starts with 'rule.'
  if (Length(NodeName) >= 5) and SameText(Copy(NodeName, 1, 5), 'rule.') then
    FGraph.RegisterRule(Node);

  Expect(tkLBrace, '"{" expected after node name');
  ParseNodeBody(Node);
  Expect(tkRBrace, '"}" expected at end of node');
end;

procedure TGrispParser.ParseNodeBody(ANode: TGNode);
var
  Key: string;
  TypeName: string;
  Value: TGValue;
begin
  while (FCurrent.Kind <> tkRBrace) and (FCurrent.Kind <> tkEOF) do
  begin
    if (FCurrent.Kind <> tkIdentifier) and (FCurrent.Kind <> tkKeywordNode) and (FCurrent.Kind <> tkKeywordArray) then
      raise EGrispParseError.CreateFmt('Attribute name expected, but found "%s" at line %d, col %d',
        [FCurrent.Lexeme, FCurrent.Line, FCurrent.Column]);
    
    Key := FCurrent.Lexeme;
    Advance;

    Expect(tkColon, '":" expected after attribute name');
    TypeName := ParseTypeName;
    Expect(tkEquals, '"=" expected after type');

    Value := ParseValue(TypeName);
    ANode.SetAttribute(Key, Value);
  end;
end;

function TGrispParser.ParseTypeName: string;
begin
  if (FCurrent.Kind <> tkIdentifier) and (FCurrent.Kind <> tkKeywordArray) and (FCurrent.Kind <> tkKeywordNode) then
    raise EGrispParseError.CreateFmt('Type name expected, but found "%s" at line %d, col %d',
      [FCurrent.Lexeme, FCurrent.Line, FCurrent.Column]);
  
  Result := FCurrent.Lexeme;
  Advance;

  if SameText(Result, 'array') then
  begin
    Expect(tkLess, '"<" expected in array type');
    if (FCurrent.Kind <> tkIdentifier) and (FCurrent.Kind <> tkKeywordNode) then
      raise EGrispParseError.CreateFmt('Element type name expected inside array<T> at line %d, col %d',
        [FCurrent.Line, FCurrent.Column]);
    Result := Result + '<' + FCurrent.Lexeme + '>';
    Advance;
    Expect(tkGreater, '">" expected in array type');
  end;
end;

function TGrispParser.ParseValue(const ATypeName: string): TGValue;
var
  ValStr: string;
  ValDouble: Double;
  ValBool: Boolean;
  ValNode: TGNode;
  ElementType: string;
  ElementVal: TGValue;
  FormatSettings: TFormatSettings;
begin
  FormatSettings := TFormatSettings.Invariant;
  Result := nil;

  if SameText(ATypeName, 'number') then
  begin
    if FCurrent.Kind <> tkNumber then
      raise EGrispParseError.CreateFmt('Number expected at line %d, col %d', [FCurrent.Line, FCurrent.Column]);
    ValStr := FCurrent.Lexeme;
    Advance;
    if not TryStrToFloat(ValStr, ValDouble, FormatSettings) then
      raise EGrispParseError.CreateFmt('Invalid number format "%s" at line %d, col %d', [ValStr, FCurrent.Line, FCurrent.Column]);
    Result := TGValue.Create(vkNumber);
    Result.NumberValue := ValDouble;
  end
  else if SameText(ATypeName, 'string') then
  begin
    if FCurrent.Kind <> tkString then
      raise EGrispParseError.CreateFmt('String expected at line %d, col %d', [FCurrent.Line, FCurrent.Column]);
    ValStr := FCurrent.Lexeme;
    Advance;
    // Strip quotes
    if (Length(ValStr) >= 2) and (((ValStr[1] = '''') and (ValStr[Length(ValStr)] = '''')) or
                                  ((ValStr[1] = '"') and (ValStr[Length(ValStr)] = '"'))) then
    begin
      ValStr := Copy(ValStr, 2, Length(ValStr) - 2);
    end;
    Result := TGValue.Create(vkString);
    Result.StringValue := ValStr;
  end
  else if SameText(ATypeName, 'boolean') then
  begin
    if FCurrent.Kind <> tkBoolean then
      raise EGrispParseError.CreateFmt('Boolean expected at line %d, col %d', [FCurrent.Line, FCurrent.Column]);
    ValStr := FCurrent.Lexeme;
    Advance;
    ValBool := SameText(ValStr, 'true');
    Result := TGValue.Create(vkBoolean);
    Result.BoolValue := ValBool;
  end
  else if SameText(ATypeName, 'identifier') then
  begin
    if (FCurrent.Kind <> tkIdentifier) and (FCurrent.Kind <> tkKeywordNode) and (FCurrent.Kind <> tkKeywordArray) then
      raise EGrispParseError.CreateFmt('Identifier expected at line %d, col %d', [FCurrent.Line, FCurrent.Column]);
    ValStr := FCurrent.Lexeme;
    Advance;
    Result := TGValue.Create(vkIdentifier);
    Result.IdentifierValue := ValStr;
  end
  else if SameText(ATypeName, 'node') then
  begin
    Expect(tkLBrace, '"{" expected for inline node');
    ValNode := FGraph.AddNode('', 'node');
    ParseNodeBody(ValNode);
    Expect(tkRBrace, '"}" expected at end of inline node');
    Result := TGValue.Create(vkNode);
    Result.NodeValue := ValNode;
  end
  else if SameText(Copy(ATypeName, 1, 5), 'array') then
  begin
    ElementType := '';
    if (Length(ATypeName) > 6) and (ATypeName[6] = '<') and (ATypeName[Length(ATypeName)] = '>') then
    begin
      ElementType := Copy(ATypeName, 7, Length(ATypeName) - 7);
    end;
    if ElementType = '' then
      raise EGrispParseError.CreateFmt('Invalid array type "%s" at line %d, col %d', [ATypeName, FCurrent.Line, FCurrent.Column]);
      
    Expect(tkLBracket, '"[" expected for array');
    Result := TGValue.Create(vkArray);
    
    if FCurrent.Kind <> tkRBracket then
    begin
      while True do
      begin
        ElementVal := ParseValue(ElementType);
        Result.ArrayValue.Add(ElementVal);
        if FCurrent.Kind = tkComma then
        begin
          Advance;
          if FCurrent.Kind = tkRBracket then
            Break; // Support optional trailing comma
        end
        else
          Break;
      end;
    end;
    Expect(tkRBracket, '"]" expected');
  end
  else
  begin
    raise EGrispParseError.CreateFmt('Unknown type "%s" at line %d, col %d', [ATypeName, FCurrent.Line, FCurrent.Column]);
  end;
end;

function TGrispParser.Parse: TGGraph;
var
  I, J: Integer;
  Node, TargetNode: TGNode;
  AttrKey: string;
  AttrVal, ArrayItem: TGValue;
begin
  try
    while FCurrent.Kind <> tkEOF do
    begin
      if FCurrent.Kind = tkKeywordNode then
        ParseNodeDecl
      else
        raise EGrispParseError.CreateFmt('Unexpected token "%s" at line %d, col %d',
          [FCurrent.Lexeme, FCurrent.Line, FCurrent.Column]);
    end;

    // Second pass for explicit edge registration
    for I := 0 to FGraph.Nodes.Count - 1 do
    begin
      Node := FGraph.Nodes[I];
      for AttrKey in Node.Attributes.Keys do
      begin
        AttrVal := Node.Attributes[AttrKey];
        if not Assigned(AttrVal) then
          Continue;

        case AttrVal.Kind of
          vkNode:
            begin
              if Assigned(AttrVal.NodeValue) then
                FGraph.AddEdge(Node, AttrVal.NodeValue, AttrKey);
            end;
          vkIdentifier:
            begin
              TargetNode := FGraph.FindNode(AttrVal.IdentifierValue);
              if Assigned(TargetNode) then
                FGraph.AddEdge(Node, TargetNode, AttrKey);
            end;
          vkArray:
            begin
              if Assigned(AttrVal.ArrayValue) then
              begin
                for J := 0 to AttrVal.ArrayValue.Count - 1 do
                begin
                  ArrayItem := AttrVal.ArrayValue[J];
                  if not Assigned(ArrayItem) then
                    Continue;
                  if ArrayItem.Kind = vkNode then
                  begin
                    if Assigned(ArrayItem.NodeValue) then
                      FGraph.AddEdge(Node, ArrayItem.NodeValue, AttrKey);
                  end
                  else if ArrayItem.Kind = vkIdentifier then
                  begin
                    TargetNode := FGraph.FindNode(ArrayItem.IdentifierValue);
                    if Assigned(TargetNode) then
                      FGraph.AddEdge(Node, TargetNode, AttrKey);
                  end;
                end;
              end;
            end;
        end;
      end;
    end;

    Result := FGraph;
  except
    FGraph.Free;
    raise;
  end;
end;

end.
