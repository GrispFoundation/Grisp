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
begin
  Parser := TGrispParser.Create(Source);
  try
    Result := Parser.Parse;
  finally
    Parser.Free;
  end;
end;

end.
