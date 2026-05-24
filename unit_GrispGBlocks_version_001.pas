unit unit_GrispGBlocks_version_001;

interface

uses
  unit_GrispParser_version_001,
  unit_GrispGraph_version_001;

function ParseGBlocks(const Source: string): TGGraph;

implementation

function ParseGBlocks(const Source: string): TGGraph;
var
  Parser: TGrispParser;
  Graph: TGGraph;
begin
  Graph := TGGraph.Create;
  Parser := TGrispParser.Create(Source, Graph);
  try
    Parser.ParseFile;
    // Parser already registered edges, but it's safe to ensure:
    Graph.RegisterEdgesFromIdentifiers;
    Result := Graph;
  except
    Parser.Free;
    Graph.Free;
    raise;
  end;
  Parser.Free;
end;

end.
