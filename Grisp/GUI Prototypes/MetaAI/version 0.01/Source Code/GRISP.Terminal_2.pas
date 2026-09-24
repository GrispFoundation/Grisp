unit GRISP.Terminal;

interface

uses System.SysUtils, System.Classes;

type
  TGRISPTerminal = class
  public
    class function GenerateUnicode: string;
    class function GenerateASCII: string;
    class function GenerateANSI: string;
    class function GenerateDelphiConsoleCode: string;
  end;

implementation

class function TGRISPTerminal.GenerateUnicode: string;
begin
  Result :=
    '╔════════════════════════════════════════════════════════════════════════════╗' + sLineBreak +
    '║ ◇ GRISP OS  Deterministic AI Runtime  [● Chat] [ Workflows] [ Knowledge] ║' + sLineBreak +
    '╠═══════════════════╦══════════════════════════════════╦═══════════════════╣' + sLineBreak +
    '║ Explorer     R W X ║ Project setup and architecture   ║ Plan / Work Items ║' + sLineBreak +
    '║ ├─ GRISP     R W X ║ You: Can you analyze GRISP?      ║ 1 [✓] Analyze     ║' + sLineBreak +
    '║ │  ├─ src    R W X ║ GRISP Assistant: Sure!           ║ 2 [○] Review      ║' + sLineBreak +
    '║ │  └─ docs   R W X ║  1. SIR 2. Planner 3. Evaluator  ║ 3 [ ] Create      ║' + sLineBreak +
    '║ Sessions          ║ ┌─ Thinking ▼─┐                  ║ Work Items High   ║' + sLineBreak +
    '║ > Setup 22/09     ║ │ ✓ Analyzing...                 │ ║                   ║' + sLineBreak +
    '║ + New Session     ║ Type your message...        [▶]  ║                   ║' + sLineBreak +
    '╚═══════════════════╩══════════════════════════════════╩═══════════════════╝';
end;

class function TGRISPTerminal.GenerateASCII: string;
begin
  Result := StringReplace(GenerateUnicode, '╔', '+', [rfReplaceAll]);
  Result := StringReplace(Result, '╗', '+', [rfReplaceAll]);
  Result := StringReplace(Result, '╚', '+', [rfReplaceAll]);
  Result := StringReplace(Result, '╝', '+', [rfReplaceAll]);
  Result := StringReplace(Result, '═', '-', [rfReplaceAll]);
  Result := StringReplace(Result, '║', '|', [rfReplaceAll]);
  Result := StringReplace(Result, '╠', '+', [rfReplaceAll]);
  Result := StringReplace(Result, '╣', '+', [rfReplaceAll]);
  Result := StringReplace(Result, '─', '-', [rfReplaceAll]);
  Result := StringReplace(Result, '│', '|', [rfReplaceAll]);
  Result := StringReplace(Result, '◇', '*', [rfReplaceAll]);
  Result := StringReplace(Result, '●', '*', [rfReplaceAll]);
  Result := StringReplace(Result, '✓', 'v', [rfReplaceAll]);
end;

class function TGRISPTerminal.GenerateANSI: string;
begin
  // ESC[38;2;0;212;255m = cyan RGB - werkt in cmd.exe Windows 10+ met VirtualTerminalLevel
  Result := #27'[38;2;0;212;255m' + GenerateUnicode + #27'[0m';
end;

class function TGRISPTerminal.GenerateDelphiConsoleCode: string;
begin
  Result :=
    'program GRISP_Terminal;' + sLineBreak +
    '{$APPTYPE CONSOLE}' + sLineBreak +
    'uses Winapi.Windows, System.SysUtils;' + sLineBreak +
    'procedure EnableANSI; var h:THandle; m:DWORD; begin h:=GetStdHandle(-11); GetConsoleMode(h,m); SetConsoleMode(h,m or 4); end;' + sLineBreak +
    'begin EnableANSI; Writeln(''GRISP OS Terminal - Delphi 13''); ReadLn; end.';
end;

end.
