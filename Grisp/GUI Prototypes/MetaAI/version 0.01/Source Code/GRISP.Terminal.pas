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
    '╔════════════════════════════════════════════════════════════╗' + sLineBreak +
    '║ GRISP OS  Deterministic AI Runtime  [Chat] [Terminal]     ║' + sLineBreak +
    '╠═══════════════╦═══════════════════════╦══════════════════╣' + sLineBreak +
    '║ Explorer R W X ║ Project setup         ║ Plan / Work Items║' + sLineBreak +
    '║ Sessions      ║ Chat + Thinking       ║ Export buttons   ║' + sLineBreak +
    '╚═══════════════╩═══════════════════════╩══════════════════╝';
end;

class function TGRISPTerminal.GenerateASCII: string;
begin
  Result := GenerateUnicode;
  Result := StringReplace(Result, '╔', '+', [rfReplaceAll]);
  Result := StringReplace(Result, '╗', '+', [rfReplaceAll]);
  Result := StringReplace(Result, '╚', '+', [rfReplaceAll]);
  Result := StringReplace(Result, '╝', '+', [rfReplaceAll]);
  Result := StringReplace(Result, '═', '-', [rfReplaceAll]);
  Result := StringReplace(Result, '║', '|', [rfReplaceAll]);
  Result := StringReplace(Result, '╠', '+', [rfReplaceAll]);
  Result := StringReplace(Result, '╣', '+', [rfReplaceAll]);
end;

class function TGRISPTerminal.GenerateANSI: string;
begin
  Result := #27'[38;2;0;212;255m' + GenerateUnicode + #27'[0m';
end;

end.
