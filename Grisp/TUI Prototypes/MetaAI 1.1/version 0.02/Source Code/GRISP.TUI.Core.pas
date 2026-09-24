unit GRISP.TUI.Core;

interface

uses
  Winapi.Windows, System.SysUtils,
  GRISP.TUI.Data;

type
  TGRISPColors = record
  const
    // Use simple console colors, not RGB ANSI which flickers in cmd.exe
    // We use Windows console attributes instead of ANSI for stability
    FG_CYAN = 11;   // Light cyan
    FG_WHITE = 15;  // White
    FG_GRAY = 8;    // Gray
    FG_GREEN = 10;  // Light green
    FG_RED = 12;    // Light red
    FG_YELLOW = 14; // Yellow
    FG_BLUE = 9;    // Light blue
    BG_DARK = 0;    // Black bg
  end;

  TTUIRect = record
    X, Y, W, H: Integer;
    constructor Create(AX, AY, AW, AH: Integer);
  end;

procedure EnableConsole;
procedure ClearScreenNoFlicker;
procedure GotoXY(X, Y: Integer);
procedure SetColor(Attr: Word);
procedure ResetColor;
procedure DrawBoxASCII(const R: TTUIRect; const Title: string; Focused: Boolean);
procedure DrawText(X, Y: Integer; const Text: string; Color: Word = 15);
procedure DrawRWX(X, Y: Integer; Perms: TPermissions);

implementation

var
  hOut: THandle;
  DefaultAttr: Word;

constructor TTUIRect.Create(AX, AY, AW, AH: Integer);
begin
  X := AX; Y := AY; W := AW; H := AH;
end;

procedure EnableConsole;
var
  dwMode: DWORD;
  info: TConsoleScreenBufferInfo;
begin
  hOut := GetStdHandle(STD_OUTPUT_HANDLE);
  GetConsoleScreenBufferInfo(hOut, info);
  DefaultAttr := info.wAttributes;

  // Enable VT only if needed, but we will use ASCII + SetConsoleTextAttribute for stability
  GetConsoleMode(hOut, dwMode);
  dwMode := dwMode or $0004; // ENABLE_VIRTUAL_TERMINAL_PROCESSING
  dwMode := dwMode or $0008; // DISABLE_NEWLINE_AUTO_RETURN
  SetConsoleMode(hOut, dwMode);

  // Use OEM codepage 437 for box drawing OR use ASCII + - | to avoid garble
  // We use ASCII + - | to be 100% compatible with any cmd.exe font
  SetConsoleOutputCP(437);
  SetConsoleCP(437);
end;

procedure ClearScreenNoFlicker;
var
  coord: TCoord;
  numWritten: DWORD;
  info: TConsoleScreenBufferInfo;
begin
  // Don't clear with ANSI #27[2J which causes flicker
  // Use FillConsoleOutputCharacter for no flicker
  GetConsoleScreenBufferInfo(hOut, info);
  coord.X := 0; coord.Y := 0;
  FillConsoleOutputCharacter(hOut, ' ', info.dwSize.X * info.dwSize.Y, coord, numWritten);
  FillConsoleOutputAttribute(hOut, DefaultAttr, info.dwSize.X * info.dwSize.Y, coord, numWritten);
  GotoXY(1,1);
end;

procedure GotoXY(X, Y: Integer);
var
  coord: TCoord;
begin
  coord.X := X - 1;
  coord.Y := Y - 1;
  SetConsoleCursorPosition(hOut, coord);
end;

procedure SetColor(Attr: Word);
begin
  SetConsoleTextAttribute(hOut, Attr);
end;

procedure ResetColor;
begin
  SetConsoleTextAttribute(hOut, DefaultAttr);
end;

procedure DrawBoxASCII(const R: TTUIRect; const Title: string; Focused: Boolean);
var
  i: Integer;
  attr: Word;
begin
  if Focused then attr := TGRISPColors.FG_CYAN else attr := TGRISPColors.FG_GRAY;
  SetColor(attr);

  GotoXY(R.X, R.Y);
  Write('+');
  for i := 1 to R.W - 2 do Write('-');
  Write('+');

  for i := 1 to R.H - 2 do
  begin
    GotoXY(R.X, R.Y + i);
    Write('|');
    GotoXY(R.X + R.W - 1, R.Y + i);
    Write('|');
  end;

  GotoXY(R.X, R.Y + R.H - 1);
  Write('+');
  for i := 1 to R.W - 2 do Write('-');
  Write('+');

  if Title <> '' then
  begin
    GotoXY(R.X + 2, R.Y);
    SetColor(TGRISPColors.FG_WHITE);
    Write(' ' + Copy(Title,1,R.W-4) + ' ');
    SetColor(attr);
  end;
  ResetColor;
end;

procedure DrawText(X, Y: Integer; const Text: string; Color: Word = 15);
begin
  GotoXY(X, Y);
  SetColor(Color);
  Write(Text);
  ResetColor;
end;

procedure DrawRWX(X, Y: Integer; Perms: TPermissions);
begin
  GotoXY(X, Y);
  if permRead in Perms then SetColor(TGRISPColors.FG_BLUE) else SetColor(TGRISPColors.FG_GRAY);
  Write('R ');
  if permWrite in Perms then SetColor(TGRISPColors.FG_GREEN) else SetColor(TGRISPColors.FG_GRAY);
  Write('W ');
  if permExecute in Perms then SetColor(TGRISPColors.FG_YELLOW) else SetColor(TGRISPColors.FG_GRAY);
  Write('X');
  ResetColor;
end;

end.
