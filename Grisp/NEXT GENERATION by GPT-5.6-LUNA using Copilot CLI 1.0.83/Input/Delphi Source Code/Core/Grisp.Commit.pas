unit Grisp.Commit;

interface

uses
  System.SysUtils, System.IOUtils, Grisp.Types, Grisp.Artifact, Grisp.Hash;

function CommitArtifact(const AArtifact: TGrispArtifactBundle; const AFinalRoot: string;
  out AEvidence: TGrispEvidence; out AError: string): Boolean;

implementation

function CommitArtifact(const AArtifact: TGrispArtifactBundle; const AFinalRoot: string;
  out AEvidence: TGrispEvidence; out AError: string): Boolean;
var
  Root, Path: string;
  I: Integer;
  Written, ReadBack: TBytes;
begin
  AError := '';
  AEvidence := Default(TGrispEvidence);
  AEvidence.EvidenceId := NewUuid;
  AEvidence.ArtifactId := AArtifact.ArtifactId;
  AEvidence.Operation := eoCommit;
  AEvidence.CreatedAt := UtcNowText;
  Root := TPath.Combine(AFinalRoot, AArtifact.ArtifactId.Replace(':', '_'));
  ForceDirectories(Root);
  try
    for I := 0 to Length(AArtifact.Files) - 1 do
    begin
      Path := TPath.Combine(Root, AArtifact.Files[I].FileName);
      if not ValidateFileName(AArtifact.Files[I].FileName, AError) then
        Exit(False);
      ForceDirectories(ExtractFileDir(Path));
      Written := AArtifact.Files[I].Content;
      TFile.WriteAllBytes(Path, Written);
      ReadBack := TFile.ReadAllBytes(Path);
      if not SameText(Sha256Bytes(ReadBack), AArtifact.Files[I].ContentSHA256) then
      begin
        AError := 'COMMIT_FAILED: committed bytes differ';
        AEvidence.Status := esFailed;
        Exit(False);
      end;
    end;
    AEvidence.Status := esOk;
    AEvidence.Tool := 'local-filesystem';
    Result := True;
  except
    on E: Exception do
    begin
      AError := 'COMMIT_FAILED: ' + E.Message;
      AEvidence.Status := esFailed;
      Result := False;
    end;
  end;
end;

end.
