unit Grisp.Artifact;

interface

uses
  System.SysUtils, System.Classes, Grisp.Types, Grisp.Hash, Grisp.Canonical;

function ValidateFileName(const AFileName: string; out AError: string): Boolean;
function BuildArtifact(var AArtifact: TGrispArtifactBundle; out AError: string): Boolean;
function ValidateArtifact(const AArtifact: TGrispArtifactBundle; out AError: string): Boolean;
function ComputeArtifactId(const AArtifact: TGrispArtifactBundle): string;

implementation

function IsWindowsDeviceName(const S: string): Boolean;
const
  Names: array[0..22] of string = (
    'CON', 'PRN', 'AUX', 'NUL',
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
    '');
var
  I: Integer;
begin
  Result := False;
  for I := Low(Names) to High(Names) do
    if SameText(S, Names[I]) then
      Exit(True);
end;

function ValidateFileName(const AFileName: string; out AError: string): Boolean;
var
  Part: string;
  Parts: TArray<string>;
  I: Integer;
begin
  AError := '';
  Result := AFileName <> '';
  if not Result then begin AError := 'empty filename'; Exit; end;

  if AFileName.IndexOf(#0) >= 0 then begin AError := 'embedded NUL'; Exit(False); end;
  if AFileName.Contains(':') then begin AError := 'colon or drive/ADS not allowed'; Exit(False); end;
  if AFileName.StartsWith('/') or AFileName.StartsWith('\') then
    begin AError := 'absolute path not allowed'; Exit(False); end;
  if AFileName.Contains('../') or AFileName.Contains('..\') or
     (AFileName = '..') or (AFileName = '.') then
    begin AError := 'path traversal not allowed'; Exit(False); end;

  Parts := AFileName.Split(['/', '\']);
  for I := 0 to High(Parts) do
  begin
    Part := Parts[I];
    if Part = '' then begin AError := 'empty path component'; Exit(False); end;
    if Part.EndsWith('.') or Part.EndsWith(' ') then
      begin AError := 'trailing dot or space not allowed'; Exit(False); end;
    if IsWindowsDeviceName(Part) then
      begin AError := 'Windows device name not allowed'; Exit(False); end;
  end;

  Result := True;
end;

function ComputeArtifactId(const AArtifact: TGrispArtifactBundle): string;
begin
  Result := Sha256Text(CanonicalManifest(AArtifact));
end;

function BuildArtifact(var AArtifact: TGrispArtifactBundle; out AError: string): Boolean;
var
  I, J: Integer;
begin
  AError := '';
  for I := 0 to High(AArtifact.Files) do
  begin
    if not ValidateFileName(AArtifact.Files[I].FileName, AError) then
      Exit(False);

    AArtifact.Files[I].ContentSHA256 := Sha256Bytes(AArtifact.Files[I].Content);
    AArtifact.Files[I].SizeBytes := Length(AArtifact.Files[I].Content);

    for J := 0 to I - 1 do
      if SameText(AArtifact.Files[I].FileName, AArtifact.Files[J].FileName) then
      begin
        AError := 'duplicate filename: ' + AArtifact.Files[I].FileName;
        Exit(False);
      end;
  end;

  AArtifact.ArtifactId := ComputeArtifactId(AArtifact);
  Result := True;
end;

function ValidateArtifact(const AArtifact: TGrispArtifactBundle; out AError: string): Boolean;
var
  I: Integer;
  ExpectedHash: string;
  ExpectedSize: Int64;
  Local: TGrispArtifactBundle;
begin
  AError := '';

  // 1. Check supplied derived fields against exact bytes.
  for I := 0 to High(AArtifact.Files) do
  begin
    ExpectedHash := Sha256Bytes(AArtifact.Files[I].Content);
    ExpectedSize := Length(AArtifact.Files[I].Content);

    if (AArtifact.Files[I].ContentSHA256 <> '') and
       (not SameText(AArtifact.Files[I].ContentSHA256, ExpectedHash)) then
    begin
      AError := 'ARTIFACT_FILE_HASH_MISMATCH: ' + AArtifact.Files[I].FileName;
      Exit(False);
    end;

    if (AArtifact.Files[I].SizeBytes <> 0) and
       (AArtifact.Files[I].SizeBytes <> ExpectedSize) then
    begin
      AError := 'ARTIFACT_FILE_SIZE_MISMATCH: ' + AArtifact.Files[I].FileName;
      Exit(False);
    end;
  end;

  // 2. Build a local copy and compare artifact identity.
  Local := AArtifact;
  Local.Files := Copy(AArtifact.Files);
  if not BuildArtifact(Local, AError) then
    Exit(False);

  if (AArtifact.ArtifactId <> '') and
     (not SameText(AArtifact.ArtifactId, Local.ArtifactId)) then
  begin
    AError := 'ARTIFACT_HASH_MISMATCH';
    Exit(False);
  end;

  Result := True;
end;

end.