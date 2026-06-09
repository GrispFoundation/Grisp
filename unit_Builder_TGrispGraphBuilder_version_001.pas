unit unit_Builder_TGrispGraphBuilder_version_001;

interface

uses
  System.SysUtils,
  System.IOUtils,
  unit_Parser_TGrispUnifiedParser_version_001,
  unit_Graph_TGrispGraph_version_001,
  unit_Debug_TGrispDebug_version_001;

type
  EGrispGraphBuilderError = class(Exception);

  TGrispGraphBuilder = class
  private
    FSource: string;
    FGraph: TGrispGraph;
    FParser: TGrispUnifiedParser;
    FFileName: string;
    FDebugEnabled: Boolean;

    procedure Debug(const Msg: string);
    procedure DebugEnter(const Method: string);
    procedure DebugExit(const Method: string);
    procedure Initialize;
    procedure Cleanup;
  public
    constructor Create(const ASource: string);
    destructor Destroy; override;

    procedure EnableDebug;
    procedure DisableDebug;

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
  Source: string;
begin
  if not TFile.Exists(FileName) then
    raise EGrispGraphBuilderError.CreateFmt('File not found: %s', [FileName]);

  Source := TFile.ReadAllText(FileName);
  Result := BuildGraphFromSource(Source);
end;

{ TGrispGraphBuilder }

constructor TGrispGraphBuilder.Create(const ASource: string);
begin
  inherited Create;
  FSource := ASource;
  FFileName := '';
  FDebugEnabled := False;
  Initialize;
  Debug('TGrispGraphBuilder created');
end;

destructor TGrispGraphBuilder.Destroy;
begin
  Debug('TGrispGraphBuilder destroyed');
  Cleanup;
  inherited Destroy;
end;

procedure TGrispGraphBuilder.EnableDebug;
begin
  FDebugEnabled := True;
  TGrispDebug.Enable;
  Debug('GraphBuilder debug enabled');
  if Assigned(FParser) then
    FParser.EnableDebug;
end;

procedure TGrispGraphBuilder.DisableDebug;
begin
  Debug('GraphBuilder debug disabled');
  FDebugEnabled := False;
  if Assigned(FParser) then
    FParser.DisableDebug;
end;

procedure TGrispGraphBuilder.Debug(const Msg: string);
begin
  if FDebugEnabled then
    TGrispDebug.Log('[GraphBuilder] ' + Msg);
end;

procedure TGrispGraphBuilder.DebugEnter(const Method: string);
begin
  if FDebugEnabled then
	TGrispDebug.LogEnter('[GraphBuilder] ' + Method);
end;

procedure TGrispGraphBuilder.DebugExit(const Method: string);
begin
  if FDebugEnabled then
    TGrispDebug.LogExit('[GraphBuilder] ' + Method);
end;

procedure TGrispGraphBuilder.Initialize;
begin
  DebugEnter('Initialize');
  FGraph := TGrispGraph.Create;
  Debug('Graph created');
  FParser := TGrispUnifiedParser.Create(FSource, FGraph);
  Debug('Parser created');
  if FDebugEnabled then
    FParser.EnableDebug;
  DebugExit('Initialize');
end;

procedure TGrispGraphBuilder.Cleanup;
begin
  DebugEnter('Cleanup');
  FreeAndNil(FParser);
  Debug('Parser freed');
  FreeAndNil(FGraph);
  Debug('Graph freed');
  DebugExit('Cleanup');
end;

function TGrispGraphBuilder.Build: TGrispGraph;
begin
  DebugEnter('Build');
  Debug(Format('Source length: %d chars', [Length(FSource)]));

  if FSource.IsEmpty then
  begin
    Debug('ERROR: Source is empty');
    raise EGrispGraphBuilderError.Create('Source is empty');
  end;

  try
    Debug('Calling FParser.ParseFile...');
    FParser.ParseFile;
    Debug('ParseFile completed successfully');

    Debug('Calling FGraph.RegisterEdgesFromIdentifiers...');
    FGraph.RegisterEdgesFromIdentifiers;
    Debug('RegisterEdgesFromIdentifiers completed');

    Debug(Format('Graph has %d nodes and %d edges', [FGraph.Nodes.Count, FGraph.Edges.Count]));

    Result := FGraph;
    FGraph := nil;  // Detach so it doesn't get freed with the builder
    Debug('Graph detached from builder');

    DebugExit('Build');
  except
    on E: Exception do
    begin
      Debug(Format('ERROR during build: %s', [E.Message]));
      Cleanup;
      raise;
    end;
  end;
end;

procedure TGrispGraphBuilder.Reload;
begin
  DebugEnter('Reload');
  Cleanup;
  if FFileName <> '' then
  begin
    Debug(Format('Reloading from file: %s', [FFileName]));
    FSource := TFile.ReadAllText(FFileName);
  end;
  Initialize;
  DebugExit('Reload');
end;

end.
