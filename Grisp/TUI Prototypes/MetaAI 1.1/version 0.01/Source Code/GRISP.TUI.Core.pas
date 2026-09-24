unit GRISP.TUI.Core;

interface

uses
  Winapi.Windows, System.SysUtils,
  GRISP.TUI.Data;

type
  TGRISPColors = record
  const
    RESET    = #27'[0m';
    CYAN     = #27'[38;2;0;212;255m';
    CYAN_DIM = #27'[38;2;30;58;107m';
    CYAN_BG  = #27'[48;2;15;42;90m';
    WHITE    = #27'[38;2;214;228;255m';
    DIM      = #27'[38;2;107;139;184m';
    GREEN    = #27'[38;2;0;255;136m';
    RED      = #27'[38;2;255;68;68m';
    AMBER    = #27'[38;2;255;170;0m';
    BLUE     = #27'[38;2;79;124;255m';
  end;

  TTUIRect = record
    X, Y, W, H: Integer;
    constructor Create(AX, AY, AW, AH: Integer);
  end;

procedure EnableANSI;
procedure ClearScreen;
procedure HideCursor;
procedure ShowCursor;
procedure GotoXY(X, Y: Integer);
procedure SetColor(const Color: string);
procedure ResetColor;
procedure DrawBox(const R: TTUIRect; const Title: string; Focused: Boolean);
procedure DrawHLine(X, Y, Len: Integer; Focused: Boolean);
procedure DrawText(X, Y: Integer; const Text: string; const Color: string = '');
procedure DrawRWX(X, Y: Integer; Perms: TPermissions);

implementation

constructor TTUIRect.Create(AX, AY, AW, AH: Integer);
begin
  X := AX; Y := AY; W := AW; H := AH;
end;

procedure EnableANSI;
var
  hOut: THandle;
  dwMode: DWORD;
begin
  hOut := GetStdHandle(STD_OUTPUT_HANDLE);
  GetConsoleMode(hOut, dwMode);
  dwMode := dwMode or $0004;
  SetConsoleMode(hOut, dwMode);
  SetConsoleOutputCP(CP_UTF8);
  SetConsoleCP(CP_UTF8);
end;

procedure ClearScreen;
begin
  Write(#27'[2J' + #27'[H');
end;

procedure HideCursor;
begin
  Write(#27'[?25l');
end;

procedure ShowCursor;
begin
  Write(#27'[?25h');
end;

procedure GotoXY(X, Y: Integer);
begin
  Write(Format(#27'[%d;%dH', [Y, X]));
end;

procedure SetColor(const Color: string);
begin
  Write(Color);
end;

procedure ResetColor;
begin
  Write(TGRISPColors.RESET);
end;

procedure DrawBox(const R: TTUIRect; const Title: string; Focused: Boolean);
var
  i: Integer;
  borderColor: string;
begin
  if Focused then borderColor := TGRISPColors.CYAN else borderColor := TGRISPColors.CYAN_DIM;
  SetColor(borderColor);
  GotoXY(R.X, R.Y);
  Write(#$E2#$94#$8C); // ┌
  for i := 1 to R.W - 2 do Write(#$E2#$94#$80); // ─
  Write(#$E2#$94#$90); // ┐
  for i := 1 to R.H - 2 do
  begin
    GotoXY(R.X, R.Y + i);
    Write(#$E2#$94#$82); // │
    GotoXY(R.X + R.W - 1, R.Y + i);
    Write(#$E2#$94#$82);
  end;
  GotoXY(R.X, R.Y + R.H - 1);
  Write(#$E2#$94#$94); // └
  for i := 1 to R.W - 2 do Write(#$E2#$94#$80);
  Write(#$E2#$94#$98); // ┘
  if Title <> '' then
  begin
    GotoXY(R.X + 2, R.Y);
    SetColor(TGRISPColors.WHITE);
    Write(' ' + Title + ' ');
    SetColor(borderColor);
  end;
  ResetColor;
end;

procedure DrawHLine(X, Y, Len: Integer; Focused: Boolean);
var
  i: Integer;
begin
  if Focused then SetColor(TGRISPColors.CYAN) else SetColor(TGRISPColors.CYAN_DIM);
  GotoXY(X, Y);
  for i := 1 to Len do Write(#$E2#$94#$80);
  ResetColor;
end;

procedure DrawText(X, Y: Integer; const Text: string; const Color: string = '');
begin
  GotoXY(X, Y);
  if Color <> '' then SetColor(Color);
  Write(Text);
  if Color <> '' then ResetColor;
end;

procedure DrawRWX(X, Y: Integer; Perms: TPermissions);
var
  hasR, hasW, hasX: Boolean;
begin
  hasR := permRead in Perms;
  hasW := permWrite in Perms;
  hasX := permExecute in Perms;
  GotoXY(X, Y);
  if hasR then SetColor(TGRISPColors.BLUE) else SetColor(TGRISPColors.DIM);
  Write('R ');
  if hasW then SetColor(TGRISPColors.GREEN) else SetColor(TGRISPColors.DIM);
  Write('W ');
  if hasX then SetColor(TGRISPColors.AMBER) else SetColor(TGRISPColors.DIM);
  Write('X');
  ResetColor;
end;

end.
