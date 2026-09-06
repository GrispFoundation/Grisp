unit GrispCapabilities;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  TGrispOp = (
    grRead,
    grWrite,
    grList,
    grDelete,
    grSyntaxCheck,
    grSemanticCheck,
    grCompile,
    grRun,
    grDebug,
    grInspectState,
    grStackTrace,
    grLspDiagnostics,
    grAstParse,
    grTestExecute,
    grReadLogs
  );

  TGrispOpSet = set of TGrispOp;

  IGrispCapability = interface
    ['{8F4E2C1A-1B3D-4E5F-9A8B-7C6D5E4F3A2B}']
    function GetName: string;
    function GetAllowedOps: TGrispOpSet;
    function GetRoot: string;
    function GetMaxSize: Int64;
    function GetMimeTypes: TArray<string>;

    function AllowsOp(Op: TGrispOp): Boolean;
    function AllowsMime(const Mime: string): Boolean;
    function IsPathAllowed(const VirtualPath: string): Boolean;
    function ValidateWrite(const VirtualPath, Mime: string; SizeBytes: Int64; out Reason: string): Boolean;

    property Name: string read GetName;
    property AllowedOps: TGrispOpSet read GetAllowedOps;
    property Root: string read GetRoot;
    property MaxSize: Int64 read GetMaxSize;
  end;

  TGrispCapability = class(TInterfacedObject, IGrispCapability)
  private
    FName: string;
    FAllowedOps: TGrispOpSet;
    FRoot: string;
    FMaxSize: Int64;
    FMimeTypes: TArray<string>;
    function NormalizeRoot(const ARoot: string): string;
  public
    constructor Create(const AName, ARoot: string; AAllowedOps: TGrispOpSet;
      const AMimeTypes: TArray<string>; AMaxSize: Int64);

    function GetName: string;
    function GetAllowedOps: TGrispOpSet;
    function GetRoot: string;
    function GetMaxSize: Int64;
    function GetMimeTypes: TArray<string>;

    function AllowsOp(Op: TGrispOp): Boolean;
    function AllowsMime(const Mime: string): Boolean;
    function IsPathAllowed(const VirtualPath: string): Boolean;
    function ValidateWrite(const VirtualPath, Mime: string; SizeBytes: Int64; out Reason: string): Boolean;

    class function OpToString(Op: TGrispOp): string;
    class function StringToOp(const S: string; out Op: TGrispOp): Boolean;
    class function DeduceMimeFromExtension(const Filename: string): string; static;
  end;

  TGrispCapabilitySet = class
  private
    FCapabilities: TDictionary<string, IGrispCapability>;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Add(const Cap: IGrispCapability);
    function Find(const Name: string; out Cap: IGrispCapability): Boolean;
    function Has(const Name: string): Boolean;
    function ValidateOperation(const CapName: string; Op: TGrispOp; const VirtualPath: string; out Reason: string): Boolean;
    function Count: Integer;
    function ToArray: TArray<IGrispCapability>;
  end;

implementation

{ TGrispCapability }

function TGrispCapability.NormalizeRoot(const ARoot: string): string;
var
  S: string;
begin
  S := ARoot.Trim;
  S := StringReplace(S, '\', '/', [rfReplaceAll]);
  if not S.StartsWith('/') then
    S := '/' + S;
  while (Length(S) > 1) and S.EndsWith('/') do
    Delete(S, Length(S), 1);
  Result := S;
end;

constructor TGrispCapability.Create(const AName, ARoot: string; AAllowedOps: TGrispOpSet;
  const AMimeTypes: TArray<string>; AMaxSize: Int64);
var
  I: Integer;
begin
  inherited Create;
  FName := AName;
  FRoot := NormalizeRoot(ARoot);
  FAllowedOps := AAllowedOps;
  FMaxSize := AMaxSize;
  SetLength(FMimeTypes, Length(AMimeTypes));
  for I := 0 to High(AMimeTypes) do
    FMimeTypes[I] := LowerCase(AMimeTypes[I].Trim);
end;

function TGrispCapability.GetName: string;
begin
  Result := FName;
end;

function TGrispCapability.GetAllowedOps: TGrispOpSet;
begin
  Result := FAllowedOps;
end;

function TGrispCapability.GetRoot: string;
begin
  Result := FRoot;
end;

function TGrispCapability.GetMaxSize: Int64;
begin
  Result := FMaxSize;
end;

function TGrispCapability.GetMimeTypes: TArray<string>;
begin
  Result := FMimeTypes;
end;

function TGrispCapability.AllowsOp(Op: TGrispOp): Boolean;
begin
  Result := Op in FAllowedOps;
end;

function TGrispCapability.AllowsMime(const Mime: string): Boolean;
var
  M, Allowed: string;
begin
  if Length(FMimeTypes) = 0 then
    Exit(True); // No MIME restrictions if empty

  M := LowerCase(Mime.Trim);
  for Allowed in FMimeTypes do
  begin
    if (Allowed = '*') or (Allowed = '*/*') then
      Exit(True);
    if Allowed = M then
      Exit(True);
    if Allowed.EndsWith('/*') and M.StartsWith(Copy(Allowed, 1, Length(Allowed) - 1)) then
      Exit(True);
  end;
  Result := False;
end;

function TGrispCapability.IsPathAllowed(const VirtualPath: string): Boolean;
var
  P: string;
begin
  P := VirtualPath.Trim;
  P := StringReplace(P, '\', '/', [rfReplaceAll]);
  if not P.StartsWith('/') then
    P := '/' + P;

  if FRoot = '/' then
    Exit(True);

  if P = FRoot then
    Exit(True);

  if P.StartsWith(FRoot + '/') then
    Exit(True);

  Result := False;
end;

function TGrispCapability.ValidateWrite(const VirtualPath, Mime: string; SizeBytes: Int64; out Reason: string): Boolean;
var
  ExtMime: string;
begin
  if not AllowsOp(grWrite) then
  begin
    Reason := Format('Capability "%s" does not allow write operations', [FName]);
    Exit(False);
  end;

  if not IsPathAllowed(VirtualPath) then
  begin
    Reason := Format('Path "%s" escapes capability root "%s"', [VirtualPath, FRoot]);
    Exit(False);
  end;

  if (FMaxSize > 0) and (SizeBytes > FMaxSize) then
  begin
    Reason := Format('Size %d bytes exceeds maximum allowed size of %d bytes for capability "%s"',
      [SizeBytes, FMaxSize, FName]);
    Exit(False);
  end;

  if (Mime <> '') and (not AllowsMime(Mime)) then
  begin
    Reason := Format('MIME type "%s" is not permitted by capability "%s"', [Mime, FName]);
    Exit(False);
  end;

  // Extension-based validation: ensure extension deduced MIME is allowed
  ExtMime := DeduceMimeFromExtension(VirtualPath);
  if not AllowsMime(ExtMime) then
  begin
    Reason := Format('File extension for "%s" implies MIME "%s" which is not permitted by capability "%s"',
      [VirtualPath, ExtMime, FName]);
    Exit(False);
  end;

  Reason := '';
  Result := True;
end;

class function TGrispCapability.DeduceMimeFromExtension(const Filename: string): string;
var
  Ext: string;
  DotPos: Integer;
begin
  DotPos := LastDelimiter('.', Filename);
  if DotPos > 0 then
    Ext := LowerCase(Copy(Filename, DotPos, Length(Filename) - DotPos + 1))
  else
    Ext := '';

  if (Ext = '.txt') or (Ext = '.log') or (Ext = '.grisp') then
    Result := 'text/plain'
  else if (Ext = '.c') or (Ext = '.h') then
    Result := 'text/x-c'
  else if (Ext = '.pas') or (Ext = '.dpr') or (Ext = '.pp') then
    Result := 'text/x-pascal'
  else if (Ext = '.py') then
    Result := 'text/x-python'
  else if (Ext = '.json') then
    Result := 'application/json'
  else if (Ext = '.exe') or (Ext = '.dll') or (Ext = '.bin') then
    Result := 'application/octet-stream'
  else
    Result := 'text/plain';
end;

class function TGrispCapability.OpToString(Op: TGrispOp): string;
begin
  case Op of
    grRead: Result := 'read';
    grWrite: Result := 'write';
    grList: Result := 'list';
    grDelete: Result := 'delete';
    grSyntaxCheck: Result := 'syntax_check';
    grSemanticCheck: Result := 'semantic_check';
    grCompile: Result := 'compile';
    grRun: Result := 'run';
    grDebug: Result := 'debug';
    grInspectState: Result := 'inspect_state';
    grStackTrace: Result := 'stack_trace';
    grLspDiagnostics: Result := 'lsp_diagnostics';
    grAstParse: Result := 'ast_parse';
    grTestExecute: Result := 'test_execute';
    grReadLogs: Result := 'read_logs';
  else
    Result := 'unknown';
  end;
end;

class function TGrispCapability.StringToOp(const S: string; out Op: TGrispOp): Boolean;
var
  Low: string;
begin
  Low := LowerCase(S.Trim);
  Result := True;
  if (Low = 'read') or (Low = 'grread') then Op := grRead
  else if (Low = 'write') or (Low = 'grwrite') then Op := grWrite
  else if (Low = 'list') or (Low = 'grlist') then Op := grList
  else if (Low = 'delete') or (Low = 'grdelete') then Op := grDelete
  else if (Low = 'syntax_check') or (Low = 'syntax') then Op := grSyntaxCheck
  else if (Low = 'semantic_check') or (Low = 'semantic') then Op := grSemanticCheck
  else if (Low = 'compile') or (Low = 'grcompile') then Op := grCompile
  else if (Low = 'run') or (Low = 'grrun') then Op := grRun
  else if (Low = 'debug') or (Low = 'grdebug') then Op := grDebug
  else if (Low = 'inspect_state') or (Low = 'inspect') then Op := grInspectState
  else if (Low = 'stack_trace') or (Low = 'stacktrace') then Op := grStackTrace
  else if (Low = 'lsp_diagnostics') or (Low = 'lsp') then Op := grLspDiagnostics
  else if (Low = 'ast_parse') or (Low = 'ast') then Op := grAstParse
  else if (Low = 'test_execute') or (Low = 'test') then Op := grTestExecute
  else if (Low = 'read_logs') or (Low = 'logs') then Op := grReadLogs
  else
    Result := False;
end;

{ TGrispCapabilitySet }

constructor TGrispCapabilitySet.Create;
begin
  inherited Create;
  FCapabilities := TDictionary<string, IGrispCapability>.Create;
end;

destructor TGrispCapabilitySet.Destroy;
begin
  FCapabilities.Free;
  inherited Destroy;
end;

procedure TGrispCapabilitySet.Add(const Cap: IGrispCapability);
begin
  if Assigned(Cap) then
    FCapabilities.AddOrSetValue(Cap.Name, Cap);
end;

function TGrispCapabilitySet.Find(const Name: string; out Cap: IGrispCapability): Boolean;
begin
  Result := FCapabilities.TryGetValue(Name, Cap);
end;

function TGrispCapabilitySet.Has(const Name: string): Boolean;
begin
  Result := FCapabilities.ContainsKey(Name);
end;

function TGrispCapabilitySet.ValidateOperation(const CapName: string; Op: TGrispOp;
  const VirtualPath: string; out Reason: string): Boolean;
var
  Cap: IGrispCapability;
begin
  if not FCapabilities.TryGetValue(CapName, Cap) then
  begin
    Reason := Format('Capability "%s" not found in active set', [CapName]);
    Exit(False);
  end;

  if not Cap.AllowsOp(Op) then
  begin
    Reason := Format('Capability "%s" does not allow operation %s', [CapName, TGrispCapability.OpToString(Op)]);
    Exit(False);
  end;

  if (VirtualPath <> '') and (not Cap.IsPathAllowed(VirtualPath)) then
  begin
    Reason := Format('Virtual path "%s" is outside capability root "%s"', [VirtualPath, Cap.Root]);
    Exit(False);
  end;

  Reason := '';
  Result := True;
end;

function TGrispCapabilitySet.Count: Integer;
begin
  Result := FCapabilities.Count;
end;

function TGrispCapabilitySet.ToArray: TArray<IGrispCapability>;
begin
  Result := FCapabilities.Values.ToArray;
end;

end.
