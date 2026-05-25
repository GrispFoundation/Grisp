unit unit_Parser_TGrispFullParser_version_001;

interface

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  unit_Token_TGrispTokenKind_version_001,      // Changed
  unit_Token_TGrispToken_version_001,          // Changed
  unit_Lexer_TGrispLexer_version_001,          // Changed
  unit_Graph_TGrispGraph_version_001,
  unit_Strategy_TGrispStrategyKind_version_001, // Added
  unit_Strategy_TGrispStrategy_version_001,
  unit_Parser_TGrispParserBase_version_001,
  unit_Parser_TGrispNodeParser_version_001,
  unit_Parser_TGrispTypeParser_version_001,
  unit_Parser_TGrispStrategyParser_version_001;

type
  TGrispFullParser = class(TGrispParserBase)
  private
    FNodeParser: TGrispNodeParser;
    FTypeParser: TGrispTypeParser;
    FStrategyParser: TGrispStrategyParser;
  public
    constructor Create(const ASource: string; AGraph: TGrispGraph);
    destructor Destroy; override;
    procedure ParseFile; override;
  end;

implementation

constructor TGrispFullParser.Create(const ASource: string; AGraph: TGrispGraph);
begin
  inherited Create(ASource, AGraph);
  FNodeParser := TGrispNodeParser.Create(ASource, AGraph);
  FTypeParser := TGrispTypeParser.Create(ASource, AGraph);
  FStrategyParser := TGrispStrategyParser.Create(ASource, AGraph);
end;

destructor TGrispFullParser.Destroy;
begin
  FStrategyParser.Free;
  FTypeParser.Free;
  FNodeParser.Free;
  inherited Destroy;
end;

procedure TGrispFullParser.ParseFile;
begin
  while FCurrent.Kind <> tkEOF do
  begin
    case FCurrent.Kind of
      tkKeywordNode:
        FNodeParser.ParseNodeDecl;
      tkKeywordType:
        FTypeParser.ParseTypeDecl;
      tkKeywordStrategy:
        FStrategyParser.ParseStrategyDecl;
      else
        raise EGrispParseError.Create('Expected node, type, or strategy declaration');
    end;
  end;
  // Register edges after all nodes are parsed
  FNodeParser.ParseFile;  // This will call RegisterEdgesForAllNodes
end;

end.
