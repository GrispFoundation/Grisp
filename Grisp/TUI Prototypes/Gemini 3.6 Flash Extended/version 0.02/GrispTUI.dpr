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
  C_DIM         = #27'[2m';
  C_CYAN        = #27'[38;2;0;240;255m';
  C_LIGHT_BLUE  = #27'[38;2;56;189;248m';
  C_DARK_BLUE   = #27'[38;2;2;132;199m';
  C_WHITE       = #27'[38;2;248;250;252m';
  C_GRAY        = #27'[38;2;100;116;139m';
  C_GREEN       = #27'[38;2;74;222;128m';
  C_YELLOW      = #27'[38;2;250;204;21m';

  // Fixed Column Widths (Inner spaces)
  W_SIDEBAR = 40;
  W_MAIN    = 72;

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

// Berekent de werkelijke VISUELE breedte op het scherm (stript ANSI codes)
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

// Vult een string aan met spaties op basis van de ZICHTBARE lengte op het scherm
function PadRightVis(const S: string; TargetWidth: Integer): string;
var
  VisLen: Integer;
begin
  VisLen := VisibleLength(S);
  if VisLen < TargetWidth then
    Result := S + StringOfChar(' ', TargetWidth - VisLen)
  else
    Result := S;
end;

procedure DrawScreen;
var
  I: Integer;
  LeftCol, RightCol: string;
  PermStr: string;
begin
  // Clear Screen & Reset Cursor
  Write(#27'[2J'#27'[H');

  if SidebarExpanded then
  begin
    // Top Header Border (40 + 1 + 72 = 113 inner spaces)
    Writeln(C_CYAN + '┌─── ' + C_WHITE + '[Tab] Toggle Sidebar' + C_CYAN + ' ' + StringOfChar('─', 14) + '┬─── ' + C_BOLD + C_WHITE + 'GRISP OS TERMINAL UI' + C_RESET + C_CYAN + ' ' + StringOfChar('─', 46) + '┐' + C_RESET);

    // Header Row
    LeftCol  := PadRightVis(' ' + C_BOLD + C_WHITE + 'PROJECT EXPLORER' + C_RESET, W_SIDEBAR);
    RightCol := PadRightVis(' ' + C_BOLD + C_LIGHT_BLUE + 'AI ASSISTANT WORKSPACE' + C_RESET, W_MAIN);
    Writeln(C_CYAN + '│' + C_RESET + LeftCol + C_CYAN + '│' + C_RESET + RightCol + C_CYAN + '│' + C_RESET);

    // Section Divider
    Writeln(C_CYAN + '├' + StringOfChar('─', W_SIDEBAR) + '┼' + StringOfChar('─', W_MAIN) + '┤' + C_RESET);

    // Rows 1..5: Project Explorer vs AI Response & Thinking
    for I := 0 to 4 do
    begin
      // Left Column
      PermStr := FormatPermissions(ProjectFiles[I].Permissions);
      if ProjectFiles[I].IsDirectory then
        LeftCol := PadRightVis('  ' + C_LIGHT_BLUE + '▼ ' + ProjectFiles[I].Name + C_RESET, W_SIDEBAR)
      else
        LeftCol := PadRightVis('    ├── ' + C_WHITE + PadRightVis(ProjectFiles[I].Name, 18) + C_GRAY + PermStr + C_RESET, W_SIDEBAR);

      // Right Column
      case I of
        0: RightCol := PadRightVis(' ' + C_YELLOW + '💭 THINKING PROCESS ' + C_GRAY + '(Ctrl+T to toggle)' + C_RESET, W_MAIN);
        1: if ThinkCollapsed then
             RightCol := PadRightVis('   ' + C_DARK_BLUE + '│ ' + C_GRAY + '> Analyseren van AST nodes en geheugenallocaties... (gecollapse)' + C_RESET, W_MAIN)
           else
             RightCol := PadRightVis('   ' + C_DARK_BLUE + '│ ' + C_WHITE + '> Analyseren AST nodes... Controleren op memory leaks in compiler.pas' + C_RESET, W_MAIN);
        2: RightCol := PadRightVis('', W_MAIN);
        3: RightCol := PadRightVis(' ' + C_WHITE + 'Hier is de voorgestelde logica voor de compiler module:' + C_RESET, W_MAIN);
        4: RightCol := PadRightVis('', W_MAIN);
      end;

      Writeln(C_CYAN + '│' + C_RESET + LeftCol + C_CYAN + '│' + C_RESET + RightCol + C_CYAN + '│' + C_RESET);
    end;

    // Divider
    Writeln(C_CYAN + '│' + StringOfChar(' ', W_SIDEBAR) + '│' + StringOfChar(' ', W_MAIN) + '│' + C_RESET);

    // Session History Header & Work Plan Header
    LeftCol  := PadRightVis(' ' + C_BOLD + C_WHITE + 'SESSIE GESCHIEDENIS' + C_RESET, W_SIDEBAR);
    RightCol := PadRightVis(' ' + C_BOLD + C_GREEN + 'INLINE WORK PLAN' + C_RESET, W_MAIN);
    Writeln(C_CYAN + '│' + C_RESET + LeftCol + C_CYAN + '│' + C_RESET + RightCol + C_CYAN + '│' + C_RESET);

    // Rows 6..11: Sessions & Work Plan Steps
    for I := 0 to 2 do
    begin
      // Subject Row
      LeftCol := PadRightVis('  ├── ' + C_WHITE + Sessions[I].Subject + C_RESET, W_SIDEBAR);
      case I of
        0: RightCol := PadRightVis('   ' + C_GREEN + '[X]' + C_WHITE + ' Step 1: Lexer uitbreiden met nieuwe tokens' + C_RESET, W_MAIN);
        1: RightCol := PadRightVis('   ' + C_GRAY + '[ ]' + C_WHITE + ' Step 2: Code generator aanpassen voor AST nodes' + C_RESET, W_MAIN);
        2: RightCol := PadRightVis('   ' + C_GRAY + '[ ]' + C_WHITE + ' Step 3: Testsuite uitvoeren en permissies valideren' + C_RESET, W_MAIN);
      end;
      Writeln(C_CYAN + '│' + C_RESET + LeftCol + C_CYAN + '│' + C_RESET + RightCol + C_CYAN + '│' + C_RESET);

      // Date/Time Row
      LeftCol := PadRightVis('  │   ' + C_GRAY + Sessions[I].DateStr + '  ' + Sessions[I].TimeStr + C_RESET, W_SIDEBAR);
      RightCol := PadRightVis('', W_MAIN);
      Writeln(C_CYAN + '│' + C_RESET + LeftCol + C_CYAN + '│' + C_RESET + RightCol + C_CYAN + '│' + C_RESET);
    end;

    // Bottom Box Divider
    Writeln(C_CYAN + '├───' + StringOfChar('─', W_SIDEBAR - 3) + '┴───' + StringOfChar('─', W_MAIN - 3) + '┤' + C_RESET);
  end
  else
  begin
    // Collapsed Mode (Full Width = 113 spaces)
    Writeln(C_CYAN + '┌─── ' + C_WHITE + '[Tab] Toggle Sidebar' + C_CYAN + ' ' + StringOfChar('─', 88) + '┐' + C_RESET);
    Writeln(C_CYAN + '│' + C_RESET + PadRightVis(' ' + C_BOLD + C_LIGHT_BLUE + 'AI ASSISTANT WORKSPACE (Sidebar Verborgen)' + C_RESET, 113) + C_CYAN + '│' + C_RESET);
    Writeln(C_CYAN + '├' + StringOfChar('─', 113) + '┤' + C_RESET);
    Writeln(C_CYAN + '│' + C_RESET + PadRightVis(' ' + C_YELLOW + '💭 THINKING PROCESS ' + C_GRAY + '(Ctrl+T to toggle)' + C_RESET, 113) + C_CYAN + '│' + C_RESET);
    if ThinkCollapsed then
      Writeln(C_CYAN + '│' + C_RESET + PadRightVis('   ' + C_DARK_BLUE + '│ ' + C_GRAY + '> Analyseren AST nodes... (gecollapse)' + C_RESET, 113) + C_CYAN + '│' + C_RESET)
    else
      Writeln(C_CYAN + '│' + C_RESET + PadRightVis('   ' + C_DARK_BLUE + '│ ' + C_WHITE + '> Analyseren van AST nodes... Controleren van geheugenallocaties in compiler.pas...' + C_RESET, 113) + C_CYAN + '│' + C_RESET);
    Writeln(C_CYAN + '│' + C_RESET + PadRightVis('', 113) + C_CYAN + '│' + C_RESET);
    Writeln(C_CYAN + '│' + C_RESET + PadRightVis(' ' + C_WHITE + 'Hier is de voorgestelde logica voor de compiler module en het actieplan voor vandaag:' + C_RESET, 113) + C_CYAN + '│' + C_RESET);
    Writeln(C_CYAN + '│' + C_RESET + PadRightVis('', 113) + C_CYAN + '│' + C_RESET);
    Writeln(C_CYAN + '│' + C_RESET + PadRightVis(' ' + C_BOLD + C_GREEN + 'INLINE WORK PLAN' + C_RESET, 113) + C_CYAN + '│' + C_RESET);
    Writeln(C_CYAN + '│' + C_RESET + PadRightVis('   ' + C_GREEN + '[X]' + C_WHITE + ' Step 1: Lexer uitbreiden met nieuwe tokens' + C_RESET, 113) + C_CYAN + '│' + C_RESET);
    Writeln(C_CYAN + '│' + C_RESET + PadRightVis('   ' + C_GRAY + '[ ]' + C_WHITE + ' Step 2: Code generator aanpassen voor AST nodes' + C_RESET, 113) + C_CYAN + '│' + C_RESET);
    Writeln(C_CYAN + '│' + C_RESET + PadRightVis('   ' + C_GRAY + '[ ]' + C_WHITE + ' Step 3: Testsuite uitvoeren en permissies valideren' + C_RESET, 113) + C_CYAN + '│' + C_RESET);
    Writeln(C_CYAN + '├' + StringOfChar('─', 113) + '┤' + C_RESET);
  end;

  // Bottom Interactive Chat Bar
  Writeln(C_CYAN + '│' + C_RESET + PadRightVis(' ' + C_BOLD + C_WHITE + 'CHAT BAR ' + C_GRAY + '(Typ bijv. /refactor, [Esc] Stop)' + C_RESET, 113) + C_CYAN + '│' + C_RESET);
  Writeln(C_CYAN + '│' + C_RESET + PadRightVis(' ' + C_LIGHT_BLUE + '> ' + C_WHITE + CurrentInput, 113) + C_CYAN + '│' + C_RESET);
  Writeln(C_CYAN + '└' + StringOfChar('─', 113) + '┘' + C_RESET);
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
        VK_TAB:
          begin
            SidebarExpanded := not SidebarExpanded;
          end;
        VK_RETURN:
          begin
            CurrentInput := '';
          end;
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
