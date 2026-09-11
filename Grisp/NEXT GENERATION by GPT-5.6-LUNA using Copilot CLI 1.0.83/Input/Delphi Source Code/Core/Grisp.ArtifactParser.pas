unit Grisp.ArtifactParser;

interface

uses
  System.SysUtils, System.JSON, System.Classes, System.RegularExpressions,
  Grisp.Types, Grisp.Artifact, Grisp.Hash;

type
  TGrispParseResult = (prParsed, prParseError, prParseAmbiguous, prSchemaError,
    prHashMismatch);

function ParseStructuredArtifact(const AResponse: string; const ATaskId: string;
  out AArtifact: TGrispArtifactBundle; out AError: string): TGrispParseResult;
function ParseMarkdownArtifact(const AResponse, ATaskId: string;
  out AArtifact: TGrispArtifactBundle; out AError: string): TGrispParseResult;

implementation

function ParseStructuredArtifact(const AResponse: string; const ATaskId: string;
  out AArtifact: TGrispArtifactBundle; out AError: string): TGrispParseResult;
var
  Root: TJSONValue;
  Files: TJSONArray;
  I: Integer;
  Obj: TJSONObject;
  Bytes: TBytes;
  Content, KindName, SuppliedArtifactId, SuppliedHash: string;
begin
  AError := '';
  Result := prSchemaError;
  Root := TJSONObject.ParseJSONValue(AResponse);
  if not (Root is TJSONObject) then begin AError := 'invalid JSON'; Exit(prParseError); end;
  try
    if not TJSONObject(Root).TryGetValue<string>('task_id', AArtifact.TaskId) then
      AArtifact.TaskId := ATaskId;
    TJSONObject(Root).TryGetValue<string>('artifact_id', SuppliedArtifactId);
    if not TJSONObject(Root).TryGetValue<TJSONArray>('files', Files) then
      begin AError := 'files array required'; Exit(prSchemaError); end;
    AArtifact.ArtifactKind := akUnit;
    AArtifact.Language := 'delphi';
    SetLength(AArtifact.Files, Files.Count);
    for I := 0 to Files.Count - 1 do
    begin
      if not (Files.Items[I] is TJSONObject) then begin AError := 'file must be object'; Exit(prSchemaError); end;
      Obj := TJSONObject(Files.Items[I]);
      if not Obj.TryGetValue<string>('filename', AArtifact.Files[I].FileName) then
        begin AError := 'filename required'; Exit(prSchemaError); end;
      Obj.TryGetValue<string>('language', AArtifact.Files[I].Language);
      Obj.TryGetValue<string>('kind', KindName);
      Obj.TryGetValue<string>('content_sha256', SuppliedHash);
      AArtifact.Files[I].Kind := afkSource;
      if not Obj.TryGetValue<string>('content', Content) then
        begin AError := 'content required'; Exit(prSchemaError); end;
      Bytes := TEncoding.UTF8.GetBytes(Content);
      if (SuppliedHash <> '') and
        not SameText(SuppliedHash, Sha256Bytes(Bytes)) then
        begin AError := 'HASH_MISMATCH'; Exit(prHashMismatch); end;
      AError := '';
      AArtifact.Files[I].Content := Bytes;
      AArtifact.Files[I].ContentEncoding := ceUtf8;
    end;
    if not BuildArtifact(AArtifact, AError) then Exit(prHashMismatch);
    if (SuppliedArtifactId <> '') and not SameText(SuppliedArtifactId, AArtifact.ArtifactId) then
      begin AError := 'ARTIFACT_HASH_MISMATCH'; Exit(prHashMismatch); end;
    Result := prParsed;
  finally
    Root.Free;
  end;
end;

function ParseMarkdownArtifact(const AResponse, ATaskId: string;
  out AArtifact: TGrispArtifactBundle; out AError: string): TGrispParseResult;
var
  Match: TMatch;
  Matches: TMatchCollection;
  Header, FileName, Language, Content: string;
begin
  AError := '';
  Matches := TRegEx.Matches(AResponse, '```([^\r\n]*)\r?\n([\s\S]*?)\r?\n```');
  if Matches.Count = 0 then begin AError := 'no fenced artifact'; Exit(prParseError); end;
  if Matches.Count > 1 then begin AError := 'multiple interpretations'; Exit(prParseAmbiguous); end;
  Match := Matches[0];
  Header := Trim(Match.Groups[1].Value);
  Content := Match.Groups[2].Value;
  FileName := '';
  Language := Header;
  if Header.Contains(':') then begin
    Language := Header.Substring(0, Header.IndexOf(':')).Trim;
    FileName := Header.Substring(Header.IndexOf(':') + 1).Trim;
  end;
  if FileName = '' then begin AError := 'filename required'; Exit(prParseError); end;
  AArtifact.TaskId := ATaskId;
  AArtifact.ArtifactKind := akUnit;
  AArtifact.Language := Language;
  SetLength(AArtifact.Files, 1);
  AArtifact.Files[0].FileName := FileName;
  AArtifact.Files[0].Language := Language;
  AArtifact.Files[0].Kind := afkSource;
  AArtifact.Files[0].Content := TEncoding.UTF8.GetBytes(Content);
  AArtifact.Files[0].ContentEncoding := ceUtf8;
  if not BuildArtifact(AArtifact, AError) then Exit(prParseError);
  Result := prParsed;
end;

end.
