unit Grisp.Hash;

interface

uses
  System.SysUtils, System.Hash, System.Classes;

function Sha256Bytes(const ABytes: TBytes): string;
function Sha256Text(const AText: string): string;

implementation

function Sha256Bytes(const ABytes: TBytes): string;
var
  H: THashSHA2;
begin
  H := THashSHA2.Create(THashSHA2.TSHA2Version.SHA256);
  if Length(ABytes) > 0 then
    H.Update(ABytes);
  Result := 'sha256:' + LowerCase(H.HashAsString);
end;

function Sha256Text(const AText: string): string;
begin
  Result := Sha256Bytes(TEncoding.UTF8.GetBytes(AText));
end;

end.