unit unit_Parser_TGrispTypeParser_version_001;

interface

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  unit_Token_TGrispTokenKind_version_001,      // Changed
  unit_Token_TGrispToken_version_001,          // Changed
  unit_Lexer_TGrispLexer_version_001,          // Changed
  unit_Graph_TGrispGraph_version_001,
  unit_Core_TGrispType_version_001,            // Added for TGrispType
  unit_Parser_TGrispParserBase_version_001;

type
  TGrispTypeParser = class(TGrispParserBase)
  private
    function ParseType: TGrispType;
  public
    procedure ParseTypeDecl;
    procedure ParseFile; override;
  end;

implementation

function TGrispTypeParser.ParseType: TGrispType;
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

procedure TGrispTypeParser.ParseTypeDecl;
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

procedure TGrispTypeParser.ParseFile;
begin
  while FCurrent.Kind <> tkEOF do
  begin
    case FCurrent.Kind of
      tkKeywordType:
        ParseTypeDecl;
      tkKeywordNode, tkKeywordStrategy:
        // Skip node and strategy declarations - handled by other parsers
        Advance;
      else
        raise EGrispParseError.Create('Expected type declaration');
    end;
  end;
end;

end.
