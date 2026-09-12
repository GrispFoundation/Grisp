unit GSDACanonicalJson;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON;

type
  TGSDACanonicalJson = class
  public
    class function Canonicalize(const Obj: TJSONValue): string; static;
  end;

implementation

function CompareUtf8Bytewise(const A, B: string): Integer;
var
  BA, BB: TBytes;
  I, Len: Integer;
begin
  BA := TEncoding.UTF8.GetBytes(A);
  BB := TEncoding.UTF8.GetBytes(B);
  Len := Min(Length(BA), Length(BB));

  for I := 0 to Len - 1 do
  begin
    if BA[I] < BB[I] then
      Exit(-1)
    else if BA[I] > BB[I] then
      Exit(1);
  end;

  if Length(BA) < Length(BB) then
    Result := -1
  else if Length(BA) > Length(BB) then
    Result := 1
  else
    Result := 0;
end;

procedure SortObjectKeys(const Obj: TJSONObject; const Keys: TList<string>);
var
  Pair: TJSONPair;
begin
  Keys.Clear;
  for Pair in Obj do
    Keys.Add(Pair.JsonString.Value);
  Keys.Sort(
    TComparer<string>.Construct(
      function(const L, R: string): Integer
      begin
        Result := CompareUtf8Bytewise(L, R);
      end
    )
  );
end;

function CanonicalizeObject(const Obj: TJSONObject): string;
var
  Keys: TList<string>;
  Key: string;
  Pair: TJSONPair;
  SB: TStringBuilder;
begin
  Keys := TList<string>.Create;
  SB := TStringBuilder.Create;
  try
    SortObjectKeys(Obj, Keys);

    SB.Append('{');
    for Key in Keys do
    begin
      Pair := Obj.Get(Key);
      if Pair = nil then
        raise Exception.CreateFmt('Duplicate or missing key in object: %s', [Key]);

      SB.Append('"');
      SB.Append(Key);
      SB.Append('":');
      SB.Append(TGSDACanonicalJson.Canonicalize(Pair.JsonValue));

      if Key <> Keys.Last then
        SB.Append(',');
    end;
    SB.Append('}');
    Result := SB.ToString;
  finally
    Keys.Free;
    SB.Free;
  end;
end;

function CanonicalizeArray(const Arr: TJSONArray): string;
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('[');
    for I := 0 to Arr.Count - 1 do
    begin
      SB.Append(TGSDACanonicalJson.Canonicalize(Arr.Items[I]));
      if I < Arr.Count - 1 then
        SB.Append(',');
    end;
    SB.Append(']');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function CanonicalizeString(const S: string): string;
begin
  // Minimal: escape quotes and backslashes; you can extend to full JSON escaping.
  Result := '"' + StringReplace(StringReplace(S, '\', '\\', [rfReplaceAll]),
                                '"', '\"', [rfReplaceAll]) + '"';
end;

function CanonicalizeNumber(const N: TJSONNumber): string;
var
  V: Double;
begin
  V := N.AsDouble;

  if (IsNan(V)) or (IsInfinite(V)) then
    raise Exception.Create('NaN or Infinity not allowed in canonical JSON');

  // Negative zero normalization
  if (V = 0.0) and (Copy(N.ToString, 1, 1) = '-') then
    Result := '0'
  else
    Result := N.ToString;
end;

class function TGSDACanonicalJson.Canonicalize(const Obj: TJSONValue): string;
begin
  if Obj = nil then
    Exit('null');

  if Obj is TJSONObject then
    Result := CanonicalizeObject(TJSONObject(Obj))
  else if Obj is TJSONArray then
    Result := CanonicalizeArray(TJSONArray(Obj))
  else if Obj is TJSONString then
    Result := CanonicalizeString(TJSONString(Obj).Value)
  else if Obj is TJSONNumber then
    Result := CanonicalizeNumber(TJSONNumber(Obj))
  else if Obj is TJSONBool then
    Result := LowerCase(Obj.ToString) // "true" or "false"
  else
    Result := Obj.ToString; // fallback
end;

end.
