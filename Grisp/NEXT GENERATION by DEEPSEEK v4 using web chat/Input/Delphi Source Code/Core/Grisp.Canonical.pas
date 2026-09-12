unit Grisp.Canonical;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, Grisp.Types;

function Utf8Bytes(const S: string): TBytes;
function Utf8Compare(const A, B: string): Integer;
function JsonQuote(const S: string): string;
function CanonicalManifest(const A: TGrispArtifactBundle): string;

implementation

function Utf8Bytes(const S: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(S);
end;

function Utf8Compare(const A, B: string): Integer;
var
  BA, BB: TBytes;
  I, N: Integer;
begin
  BA := Utf8Bytes(A);
  BB := Utf8Bytes(B);
  N := Min(Length(BA), Length(BB));
  for I := 0 to N - 1 do
    if BA[I] <> BB[I] then
      Exit(BA[I] - BB[I]);
  Result := Length(BA) - Length(BB);
end;

function JsonQuote(const S: string): string;
var
  I: Integer;
  C: Char;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('"');
    for I := 1 to Length(S) do
    begin
      C := S[I];
      case C of
        '"': SB.Append('\"');
        '\': SB.Append('\\');
        #8: SB.Append('\b');
        #9: SB.Append('\t');
        #10: SB.Append('\n');
        #12: SB.Append('\f');
        #13: SB.Append('\r');
      else
        if Ord(C) < 32 then
          SB.Append(Format('\u%.4x', [Ord(C)]))
        else
          SB.Append(C);
      end;
    end;
    SB.Append('"');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function CanonicalManifest(const A: TGrispArtifactBundle): string;
var
  SB: TStringBuilder;
  Files: TArray<TGrispArtifactFile>;
  I, J: Integer;
  Tmp: TGrispArtifactFile;

  procedure AddField(const Name, Value: string; AddComma: Boolean);
  begin
    if AddComma then SB.Append(',');
    SB.Append(JsonQuote(Name));
    SB.Append(':');
    SB.Append(Value);
  end;

begin
  Files := Copy(A.Files);

  // Sort by filename UTF-8, then content hash UTF-8.
  for I := 0 to High(Files) do
    for J := I + 1 to High(Files) do
      if (Utf8Compare(Files[I].FileName, Files[J].FileName) > 0) or
         ((Utf8Compare(Files[I].FileName, Files[J].FileName) = 0) and
          (Utf8Compare(Files[I].ContentSHA256, Files[J].ContentSHA256) > 0)) then
      begin
        Tmp := Files[I];
        Files[I] := Files[J];
        Files[J] := Tmp;
      end;

  SB := TStringBuilder.Create;
  try
    SB.Append('{');
    AddField('task_id', JsonQuote(A.TaskId), False);
    if A.ParentArtifactId <> '' then
      AddField('parent_artifact_id', JsonQuote(A.ParentArtifactId), True);
    AddField('revision', IntToStr(A.Revision), True);
    AddField('artifact_kind', JsonQuote(ArtifactKindName(A.ArtifactKind)), True);
    AddField('language', JsonQuote(A.Language), True);

    if True then
    begin
      SB.Append(',');
      SB.Append('"files":[');
      for I := 0 to High(Files) do
      begin
        if I > 0 then SB.Append(',');
        SB.Append('{');
        AddField('filename', JsonQuote(Files[I].FileName), False);
        AddField('language', JsonQuote(Files[I].Language), True);
        AddField('kind', JsonQuote(FileKindName(Files[I].Kind)), True);
        AddField('content_encoding', JsonQuote(ContentEncodingName(Files[I].ContentEncoding)), True);
        AddField('content_sha256', JsonQuote(Files[I].ContentSHA256), True);
        AddField('size_bytes', IntToStr(Files[I].SizeBytes), True);
        SB.Append('}');
      end;
      SB.Append(']');
    end;

    SB.Append(',');
    SB.Append('"provenance":{');
    // Simplified: add non-empty fields.
    if A.Provenance.Provider <> '' then AddField('provider', JsonQuote(A.Provenance.Provider), False);
    if A.Provenance.WorkerId <> '' then AddField('worker_id', JsonQuote(A.Provenance.WorkerId), True);
    if A.Provenance.SessionId <> '' then AddField('session_id', JsonQuote(A.Provenance.SessionId), True);
    if A.Provenance.TabId <> '' then AddField('tab_id', JsonQuote(A.Provenance.TabId), True);
    if A.Provenance.MessageId <> '' then AddField('message_id', JsonQuote(A.Provenance.MessageId), True);
    if A.Provenance.PromptHash <> '' then AddField('prompt_hash', JsonQuote(A.Provenance.PromptHash), True);
    if A.Provenance.ResponseHash <> '' then AddField('response_hash', JsonQuote(A.Provenance.ResponseHash), True);
    if A.Provenance.CreatedAt <> '' then AddField('created_at', JsonQuote(A.Provenance.CreatedAt), True);
    SB.Append('}');

    SB.Append(',');
    if A.MetadataJson = '' then
      SB.Append('"metadata":{}')
    else
      SB.Append('"metadata":' + A.MetadataJson);

    SB.Append('}');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

end.