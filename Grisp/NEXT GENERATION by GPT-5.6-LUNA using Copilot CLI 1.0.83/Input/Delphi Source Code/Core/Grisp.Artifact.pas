unit Grisp.Artifact;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils, Grisp.Types,
  Grisp.Hash, Grisp.Canonical;

function ValidateFileName(const AFileName: string; out AError: string): Boolean;
function BuildArtifact(var AArtifact: TGrispArtifactBundle; out AError: string): Boolean;
function ValidateArtifact(const AArtifact: TGrispArtifactBundle; out AError: string): Boolean;
function ComputeArtifactId(const AArtifact: TGrispArtifactBundle): string;

implementation

function ValidateFileName(const AFileName: string; out AError: string): Boolean;
begin
  AError := '';
  Result := AFileName <> '';
  if not Result then AError := 'empty filename';
  if Result and (AFileName.IndexOf(#0) >= 0) then begin Result := False; AError := 'embedded NUL'; end;
  if Result and (AFileName[1] = '\') then begin Result := False; AError := 'absolute path'; end;
  if Result and (Length(AFileName) >= 2) and (AFileName[2] = ':') then
    begin Result := False; AError := 'drive-qualified path'; end;
  if Result and ((AFileName.StartsWith('\\')) or AFileName.Contains('../') or
    AFileName.Contains('..\' )) then begin Result := False; AError := 'path traversal'; end;
  if Result and ((AFileName = '.') or (AFileName = '..')) then
    begin Result := False; AError := 'invalid path component'; end;
end;

function ComputeArtifactId(const AArtifact: TGrispArtifactBundle): string;
begin
  Result := Sha256Text(CanonicalArtifactManifest(AArtifact));
end;

function BuildArtifact(var AArtifact: TGrispArtifactBundle; out AError: string): Boolean;
var
  I, J: Integer;
begin
  AError := '';
  for I := 0 to Length(AArtifact.Files) - 1 do
  begin
    if not ValidateFileName(AArtifact.Files[I].FileName, AError) then Exit(False);
    AArtifact.Files[I].ContentSHA256 := Sha256Bytes(AArtifact.Files[I].Content);
    AArtifact.Files[I].SizeBytes := Length(AArtifact.Files[I].Content);
    for J := 0 to I - 1 do
      if CompareStr(AArtifact.Files[I].FileName, AArtifact.Files[J].FileName) = 0 then
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
  CopyArtifact: TGrispArtifactBundle;
begin
  CopyArtifact := AArtifact;
  if not BuildArtifact(CopyArtifact, AError) then Exit(False);
  if (AArtifact.ArtifactId = '') or
    not SameText(AArtifact.ArtifactId, CopyArtifact.ArtifactId) then
  begin
    AError := 'ARTIFACT_HASH_MISMATCH';
    Exit(False);
  end;
  Result := True;
end;

end.
