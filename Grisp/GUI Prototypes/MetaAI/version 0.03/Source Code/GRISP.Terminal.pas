unit GRISP.Terminal;

interface

type
  TGRISPTerminal = class
  public
    class function GenerateUnicode: string;
    class function GenerateASCII: string;
    class function GenerateANSI: string;
  end;

implementation

uses System.SysUtils;

class function TGRISPTerminal.GenerateUnicode: string;
begin
  Result :=
    'GRISP OS  v0.03 - Export OK' + sLineBreak +
    'Explorer R W X colored - Plan fixed - Export buttons fixed';
end;

class function TGRISPTerminal.GenerateASCII: string;
begin
  Result := GenerateUnicode;
end;

class function TGRISPTerminal.GenerateANSI: string;
begin
  Result := #27'[38;2;0;212;255m' + GenerateUnicode + #27'[0m';
end;

end.
