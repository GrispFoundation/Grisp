program GrispTUI;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows;

type
  TApp = class
  private
    FChat: TStringList;
    FInput: string;
    FRunning: Boolean;
    FThinkVisible: Boolean;
    FSessionsVisible: Boolean;
    FExplorerVisible: Boolean;
    FWidth, FHeight: Integer;

    procedure GetConsoleSize;
    procedure SetColor(AColor: Word);
    procedure GotoXY(X, Y: Integer);
    procedure ClearScreen;
    procedure ClrLine(Y: Integer);
    procedure DrawAll;
    procedure DrawHeader;
    procedure DrawLeftPanels;
    procedure DrawMain;
    procedure DrawInputBar;
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

procedure TApp.GetConsoleSize;
var
  Info: TConsoleScreenBufferInfo;
begin
  GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), Info);
  FWidth  := Info.dwSize.X;
  FHeight := Info.srWindow.Bottom - Info.srWindow.Top + 1;

  if FWidth < 80 then FWidth := 80;
  if FHeight < 25 then FHeight := 25;
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
  FillConsoleOutputAttribute(Handle, 7, Info.dwSize.X * Info.dwSize.Y, Coord, Written);
  SetConsoleCursorPosition(Handle, Coord);
end;

procedure TApp.ClrLine(Y: Integer);
begin
  GotoXY(1, Y);
  Write(StringOfChar(' ', FWidth));
end;

procedure TApp.AddMessage(const AWho, AText: string);
begin
  FChat.Add(AWho + ': ' + AText);
end;

procedure TApp.DrawHeader;
begin
  SetColor(11); // cyan
  GotoXY(1, 1);
  Write(' ' + StringOfChar('=', FWidth - 2));
  GotoXY(1, 2);
  Write('  GRISP OS  -  Text User Interface');
  GotoXY(FWidth - 25, 2);
  Write('[F1]Ses [F2]Exp [F3]Think');
  GotoXY(1, 3);
  Write(' ' + StringOfChar('=', FWidth - 2));
end;

procedure TApp.DrawLeftPanels;
var
  Y: Integer;
begin
  Y := 5;

  // SESSIONS
  if FSessionsVisible then
  begin
    SetColor(14); // yellow
    GotoXY(2, Y); Write('SESSIONS');
    SetColor(7);
    Inc(Y);
    GotoXY(2, Y); Write('* Architecture Analysis'); Inc(Y);
    GotoXY(4, Y); Write('Today 14:32'); Inc(Y);
    GotoXY(2, Y); Write('  Project Setup'); Inc(Y);
    GotoXY(4, Y); Write('Yesterday'); Inc(Y);
    GotoXY(2, Y); Write('  Dependency Review'); Inc(Y);
    GotoXY(2, Y); Write('+ New Session');
    Inc(Y, 2);
  end
  else
  begin
    SetColor(8);
    GotoXY(2, Y); Write('[SESSIONS hidden - F1]');
    Inc(Y, 2);
  end;

  // EXPLORER
  if FExplorerVisible then
  begin
    SetColor(14);
    GotoXY(2, Y); Write('EXPLORER');
    SetColor(7);
    Inc(Y);
    GotoXY(2, Y); Write('project-grisp     R W X'); Inc(Y);
    GotoXY(2, Y); Write('  +- src          R W X'); Inc(Y);
    GotoXY(2, Y); Write('  |  +- vfs.c     R - X'); Inc(Y);
    GotoXY(2, Y); Write('  |  +- init.c    R - X'); Inc(Y);
    GotoXY(2, Y); Write('  +- core         R W X'); Inc(Y);
    GotoXY(2, Y); Write('  +- docs         R - -');
  end
  else
  begin
    SetColor(8);
    GotoXY(2, Y); Write('[EXPLORER hidden - F2]');
  end;
end;

procedure TApp.DrawMain;
var
  LeftPanelWidth: Integer;
  ChatStartX, ChatWidth: Integer;
  i, Line, Start: Integer;
begin
  LeftPanelWidth := 28;
  ChatStartX := LeftPanelWidth + 2;
  ChatWidth := FWidth - ChatStartX - 1;

  // THINK
  if FThinkVisible then
  begin
    SetColor(8);
    GotoXY(ChatStartX, 5);
    Write('THINK: Analyzing project structure... checking VFS layer...');
  end;

  // Chat berichten
  SetColor(7);
  Start := FChat.Count - (FHeight - 18);
  if Start < 0 then Start := 0;

  Line := 7;
  for i := Start to FChat.Count - 1 do
  begin
    GotoXY(ChatStartX, Line);
    Write(StringOfChar(' ', ChatWidth)); // clear
    GotoXY(ChatStartX, Line);

    if Pos('You:', FChat[i]) = 1 then
      SetColor(14)
    else
      SetColor(7);

    Write(Copy(FChat[i], 1, ChatWidth - 1));
    Inc(Line);
    if Line > FHeight - 12 then Break;
  end;

  // Work Plan
  SetColor(10); // green
  GotoXY(ChatStartX, FHeight - 11);
  Write('+-- Proposed Work Plan ' + StringOfChar('-', ChatWidth - 24) + '+');

  SetColor(7);
  GotoXY(ChatStartX, FHeight - 10); Write('| 1. Analyze VFS Layer                  Pending   |');
  GotoXY(ChatStartX, FHeight -  9); Write('| 2. Define Integration Points          Pending   |');
  GotoXY(ChatStartX, FHeight -  8); Write('| 3. Design Abstraction Layer           Pending   |');
  GotoXY(ChatStartX, FHeight -  7); Write('| 4. Implement & Refactor               Pending   |');
  GotoXY(ChatStartX, FHeight -  6); Write('| 5. Validate & Test                    Pending   |');
  GotoXY(ChatStartX, FHeight -  5); Write('| Effort: 2-3 days                      Progress  |');

  SetColor(10);
  GotoXY(ChatStartX, FHeight -  4);
  Write('+' + StringOfChar('-', ChatWidth - 2) + '+');
end;

procedure TApp.DrawInputBar;
begin
  SetColor(11);
  GotoXY(1, FHeight - 2);
  Write(StringOfChar('-', FWidth));

  GotoXY(1, FHeight - 1);
  Write('> ');
  SetColor(7);
  Write(FInput);
  Write(StringOfChar(' ', FWidth - Length(FInput) - 3));
end;

procedure TApp.DrawAll;
begin
  GetConsoleSize;
  ClearScreen;
  DrawHeader;
  DrawLeftPanels;
  DrawMain;
  DrawInputBar;

  // Cursor op de juiste plek
  GotoXY(3 + Length(FInput), FHeight - 1);
end;

procedure TApp.HandleInput;
var
  KeyEvent: TInputRecord;
  Read: DWORD;
begin
  while FRunning do
  begin
    DrawAll;

    ReadConsoleInput(GetStdHandle(STD_INPUT_HANDLE), KeyEvent, 1, Read);

    if (KeyEvent.EventType = KEY_EVENT) and KeyEvent.Event.KeyEvent.bKeyDown then
    begin
      case KeyEvent.Event.KeyEvent.wVirtualKeyCode of
        VK_ESCAPE:
          FRunning := False;

        VK_RETURN:
          if Trim(FInput) <> '' then
          begin
            AddMessage('You', FInput);
            AddMessage('GRISP', 'Processing: "' + FInput + '" ...');
            FInput := '';
          end;

        VK_BACK:
          if Length(FInput) > 0 then
            Delete(FInput, Length(FInput), 1);

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

procedure TApp.Run;
begin
  SetConsoleTitle('GRISP OS - TUI');
  HandleInput;
  ClearScreen;
  SetColor(7);
  WriteLn('GRISP TUI closed.');
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
