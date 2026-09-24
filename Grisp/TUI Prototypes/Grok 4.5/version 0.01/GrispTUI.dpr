program GrispTUI;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows;

const
  // Schermgrootte (pas aan naar wens)
  SCREEN_W = 100;
  SCREEN_H = 35;

  // Kleuren (Windows console)
  COL_RESET   = 7;
  COL_TITLE   = 11;  // licht cyaan
  COL_ACCENT  = 14;  // geel
  COL_DIM     = 8;
  COL_TEXT    = 7;
  COL_GREEN   = 10;

type
  TApp = class
  private
    FChat: TStringList;
    FInput: string;
    FRunning: Boolean;
    FThinkVisible: Boolean;
    FSessionsVisible: Boolean;
    FExplorerVisible: Boolean;

    procedure SetColor(AColor: Word);
    procedure GotoXY(X, Y: Integer);
    procedure ClearScreen;
    procedure DrawFrame;
    procedure DrawSessions;
    procedure DrawExplorer;
    procedure DrawThink;
    procedure DrawChat;
    procedure DrawInput;
    procedure DrawAll;
    procedure HandleInput;
    procedure AddMessage(const AWho, AText: string);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Run;
  end;

constructor TApp.Create;
begin
  inherited;
  FChat := TStringList.Create;
  FInput := '';
  FRunning := True;
  FThinkVisible := True;
  FSessionsVisible := True;
  FExplorerVisible := True;

  AddMessage('GRISP', 'Hello Alex, how can I help you with GRISP today?');
  AddMessage('You', 'Create a plan for integrating the VFS layer.');
  AddMessage('GRISP', 'Understood. Reviewing project structure and VFS layer...');
end;

destructor TApp.Destroy;
begin
  FChat.Free;
  inherited;
end;

procedure TApp.SetColor(AColor: Word);
begin
  SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), AColor);
end;

procedure TApp.GotoXY(X, Y: Integer);
var
  Coord: TCoord;
begin
  Coord.X := X - 1;
  Coord.Y := Y - 1;
  SetConsoleCursorPosition(GetStdHandle(STD_OUTPUT_HANDLE), Coord);
end;

procedure TApp.ClearScreen;
var
  Coord: TCoord;
  Written: DWORD;
  Info: TConsoleScreenBufferInfo;
  Handle: THandle;
begin
  Handle := GetStdHandle(STD_OUTPUT_HANDLE);
  GetConsoleScreenBufferInfo(Handle, Info);
  Coord.X := 0;
  Coord.Y := 0;
  FillConsoleOutputCharacter(Handle, ' ', Info.dwSize.X * Info.dwSize.Y, Coord, Written);
  FillConsoleOutputAttribute(Handle, Info.wAttributes, Info.dwSize.X * Info.dwSize.Y, Coord, Written);
  SetConsoleCursorPosition(Handle, Coord);
end;

procedure TApp.AddMessage(const AWho, AText: string);
begin
  FChat.Add(AWho + ': ' + AText);
end;

procedure TApp.DrawFrame;
begin
  SetColor(COL_TITLE);
  GotoXY(1, 1);
  Write('╔' + StringOfChar('═', SCREEN_W - 2) + '╗');
  GotoXY(1, 2);
  Write('║  GRISP OS  -  Text User Interface' + StringOfChar(' ', SCREEN_W - 38) + '║');
  GotoXY(1, 3);
  Write('╠' + StringOfChar('═', 24) + '╤' + StringOfChar('═', SCREEN_W - 27) + '╣');
end;

procedure TApp.DrawSessions;
var
  i: Integer;
begin
  if not FSessionsVisible then Exit;

  SetColor(COL_ACCENT);
  GotoXY(3, 4);
  Write('SESSIONS');

  SetColor(COL_TEXT);
  GotoXY(3, 5);  Write('● Architecture Analysis');
  GotoXY(3, 6);  Write('  Today 14:32');
  GotoXY(3, 7);  Write('○ Project Setup');
  GotoXY(3, 8);  Write('  Yesterday');
  GotoXY(3, 9);  Write('○ Dependency Review');
  GotoXY(3,10);  Write('+ New Session');
end;

procedure TApp.DrawExplorer;
begin
  if not FExplorerVisible then Exit;

  SetColor(COL_ACCENT);
  GotoXY(3, 12);
  Write('EXPLORER');

  SetColor(COL_TEXT);
  GotoXY(3, 13); Write('📁 project-grisp   R W X');
  GotoXY(3, 14); Write('  ├─ src           R W X');
  GotoXY(3, 15); Write('  │  ├─ vfs.c      R - X');
  GotoXY(3, 16); Write('  │  └─ init.c     R - X');
  GotoXY(3, 17); Write('  ├─ core          R W X');
  GotoXY(3, 18); Write('  └─ docs          R - -');
end;

procedure TApp.DrawThink;
begin
  if not FThinkVisible then Exit;

  SetColor(COL_DIM);
  GotoXY(28, 4);
  Write('THINK: Analyzing project structure... checking VFS layer...');
end;

procedure TApp.DrawChat;
var
  i, Line: Integer;
  Start: Integer;
begin
  SetColor(COL_TEXT);

  // Toon de laatste regels van de chat
  Start := FChat.Count - 12;
  if Start < 0 then Start := 0;

  Line := 6;
  for i := Start to FChat.Count - 1 do
  begin
    GotoXY(28, Line);
    Write(StringOfChar(' ', SCREEN_W - 30)); // clear line
    GotoXY(28, Line);
    if Pos('You:', FChat[i]) = 1 then
      SetColor(COL_ACCENT)
    else
      SetColor(COL_TEXT);
    Write(Copy(FChat[i], 1, SCREEN_W - 32));
    Inc(Line);
    if Line > SCREEN_H - 6 then Break;
  end;

  // Work Plan box
  SetColor(COL_GREEN);
  GotoXY(28, SCREEN_H - 12);
  Write('┌─ Proposed Work Plan ─────────────────────────────────────┐');
  SetColor(COL_TEXT);
  GotoXY(28, SCREEN_H - 11); Write('│ ☐ 1. Analyze VFS Layer                       Pending    │');
  GotoXY(28, SCREEN_H - 10); Write('│ ☐ 2. Define Integration Points               Pending    │');
  GotoXY(28, SCREEN_H -  9); Write('│ ☐ 3. Design Abstraction Layer                Pending    │');
  GotoXY(28, SCREEN_H -  8); Write('│ ☐ 4. Implement & Refactor                    Pending    │');
  GotoXY(28, SCREEN_H -  7); Write('│ ☐ 5. Validate & Test                         Pending    │');
  GotoXY(28, SCREEN_H -  6); Write('│ Effort: 2-3 days                             Progress   │');
  SetColor(COL_GREEN);
  GotoXY(28, SCREEN_H -  5); Write('└─────────────────────────────────────────────────────────┘');
end;

procedure TApp.DrawInput;
begin
  SetColor(COL_TITLE);
  GotoXY(1, SCREEN_H - 2);
  Write('╠' + StringOfChar('═', SCREEN_W - 2) + '╣');

  GotoXY(1, SCREEN_H - 1);
  Write('║ > ');
  SetColor(COL_TEXT);
  Write(FInput);
  Write(StringOfChar(' ', SCREEN_W - Length(FInput) - 6));
  SetColor(COL_TITLE);
  Write('║');

  GotoXY(1, SCREEN_H);
  Write('╚' + StringOfChar('═', SCREEN_W - 2) + '╝');
end;

procedure TApp.DrawAll;
begin
  ClearScreen;
  DrawFrame;
  DrawSessions;
  DrawExplorer;
  DrawThink;
  DrawChat;
  DrawInput;
  // Cursor op de invoerregel
  GotoXY(5 + Length(FInput), SCREEN_H - 1);
end;

procedure TApp.HandleInput;
var
  Key: Char;
  KeyEvent: TInputRecord;
  Read: DWORD;
begin
  while FRunning do
  begin
    DrawAll;

    // Wacht op toets
    ReadConsoleInput(GetStdHandle(STD_INPUT_HANDLE), KeyEvent, 1, Read);

    if KeyEvent.EventType = KEY_EVENT then
    begin
      if KeyEvent.Event.KeyEvent.bKeyDown then
      begin
        case KeyEvent.Event.KeyEvent.wVirtualKeyCode of
          VK_ESCAPE:
            FRunning := False;

          VK_RETURN:
            begin
              if Trim(FInput) <> '' then
              begin
                AddMessage('You', FInput);
                AddMessage('GRISP', 'Processing: "' + FInput + '" ...');
                FInput := '';
              end;
            end;

          VK_BACK:
            begin
              if Length(FInput) > 0 then
                Delete(FInput, Length(FInput), 1);
            end;

          VK_F1: FSessionsVisible := not FSessionsVisible;
          VK_F2: FExplorerVisible := not FExplorerVisible;
          VK_F3: FThinkVisible := not FThinkVisible;

        else
          if KeyEvent.Event.KeyEvent.AsciiChar >= ' ' then
            FInput := FInput + KeyEvent.Event.KeyEvent.AsciiChar;
        end;
      end;
    end;
  end;
end;

procedure TApp.Run;
begin
  // Consolesettings
  SetConsoleTitle('GRISP OS - TUI');
  // Optioneel: schermbuffer groter maken
  HandleInput;
  ClearScreen;
  SetColor(COL_RESET);
  WriteLn;
  WriteLn('GRISP TUI afgesloten.');
end;

var
  App: TApp;

begin
  try
    App := TApp.Create;
    try
      App.Run;
    finally
      App.Free;
    end;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
