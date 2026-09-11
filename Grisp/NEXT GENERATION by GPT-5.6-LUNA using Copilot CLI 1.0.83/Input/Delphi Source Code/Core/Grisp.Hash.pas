unit Grisp.Hash;

interface

uses
  System.SysUtils, System.Hash, System.Classes;

function Sha256Bytes(const ABytes: TBytes): string;
function Sha256Text(const AText: string): string;

implementation

function Sha256Bytes(const ABytes: TBytes): string;
var
  Stream: TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  try
    if Length(ABytes) > 0 then Stream.WriteBuffer(ABytes[0], Length(ABytes));
    Stream.Position := 0;
    Result := 'sha256:' + LowerCase(THashSHA2.GetHashString(Stream));
  finally
    Stream.Free;
  end;
end;

function Sha256Text(const AText: string): string;
begin
  Result := Sha256Bytes(TEncoding.UTF8.GetBytes(AText));
end;

end.
