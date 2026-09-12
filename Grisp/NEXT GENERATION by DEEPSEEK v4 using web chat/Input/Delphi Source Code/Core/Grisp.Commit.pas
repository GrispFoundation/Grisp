unit Grisp.Commit;

interface

uses
  System.SysUtils, System.IOUtils, Grisp.Types, Grisp.Artifact, Grisp.Hash;

function CommitArtifact(
  const AArtifact: TGrispArtifactBundle;
  const AFinalRoot: string;
  out AEvidence: TGrispEvidence;
  out AError: string
): Boolean;

implementation

function CommitArtifact(
  const AArtifact: TGrispArtifactBundle;
  const AFinalRoot: string;
  out AEvidence: TGrispEvidence;
  out AError: string
): Boolean;
var
  StagingRoot, FinalRoot, Path: string;
  I: Integer;
  ReadBack: TBytes;
begin
  AError := '';
  AEvidence := Default(TGrispEvidence);
  AEvidence.EvidenceId := NewUuid;
  AEvidence.TaskId := AArtifact.TaskId;
  AEvidence.ArtifactId := AArtifact.ArtifactId;
  AEvidence.Operation := eoCommit;
  AEvidence.Tool := 'local-filesystem';
  AEvidence.CreatedAt := UtcNowText;

  // Validate before commit.
  if not ValidateArtifact(AArtifact, AError) then
  begin
    AEvidence.Status := esRejected;
    Exit(False);
  end;

  StagingRoot := TPath.Combine(AFinalRoot, '.staging_' + NewUuid);
  FinalRoot := TPath.Combine(AFinalRoot, AArtifact.ArtifactId.Replace(':', '_'));

  if TDirectory.Exists(FinalRoot) then
  begin
    AError := 'COMMIT_FAILED: final artifact path already exists';
    AEvidence.Status := esFailed;
    Exit(False);
  end;

  ForceDirectories(StagingRoot);
  try
    // 1. Write all files into staging.
    for I := 0 to High(AArtifact.Files) do
    begin
      if not ValidateFileName(AArtifact.Files[I].FileName, AError) then
      begin
        AEvidence.Status := esFailed;
        Exit(False);
      end;

      Path := TPath.Combine(StagingRoot, AArtifact.Files[I].FileName);
      ForceDirectories(ExtractFileDir(Path));
      TFile.WriteAllBytes(Path, AArtifact.Files[I].Content);
    end;

    // 2. Read back and verify hashes.
    for I := 0 to High(AArtifact.Files) do
    begin
      Path := TPath.Combine(StagingRoot, AArtifact.Files[I].FileName);
      ReadBack := TFile.ReadAllBytes(Path);
      if not SameText(Sha256Bytes(ReadBack), AArtifact.Files[I].ContentSHA256) then
      begin
        AError := 'COMMIT_FAILED: staging bytes differ for ' + AArtifact.Files[I].FileName;
        AEvidence.Status := esFailed;
        Exit(False);
      end;
    end;

    // 3. Atomic publish.
    TDirectory.Move(StagingRoot, FinalRoot);

    // 4. Re-read committed bytes and verify final identity.
    for I := 0 to High(AArtifact.Files) do
    begin
      Path := TPath.Combine(FinalRoot, AArtifact.Files[I].FileName);
      ReadBack := TFile.ReadAllBytes(Path);
      if not SameText(Sha256Bytes(ReadBack), AArtifact.Files[I].ContentSHA256) then
      begin
        AError := 'COMMIT_FAILED: post-commit verification mismatch for ' + AArtifact.Files[I].FileName;
        AEvidence.Status := esFailed;
        Exit(False);
      end;
    end;

    AEvidence.Status := esOk;
    AEvidence.OutputHash := AArtifact.ArtifactId;
    Result := True;
  except
    on E: Exception do
    begin
      AError := 'COMMIT_FAILED: ' + E.Message;
      AEvidence.Status := esFailed;
      if TDirectory.Exists(StagingRoot) then
        TDirectory.Delete(StagingRoot, True);
      Result := False;
    end;
  end;
end;

end.