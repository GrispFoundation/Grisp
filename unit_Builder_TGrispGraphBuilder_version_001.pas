unit unit_Builder_TGrispGraphBuilder_version_001;

interface

uses
  System.SysUtils,
  System.IOUtils,
  unit_Parser_TGrispFullParser_version_001,
  unit_Graph_TGrispGraph_version_001;

type
  EGrispGraphBuilderError = class(Exception);

  TGrispGraphBuilder = class
  private
    FSource: string;
    FGraph: TGrispGraph;
    FParser: TGrispFullParser;
    FFileName: string;

    procedure Initialize;
    procedure Cleanup;
  public
    constructor Create(const ASource: string);
    constructor CreateFromFile(const AFileName: string);
    destructor Destroy; override;

    function Build: TGrispGraph;
    procedure Reload;

    property Source: string read FSource write FSource;
    property Graph: TGrispGraph read FGraph;
    property FileName: string read FFileName;
  end;

// Simple function-based API
function BuildGraphFromSource(const Source: string): TGrispGraph;
function BuildGraphFromFile(const FileName: string): TGrispGraph;

implementation

function BuildGraphFromSource(const Source: string): TGrispGraph;
var
  Builder: TGrispGraphBuilder;
begin
  Builder := TGrispGraphBuilder.Create(Source);
  try
    Result := Builder.Build;
  finally
    Builder.Free;
  end;
end;

function BuildGraphFromFile(const FileName: string): TGrispGraph;
var
  Builder: TGrispGraphBuilder;
begin
  Builder := TGrispGraphBuilder.CreateFromFile(FileName);
  try
    Result := Builder.Build;
  finally
    Builder.Free;
  end;
end;

{ TGrispGraphBuilder }

constructor TGrispGraphBuilder.Create(const ASource: string);
begin
  inherited Create;
  FSource := ASource;
  FFileName := '';
  Initialize;
end;

constructor TGrispGraphBuilder.CreateFromFile(const AFileName: string);
begin
  inherited Create;
  if not TFile.Exists(AFileName) then
    raise EGrispGraphBuilderError.CreateFmt('File not found: %s', [AFileName]);

  FFileName := AFileName;
  FSource := TFile.ReadAllText(AFileName);
  Initialize;
end;

destructor TGrispGraphBuilder.Destroy;
begin
  Cleanup;
  inherited Destroy;
end;

procedure TGrispGraphBuilder.Initialize;
begin
  FGraph := TGrispGraph.Create;
  FParser := TGrispFullParser.Create(FSource, FGraph);
end;

procedure TGrispGraphBuilder.Cleanup;
begin
  FreeAndNil(FParser);
  FreeAndNil(FGraph);
end;

function TGrispGraphBuilder.Build: TGrispGraph;
begin
  Result := nil;

  if FSource.IsEmpty then
    raise EGrispGraphBuilderError.Create('Source is empty');

  try
    FParser.ParseFile;
    FGraph.RegisterEdgesFromIdentifiers;
    Result := FGraph;
    // Detach so it doesn't get freed with the builder
    FGraph := nil;
  except
    Cleanup;
    raise;
  end;
end;

procedure TGrispGraphBuilder.Reload;
begin
  Cleanup;
  if FFileName <> '' then
    FSource := TFile.ReadAllText(FFileName);
  Initialize;
end;

end.
