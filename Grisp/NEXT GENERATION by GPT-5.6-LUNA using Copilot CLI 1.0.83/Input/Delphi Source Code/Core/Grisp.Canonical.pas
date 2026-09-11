unit Grisp.Canonical;

interface

uses
  System.SysUtils, System.JSON, System.Generics.Collections, Grisp.Types;

function CanonicalJson(const AValue: TJSONValue): string;
function CanonicalArtifactManifest(const AArtifact: TGrispArtifactBundle): string;

implementation

function JsonQuote(const AValue: string): string;
begin
  Result := TJSONString.Create(AValue).ToJSON;
end;

function CanonicalJson(const AValue: TJSONValue): string;
var
  Pair, PairTemp: TJSONPair;
  Pairs: TList<TJSONPair>;
  Item: TJSONValue;
  I, J: Integer;
begin
  if AValue is TJSONObject then
  begin
    Pairs := TList<TJSONPair>.Create;
    try
      for Pair in TJSONObject(AValue) do Pairs.Add(Pair);
      for I := 0 to Pairs.Count - 1 do
        for J := I + 1 to Pairs.Count - 1 do
          if CompareStr(Pairs[I].JsonString.Value, Pairs[J].JsonString.Value) > 0 then
          begin
            PairTemp := Pairs[I];
            Pairs[I] := Pairs[J];
            Pairs[J] := PairTemp;
          end;
      Result := '{';
      for I := 0 to Pairs.Count - 1 do
      begin
        if I > 0 then Result := Result + ',';
        Result := Result + JsonQuote(Pairs[I].JsonString.Value) + ':' +
          CanonicalJson(Pairs[I].JsonValue);
      end;
      Result := Result + '}';
    finally
      Pairs.Free;
    end;
  end
  else if AValue is TJSONArray then
  begin
    Result := '[';
    for I := 0 to TJSONArray(AValue).Count - 1 do
    begin
      if I > 0 then Result := Result + ',';
      Item := TJSONArray(AValue).Items[I];
      Result := Result + CanonicalJson(Item);
    end;
    Result := Result + ']';
  end
  else
    Result := AValue.ToJSON;
end;

function CanonicalArtifactManifest(const AArtifact: TGrispArtifactBundle): string;
var
  Root, FileObject: TJSONObject;
  Provenance: TJSONObject;
  Files: TJSONArray;
  Sorted: TArray<TGrispArtifactFile>;
  F, Temp: TGrispArtifactFile;
  I, J: Integer;
  Metadata: TJSONValue;
begin
  Sorted := Copy(AArtifact.Files);
  for I := 0 to Length(Sorted) - 1 do
    for J := I + 1 to Length(Sorted) - 1 do
      if (CompareStr(Sorted[I].FileName, Sorted[J].FileName) > 0) or
        ((Sorted[I].FileName = Sorted[J].FileName) and
        (CompareStr(Sorted[I].ContentSHA256, Sorted[J].ContentSHA256) > 0)) then
      begin
        Temp := Sorted[I];
        Sorted[I] := Sorted[J];
        Sorted[J] := Temp;
      end;
  Root := TJSONObject.Create;
  try
    Root.AddPair('task_id', AArtifact.TaskId);
    if AArtifact.ParentArtifactId <> '' then
      Root.AddPair('parent_artifact_id', AArtifact.ParentArtifactId);
    Root.AddPair('revision', TJSONNumber.Create(AArtifact.Revision));
    Root.AddPair('artifact_kind', ArtifactKindName(AArtifact.ArtifactKind));
    Root.AddPair('language', AArtifact.Language);
    Files := TJSONArray.Create;
    Root.AddPair('files', Files);
    for I := 0 to Length(Sorted) - 1 do
    begin
      F := Sorted[I];
      FileObject := TJSONObject.Create;
      FileObject.AddPair('filename', F.FileName);
      FileObject.AddPair('language', F.Language);
      FileObject.AddPair('kind', FileKindName(F.Kind));
      FileObject.AddPair('content_encoding', ContentEncodingName(F.ContentEncoding));
      FileObject.AddPair('content_sha256', F.ContentSHA256);
      FileObject.AddPair('size_bytes', TJSONNumber.Create(F.SizeBytes));
      Files.AddElement(FileObject);
    end;
    Provenance := TJSONObject.Create;
    if AArtifact.Provenance.Provider <> '' then Provenance.AddPair('provider', AArtifact.Provenance.Provider);
    if AArtifact.Provenance.WorkerId <> '' then Provenance.AddPair('worker_id', AArtifact.Provenance.WorkerId);
    if AArtifact.Provenance.SessionId <> '' then Provenance.AddPair('session_id', AArtifact.Provenance.SessionId);
    if AArtifact.Provenance.TabId <> '' then Provenance.AddPair('tab_id', AArtifact.Provenance.TabId);
    if AArtifact.Provenance.MessageId <> '' then Provenance.AddPair('message_id', AArtifact.Provenance.MessageId);
    if AArtifact.Provenance.PromptHash <> '' then Provenance.AddPair('prompt_hash', AArtifact.Provenance.PromptHash);
    if AArtifact.Provenance.ResponseHash <> '' then Provenance.AddPair('response_hash', AArtifact.Provenance.ResponseHash);
    if AArtifact.Provenance.CreatedAt <> '' then Provenance.AddPair('created_at', AArtifact.Provenance.CreatedAt);
    Root.AddPair('provenance', Provenance);
    Metadata := TJSONObject.ParseJSONValue(AArtifact.MetadataJson);
    if Metadata = nil then Metadata := TJSONObject.Create;
    Root.AddPair('metadata', Metadata);
    Result := CanonicalJson(Root);
  finally
    Root.Free;
  end;
end;

end.
