unit Grisp.Canonical;

interface

uses
  System.SysUtils, System.Classes, System.Hash, Grisp.Types;

type
  TGrispCanonical = class
  public
    /// <summary>
    /// Encodes string into strict BOM-less UTF-8 bytes.
    /// </summary>
    class function ToUTF8Bytes(const AInput: string): TBytes; static;

    /// <summary>
    /// Generates canonical lowercase SHA-256 checksum over byte payloads.
    /// </summary>
    class function ComputeSHA256(const AData: TBytes): string; overload; static;
    class function ComputeSHA256(const AText: string): string; overload; static;

    /// <summary>
    /// Validates candidate manifest raw bytes against the embedded content hash.
    /// </summary>
    class function VerifyManifest(const AManifest: TGrispManifest): Boolean; static;
  end;

implementation

class function TGrispCanonical.ToUTF8Bytes(const AInput: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(AInput);
end;

class function TGrispCanonical.ComputeSHA256(const AData: TBytes): string;
var
  Hasher: THashSHA2;
begin
  Hasher := THashSHA2.Create(THashSHA2.TSHA2Version.SHA256);
  if Length(AData) > 0 then
    Hasher.Update(AData);
  Result := Hasher.HashAsString.ToLower;
end;

class function TGrispCanonical.ComputeSHA256(const AText: string): string;
begin
  Result := ComputeSHA256(ToUTF8Bytes(AText));
end;

class function TGrispCanonical.VerifyManifest(const AManifest: TGrispManifest): Boolean;
var
  CalculatedHash: string;
begin
  if Length(AManifest.RawBytes) = 0 then
    Exit(False);

  CalculatedHash := ComputeSHA256(AManifest.RawBytes);
  Result := SameText(CalculatedHash, AManifest.ContentHash);
end;

end.
