program GrispTUI;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes;

const
  // ANSI Colors & Styles
  C_RESET       = #27'[0m';
  C_BOLD        = #27'[1m';
  C_CYAN        = #27'[38;2;0;240;255m';
  C_LIGHT_BLUE  = #27'[38;2;56;189;248m';
  C_DARK_BLUE   = #27'[38;2;2;132;199m';
  C_WHITE       = #27'[38;2;248;250;252m';
  C_GRAY        = #27'[38;2;100;116;139m';
  C_GREEN       = #27'[38;2;74;222;128m';
  C_YELLOW      = #27'[38;2;250;204;21m';

type
  TFilePermission = (fpRead, fpWrite, fpExecute);
  TFilePermissions = set of TFilePermission;

  TProjectItem = record
    Name: string;
    IsDirectory: Boolean;
    IndentLevel: Integer;
    Permissions: TFilePermissions;
    constructor Create(const AName: string; AIsDir: Boolean; AIndent: Integer; APerms: TFilePermissions);
  end;

  TSessionItem = record
    Subject: string;
    DateStr: string;
    TimeStr: string;
    constructor Create(const ASubject, ADate, ATime: string);
  end;

var
  SidebarExpanded: Boolean = True;
  ThinkCollapsed: Boolean = True;
  ProjectFiles: array of TProjectItem;
  Sessions: array of TSessionItem;
  CurrentInput: string = '';

constructor TProjectItem.Create(const AName: string; AIsDir: Boolean; AIndent: Integer; APerms: TFilePermissions);
begin
  Name := AName;
  IsDirectory := AIsDir;
  IndentLevel := AIndent;
  Permissions := APerms;
end;

constructor TSessionItem.Create(const ASubject, ADate, ATime: string);
begin
  Subject := ASubject;
  DateStr := ADate;
  TimeStr := ATime;
end;

procedure EnableVirtualTerminalProcessing;
var
  HOut: THandle;
  Mode: DWORD;
begin
  HOut := GetStdHandle(STD_OUTPUT_HANDLE);
  if (HOut <> INVALID_HANDLE_VALUE) and GetConsoleMode(HOut, Mode) then
  begin
    Mode := Mode or ENABLE_VIRTUAL_TERMINAL_PROCESSING;
    SetConsoleMode(HOut, Mode);
  end;
  SetConsoleOutputCP(CP_UTF8);
  SetConsoleCP(CP_UTF8);
end;

procedure GetConsoleSize(out Width, Height: Integer);
var
  HOut: THandle;
  CSBI: CONSOLE_SCREEN_BUFFER_INFO;
begin
  Width := 100;
  Height := 30;
  HOut := GetStdHandle(STD_OUTPUT_HANDLE);
  if (HOut <> INVALID_HANDLE_VALUE) and GetConsoleScreenBufferInfo(HOut, CSBI) then
  begin
    Width := CSBI.srWindow.Right - CSBI.srWindow.Left + 1;
    Height := CSBI.srWindow.Bottom - CSBI.srWindow.Top + 1;
  end;
end;

procedure InitData;
begin
  SetLength(ProjectFiles, 5);
  ProjectFiles[0] := TProjectItem.Create('src/', True, 0, [fpRead, fpExecute]);
  ProjectFiles[1] := TProjectItem.Create('main.pas', False, 1, [fpRead, fpWrite, fpExecute]);
  ProjectFiles[2] := TProjectItem.Create('compiler.pas', False, 1, [fpRead, fpExecute]);
  ProjectFiles[3] := TProjectItem.Create('types.pas', False, 1, [fpRead, fpWrite]);
  ProjectFiles[4] := TProjectItem.Create('build.cmd', False, 1, [fpExecute]);

  SetLength(Sessions, 3);
  Sessions[0] := TSessionItem.Create('AST Parser Refactor', '2026-09-24', '14:10');
  Sessions[1] := TSessionItem.Create('Memory Bugfix', '2026-09-23', '09:45');
  Sessions[2] := TSessionItem.Create('GRISP Canvas Integration', '2026-09-21', '16:30');
end;

function FormatPermissions(Perms: TFilePermissions): string;
begin
  Result := '[';
  if fpRead in Perms then Result := Result + 'r' else Result := Result + '-';
  if fpWrite in Perms then Result := Result + 'w' else Result := Result + '-';
  if fpExecute in Perms then Result := Result + 'x' else Result := Result + '-';
  Result := Result + ']';
end;

function VisibleLength(const S: string): Integer;
var
  I, Len: Integer;
  InEscape: Boolean;
begin
  Result := 0;
  InEscape := False;
  I := 1;
  Len := Length(S);
  while I <= Len do
  begin
    if S[I] = #27 then
    begin
      InEscape := True;
      Inc(I);
      Continue;
    end;

    if InEscape then
    begin
      if CharInSet(S[I], ['a'..'z', 'A'..'Z']) then
        InEscape := False;
      Inc(I);
      Continue;
    end;

    Inc(Result);
    Inc(I);
  end;
end;

function PadRightVis(const S: string; TargetWidth: Integer): string;
var
  VisLen: Integer;
begin
  if TargetWidth <= 0 then Exit('');
  VisLen := VisibleLength(S);
  if VisLen < TargetWidth then
    Result := S + StringOfChar(' ', TargetWidth - VisLen)
  else
    Result := S;
end;

procedure DrawScreen;
var
  I: Integer;
  TermWidth, TermHeight: Integer;
  WSidebar, WMain, InnerW: Integer;
  LeftCol, RightCol: string;
  PermStr: string;
  RowsDrawn, FillLines: Integer;
  HeaderTagLeft, HeaderTagRight: string;
  DashLeft, DashRight, DashCount: Integer;
begin
  GetConsoleSize(TermWidth, TermHeight);
  if TermWidth < 65 then TermWidth := 65;

  HeaderTagLeft := ' [Tab] Sidebar ';
  HeaderTagRight := ' GRISP OS TERMINAL UI ';

  Write(#27'[2J'#27'[H');
  RowsDrawn := 0;

  if SidebarExpanded then
  begin
    WSidebar := TermWidth div 3;
    if WSidebar < 34 then WSidebar := 34;
    WMain := TermWidth - WSidebar - 3;

    // Exact Bovenrand Berekening
    DashLeft := WSidebar - VisibleLength(HeaderTagLeft) - 1;
    if DashLeft < 0 then DashLeft := 0;
    DashRight := WMain - VisibleLength(HeaderTagRight) - 1;
    if DashRight < 0 then DashRight := 0;

    Writeln(C_CYAN + '┌─' + C_WHITE + HeaderTagLeft + C_CYAN + StringOfChar('─', DashLeft) +
            '┬─' + C_BOLD + C_WHITE + HeaderTagRight + C_RESET + C_CYAN + StringOfChar('─', DashRight) + '┐' + C_RESET);
    Inc(RowsDrawn);

    // Header Titel
    LeftCol  := PadRightVis(' ' + C_BOLD + C_WHITE + 'PROJECT EXPLORER' + C_RESET, WSidebar);
    RightCol := PadRightVis(' ' + C_BOLD + C_LIGHT_BLUE + 'AI ASSISTANT WORKSPACE' + C_RESET, WMain);
    Writeln(C_CYAN + '│' + C_RESET + LeftCol + C_CYAN + '│' + C_RESET + RightCol + C_CYAN + '│' + C_RESET);
    Inc(RowsDrawn);

    // Scheidingslijn
    Writeln(C_CYAN + '├' + StringOfChar('─', WSidebar) + '┼' + StringOfChar('─', WMain) + '┤' + C_RESET);
    Inc(RowsDrawn);

    // Bestanden & Thinking Process
    for I := 0 to 4 do
    begin
      PermStr := FormatPermissions(ProjectFiles[I].Permissions);
      if ProjectFiles[I].IsDirectory then
        LeftCol := PadRightVis('  ' + C_LIGHT_BLUE + '▼ ' + ProjectFiles[I].Name + C_RESET, WSidebar)
      else
        LeftCol := PadRightVis('    ├── ' + C_WHITE + PadRightVis(ProjectFiles[I].Name, WSidebar - 14) + C_GRAY + PermStr + C_RESET, WSidebar);

      case I of
        0: RightCol := PadRightVis(' ' + C_YELLOW + '💭 THINKING PROCESS ' + C_GRAY + '(Ctrl+T to toggle)' + C_RESET, WMain);
        1: if ThinkCollapsed then
             RightCol := PadRightVis('   ' + C_DARK_BLUE + '│ ' + C_GRAY + '> Analyseren van AST nodes... (gecollapse)' + C_RESET, WMain)
           else
             RightCol := PadRightVis('   ' + C_DARK_BLUE + '│ ' + C_WHITE + '> Analyseren AST nodes... Check geheugen op leaks' + C_RESET, WMain);
        2: RightCol := PadRightVis('', WMain);
        3: RightCol := PadRightVis(' ' + C_WHITE + 'Hier is de voorgestelde logica voor de compiler module:' + C_RESET, WMain);
        4: RightCol := PadRightVis('', WMain);
      end;

      Writeln(C_CYAN + '│' + C_RESET + LeftCol + C_CYAN + '│' + C_RESET + RightCol + C_CYAN + '│' + C_RESET);
      Inc(RowsDrawn);
    end;

    Writeln(C_CYAN + '│' + StringOfChar(' ', WSidebar) + '│' + StringOfChar(' ', WMain) + '│' + C_RESET);
    Inc(RowsDrawn);

    // Sessie Geschiedenis & Work Plan
    LeftCol  := PadRightVis(' ' + C_BOLD + C_WHITE + 'SESSIE GESCHIEDENIS' + C_RESET, WSidebar);
    RightCol := PadRightVis(' ' + C_BOLD + C_GREEN + 'INLINE WORK PLAN' + C_RESET, WMain);
    Writeln(C_CYAN + '│' + C_RESET + LeftCol + C_CYAN + '│' + C_RESET + RightCol + C_CYAN + '│' + C_RESET);
    Inc(RowsDrawn);

    for I := 0 to 2 do
    begin
      LeftCol := PadRightVis('  ├── ' + C_WHITE + Sessions[I].Subject + C_RESET, WSidebar);
      case I of
        0: RightCol := PadRightVis('   ' + C_GREEN + '[X]' + C_WHITE + ' Step 1: Lexer uitbreiden met nieuwe tokens' + C_RESET, WMain);
        1: RightCol := PadRightVis('   ' + C_GRAY + '[ ]' + C_WHITE + ' Step 2: Code generator aanpassen voor AST nodes' + C_RESET, WMain);
        2: RightCol := PadRightVis('   ' + C_GRAY + '[ ]' + C_WHITE + ' Step 3: Testsuite uitvoeren en permissies valideren' + C_RESET, WMain);
      end;
      Writeln(C_CYAN + '│' + C_RESET + LeftCol + C_CYAN + '│' + C_RESET + RightCol + C_CYAN + '│' + C_RESET);
      Inc(RowsDrawn);

      LeftCol := PadRightVis('  │   ' + C_GRAY + Sessions[I].DateStr + '  ' + Sessions[I].TimeStr + C_RESET, WSidebar);
      RightCol := PadRightVis('', WMain);
      Writeln(C_CYAN + '│' + C_RESET + LeftCol + C_CYAN + '│' + C_RESET + RightCol + C_CYAN + '│' + C_RESET);
      Inc(RowsDrawn);
    end;

    // Opvullen hoogte
    FillLines := TermHeight - RowsDrawn - 5;
    for I := 1 to FillLines do
    begin
      Writeln(C_CYAN + '│' + StringOfChar(' ', WSidebar) + '│' + StringOfChar(' ', WMain) + '│' + C_RESET);
    end;

    Writeln(C_CYAN + '├─' + StringOfChar('─', WSidebar - 1) + '┴─' + StringOfChar('─', WMain - 1) + '┤' + C_RESET);
  end
  else
  begin
    // COLLAPSED MODE (Ingeschakeld via Tab)
    WMain := TermWidth - 2;
    InnerW := WMain - 4; // Binnenbreedte voor Cards

    // Bovenrand exact uitgelijnd op TermWidth
    DashCount := WMain - VisibleLength(HeaderTagLeft) - VisibleLength(HeaderTagRight) - 2;
    if DashCount < 0 then DashCount := 0;

    Writeln(C_CYAN + '┌─' + C_WHITE + HeaderTagLeft + C_CYAN + StringOfChar('─', DashCount) +
            C_BOLD + C_WHITE + HeaderTagRight + C_RESET + C_CYAN + '─┐' + C_RESET);
    Inc(RowsDrawn);

    // AI Workspace Banner
    Writeln(C_CYAN + '│' + C_RESET + PadRightVis(' ' + C_BOLD + C_LIGHT_BLUE + '🤖 AI ASSISTANT WORKSPACE' + C_GRAY + ' (Sidebar verborgen)', WMain) + C_CYAN + '│' + C_RESET);
    Writeln(C_CYAN + '├─' + StringOfChar('─', WMain - 1) + '┤' + C_RESET);
    Inc(RowsDrawn, 2);

    // Ruimte boven Thinking Card
    Writeln(C_CYAN + '│' + StringOfChar(' ', WMain) + '│' + C_RESET);
    Inc(RowsDrawn);

    // THINKING CARD
    Writeln(C_CYAN + '│  ' + C_DARK_BLUE + '┌─ ' + C_YELLOW + '💭 THINKING PROCESS ' + C_GRAY + '(Ctrl+T to toggle) ' + C_DARK_BLUE + StringOfChar('─', InnerW - 41) + '┐' + C_CYAN + '  │' + C_RESET);
    if ThinkCollapsed then
      Writeln(C_CYAN + '│  ' + C_DARK_BLUE + '│ ' + C_GRAY + PadRightVis('> Analyseren van AST nodes en geheugenallocaties in compiler.pas... (gecollapse)', InnerW - 4) + C_DARK_BLUE + ' │' + C_CYAN + '  │' + C_RESET)
    else
      Writeln(C_CYAN + '│  ' + C_DARK_BLUE + '│ ' + C_WHITE + PadRightVis('> Analyseren AST nodes... Controleren op geheugenallocaties in compiler.pas...', InnerW - 4) + C_DARK_BLUE + ' │' + C_CYAN + '  │' + C_RESET);
    Writeln(C_CYAN + '│  ' + C_DARK_BLUE + '└' + StringOfChar('─', InnerW - 2) + '┘' + C_CYAN + '  │' + C_RESET);
    Inc(RowsDrawn, 3);

    // Tussenruimte
    Writeln(C_CYAN + '│' + StringOfChar(' ', WMain) + '│' + C_RESET);
    Writeln(C_CYAN + '│  ' + C_WHITE + PadRightVis('Hier is de voorgestelde logica voor de compiler module en het bijbehorende actieplan:', WMain - 4) + '  │' + C_RESET);
    Writeln(C_CYAN + '│' + StringOfChar(' ', WMain) + '│' + C_RESET);
    Inc(RowsDrawn, 3);

    // WORK PLAN CARD
    Writeln(C_CYAN + '│  ' + C_DARK_BLUE + '┌─ ' + C_BOLD + C_GREEN + 'INLINE WORK PLAN ' + C_DARK_BLUE + StringOfChar('─', InnerW - 21) + '┐' + C_CYAN + '  │' + C_RESET);
    Writeln(C_CYAN + '│  ' + C_DARK_BLUE + '│ ' + C_GREEN + '[X]' + C_WHITE + PadRightVis(' Step 1: Lexer uitbreiden met nieuwe tokens', InnerW - 8) + C_DARK_BLUE + ' │' + C_CYAN + '  │' + C_RESET);
    Writeln(C_CYAN + '│  ' + C_DARK_BLUE + '│ ' + C_GRAY + '[ ]' + C_WHITE + PadRightVis(' Step 2: Code generator aanpassen voor AST nodes', InnerW - 8) + C_DARK_BLUE + ' │' + C_CYAN + '  │' + C_RESET);
    Writeln(C_CYAN + '│  ' + C_DARK_BLUE + '│ ' + C_GRAY + '[ ]' + C_WHITE + PadRightVis(' Step 3: Testsuite uitvoeren en permissies valideren', InnerW - 8) + C_DARK_BLUE + ' │' + C_CYAN + '  │' + C_RESET);
    Writeln(C_CYAN + '│  ' + C_DARK_BLUE + '└' + StringOfChar('─', InnerW - 2) + '┘' + C_CYAN + '  │' + C_RESET);
    Inc(RowsDrawn, 5);

    // Dynamische opvulling onder de kaarten
    FillLines := TermHeight - RowsDrawn - 5;
    for I := 1 to FillLines do
    begin
      Writeln(C_CYAN + '│' + StringOfChar(' ', WMain) + '│' + C_RESET);
    end;

    Writeln(C_CYAN + '├─' + StringOfChar('─', WMain - 1) + '┤' + C_RESET);
  end;

  // Chat bar onderaan
  Writeln(C_CYAN + '│' + C_RESET + PadRightVis(' ' + C_BOLD + C_WHITE + 'CHAT BAR ' + C_GRAY + '(Typ bijv. /refactor, [Esc] Stop)' + C_RESET, TermWidth - 2) + C_CYAN + '│' + C_RESET);
  Writeln(C_CYAN + '│' + C_RESET + PadRightVis(' ' + C_LIGHT_BLUE + '> ' + C_WHITE + CurrentInput, TermWidth - 2) + C_CYAN + '│' + C_RESET);
  Write(C_CYAN + '└─' + StringOfChar('─', TermWidth - 3) + '┘' + C_RESET);
end;

procedure RunEventLoop;
var
  Key: Char;
  HIn: THandle;
  Rec: INPUT_RECORD;
  ReadCount: DWORD;
begin
  HIn := GetStdHandle(STD_INPUT_HANDLE);
  while True do
  begin
    DrawScreen;

    ReadConsoleInput(HIn, Rec, 1, ReadCount);
    if (ReadCount > 0) and (Rec.EventType = KEY_EVENT) and Rec.Event.KeyEvent.bKeyDown then
    begin
      Key := Rec.Event.KeyEvent.UnicodeChar;

      case Rec.Event.KeyEvent.wVirtualKeyCode of
        VK_ESCAPE: Break;
        VK_TAB: SidebarExpanded := not SidebarExpanded;
        VK_RETURN: CurrentInput := '';
        VK_BACK:
          begin
            if Length(CurrentInput) > 0 then
              Delete(CurrentInput, Length(CurrentInput), 1);
          end;
        else
          if (Ord(Key) = 20) then // Ctrl+T
            ThinkCollapsed := not ThinkCollapsed
          else if Ord(Key) >= 32 then
            CurrentInput := CurrentInput + Key;
      end;
    end;
  end;
end;

begin
  try
    EnableVirtualTerminalProcessing;
    InitData;
    RunEventLoop;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
