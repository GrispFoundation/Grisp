program GrispTUI;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes;

const
  // Windows Console Virtual Terminal (ANSI) Sequences
  C_RESET       = #27'[0m';
  C_BOLD        = #27'[1m';
  C_CYAN        = #27'[38;2;0;240;255m';
  C_LIGHT_BLUE  = #27'[38;2;56;189;248m';
  C_DARK_BLUE   = #27'[38;2;2;132;199m';
  C_WHITE       = #27'[38;2;248;250;252m';
  C_GRAY        = #27'[38;2;100;116;139m';
  C_GREEN       = #27'[38;2;74;222;128m';
  C_BG_DARK     = #27'[48;2;10;14;23m';

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

procedure DrawScreen;
var
  I: Integer;
  PermStr: string;
begin
  // Clear Screen & Reset Cursor
  Write(#27'[2J'#27'[H');

  // Header
  Writeln(C_CYAN + '╔═══' + C_WHITE + '[Tab] Toggle Sidebar' + C_CYAN + ' ═════════════════════╦═══ ' + C_BOLD + 'GRISP OS TERMINAL UI' + C_RESET + C_CYAN + ' ═════════════════════════════════════╗' + C_RESET);

  // Body Rows
  if SidebarExpanded then
  begin
    // Sidebar Top
    Writeln(C_CYAN + '║ ' + C_BOLD + C_WHITE + '🗁 PROJECT EXPLORER' + C_RESET + '                     ' + C_CYAN + '║ ' + C_BOLD + C_LIGHT_BLUE + '🤖 AI RESPONSE' + C_RESET);

    // File Items & Think Header
    for I := 0 to High(ProjectFiles) do
    begin
      PermStr := FormatPermissions(ProjectFiles[I].Permissions);
      if ProjectFiles[I].IsDirectory then
        Write(C_CYAN + '║ ' + C_LIGHT_BLUE + '├──▼ ' + ProjectFiles[I].Name + StringOfChar(' ', 22 - Length(ProjectFiles[I].Name)))
      else
        Write(C_CYAN + '║ ' + C_WHITE + '│   ├── ' + ProjectFiles[I].Name + C_GRAY + StringOfChar(' ', 14 - Length(ProjectFiles[I].Name)) + C_LIGHT_BLUE + PermStr + ' ');

      // Render Chat Content alongside Explorer
      case I of
        0: Writeln(C_CYAN + '║ ' + C_DARK_BLUE + '┌─► THINKING PROCESS ' + C_WHITE + '[Ctrl+T to toggle] ' + C_DARK_BLUE + '────────────────────────┐' + C_RESET);
        1: if ThinkCollapsed then
             Writeln(C_CYAN + '║ ' + C_DARK_BLUE + '│ ' + C_GRAY + '> Analyseren AST nodes... (gecollapse)                      ' + C_DARK_BLUE + '│' + C_RESET)
           else
             Writeln(C_CYAN + '║ ' + C_DARK_BLUE + '│ ' + C_WHITE + '> Analyseren van AST nodes... Controleren geheugenallocaties' + C_DARK_BLUE + '│' + C_RESET);
        2: Writeln(C_CYAN + '║ ' + C_DARK_BLUE + '└────────────────────────────────────────────────────────┘' + C_RESET);
        3: Writeln(C_CYAN + '║ ' + C_WHITE + 'Hier is de voorgestelde logica voor de compiler module:' + C_RESET);
        4: Writeln(C_CYAN + '║ ' + C_RESET);
      end;
    end;

    // Session History Header
    Writeln(C_CYAN + '║                                         ║                                                            ' + C_CYAN + '║');
    Writeln(C_CYAN + '║ ' + C_BOLD + C_WHITE + '🗎 SESSIE GESCHIEDENIS                  ' + C_CYAN + '║ ' + C_DARK_BLUE + '┌─ INLINE WORK PLAN ─────────────────────────────────────┐' + C_RESET);

    // Sessions & Work Plan Items
    for I := 0 to High(Sessions) do
    begin
      Write(C_CYAN + '║ ' + C_WHITE + '├── ' + Sessions[I].Subject + StringOfChar(' ', 28 - Length(Sessions[I].Subject)));

      case I of
        0: Writeln(C_CYAN + '║ ' + C_DARK_BLUE + '│ ' + C_GREEN + '[X] Step 1: Lexer uitbreiden met nieuwe tokens          ' + C_DARK_BLUE + '│' + C_RESET);
        1: Writeln(C_CYAN + '║ ' + C_DARK_BLUE + '│ ' + C_WHITE + '[ ] Step 2: Code generator aanpassen voor AST nodes    ' + C_DARK_BLUE + '│' + C_RESET);
        2: Writeln(C_CYAN + '║ ' + C_DARK_BLUE + '│ ' + C_WHITE + '[ ] Step 3: Testsuite uitvoeren en permissies valideren ' + C_DARK_BLUE + '│' + C_RESET);
      end;

      Writeln(C_CYAN + '║ ' + C_GRAY + '│   ' + Sessions[I].DateStr + ' │ ' + Sessions[I].TimeStr + '                  ' + C_CYAN + '║ ' + C_DARK_BLUE + '└────────────────────────────────────────────────────────┘' + C_RESET);
    end;
  end
  else
  begin
    // Maximized View (Sidebar Collapsed)
    Writeln(C_CYAN + '║ ' + C_BOLD + C_LIGHT_BLUE + '🤖 AI RESPONSE (Sidebar Verborgen)' + C_RESET);
    Writeln(C_CYAN + '║ ' + C_DARK_BLUE + '┌─► THINKING PROCESS [Ctrl+T to toggle] ────────────────────────────────────────────────────────┐' + C_RESET);
    if ThinkCollapsed then
      Writeln(C_CYAN + '║ ' + C_DARK_BLUE + '│ ' + C_GRAY + '> Analyseren AST nodes... (gecollapse)                                                      ' + C_DARK_BLUE + '│' + C_RESET)
    else
      Writeln(C_CYAN + '║ ' + C_DARK_BLUE + '│ ' + C_WHITE + '> Analyseren van AST nodes... Controleren van geheugenallocaties in compiler.pas...        ' + C_DARK_BLUE + '│' + C_RESET);
    Writeln(C_CYAN + '║ ' + C_DARK_BLUE + '└───────────────────────────────────────────────────────────────────────────────────────────────┘' + C_RESET);
    Writeln(C_CYAN + '║ ' + C_WHITE + 'Hier is de voorgestelde logica voor de compiler module en het actieplan voor vandaag:' + C_RESET);
    Writeln(C_CYAN + '║ ' + C_RESET);
    Writeln(C_CYAN + '║ ' + C_DARK_BLUE + '┌─ INLINE WORK PLAN ────────────────────────────────────────────────────────────────────────────┐' + C_RESET);
    Writeln(C_CYAN + '║ ' + C_DARK_BLUE + '│ ' + C_GREEN + '[X] Step 1: Lexer uitbreiden met nieuwe tokens                                                  ' + C_DARK_BLUE + '│' + C_RESET);
    Writeln(C_CYAN + '║ ' + C_DARK_BLUE + '│ ' + C_WHITE + '[ ] Step 2: Code generator aanpassen voor AST nodes                                            ' + C_DARK_BLUE + '│' + C_RESET);
    Writeln(C_CYAN + '║ ' + C_DARK_BLUE + '│ ' + C_WHITE + '[ ] Step 3: Testsuite uitvoeren en permissies valideren                                         ' + C_DARK_BLUE + '│' + C_RESET);
    Writeln(C_CYAN + '║ ' + C_DARK_BLUE + '└───────────────────────────────────────────────────────────────────────────────────────────────┘' + C_RESET);
  end;

  // Bottom Divider & Chat Input Bar
  Writeln(C_CYAN + '╠═════════════════════════════════════════╩═════════════════════════════════════════════════════════════╣' + C_RESET);
  Writeln(C_CYAN + '║ ' + C_BOLD + C_WHITE + '💬 CHAT BAR ' + C_GRAY + '(Typ commando bijv. /refactor, [Esc] Stop)' + C_RESET);
  Write(C_CYAN + '║ ' + C_LIGHT_BLUE + '> ' + C_WHITE + CurrentInput);
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
        VK_ESCAPE: Break; // Quit
        VK_TAB:
          begin
            SidebarExpanded := not SidebarExpanded;
          end;
        VK_RETURN:
          begin
            CurrentInput := ''; // Process input
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
