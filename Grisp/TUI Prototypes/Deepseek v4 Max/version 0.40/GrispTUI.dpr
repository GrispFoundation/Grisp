program GrispTUI;

{$APPTYPE CONSOLE}
{$R *.res}

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.Math;

const
  APP_NAME    = 'GRISP OS';
  APP_VERSION = 'v0.40';

  { ── Opties ── }
  OPT_SHOW_DIAMONDS         : Boolean = False;
  OPT_SHOW_RESOURCE_ARROWS  : Boolean = False;
  OPT_SHOW_SESSION_ARROWS   : Boolean = False;
  OPT_SHOW_PRIORITY_LABELS  : Boolean = False;
  OPT_SHOW_CHAT_DATE        : Boolean = True;
  OPT_SHOW_KEY_BRACKETS     : Boolean = False;  { [F1]Left  vs  F1 Left }
  OPT_SHOW_X_BRACKETS       : Boolean = False;  { [X]  vs  X }

  GLYPH_DIAMOND   = #$25C8;  GLYPH_FDIAMOND  = #$25C6;
  GLYPH_RTRI      = #$25B8;  GLYPH_DTRI      = #$25BE;
  GLYPH_PTRI      = #$25B6;  GLYPH_CHECKED   = #$2611;
  GLYPH_UNCHECKED = #$2610;  GLYPH_GT        = #$203A;
  GLYPH_DOT       = #$25CF;  GLYPH_UP        = #$25B2;
  GLYPH_SCROLL    = #$2588;
  GLYPH_TOPLEFT   = #$250C;  GLYPH_TOPRIGHT  = #$2510;
  GLYPH_BOTLEFT   = #$2514;  GLYPH_BOTRIGHT  = #$2518;
  GLYPH_HORZ      = #$2500;  GLYPH_VERT      = #$2502;
  GLYPH_TEEDOWN   = #$252C;  GLYPH_TEEWEST   = #$2524;
  GLYPH_TEEUP     = #$2534;  GLYPH_TEEEAST   = #$251C;

  ESC = #27;
  ANSI_RESET = ESC + '[0m';
  ANSI_BOLD  = ESC + '[1m';
  ANSI_DIM   = ESC + '[2m';
  ERASE_LINE = ESC + '[2K';
  NL = #13#10 + ERASE_LINE;

  FG_CYAN   = ESC + '[38;2;34;211;238m';
  FG_PURPLE = ESC + '[38;2;59;130;246m';
  FG_BORDER = ESC + '[38;2;51;65;85m';
  FG_USER   = ESC + '[38;2;147;197;253m';
  FG_TEXT   = ESC + '[38;2;255;255;255m';
  FG_GRAY   = ESC + '[38;2;148;163;184m';
  FG_DGRAY  = ESC + '[38;2;100;116;139m';
  FG_GREEN  = ESC + '[38;2;34;197;94m';
  FG_AMBER  = ESC + '[38;2;245;158;11m';
  FG_SLATE  = ESC + '[38;2;56;189;248m';
  FG_RED    = ESC + '[38;2;239;68;68m';

  BG_MAIN   = ESC + '[48;2;10;14;26m';
  BG_PANEL  = ESC + '[48;2;13;21;36m';
  BG_BAR    = ESC + '[48;2;8;12;22m';
  BG_INPUT  = ESC + '[48;2;16;27;48m';
  BG_USER   = ESC + '[48;2;30;58;138m';
  BG_AI     = ESC + '[48;2;22;40;66m';
  BG_SELECT = ESC + '[48;2;55;95;150m';

  CURSOR_HIDE    = ESC + '[?25l';
  CURSOR_SHOW    = ESC + '[?25h';
  SCREEN_ALT_ON  = ESC + '[?1049h';
  SCREEN_ALT_OFF = ESC + '[?1049l';
  SCREEN_CLEAR   = ESC + '[3J' + ESC + '[2J' + ESC + '[H';
  CURSOR_HOME    = ESC + '[H';

  SIM_INTERVAL_MS = 900;
  MIN_W_LEFT      = 110;
  MIN_W_RIGHT     = 90;
  MIN_PANE_WIDTH  = 20;
  MIN_CHAT_WIDTH  = 34;
  MIN_CONTENT_H   = 3;

  MY_CF_UNICODETEXT = 13;

  EVT_KEY           = $0001;
  EVT_MOUSE         = $0002;
  EVT_MOUSE_MOVED   = $0001;
  EVT_MOUSE_WHEELED = $0004;

  AUTO_SCROLL_MS = 40;

type
  TChatRole = (crUser, crAssistant, crSystem);
  TChatMessage = record
    Role : TChatRole;
    Text : string;
    Time : string;
    Date : string;
    FullStamp : string;
  end;
  TPlanStatus = (psDone, psRunning, psQueued);
  TPlanItem = record Text : string; Status : TPlanStatus; end;
  TWorkPriority = (wpHigh, wpMedium, wpLow);
  TWorkItem = record Text : string; Prio : TWorkPriority; end;
  TSession = record Name : string; Meta : string; Messages : TList<TChatMessage>; end;
  TTreeItem = record Name : string; Depth : Integer; Perm : string; Expanded : Boolean; end;

  TInputKind = (ikNone, ikChar, ikSpecial, ikMouse);
  TInputEvent = record
    Kind : TInputKind; Ch : WideChar; VK : Word;
    ModCtrl, ModAlt, ModShift : Boolean;
    MouseX, MouseY, MouseButton, WheelDelta : Integer;
    IsMove : Boolean;
  end;
  TVisualLine = record BufStart : Integer; Text : string; end;
  TMouseShape = (msArrow, msSizeWE, msSizeNS, msIBeam, msHand);

var
  StdOutHandle, StdInHandle : THandle;
  ScreenWidth, ScreenHeight : Integer;
  ColLeft, ColCenter, ColRight : Integer;
  ContentHeight, InputHeight : Integer;
  LeftSplitRow, RightPlanRows, RightWorkRows : Integer;

  ChatMessages  : TList<TChatMessage>;
  PlanItems     : TList<TPlanItem>;
  WorkItems     : TList<TWorkItem>;
  ThinkingLines : TList<string>;
  SessionList   : TList<TSession>;
  TreeList      : TList<TTreeItem>;

  CurrentSessionName : string;
  ActiveSessionIndex : Integer = 0;

  TreeVisibleRows, TreeVisibleIdx : TArray<Integer>;
  SessionTitleRows, SessionIdxAtRow : TArray<Integer>;

  InputBuffer : string; InputCursor : Integer = 0;

  WantLeftPanel, WantRightPanel, WantThinking, MouseEnabled : Boolean;
  ShowLeftPanel, ShowRightPanel, ShowThinking : Boolean;

  UserColLeft   : Integer = 0;
  UserColRight  : Integer = 0;
  UserInputRows : Integer = 0;
  UserLeftSplit : Integer = 0;
  UserPlanRows  : Integer = 0;
  UserWorkRows  : Integer = 0;

  IsDragging  : Boolean = False;
  DragTarget  : Integer = 0;
  HoverTarget : Integer = 0;
  CurrentMouseShape : TMouseShape = msArrow;

  ChatScroll    : Integer = 0;  ChatMaxScroll    : Integer = 0;
  InputScroll   : Integer = 0;  InputMaxScroll   : Integer = 0;
  ResScroll     : Integer = 0;  ResMaxScroll     : Integer = 0;
  SesScroll     : Integer = 0;  SesMaxScroll     : Integer = 0;
  PlanScroll    : Integer = 0;  PlanMaxScroll    : Integer = 0;
  WorkScroll    : Integer = 0;  WorkMaxScroll    : Integer = 0;
  ThinkScroll   : Integer = 0;  ThinkMaxScroll   : Integer = 0;

  ChatFullPlain : TArray<string>;
  ChatFullKind  : TArray<Integer>;
  ChatWindowStart : Integer = 0;
  SelActive     : Boolean = False;
  SelAnchorRow  : Integer = -1;
  SelAnchorCol  : Integer = 0;
  SelFocusRow   : Integer = -1;
  SelFocusCol   : Integer = 0;
  IsSelecting   : Boolean = False;
  AutoScrollDir : Integer = 0;
  AutoScrollX   : Integer = 0;
  AutoScrollTick: Cardinal = 0;

  QuitRequested     : Boolean = False;
  ExitDialogVisible : Boolean = False;
  SimActive     : Boolean = False; SimStep : Integer = 0; SimTimer : Cardinal = 0;
  PromptState   : string = 'READY'; StatusKind : Integer = 0;

  NeedsRedraw     : Boolean = True;
  ForceFullRedraw : Boolean = False;

procedure ReadTerminalSize(out W, H : Integer);
var Info : TConsoleScreenBufferInfo;
begin
  if GetConsoleScreenBufferInfo(StdOutHandle, Info) then
  begin W := Info.srWindow.Right - Info.srWindow.Left + 1;
        H := Info.srWindow.Bottom - Info.srWindow.Top + 1; end
  else begin W := 140; H := 40; end;
  if W < 40 then W := 40;
  if H < 12 then H := 12;
end;

procedure WriteAtomic(const S : string);
var Written : DWORD;
begin if S = '' then Exit;
  WriteConsoleW(StdOutHandle, PWideChar(S), Length(S), Written, nil); end;

procedure ApplyInputMode;
var Mode : DWORD;
begin
  GetConsoleMode(StdInHandle, Mode);
  Mode := Mode or ENABLE_EXTENDED_FLAGS or ENABLE_WINDOW_INPUT or ENABLE_MOUSE_INPUT;
  if MouseEnabled then
    Mode := Mode and not ENABLE_QUICK_EDIT_MODE and not ENABLE_PROCESSED_INPUT
  else
    Mode := Mode and not ENABLE_MOUSE_INPUT or ENABLE_QUICK_EDIT_MODE or ENABLE_PROCESSED_INPUT;
  SetConsoleMode(StdInHandle, Mode);
end;

procedure InitializeConsole;
var Mode : DWORD;
begin
  StdOutHandle := GetStdHandle(STD_OUTPUT_HANDLE);
  StdInHandle := GetStdHandle(STD_INPUT_HANDLE);
  GetConsoleMode(StdOutHandle, Mode);
  SetConsoleMode(StdOutHandle,
    (Mode or ENABLE_VIRTUAL_TERMINAL_PROCESSING or ENABLE_PROCESSED_OUTPUT)
    and not ENABLE_WRAP_AT_EOL_OUTPUT);
  SetConsoleOutputCP(CP_UTF8); SetConsoleCP(CP_UTF8);
  SetConsoleTitle(PChar(APP_NAME + ' ' + APP_VERSION + ' — Terminal UI'));
  ApplyInputMode;
end;

function ReadInputEvent : TInputEvent;
var Available : DWORD; Rec : INPUT_RECORD; Read : DWORD;
    ButtonState, ControlKeys : DWORD; WheelRaw : SmallInt;
begin
  Result.Kind := ikNone; Result.IsMove := False;
  while True do
  begin
    Available := 0;
    if not GetNumberOfConsoleInputEvents(StdInHandle, Available) then Exit;
    if Available = 0 then Exit;
    if not ReadConsoleInputW(StdInHandle, Rec, 1, Read) then Exit;
    if Rec.EventType = EVT_KEY then
    begin
      if not Rec.Event.KeyEvent.bKeyDown then Continue;
      ControlKeys := Rec.Event.KeyEvent.dwControlKeyState;
      Result.ModCtrl := (ControlKeys and (LEFT_CTRL_PRESSED or RIGHT_CTRL_PRESSED)) <> 0;
      Result.ModAlt := (ControlKeys and (LEFT_ALT_PRESSED or RIGHT_ALT_PRESSED)) <> 0;
      Result.ModShift := (ControlKeys and SHIFT_PRESSED) <> 0;
      Result.VK := Rec.Event.KeyEvent.wVirtualKeyCode;
      Result.Ch := Rec.Event.KeyEvent.UnicodeChar;
      if (Result.Ch = #0) and (Result.VK <> 0) then Result.Kind := ikSpecial
      else if Result.Ch <> #0 then Result.Kind := ikChar else Result.Kind := ikNone;
      Exit;
    end;
    if Rec.EventType = EVT_MOUSE then
    begin
      ButtonState := Rec.Event.MouseEvent.dwButtonState;
      Result.Kind := ikMouse;
      Result.MouseX := Rec.Event.MouseEvent.dwMousePosition.X + 1;
      Result.MouseY := Rec.Event.MouseEvent.dwMousePosition.Y + 1;
      if (ButtonState and FROM_LEFT_1ST_BUTTON_PRESSED) <> 0 then Result.MouseButton := 1
      else if (ButtonState and RIGHTMOST_BUTTON_PRESSED) <> 0 then Result.MouseButton := 2
      else Result.MouseButton := 0;
      if (Rec.Event.MouseEvent.dwEventFlags and EVT_MOUSE_WHEELED) <> 0 then
      begin WheelRaw := SmallInt(ButtonState shr 16); Result.WheelDelta := WheelRaw; end
      else Result.WheelDelta := 0;
      if (Rec.Event.MouseEvent.dwEventFlags and EVT_MOUSE_MOVED) <> 0 then
        Result.IsMove := True;
      Exit;
    end;
  end;
end;

function VisibleLength(const S : string) : Integer;
var I : Integer; InEscape : Boolean;
begin
  Result := 0; InEscape := False;
  for I := 1 to Length(S) do
    if InEscape then
    begin if CharInSet(S[I], ['a'..'z', 'A'..'Z']) then InEscape := False; end
    else if S[I] = #27 then InEscape := True else Inc(Result);
end;

function TruncateAnsiString(const S : string; MaxVisible : Integer) : string;
var I, Vis : Integer; InEscape : Boolean;
begin
  Result := ''; Vis := 0; InEscape := False; I := 1;
  while I <= Length(S) do
  begin
    if InEscape then
    begin Result := Result + S[I];
      if CharInSet(S[I], ['a'..'z', 'A'..'Z']) then InEscape := False; Inc(I); end
    else if S[I] = #27 then
    begin InEscape := True; Result := Result + S[I]; Inc(I); end
    else if Vis < MaxVisible then
    begin Result := Result + S[I]; Inc(Vis); Inc(I); end
    else Break;
  end;
end;

function PadToWidth(const S : string; TargetWidth : Integer;
                    const PadBackground : string) : string;
var Vis : Integer;
begin
  if TargetWidth <= 0 then Exit('');
  Vis := VisibleLength(S);
  if Vis > TargetWidth then
    Result := TruncateAnsiString(S, TargetWidth) + ANSI_RESET + PadBackground
  else
    Result := S + ANSI_RESET + PadBackground
            + StringOfChar(' ', TargetWidth - Vis);
end;

function StripAnsi(const S : string) : string;
var I : Integer; InEscape : Boolean;
begin
  Result := ''; InEscape := False;
  for I := 1 to Length(S) do
  begin
    if InEscape then
    begin
      if CharInSet(S[I], ['a'..'z','A'..'Z']) then InEscape := False;
    end
    else if S[I] = #27 then InEscape := True
    else Result := Result + S[I];
  end;
end;

function RenderLineWithSelection(const Plain : string; LeadLen : Integer;
  const BubbleBg : string; SelStart, SelEnd : Integer) : string;
var I, Len : Integer; InSel, PrevInSel : Boolean;
begin
  Len := Length(Plain);
  if SelStart < 0 then SelStart := 0;
  if SelEnd > Len then SelEnd := Len;
  if SelEnd < SelStart then SelEnd := SelStart;
  Result := ''; PrevInSel := False;
  for I := 1 to Len do
  begin
    InSel := (I - 1 >= SelStart) and (I - 1 < SelEnd);
    if I = 1 then
    begin
      if InSel then Result := Result + BG_SELECT + FG_TEXT + ANSI_BOLD
      else if LeadLen > 0 then Result := Result + BG_MAIN + FG_TEXT
      else Result := Result + BubbleBg + FG_TEXT;
    end
    else if InSel <> PrevInSel then
    begin
      if InSel then Result := Result + BG_SELECT + FG_TEXT + ANSI_BOLD
      else if (I - 1) < LeadLen then Result := Result + BG_MAIN + FG_TEXT
      else Result := Result + BubbleBg + FG_TEXT;
    end;
    Result := Result + Plain[I];
    PrevInSel := InSel;
  end;
  Result := Result + ANSI_RESET + BG_MAIN;
end;

function WrapParagraph(const Text : string; MaxWidth : Integer) : TArray<string>;
var
  L : TList<string>; RawLines : TArray<string>; RawLine : string;
  Cur, Word : string; I, StartPos : Integer; HadText : Boolean;

  procedure FlushCurrent;
  begin if Cur <> '' then begin L.Add(Cur); Cur := ''; end; end;

  procedure AddRawLine(const Value : string);
  var J : Integer;
  begin
    Cur := ''; HadText := False; J := 1;
    while J <= Length(Value) do
    begin
      while (J <= Length(Value)) and (Value[J] = ' ') do Inc(J);
      if J > Length(Value) then Break;
      StartPos := J;
      while (J <= Length(Value)) and (Value[J] <> ' ') do Inc(J);
      Word := Copy(Value, StartPos, J - StartPos);
      HadText := True;
      while Length(Word) > MaxWidth do
      begin FlushCurrent; L.Add(Copy(Word, 1, MaxWidth)); Delete(Word, 1, MaxWidth); end;
      if Word = '' then Continue;
      if Cur = '' then Cur := Word
      else if Length(Cur) + 1 + Length(Word) <= MaxWidth then Cur := Cur + ' ' + Word
      else begin FlushCurrent; Cur := Word; end;
    end;
    FlushCurrent;
    if not HadText then L.Add('');
  end;

begin
  if MaxWidth < 1 then MaxWidth := 1;
  L := TList<string>.Create;
  try
    RawLines := StringReplace(Text, #13#10, #10, [rfReplaceAll]).Split([#10]);
    for I := 0 to High(RawLines) do
    begin
      RawLine := StringReplace(RawLines[I], #13, '', [rfReplaceAll]);
      RawLine := StringReplace(RawLine, #9, ' ', [rfReplaceAll]);
      AddRawLine(RawLine);
    end;
    if L.Count = 0 then L.Add('');
    SetLength(Result, L.Count);
    for I := 0 to L.Count - 1 do Result[I] := L[I];
  finally L.Free; end;
end;

function BuildVisualLines(const Buf : string; WrapWidth : Integer) : TArray<TVisualLine>;
var Lines : TList<TVisualLine>; Current : TVisualLine; I : Integer;
begin
  Lines := TList<TVisualLine>.Create;
  try
    Current.BufStart := 1; Current.Text := '';
    for I := 1 to Length(Buf) do
    begin
      if Buf[I] = #10 then
      begin Lines.Add(Current); Current.BufStart := I + 1; Current.Text := ''; end
      else
      begin
        if Length(Current.Text) >= WrapWidth then
        begin Lines.Add(Current); Current.BufStart := I; Current.Text := ''; end;
        Current.Text := Current.Text + Buf[I];
      end;
    end;
    Lines.Add(Current);
    SetLength(Result, Lines.Count);
    for I := 0 to Lines.Count - 1 do Result[I] := Lines[I];
  finally Lines.Free; end;
end;

function CursorVisualPos(const Lines : TArray<TVisualLine>;
  Cursor : Integer; out VisRow, VisCol : Integer) : Boolean;
var I, N : Integer;
begin
  VisRow := 0; VisCol := 0; Result := False;
  N := Length(Lines); if N = 0 then Exit;
  for I := 0 to N - 1 do
  begin
    if I = N - 1 then
    begin VisRow := I; VisCol := Cursor - (Lines[I].BufStart - 1);
      if VisCol < 0 then VisCol := 0;
      if VisCol > Length(Lines[I].Text) then VisCol := Length(Lines[I].Text);
      Result := True; Exit; end
    else if Cursor < Lines[I + 1].BufStart - 1 then
    begin VisRow := I; VisCol := Cursor - (Lines[I].BufStart - 1);
      if VisCol < 0 then VisCol := 0;
      if VisCol > Length(Lines[I].Text) then VisCol := Length(Lines[I].Text);
      Result := True; Exit; end;
  end;
end;

function InputWrapWidth : Integer;
begin Result := ScreenWidth - 5; if Result < 5 then Result := 5; end;

function CurrentShortTime : string;
begin Result := FormatDateTime('hh:nn', Now); end;

function CurrentShortDate : string;
var Y, M, D : Word;
begin
  DecodeDate(Now, Y, M, D);
  Result := Format('%.2d %.3s', [D, FormatSettings.ShortMonthNames[M]]);
end;

{ Volledige timestamp voor chat, bijv. "25 September 2026 15:34:33". }
function CurrentFullStamp : string;
var Y, M, D : Word; H, Mn, S, Ms : Word;
begin
  DecodeDate(Now, Y, M, D); DecodeTime(Now, H, Mn, S, Ms);
  Result := Format('%d %s %d %.2d:%.2d:%.2d',
    [D, FormatSettings.LongMonthNames[M], Y, H, Mn, S]);
end;

function CurrentLongTime : string;
var Y, M, D : Word; H, Mn, S, Ms : Word;
begin
  DecodeDate(Now, Y, M, D); DecodeTime(Now, H, Mn, S, Ms);
  Result := Format('%d %s %d %.2d:%.2d:%.2d',
    [D, FormatSettings.LongMonthNames[M], Y, H, Mn, S]);
end;

function RepeatChar(const C : Char; N : Integer) : string;
begin if N <= 0 then Result := '' else Result := StringOfChar(C, N); end;

function ScrollThumbChar(Scroll, MaxScroll, BodyH, Row : Integer) : string;
var ThumbTop, ThumbH, Total, S : Integer;
begin
  Total := MaxScroll + BodyH;
  if (BodyH <= 0) or (MaxScroll <= 0) or (Total <= BodyH) then
  begin Result := FG_DGRAY + GLYPH_VERT; Exit; end;
  ThumbH := Max(1, BodyH * BodyH div Total);
  if ThumbH > BodyH then ThumbH := BodyH;
  S := Scroll; if S < 0 then S := 0; if S > MaxScroll then S := MaxScroll;
  ThumbTop := (BodyH - ThumbH) * S div Max(1, MaxScroll);
  if (Row >= ThumbTop) and (Row < ThumbTop + ThumbH) then
    Result := FG_CYAN + GLYPH_SCROLL
  else Result := FG_DGRAY + GLYPH_VERT;
end;

function ChatThumbChar(Scroll, MaxScroll, BodyH, Row : Integer) : string;
begin Result := ScrollThumbChar(MaxScroll - Scroll, MaxScroll, BodyH, Row); end;

function MouseToScrollTop(MouseY, TopRow, BodyH, MaxScroll : Integer) : Integer;
var RelY : Integer;
begin
  if (BodyH <= 1) or (MaxScroll <= 0) then begin Result := 0; Exit; end;
  RelY := MouseY - TopRow;
  if RelY < 0 then RelY := 0;
  if RelY >= BodyH then RelY := BodyH - 1;
  Result := RelY * MaxScroll div (BodyH - 1);
end;

function MouseToChatScroll(MouseY, TopRow, BodyH, MaxScroll : Integer) : Integer;
var RelY : Integer;
begin
  if (BodyH <= 1) or (MaxScroll <= 0) then begin Result := 0; Exit; end;
  RelY := MouseY - TopRow;
  if RelY < 0 then RelY := 0;
  if RelY >= BodyH then RelY := BodyH - 1;
  Result := (BodyH - 1 - RelY) * MaxScroll div (BodyH - 1);
end;

function MaxInputRows : Integer;
begin Result := ScreenHeight - 7 - MIN_CONTENT_H; if Result < 1 then Result := 1; end;

procedure RecomputeLayout;
var AvailableRows : Integer;
begin
  ReadTerminalSize(ScreenWidth, ScreenHeight);
  ShowLeftPanel := WantLeftPanel and (ScreenWidth >= MIN_W_LEFT);
  ShowRightPanel := WantRightPanel and (ScreenWidth >= MIN_W_RIGHT);
  ShowThinking := WantThinking;

  if ShowLeftPanel then
  begin if UserColLeft > 0 then ColLeft := UserColLeft
        else ColLeft := EnsureRange(ScreenWidth div 7, 26, 36);
    if ColLeft < MIN_PANE_WIDTH then ColLeft := MIN_PANE_WIDTH; end
  else ColLeft := 0;

  if ShowRightPanel then
  begin if UserColRight > 0 then ColRight := UserColRight
        else ColRight := EnsureRange(ScreenWidth div 5, 34, 46);
    if ColRight < MIN_PANE_WIDTH then ColRight := MIN_PANE_WIDTH; end
  else ColRight := 0;

  ColCenter := ScreenWidth - ColLeft - ColRight - 4;
  if ColCenter < MIN_CHAT_WIDTH then
  begin
    if ShowRightPanel then
    begin ColRight := ColRight - (MIN_CHAT_WIDTH - ColCenter);
      if ColRight < MIN_PANE_WIDTH then ColRight := MIN_PANE_WIDTH;
      ColCenter := ScreenWidth - ColLeft - ColRight - 4; end;
    if (ColCenter < MIN_CHAT_WIDTH) and ShowLeftPanel then
    begin ColLeft := ColLeft - (MIN_CHAT_WIDTH - ColCenter);
      if ColLeft < MIN_PANE_WIDTH then ColLeft := MIN_PANE_WIDTH;
      ColCenter := ScreenWidth - ColLeft - ColRight - 4; end;
    if ColCenter < 12 then ColCenter := 12;
  end;

  if UserInputRows > 0 then InputHeight := UserInputRows
  else if ScreenHeight < 24 then InputHeight := 1
  else InputHeight := 3;
  if InputHeight < 1 then InputHeight := 1;
  if InputHeight > MaxInputRows then InputHeight := MaxInputRows;

  ContentHeight := ScreenHeight - 7 - InputHeight;
  if ContentHeight < MIN_CONTENT_H then
  begin ContentHeight := MIN_CONTENT_H;
    InputHeight := ScreenHeight - 7 - ContentHeight;
    if InputHeight < 1 then InputHeight := 1; end;

  if UserLeftSplit > 0 then LeftSplitRow := UserLeftSplit
  else LeftSplitRow := (ContentHeight - 1) div 2;
  if LeftSplitRow < 2 then LeftSplitRow := 2;
  if LeftSplitRow > ContentHeight - 3 then LeftSplitRow := ContentHeight - 3;

  AvailableRows := ContentHeight - 2;
  if UserPlanRows > 0 then RightPlanRows := UserPlanRows
  else RightPlanRows := AvailableRows div 3;
  if UserWorkRows > 0 then RightWorkRows := UserWorkRows
  else RightWorkRows := AvailableRows div 3;
  if RightPlanRows < 3 then RightPlanRows := 3;
  if RightWorkRows < 3 then RightWorkRows := 3;
  while (RightPlanRows + RightWorkRows) > AvailableRows - 3 do
  begin if RightWorkRows > 3 then Dec(RightWorkRows)
        else if RightPlanRows > 3 then Dec(RightPlanRows) else Break; end;
end;

procedure AddMsg(const Sess : TSession; const R : TChatRole; const T : string);
var M : TChatMessage;
begin
  M.Role := R; M.Text := T;
  M.Time := CurrentShortTime;
  M.Date := CurrentShortDate;
  M.FullStamp := CurrentFullStamp;
  Sess.Messages.Add(M);
end;

procedure InitializeApplicationData;
var Session : TSession; Plan : TPlanItem; Work : TWorkItem; Tree : TTreeItem;
begin
  PlanItems := TList<TPlanItem>.Create;
  WorkItems := TList<TWorkItem>.Create;
  ThinkingLines := TList<string>.Create;
  SessionList := TList<TSession>.Create;
  TreeList := TList<TTreeItem>.Create;

  Tree.Name:='Local';          Tree.Depth:=0; Tree.Perm:='';    Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='Projects';       Tree.Depth:=1; Tree.Perm:='RWX'; Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='GRISP';          Tree.Depth:=2; Tree.Perm:='RWX'; Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='MME-Registry';   Tree.Depth:=2; Tree.Perm:='RW';  Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='Agent-Network';  Tree.Depth:=2; Tree.Perm:='RW';  Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='Data-Pipeline';  Tree.Depth:=2; Tree.Perm:='RWX'; Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='VFS-Layer';      Tree.Depth:=2; Tree.Perm:='RW';  Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='Compiler';       Tree.Depth:=2; Tree.Perm:='RWX'; Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='Runtime';        Tree.Depth:=2; Tree.Perm:='RW';  Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='Data';           Tree.Depth:=1; Tree.Perm:='RW';  Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='Models';         Tree.Depth:=2; Tree.Perm:='RW';  Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='Datasets';       Tree.Depth:=2; Tree.Perm:='RW';  Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='Raw';            Tree.Depth:=3; Tree.Perm:='R';   Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='Processed';      Tree.Depth:=3; Tree.Perm:='RW';  Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='Cache';          Tree.Depth:=3; Tree.Perm:='RW';  Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='Cloud';          Tree.Depth:=1; Tree.Perm:='R';   Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='AWS';            Tree.Depth:=2; Tree.Perm:='R';   Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='Azure';          Tree.Depth:=2; Tree.Perm:='R';   Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='Archive';        Tree.Depth:=1; Tree.Perm:='RW';  Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='Old-Projects';   Tree.Depth:=2; Tree.Perm:='R';   Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='Backups';        Tree.Depth:=2; Tree.Perm:='R';   Tree.Expanded:=True;  TreeList.Add(Tree);

  Session.Name:='Architecture Review';      Session.Meta:='24 sep 2026 14:30:23';
  Session.Messages := TList<TChatMessage>.Create;
  AddMsg(Session, crAssistant, 'Hello Alex, how can I help you with GRISP today?');
  AddMsg(Session, crAssistant, 'I can help with analysis, planning, or code generation. Just ask.');
  SessionList.Add(Session);

  Session.Name:='MME Schema Draft';         Session.Meta:='24 sep 2026 12:10:08';
  Session.Messages := TList<TChatMessage>.Create;
  AddMsg(Session, crAssistant, 'Schema draft loaded. 12 resource types ready for review.');
  SessionList.Add(Session);

  Session.Name:='Agent Graph';              Session.Meta:='23 sep 2026 18:22:44';
  Session.Messages := TList<TChatMessage>.Create;
  AddMsg(Session, crAssistant, 'Agent network graph is available. 7 nodes connected.');
  SessionList.Add(Session);

  Session.Name:='VFS Refactor Notes';       Session.Meta:='23 sep 2026 09:15:31';
  Session.Messages := TList<TChatMessage>.Create;
  AddMsg(Session, crAssistant, 'VFS refactor plan ready. Awaiting your go-ahead.');
  SessionList.Add(Session);

  Session.Name:='Memory Bugfix';            Session.Meta:='22 sep 2026 16:45:12';
  Session.Messages := TList<TChatMessage>.Create;
  AddMsg(Session, crAssistant, 'Memory leak in the graph allocator has been patched.');
  SessionList.Add(Session);

  Session.Name:='AST Parser Refactor';      Session.Meta:='22 sep 2026 11:30:05';
  Session.Messages := TList<TChatMessage>.Create;
  AddMsg(Session, crAssistant, 'AST parser now handles all expression forms.');
  SessionList.Add(Session);

  Session.Name:='GRISP Canvas Integration'; Session.Meta:='21 sep 2026 15:20:48';
  Session.Messages := TList<TChatMessage>.Create;
  AddMsg(Session, crAssistant, 'Canvas backend is wired up. Rendering tests pending.');
  SessionList.Add(Session);

  Session.Name:='Dependency Update';        Session.Meta:='21 sep 2026 09:12:33';
  Session.Messages := TList<TChatMessage>.Create;
  AddMsg(Session, crAssistant, 'All dependencies bumped to current versions.');
  SessionList.Add(Session);

  Session.Name:='Runtime Diagnostics';      Session.Meta:='20 sep 2026 17:05:21';
  Session.Messages := TList<TChatMessage>.Create;
  AddMsg(Session, crAssistant, 'Diagnostic endpoints exposed for live tracing.');
  SessionList.Add(Session);

  Session.Name:='Compiler Optimizations';   Session.Meta:='19 sep 2026 13:42:56';
  Session.Messages := TList<TChatMessage>.Create;
  AddMsg(Session, crAssistant, 'Two-pass optimizer reduces IR size by 18%.');
  SessionList.Add(Session);

  Session.Name:='Boot Sequence Debug';      Session.Meta:='18 sep 2026 10:28:17';
  Session.Messages := TList<TChatMessage>.Create;
  AddMsg(Session, crAssistant, 'Cold start time reduced from 340ms to 180ms.');
  SessionList.Add(Session);

  Session.Name:='VM Spec Review';           Session.Meta:='17 sep 2026 16:55:09';
  Session.Messages := TList<TChatMessage>.Create;
  AddMsg(Session, crAssistant, 'Bytecode spec finalized for v1.0.');
  SessionList.Add(Session);

  Session.Name:='Protocol Compliance';      Session.Meta:='16 sep 2026 14:20:41';
  Session.Messages := TList<TChatMessage>.Create;
  AddMsg(Session, crAssistant, 'All mandatory GARP/1.26 vectors pass.');
  SessionList.Add(Session);

  Session.Name:='Security Audit';           Session.Meta:='15 sep 2026 11:08:52';
  Session.Messages := TList<TChatMessage>.Create;
  AddMsg(Session, crAssistant, 'No critical findings. Two low-severity notes filed.');
  SessionList.Add(Session);

  Session.Name:='Performance Baseline';     Session.Meta:='14 sep 2026 09:45:22';
  Session.Messages := TList<TChatMessage>.Create;
  AddMsg(Session, crAssistant, 'Baseline captured: 1.2M ops/sec on reference hardware.');
  SessionList.Add(Session);

  ActiveSessionIndex := 0;
  CurrentSessionName := SessionList[0].Name;
  ChatMessages := SessionList[0].Messages;

  Plan.Text:='Analyze VFS Layer';            Plan.Status:=psDone;    PlanItems.Add(Plan);
  Plan.Text:='Extract MME schema';           Plan.Status:=psDone;    PlanItems.Add(Plan);
  Plan.Text:='Map Agent Network';            Plan.Status:=psRunning; PlanItems.Add(Plan);
  Plan.Text:='Draft DNA report';             Plan.Status:=psQueued;  PlanItems.Add(Plan);
  Plan.Text:='Validate permissions matrix';  Plan.Status:=psQueued;  PlanItems.Add(Plan);
  Plan.Text:='Refactor AST parser';          Plan.Status:=psQueued;  PlanItems.Add(Plan);
  Plan.Text:='Implement graph evaluator';    Plan.Status:=psQueued;  PlanItems.Add(Plan);
  Plan.Text:='Update protocol docs';         Plan.Status:=psQueued;  PlanItems.Add(Plan);
  Plan.Text:='Write integration tests';      Plan.Status:=psQueued;  PlanItems.Add(Plan);
  Plan.Text:='Review security model';        Plan.Status:=psQueued;  PlanItems.Add(Plan);
  Plan.Text:='Optimize memory layout';       Plan.Status:=psQueued;  PlanItems.Add(Plan);
  Plan.Text:='Finalize v1.0 spec';           Plan.Status:=psQueued;  PlanItems.Add(Plan);

  Work.Text:='Implement GRISP runtime';      Work.Prio:=wpHigh;   WorkItems.Add(Work);
  Work.Text:='Add graph visualization';      Work.Prio:=wpMedium; WorkItems.Add(Work);
  Work.Text:='Write unit tests';             Work.Prio:=wpMedium; WorkItems.Add(Work);
  Work.Text:='Update LSBP integration';      Work.Prio:=wpLow;    WorkItems.Add(Work);
  Work.Text:='Refactor memory allocator';    Work.Prio:=wpHigh;   WorkItems.Add(Work);
  Work.Text:='Optimize graph traversal';     Work.Prio:=wpMedium; WorkItems.Add(Work);
  Work.Text:='Add telemetry hooks';          Work.Prio:=wpLow;    WorkItems.Add(Work);
  Work.Text:='Review error handling';        Work.Prio:=wpMedium; WorkItems.Add(Work);
  Work.Text:='Implement cancellation';       Work.Prio:=wpHigh;   WorkItems.Add(Work);
  Work.Text:='Add replay support';           Work.Prio:=wpMedium; WorkItems.Add(Work);
  Work.Text:='Improve diagnostics';          Work.Prio:=wpLow;    WorkItems.Add(Work);
  Work.Text:='Fix race condition';           Work.Prio:=wpHigh;   WorkItems.Add(Work);
  Work.Text:='Add fuzzing tests';            Work.Prio:=wpMedium; WorkItems.Add(Work);
  Work.Text:='Document adapter contract';    Work.Prio:=wpLow;    WorkItems.Add(Work);
  Work.Text:='Prepare release notes';        Work.Prio:=wpLow;    WorkItems.Add(Work);

  ThinkingLines.Add('Waiting for user input...');
  ThinkingLines.Add('Parsing GRISP environment...');
  ThinkingLines.Add('Ready to assist.');
  ThinkingLines.Add('Scanning resource tree...');
  ThinkingLines.Add('Indexing MME schema nodes...');
  ThinkingLines.Add('Mapping agent network topology...');
  ThinkingLines.Add('Cross-referencing VFS layer...');
  ThinkingLines.Add('Validating permission matrix...');
  ThinkingLines.Add('Analyzing dependency graph...');
  ThinkingLines.Add('Checking protocol compliance...');
  ThinkingLines.Add('Compiling AST parser...');
  ThinkingLines.Add('Evaluating execution plan...');
  ThinkingLines.Add('Estimating runtime complexity...');
  ThinkingLines.Add('Profiling memory allocation...');
  ThinkingLines.Add('Reviewing cancellation paths...');
  ThinkingLines.Add('Testing replay support...');
  ThinkingLines.Add('Verifying terminal arbitration...');
  ThinkingLines.Add('Preparing diagnostics...');
  ThinkingLines.Add('Ready for next operation.');

  WantLeftPanel := True; WantRightPanel := True; WantThinking := True;
  MouseEnabled := True; ExitDialogVisible := False; QuitRequested := False;
  RecomputeLayout;
  ApplyInputMode;
end;

procedure ShutdownApplicationData;
var I : Integer;
begin
  for I := 0 to SessionList.Count - 1 do SessionList[I].Messages.Free;
  PlanItems.Free; WorkItems.Free; ThinkingLines.Free;
  SessionList.Free; TreeList.Free;
end;

procedure SwitchSession(Idx : Integer);
begin
  if (Idx < 0) or (Idx >= SessionList.Count) then Exit;
  ActiveSessionIndex := Idx; CurrentSessionName := SessionList[Idx].Name;
  ChatMessages := SessionList[Idx].Messages; ChatScroll := 0;
  SelActive := False; SelAnchorRow := -1; SelFocusRow := -1; AutoScrollDir := 0;
end;

function ComputeTreeVisibility : TArray<Integer>;
var I, D : Integer; Chain : array[0..15] of Boolean; Tmp : TList<Integer>;
begin
  Tmp := TList<Integer>.Create;
  try
    if TreeList.Count = 0 then begin SetLength(Result, 0); Exit; end;
    Chain[0] := True;
    for I := 0 to TreeList.Count - 1 do
    begin
      D := TreeList[I].Depth; if D > 15 then D := 15;
      if (D = 0) or Chain[D - 1] then
      begin Tmp.Add(I); Chain[D] := TreeList[I].Expanded; end
      else Chain[D] := False;
    end;
    SetLength(Result, Tmp.Count);
    for I := 0 to Tmp.Count - 1 do Result[I] := Tmp[I];
  finally Tmp.Free; end;
end;

function NodeHasVisibleChildren(Idx : Integer) : Boolean;
begin
  Result := (Idx + 1 < TreeList.Count) and
            (TreeList[Idx + 1].Depth > TreeList[Idx].Depth);
end;

function RenderLeftPane : TArray<string>;
var
  Lines : TList<string>;
  I, Indent, NameWidth, RowUsed : Integer;
  Buf, PermColor, NameField, DividerCol, SessionTitle, MetaStr, SessTitleBuf, Arrow, TitleText : string;
  Visible : TArray<Integer>;
  Item : TTreeItem;
  Session : TSession;
  Vis : TList<Integer>;
  SessRowText : TList<string>;
  SessRowSess : TList<Integer>;
  SessTitleRowsArr : TList<Integer>;
  SessTitleIdxArr  : TList<Integer>;
  ContentW : Integer;
  ResBodyH, SesBodyH, TotalSessLines : Integer;

  procedure AddResourceRow(const Text : string; BarRow : Integer);
  begin
    Lines.Add(PadToWidth(Text, ContentW, BG_PANEL) + ANSI_RESET
            + BG_PANEL + ScrollThumbChar(ResScroll, ResMaxScroll, ResBodyH,
                BarRow) + ANSI_RESET);
  end;

  procedure AddSessionsRow(const Text : string; BarRow : Integer);
  begin
    Lines.Add(PadToWidth(Text, ContentW, BG_PANEL) + ANSI_RESET
            + BG_PANEL + ScrollThumbChar(SesScroll, SesMaxScroll, SesBodyH,
                BarRow) + ANSI_RESET);
  end;

begin
  Lines := TList<string>.Create;
  Vis := TList<Integer>.Create;
  SessRowText := TList<string>.Create;
  SessRowSess := TList<Integer>.Create;
  SessTitleRowsArr := TList<Integer>.Create;
  SessTitleIdxArr  := TList<Integer>.Create;
  try
    ContentW := ColLeft - 1;
    ResBodyH := LeftSplitRow - 2;
    if ResBodyH < 0 then ResBodyH := 0;
    SesBodyH := ContentHeight - LeftSplitRow - 3;
    if SesBodyH < 0 then SesBodyH := 0;

    Visible := ComputeTreeVisibility;
    ResMaxScroll := Length(Visible) - ResBodyH;
    if ResMaxScroll < 0 then ResMaxScroll := 0;
    if ResScroll > ResMaxScroll then ResScroll := ResMaxScroll;
    if ResScroll < 0 then ResScroll := 0;

    { v0.40: sessies zonder indent, wel blauw bij active. }
    for I := 0 to SessionList.Count - 1 do
    begin
      Session := SessionList[I];
      if OPT_SHOW_SESSION_ARROWS then
        SessionTitle := GLYPH_RTRI + ' ' + Session.Name
      else
        SessionTitle := Session.Name;
      MetaStr := ' (' + Session.Meta + ')';

      if I = ActiveSessionIndex then
        SessTitleBuf := BG_PANEL + FG_CYAN + ANSI_BOLD + SessionTitle
      else
        SessTitleBuf := BG_PANEL + FG_TEXT + SessionTitle;

      if VisibleLength(SessionTitle) + Length(MetaStr) + 2 <= ContentW then
      begin
        SessRowText.Add(SessTitleBuf + FG_GRAY + MetaStr);
        SessRowSess.Add(I);
      end
      else
      begin
        SessRowText.Add(SessTitleBuf);
        SessRowSess.Add(I);
        SessRowText.Add(BG_PANEL + FG_GRAY + Session.Meta);
        SessRowSess.Add(-1);
      end;
    end;
    TotalSessLines := SessRowText.Count;
    SesMaxScroll := TotalSessLines - SesBodyH;
    if SesMaxScroll < 0 then SesMaxScroll := 0;
    if SesScroll > SesMaxScroll then SesScroll := SesMaxScroll;
    if SesScroll < 0 then SesScroll := 0;

    if OPT_SHOW_DIAMONDS then TitleText := ' ' + GLYPH_FDIAMOND + ' RESOURCES'
    else TitleText := ' RESOURCES';
    Lines.Add(PadToWidth(BG_PANEL + FG_CYAN + ANSI_BOLD + TitleText,
      ContentW, BG_PANEL) + ANSI_RESET + BG_PANEL + ' ' + ANSI_RESET);
    Lines.Add(PadToWidth(BG_PANEL + FG_BORDER + ' ' + RepeatChar(GLYPH_HORZ, ContentW - 1),
      ContentW, BG_PANEL) + ANSI_RESET + BG_PANEL + ' ' + ANSI_RESET);
    RowUsed := 2;

    I := ResScroll;
    while RowUsed < LeftSplitRow do
    begin
      if I < Length(Visible) then
      begin
        Item := TreeList[Visible[I]];
        Indent := 1 + Item.Depth * 2;
        NameWidth := ContentW - Indent - 8;
        if NameWidth < 4 then NameWidth := 4;

        if Item.Perm = '' then
        begin
          if Item.Expanded then Arrow := GLYPH_DTRI else Arrow := GLYPH_RTRI;
          if OPT_SHOW_RESOURCE_ARROWS then
            Buf := BG_PANEL + FG_CYAN + StringOfChar(' ', Indent)
                 + FG_CYAN + Arrow + ' ' + ANSI_BOLD + Item.Name
          else
            Buf := BG_PANEL + FG_CYAN + StringOfChar(' ', Indent)
                 + ANSI_BOLD + Item.Name;
        end
        else
        begin
          if Item.Perm = 'RWX' then PermColor := FG_CYAN
          else if Item.Perm = 'RW' then PermColor := FG_AMBER
          else PermColor := FG_GRAY;
          NameField := Item.Name;
          if Length(NameField) > NameWidth then NameField := Copy(NameField, 1, NameWidth);
          NameField := NameField + StringOfChar(' ', NameWidth - Length(NameField));
          if OPT_SHOW_RESOURCE_ARROWS then
            Buf := BG_PANEL + StringOfChar(' ', Indent) + FG_TEXT + GLYPH_RTRI + ' '
                 + NameField + ' ' + PermColor + Item.Perm
          else
            Buf := BG_PANEL + StringOfChar(' ', Indent) + FG_TEXT
                 + NameField + ' ' + PermColor + Item.Perm;
        end;
        AddResourceRow(Buf, RowUsed - 2);
        Vis.Add(4 + RowUsed);
        Inc(I);
      end
      else
        AddResourceRow(BG_PANEL, RowUsed - 2);
      Inc(RowUsed);
    end;

    SetLength(TreeVisibleRows, Vis.Count);
    for I := 0 to Vis.Count - 1 do TreeVisibleRows[I] := Vis[I];
    SetLength(TreeVisibleIdx, Vis.Count);
    for I := 0 to Vis.Count - 1 do TreeVisibleIdx[I] := Visible[I + ResScroll];

    if (HoverTarget = 11) or (IsDragging and (DragTarget = 11)) then
      DividerCol := FG_CYAN else DividerCol := FG_BORDER;
    Lines.Add(BG_PANEL + DividerCol + RepeatChar(GLYPH_HORZ, ColLeft) + ANSI_RESET);
    Inc(RowUsed);

    if OPT_SHOW_DIAMONDS then TitleText := ' ' + GLYPH_FDIAMOND + ' SESSIONS'
    else TitleText := ' SESSIONS';
    Lines.Add(PadToWidth(BG_PANEL + FG_CYAN + ANSI_BOLD + TitleText,
      ContentW, BG_PANEL) + ANSI_RESET + BG_PANEL + ' ' + ANSI_RESET);
    Lines.Add(PadToWidth(BG_PANEL + FG_BORDER + ' ' + RepeatChar(GLYPH_HORZ, ContentW - 1),
      ContentW, BG_PANEL) + ANSI_RESET + BG_PANEL + ' ' + ANSI_RESET);
    RowUsed := RowUsed + 2;

    I := SesScroll;
    while RowUsed < ContentHeight do
    begin
      if I < TotalSessLines then
      begin
        if SessRowSess[I] >= 0 then
        begin
          SessTitleRowsArr.Add(4 + RowUsed);
          SessTitleIdxArr.Add(SessRowSess[I]);
        end;
        AddSessionsRow(SessRowText[I], RowUsed - LeftSplitRow - 3);
        Inc(I);
      end
      else
        AddSessionsRow(BG_PANEL, RowUsed - LeftSplitRow - 3);
      Inc(RowUsed);
    end;

    SetLength(SessionTitleRows, SessTitleRowsArr.Count);
    for I := 0 to SessTitleRowsArr.Count - 1 do
      SessionTitleRows[I] := SessTitleRowsArr[I];
    SetLength(SessionIdxAtRow, SessTitleIdxArr.Count);
    for I := 0 to SessTitleIdxArr.Count - 1 do
      SessionIdxAtRow[I] := SessTitleIdxArr[I];

    while Lines.Count < ContentHeight do
      AddSessionsRow(BG_PANEL, Lines.Count - LeftSplitRow - 3);

    SetLength(Result, Lines.Count);
    for I := 0 to Lines.Count - 1 do Result[I] := Lines[I];
  finally
    Lines.Free; Vis.Free;
    SessRowText.Free; SessRowSess.Free;
    SessTitleRowsArr.Free; SessTitleIdxArr.Free;
  end;
end;

function ChatBarX : Integer;
begin
  if ShowLeftPanel then Result := ColLeft + ColCenter + 2
  else Result := ColCenter + 1;
end;

function ChatBodyLeftX : Integer;
begin
  if ShowLeftPanel then Result := ColLeft + 3
  else Result := 3;
end;

{ v0.40: chat header is vast — niet scrollbaar. Body wordt alleen gescrold. }
function RenderCenterPane : TArray<string>;
var
  Vis, Full : TList<string>;
  PlainList : TList<string>;
  KindList  : TList<Integer>;
  I, J, Total, WS, WE, BodyH, RightPad : Integer;
  Msg : TChatMessage; Wrapped : TArray<string>;
  Buf, Plain, SenderColor, Prefix, TimePart, Header : string;
  BodyW : Integer;
  S1, S2 : Integer;
  R1, R2, C1, C2, TmpI : Integer;

  function EffectiveSelForLine(Row : Integer; out A, B : Integer) : Boolean;
  begin
    Result := False; A := 0; B := 0;
    if not SelActive then Exit;
    R1 := SelAnchorRow; C1 := SelAnchorCol;
    R2 := SelFocusRow;  C2 := SelFocusCol;
    if (R1 > R2) or ((R1 = R2) and (C1 > C2)) then
    begin TmpI := R1; R1 := R2; R2 := TmpI; TmpI := C1; C1 := C2; C2 := TmpI; end;
    if (Row < R1) or (Row > R2) then Exit;
    if R1 = R2 then begin A := C1; B := C2; end
    else if Row = R1 then begin A := C1; B := Length(PlainList[Row]); end
    else if Row = R2 then begin A := 0; B := C2; end
    else begin A := 0; B := Length(PlainList[Row]); end;
    Result := True;
  end;

begin
  Vis := TList<string>.Create;
  Full := TList<string>.Create;
  PlainList := TList<string>.Create;
  KindList := TList<Integer>.Create;
  try
    BodyW := ColCenter - 1;
    BodyH := ContentHeight - 2;
    if BodyH < 1 then BodyH := 1;

    if OPT_SHOW_DIAMONDS then
      Header := BG_MAIN + ' ' + FG_CYAN + ANSI_BOLD + GLYPH_FDIAMOND + ' CHAT'
              + ANSI_RESET + BG_MAIN + FG_DGRAY + ' - ' + FG_TEXT + CurrentSessionName
    else
      Header := BG_MAIN + ' ' + FG_CYAN + ANSI_BOLD + 'CHAT'
              + ANSI_RESET + BG_MAIN + FG_DGRAY + ' - ' + FG_TEXT + CurrentSessionName;
    if ChatScroll > 0 then
      Header := Header + ANSI_RESET + BG_MAIN + '  ' + FG_AMBER + GLYPH_UP
              + ' +' + IntToStr(ChatScroll);

    { Header + divider worden ALTIJD gerenderd, buiten scroll. }
    Vis.Add(PadToWidth(Header, BodyW, BG_MAIN) + ANSI_RESET + BG_MAIN + ' ' + ANSI_RESET);
    Vis.Add(PadToWidth(BG_MAIN + ' ' + FG_BORDER + RepeatChar(GLYPH_HORZ, BodyW - 1),
      BodyW, BG_MAIN) + ANSI_RESET + BG_MAIN + ' ' + ANSI_RESET);

    { Body opbouwen }
    for I := 0 to ChatMessages.Count - 1 do
    begin
      Msg := ChatMessages[I];
      case Msg.Role of
        crUser: begin SenderColor := FG_USER + ANSI_BOLD; Prefix := ' You'; end;
        crAssistant: begin SenderColor := FG_CYAN + ANSI_BOLD;
                          if OPT_SHOW_DIAMONDS then
                            Prefix := ' ' + GLYPH_DIAMOND + ' GRISP Assistant'
                          else
                            Prefix := ' GRISP Assistant'; end;
        else begin SenderColor := FG_AMBER + ANSI_BOLD; Prefix := ' [sys]'; end;
      end;

      { v0.40: gebruik volledige timestamp als er ruimte is. }
      if OPT_SHOW_CHAT_DATE and (BodyW >= 70) then
        TimePart := '[' + Msg.FullStamp + ']'
      else if OPT_SHOW_CHAT_DATE and (BodyW >= 45) then
        TimePart := '[' + Msg.Date + ' ' + Msg.Time + ']'
      else if BodyW >= 30 then
        TimePart := '[' + Msg.Date + ' ' + Msg.Time + ']'
      else
        TimePart := '[' + Msg.Time + ']';

      Buf := BG_MAIN + SenderColor + Prefix;
      RightPad := BodyW - 2 - VisibleLength(Buf) - Length(TimePart);
      if RightPad < 1 then RightPad := 1;
      Buf := Buf + StringOfChar(' ', RightPad) + FG_DGRAY + TimePart + ' ';
      Full.Add(Buf);
      PlainList.Add(StripAnsi(Buf));
      KindList.Add(6);

      Wrapped := WrapParagraph(Msg.Text, BodyW - 4);
      for J := 0 to High(Wrapped) do
      begin
        case Msg.Role of
          crUser:
            begin
              Plain := '  ' + Wrapped[J] + '  ';
              Full.Add(BG_MAIN + '  ' + BG_USER + FG_TEXT + Wrapped[J] + '  '
                     + ANSI_RESET + BG_MAIN);
              KindList.Add(2);
            end;
          crAssistant:
            begin
              Plain := '  ' + Wrapped[J] + '  ';
              Full.Add(BG_MAIN + '  ' + BG_AI + FG_TEXT + Wrapped[J] + '  '
                     + ANSI_RESET + BG_MAIN);
              KindList.Add(3);
            end;
          else
            begin
              Plain := '    ' + Wrapped[J];
              Full.Add(BG_MAIN + '    ' + FG_GRAY + Wrapped[J]);
              KindList.Add(4);
            end;
        end;
        PlainList.Add(Plain);
      end;

      Full.Add(BG_MAIN);
      PlainList.Add('');
      KindList.Add(5);
    end;

    SetLength(ChatFullPlain, PlainList.Count);
    for I := 0 to PlainList.Count - 1 do ChatFullPlain[I] := PlainList[I];
    SetLength(ChatFullKind, KindList.Count);
    for I := 0 to KindList.Count - 1 do ChatFullKind[I] := KindList[I];

    Total := Full.Count;
    if Total > BodyH then ChatMaxScroll := Total - BodyH else ChatMaxScroll := 0;
    if ChatScroll > ChatMaxScroll then ChatScroll := ChatMaxScroll;
    if ChatScroll < 0 then ChatScroll := 0;
    WE := Total - ChatScroll; if WE < 0 then WE := 0;
    WS := WE - BodyH; if WS < 0 then WS := 0;

    ChatWindowStart := WS;

    { Body rijen — scrollen. }
    for I := 0 to BodyH - 1 do
    begin
      if (WS + I) < Full.Count then
      begin
        if EffectiveSelForLine(WS + I, S1, S2) then
        begin
          case ChatFullKind[WS + I] of
            2: Buf := RenderLineWithSelection(ChatFullPlain[WS + I], 2, BG_USER, S1, S2);
            3: Buf := RenderLineWithSelection(ChatFullPlain[WS + I], 2, BG_AI, S1, S2);
            4: Buf := RenderLineWithSelection(ChatFullPlain[WS + I], 4, BG_MAIN, S1, S2);
            6: Buf := RenderLineWithSelection(ChatFullPlain[WS + I], 0, BG_MAIN, S1, S2);
            else Buf := Full[WS + I];
          end;
          Vis.Add(PadToWidth(Buf, BodyW, BG_MAIN) + ANSI_RESET
                + BG_MAIN + ChatThumbChar(ChatScroll, ChatMaxScroll, BodyH,
                    I) + ANSI_RESET);
        end
        else
          Vis.Add(PadToWidth(Full[WS + I], BodyW, BG_MAIN) + ANSI_RESET
                + BG_MAIN + ChatThumbChar(ChatScroll, ChatMaxScroll, BodyH,
                    I) + ANSI_RESET);
      end
      else
        Vis.Add(PadToWidth(BG_MAIN, BodyW, BG_MAIN) + ANSI_RESET
              + BG_MAIN + ChatThumbChar(ChatScroll, ChatMaxScroll, BodyH,
                  I) + ANSI_RESET);
    end;

    { Zorg dat we exact ContentHeight regels hebben. }
    while Vis.Count < ContentHeight do
      Vis.Add(PadToWidth(BG_MAIN, BodyW, BG_MAIN) + ANSI_RESET
            + BG_MAIN + ' ' + ANSI_RESET);

    SetLength(Result, Vis.Count);
    for I := 0 to Vis.Count - 1 do Result[I] := Vis[I];
  finally
    Vis.Free; Full.Free; PlainList.Free; KindList.Free;
  end;
end;

function RenderRightPane : TArray<string>;
var
  Lines : TList<string>; I, ThinkRows, Div1, Div2, BodyW : Integer;
  Buf, Sym, SymCol, PrioCol, PrioLabel, DivCol1, DivCol2, TitleText, WorkLine : string;
  Plan : TPlanItem; Work : TWorkItem;
  PlanBodyH, WorkBodyH, ThinkBodyH : Integer;
  PlanRowUsed, WorkRowUsed, ThinkRowUsed : Integer;

  procedure AddLine(const S : string; BarRow : Integer; const BarKind : Char);
  begin
    case BarKind of
      'P': Lines.Add(PadToWidth(S, BodyW, BG_PANEL) + ANSI_RESET
                    + BG_PANEL + ScrollThumbChar(PlanScroll, PlanMaxScroll,
                        PlanBodyH, BarRow) + ANSI_RESET);
      'W': Lines.Add(PadToWidth(S, BodyW, BG_PANEL) + ANSI_RESET
                    + BG_PANEL + ScrollThumbChar(WorkScroll, WorkMaxScroll,
                        WorkBodyH, BarRow) + ANSI_RESET);
      'T': Lines.Add(PadToWidth(S, BodyW, BG_PANEL) + ANSI_RESET
                    + BG_PANEL + ScrollThumbChar(ThinkScroll, ThinkMaxScroll,
                        ThinkBodyH, BarRow) + ANSI_RESET);
      else Lines.Add(PadToWidth(S, BodyW, BG_PANEL) + ANSI_RESET
                    + BG_PANEL + ' ' + ANSI_RESET);
    end;
  end;

begin
  Lines := TList<string>.Create;
  try
    BodyW := ColRight - 1;

    ThinkRows := ContentHeight - 2 - RightPlanRows - RightWorkRows;
    if ThinkRows < 3 then ThinkRows := 3;
    Div1 := RightPlanRows;
    Div2 := RightPlanRows + 1 + RightWorkRows;

    PlanBodyH  := RightPlanRows - 2;    if PlanBodyH  < 0 then PlanBodyH := 0;
    WorkBodyH  := RightWorkRows - 2;    if WorkBodyH  < 0 then WorkBodyH := 0;
    ThinkBodyH := ThinkRows - 2;        if ThinkBodyH < 0 then ThinkBodyH := 0;

    if (HoverTarget = 12) or (IsDragging and (DragTarget = 12)) then
      DivCol1 := FG_CYAN else DivCol1 := FG_BORDER;
    if (HoverTarget = 13) or (IsDragging and (DragTarget = 13)) then
      DivCol2 := FG_CYAN else DivCol2 := FG_BORDER;

    if OPT_SHOW_DIAMONDS then TitleText := ' ' + GLYPH_FDIAMOND + ' CURRENT PLAN'
    else TitleText := ' CURRENT PLAN';
    AddLine(BG_PANEL + FG_CYAN + ANSI_BOLD + TitleText, 0, 'X');
    AddLine(BG_PANEL + FG_BORDER + ' ' + RepeatChar(GLYPH_HORZ, BodyW - 1), 0, 'X');

    PlanMaxScroll := PlanItems.Count - PlanBodyH;
    if PlanMaxScroll < 0 then PlanMaxScroll := 0;
    if PlanScroll > PlanMaxScroll then PlanScroll := PlanMaxScroll;
    if PlanScroll < 0 then PlanScroll := 0;

    PlanRowUsed := 0; I := PlanScroll;
    while PlanRowUsed < PlanBodyH do
    begin
      if I < PlanItems.Count then
      begin
        Plan := PlanItems[I];
        case Plan.Status of
          psDone:    begin Sym := GLYPH_CHECKED;   SymCol := FG_GREEN; end;
          psRunning: begin Sym := GLYPH_PTRI;      SymCol := FG_AMBER; end;
          else       begin Sym := GLYPH_UNCHECKED; SymCol := FG_DGRAY; end;
        end;
        Buf := BG_PANEL + ' ' + SymCol + Sym + ' ' + FG_TEXT + Plan.Text;
      end else Buf := BG_PANEL;
      AddLine(Buf, PlanRowUsed, 'P');
      Inc(PlanRowUsed); Inc(I);
    end;
    while Lines.Count < Div1 do begin AddLine(BG_PANEL, PlanRowUsed, 'P'); Inc(PlanRowUsed); end;

    Lines.Add(DivCol1 + RepeatChar(GLYPH_HORZ, ColRight) + ANSI_RESET);

    if OPT_SHOW_DIAMONDS then TitleText := ' ' + GLYPH_FDIAMOND + ' WORK ITEMS'
    else TitleText := ' WORK ITEMS';
    AddLine(BG_PANEL + FG_CYAN + ANSI_BOLD + TitleText, 0, 'X');
    AddLine(BG_PANEL + FG_BORDER + ' ' + RepeatChar(GLYPH_HORZ, BodyW - 1), 0, 'X');

    WorkMaxScroll := WorkItems.Count - WorkBodyH;
    if WorkMaxScroll < 0 then WorkMaxScroll := 0;
    if WorkScroll > WorkMaxScroll then WorkScroll := WorkMaxScroll;
    if WorkScroll < 0 then WorkScroll := 0;

    WorkRowUsed := 0; I := WorkScroll;
    while WorkRowUsed < WorkBodyH do
    begin
      if I < WorkItems.Count then
      begin
        Work := WorkItems[I];
        case Work.Prio of
          wpHigh:   begin PrioCol := FG_RED;   PrioLabel := '[HIGH]'; end;
          wpMedium: begin PrioCol := FG_AMBER; PrioLabel := '[MED ]'; end;
          else      begin PrioCol := FG_GREEN; PrioLabel := '[LOW ]'; end;
        end;
        if OPT_SHOW_PRIORITY_LABELS then
          WorkLine := BG_PANEL + ' ' + FG_TEXT + Work.Text + '  ' + PrioCol + PrioLabel
        else
          WorkLine := BG_PANEL + ' ' + PrioCol + Work.Text;
        Buf := WorkLine;
      end else Buf := BG_PANEL;
      AddLine(Buf, WorkRowUsed, 'W');
      Inc(WorkRowUsed); Inc(I);
    end;
    while Lines.Count < Div2 do begin AddLine(BG_PANEL, WorkRowUsed, 'W'); Inc(WorkRowUsed); end;

    Lines.Add(DivCol2 + RepeatChar(GLYPH_HORZ, ColRight) + ANSI_RESET);

    if OPT_SHOW_DIAMONDS then TitleText := ' ' + GLYPH_FDIAMOND + ' THINKING'
    else TitleText := ' THINKING';
    if ShowThinking then
      AddLine(BG_PANEL + FG_PURPLE + ANSI_BOLD + TitleText + '  ' + FG_DGRAY + '[F3]', 0, 'X')
    else
      AddLine(BG_PANEL + FG_DGRAY + TitleText + '  [F3 - hidden]', 0, 'X');
    AddLine(BG_PANEL + FG_BORDER + ' ' + RepeatChar(GLYPH_HORZ, BodyW - 1), 0, 'X');

    ThinkMaxScroll := ThinkingLines.Count - ThinkBodyH;
    if ThinkMaxScroll < 0 then ThinkMaxScroll := 0;
    if ThinkScroll > ThinkMaxScroll then ThinkScroll := ThinkMaxScroll;
    if ThinkScroll < 0 then ThinkScroll := 0;

    ThinkRowUsed := 0; I := ThinkScroll;
    while ThinkRowUsed < ThinkBodyH do
    begin
      if ShowThinking and (I < ThinkingLines.Count) then
        Buf := BG_PANEL + ' ' + FG_BORDER + GLYPH_GT + ' ' + FG_GRAY + ThinkingLines[I]
      else Buf := BG_PANEL;
      AddLine(Buf, ThinkRowUsed, 'T');
      Inc(ThinkRowUsed); Inc(I);
    end;

    while Lines.Count < ContentHeight do
    begin AddLine(BG_PANEL, ThinkRowUsed, 'T'); Inc(ThinkRowUsed); end;

    SetLength(Result, Lines.Count);
    for I := 0 to Lines.Count - 1 do Result[I] := Lines[I];
  finally Lines.Free; end;
end;

{ ============================================================================
  Top bar — v0.40: compact, geen overlap, optionele brackets.
  ============================================================================ }

function FKeyPlain(K, Lbl : string) : string;
begin
  if OPT_SHOW_KEY_BRACKETS then
    Result := '[' + K + ']' + Lbl
  else
    Result := K + ' ' + Lbl;
end;

function XBtnText : string;
begin
  if OPT_SHOW_X_BRACKETS then Result := '[X]' else Result := 'X';
end;

function TopBarFKeyText(ParaIndex: Integer) : string;
begin
  case ParaIndex of
    1: Result := FKeyPlain('F1', 'Left');
    2: Result := FKeyPlain('F2', 'Right');
    3: Result := FKeyPlain('F3', 'Think');
    4: Result := FKeyPlain('F4', 'Step');
    5: Result := FKeyPlain('F5', 'Mouse');
    6: Result := FKeyPlain('F6', 'Reset');
    else Result := '';
  end;
end;

function TopBarExtraText(ParaIndex: Integer) : string;
begin
  case ParaIndex of
    1: Result := FKeyPlain('Ctrl+Enter', 'Send');
    2: Result := FKeyPlain('Ctrl+C',     'Copy');
    3: Result := FKeyPlain('Esc',        'Quit');
    else Result := '';
  end;
end;

function StyleTopBarSegment(const ParaText: string; ParaHot: Boolean) : string;
var
  SepPos, KeyEnd, LabelStart : Integer;
  KeyColor, TextColor : string;
begin
  if ParaHot then
  begin KeyColor := FG_CYAN + ANSI_BOLD; TextColor := FG_TEXT + ANSI_BOLD; end
  else
  begin KeyColor := FG_CYAN; TextColor := FG_TEXT; end;

  if OPT_SHOW_KEY_BRACKETS then
  begin
    SepPos := Pos(']', ParaText);
    if SepPos > 0 then
      Result := KeyColor + Copy(ParaText, 1, SepPos)
              + TextColor + Copy(ParaText, SepPos + 1, MaxInt)
              + ANSI_RESET + BG_BAR
    else Result := TextColor + ParaText + ANSI_RESET + BG_BAR;
  end
  else
  begin
    SepPos := Pos(' ', ParaText);
    if SepPos > 0 then
    begin
      KeyEnd := SepPos - 1;
      LabelStart := SepPos + 1;
      Result := KeyColor + Copy(ParaText, 1, KeyEnd)
              + TextColor + ' ' + Copy(ParaText, LabelStart, MaxInt)
              + ANSI_RESET + BG_BAR;
    end
    else Result := TextColor + ParaText + ANSI_RESET + BG_BAR;
  end;
end;

{ v0.40: dynamische topbar. Retourneert per segment wat past. }
procedure ComputeTopBar(
  out Title : string;
  out FKeys : TArray<string>;
  out Extras : TArray<string>;
  out ClockStr : string;
  out XBtn : string;
  out TitleW, FKeyStart, ExtraStart, CloseStart : Integer);
var
  I, TotalW, AvailW, ClockW, XW : Integer;
  Candidates : array[0..8] of string;
  TitleText : string;
  IncludeTitle : Boolean;
begin
  if OPT_SHOW_DIAMONDS then
    TitleText := GLYPH_DIAMOND + ' ' + APP_NAME + ' ' + APP_VERSION
  else
    TitleText := APP_NAME + ' ' + APP_VERSION;

  IncludeTitle := True;

  if ScreenWidth < 80 then
    ClockStr := FormatDateTime('hh:nn', Now)
  else
    ClockStr := CurrentLongTime;

  ClockW := VisibleLength(ClockStr);
  XBtn := XBtnText;
  XW := VisibleLength(XBtn);

  { Layout rechterkant: clock + ' ' + X }
  CloseStart := ScreenWidth - 1 - XW + 1;   { kolom waar X begint }

  { Beschikbare ruimte voor titel + F-keys + extras }
  AvailW := ScreenWidth - 2 - ClockW - XW - 2;   { -2 voor 2 spaties tussen }

  for I := 1 to 6 do Candidates[I-1] := TopBarFKeyText(I);
  for I := 1 to 3 do Candidates[5+I] := TopBarExtraText(I);

  SetLength(FKeys, 0);
  SetLength(Extras, 0);

  { Titel als eerste — maar kan later wegvallen als er te weinig ruimte is. }
  Title := ' ' + TitleText;   { 1 spatie links }
  TitleW := VisibleLength(Title);
  TotalW := TitleW;

  { Voeg F-keys toe }
  for I := 0 to 5 do
  begin
    if TotalW + 1 + VisibleLength(Candidates[I]) <= AvailW then
    begin
      Inc(TotalW, 1 + VisibleLength(Candidates[I]));
      SetLength(FKeys, Length(FKeys) + 1);
      FKeys[High(FKeys)] := Candidates[I];
    end
    else Break;
  end;

  { Voeg extras toe }
  for I := 6 to 8 do
  begin
    if TotalW + 1 + VisibleLength(Candidates[I]) <= AvailW then
    begin
      Inc(TotalW, 1 + VisibleLength(Candidates[I]));
      SetLength(Extras, Length(Extras) + 1);
      Extras[High(Extras)] := Candidates[I];
    end
    else Break;
  end;

  FKeyStart := 2 + TitleW + 1;
  ExtraStart := FKeyStart + VisibleLength(FKeys[0]) + 1;   { zal per frame herzien worden }
  if Length(FKeys) = 0 then
  begin
    ExtraStart := FKeyStart;
  end
  else
  begin
    ExtraStart := FKeyStart;
    for I := 0 to High(FKeys) do
      ExtraStart := ExtraStart + VisibleLength(FKeys[I]) + 1;
  end;

  { Titel mag niet wegvallen tenzij we echt geen ruimte hebben. }
  if not IncludeTitle and (TotalW + 1 + TitleW <= AvailW) then
  begin
    Title := ' ' + TitleText;
    TitleW := VisibleLength(Title);
  end;
end;

function TopBarActionAt(ParaX, ParaY : Integer) : Integer;
var
  Title, ClockStr, XBtn : string;
  FKeys, Extras : TArray<string>;
  TitleW, FKeyStart, ExtraStart, CloseStart, I, XStart, XEnd : Integer;
begin
  Result := 0;
  if ParaY <> 2 then Exit;

  ComputeTopBar(Title, FKeys, Extras, ClockStr, XBtn, TitleW, FKeyStart, ExtraStart, CloseStart);

  if (ParaX >= CloseStart) and (ParaX <= CloseStart + Length(XBtn) - 1) then
  begin Result := 10; Exit; end;

  XStart := FKeyStart;
  for I := 0 to High(FKeys) do
  begin
    XEnd := XStart + VisibleLength(FKeys[I]) - 1;
    if (ParaX >= XStart) and (ParaX <= XEnd) then
    begin Result := I + 1; Exit; end;
    XStart := XEnd + 2;
  end;

  XStart := ExtraStart;
  for I := 0 to High(Extras) do
  begin
    XEnd := XStart + VisibleLength(Extras[I]) - 1;
    if (ParaX >= XStart) and (ParaX <= XEnd) then
    begin Result := 7 + I; Exit; end;
    XStart := XEnd + 2;
  end;
end;

{ ============================================================================
  Exit dialog
  ============================================================================ }

function ExitDialogWidth : Integer;
begin
  Result := 50;
  if Result > ScreenWidth - 4 then Result := ScreenWidth - 4;
  if Result < 34 then Result := 34;
end;

function ExitDialogHeight : Integer;
begin Result := 7; end;

function ExitDialogTop : Integer;
begin
  Result := (ScreenHeight - ExitDialogHeight) div 2 + 1;
  if Result < 3 then Result := 3;
end;

function ExitDialogLeft : Integer;
begin Result := (ScreenWidth - ExitDialogWidth) div 2 + 1; end;

function ExitDialogButtonAt(ParaX, ParaY : Integer) : Integer;
var W, L, T, PadL, RelX : Integer;
begin
  Result := 0;
  W := ExitDialogWidth;
  L := ExitDialogLeft;
  T := ExitDialogTop;
  PadL := 4;
  if ParaY <> T + 4 then Exit;
  RelX := ParaX - L - 1 - PadL;
  if (RelX >= 0) and (RelX <= 6) then Result := 1
  else if (RelX >= 11) and (RelX <= 16) then Result := 2
  else if (RelX >= 21) and (RelX <= 35) then Result := 3;
end;

procedure RequestExit;
begin
  IsDragging := False; DragTarget := 0; HoverTarget := 0;
  CurrentMouseShape := msArrow;
  ExitDialogVisible := True;
  NeedsRedraw := True;
end;

procedure CancelExit;
begin
  ExitDialogVisible := False; HoverTarget := 0;
  NeedsRedraw := True;
end;

procedure ConfirmExit;
begin
  ExitDialogVisible := False;
  QuitRequested := True;
end;

procedure AppendAt(const SB: TStringBuilder; ParaX, ParaY : Integer;
  const ParaText : string);
begin
  SB.Append(ESC + '[' + IntToStr(ParaY) + ';' + IntToStr(ParaX) + 'H' + ParaText);
end;

function RenderExitDialogOverlay : string;
var
  SB : TStringBuilder;
  W, H, L, T, InnerW, PadL : Integer;
  YesBtn, NoBtn, CancelBtn, ButtonRow, Blank : string;
  YesHot, NoHot, CancelHot : Boolean;
begin
  SB := TStringBuilder.Create;
  try
    W := ExitDialogWidth; H := ExitDialogHeight;
    L := ExitDialogLeft; T := ExitDialogTop;
    InnerW := W - 2; PadL := 4;

    YesHot := (HoverTarget = 61);
    NoHot := (HoverTarget = 62);
    CancelHot := (HoverTarget = 63);

    Blank := BG_PANEL + StringOfChar(' ', InnerW) + ANSI_RESET;

    AppendAt(SB, L, T,
      BG_PANEL + FG_BORDER + GLYPH_TOPLEFT
      + RepeatChar(GLYPH_HORZ, InnerW) + GLYPH_TOPRIGHT + ANSI_RESET);

    AppendAt(SB, L, T + 1,
      BG_PANEL + FG_BORDER + GLYPH_VERT + ANSI_RESET
      + PadToWidth(BG_PANEL + '  ' + FG_RED + ANSI_BOLD + 'Exit GRISP OS ?',
                   InnerW, BG_PANEL)
      + ANSI_RESET + BG_PANEL + FG_BORDER + GLYPH_VERT + ANSI_RESET);

    AppendAt(SB, L, T + 2,
      BG_PANEL + FG_BORDER + GLYPH_VERT + ANSI_RESET
      + Blank + BG_PANEL + FG_BORDER + GLYPH_VERT + ANSI_RESET);

    AppendAt(SB, L, T + 3,
      BG_PANEL + FG_BORDER + GLYPH_VERT + ANSI_RESET
      + Blank + BG_PANEL + FG_BORDER + GLYPH_VERT + ANSI_RESET);

    if YesHot then
      YesBtn := BG_SELECT + FG_TEXT + ANSI_BOLD + '(Y/y)es' + ANSI_RESET + BG_PANEL
    else YesBtn := FG_GREEN + ANSI_BOLD + '(Y/y)es' + ANSI_RESET + BG_PANEL;
    if NoHot then
      NoBtn := BG_SELECT + FG_TEXT + ANSI_BOLD + '(N/n)o' + ANSI_RESET + BG_PANEL
    else NoBtn := FG_CYAN + ANSI_BOLD + '(N/n)o' + ANSI_RESET + BG_PANEL;
    if CancelHot then
      CancelBtn := BG_SELECT + FG_TEXT + ANSI_BOLD + '(ESC/C/c/)ancel' + ANSI_RESET + BG_PANEL
    else CancelBtn := FG_AMBER + ANSI_BOLD + '(ESC/C/c/)ancel' + ANSI_RESET + BG_PANEL;

    ButtonRow := BG_PANEL + StringOfChar(' ', PadL)
               + YesBtn + StringOfChar(' ', 4)
               + NoBtn + StringOfChar(' ', 4)
               + CancelBtn;

    AppendAt(SB, L, T + 4,
      BG_PANEL + FG_BORDER + GLYPH_VERT + ANSI_RESET
      + PadToWidth(ButtonRow, InnerW, BG_PANEL)
      + ANSI_RESET + BG_PANEL + FG_BORDER + GLYPH_VERT + ANSI_RESET);

    AppendAt(SB, L, T + 5,
      BG_PANEL + FG_BORDER + GLYPH_VERT + ANSI_RESET
      + Blank + BG_PANEL + FG_BORDER + GLYPH_VERT + ANSI_RESET);

    AppendAt(SB, L, T + H - 1,
      BG_PANEL + FG_BORDER + GLYPH_BOTLEFT
      + RepeatChar(GLYPH_HORZ, InnerW) + GLYPH_BOTRIGHT + ANSI_RESET);

    Result := SB.ToString;
  finally SB.Free; end;
end;

function RenderFrame : string;
var
  SB : TStringBuilder;
  LeftPane, CenterPane, RightPane : TArray<string>;
  InputLines : TArray<TVisualLine>;
  I, RowIndex, CaretRow, CaretCol, VisRow, VisCol : Integer;
  MaxScroll, FirstInputRow : Integer;
  TopBar, SepTop, SepBot, StatusLine, TitleLine : string;
  MouseLabel, ClockStr, CloseColor, SelectionLabel, XBtn : string;
  TopBarFKeys, TopBarExtraKeys : TArray<string>;
  TitleW, TopBarFKeyStart, TopBarExtraStart, TopBarCloseStart : Integer;
  V1Hot, V2Hot, H10Hot : Boolean;
  SepC1, SepC2, SepBotAll, TJLeft, TJRight : string;
  LineText, InputPadded, MainTitle : string;
begin
  SB := TStringBuilder.Create;
  try
    if ExitDialogVisible then SB.Append(ANSI_DIM);
    SB.Append(CURSOR_HIDE);
    SB.Append(CURSOR_HOME);
    SB.Append(ERASE_LINE);

    V1Hot  := (HoverTarget = 1)  or (IsDragging and (DragTarget = 1));
    V2Hot  := (HoverTarget = 2)  or (IsDragging and (DragTarget = 2));
    H10Hot := (HoverTarget = 10) or (IsDragging and (DragTarget = 10));

    if V1Hot then SepC1 := FG_CYAN else SepC1 := FG_BORDER;
    if V2Hot then SepC2 := FG_CYAN else SepC2 := FG_BORDER;
    if V1Hot or H10Hot then TJLeft := FG_CYAN else TJLeft := FG_BORDER;
    if V2Hot or H10Hot then TJRight := FG_CYAN else TJRight := FG_BORDER;

    SB.Append(FG_BORDER + GLYPH_TOPLEFT
            + RepeatChar(GLYPH_HORZ, ScreenWidth - 2)
            + GLYPH_TOPRIGHT + ANSI_RESET + NL);

    ComputeTopBar(MainTitle, TopBarFKeys, TopBarExtraKeys, ClockStr, XBtn,
      TitleW, TopBarFKeyStart, TopBarExtraStart, TopBarCloseStart);

    TopBar := BG_BAR + FG_CYAN + ANSI_BOLD + MainTitle + ANSI_RESET + BG_BAR;
    for I := 0 to High(TopBarFKeys) do
    begin
      TopBar := TopBar + BG_BAR + ' ';
      TopBar := TopBar + StyleTopBarSegment(TopBarFKeys[I], HoverTarget = 40 + I);
    end;
    for I := 0 to High(TopBarExtraKeys) do
    begin
      TopBar := TopBar + BG_BAR + ' ';
      TopBar := TopBar + StyleTopBarSegment(TopBarExtraKeys[I], HoverTarget = 50 + I);
    end;

    { Pad tot er ruimte is voor clock + ' ' + XBtn. }
    TopBar := PadToWidth(TopBar,
      ScreenWidth - 2 - VisibleLength(ClockStr) - VisibleLength(XBtn) - 1, BG_BAR);

    if HoverTarget = 60 then CloseColor := FG_RED + ANSI_BOLD else CloseColor := FG_TEXT;
    TopBar := TopBar + BG_BAR + ' ' + FG_CYAN + ClockStr + ' ' + CloseColor + XBtn + ANSI_RESET;

    SB.Append(FG_BORDER + GLYPH_VERT + ANSI_RESET
            + PadToWidth(TopBar, ScreenWidth - 2, BG_BAR) + ANSI_RESET
            + FG_BORDER + GLYPH_VERT + ANSI_RESET + NL);

    if ShowLeftPanel and ShowRightPanel then
      SepTop := FG_BORDER + GLYPH_TEEEAST + RepeatChar(GLYPH_HORZ, ColLeft)
              + SepC1 + GLYPH_TEEDOWN + ANSI_RESET + FG_BORDER
              + RepeatChar(GLYPH_HORZ, ColCenter)
              + SepC2 + GLYPH_TEEDOWN + ANSI_RESET + FG_BORDER
              + RepeatChar(GLYPH_HORZ, ColRight) + GLYPH_TEEWEST + ANSI_RESET
    else if ShowRightPanel then
      SepTop := FG_BORDER + GLYPH_TEEEAST
              + RepeatChar(GLYPH_HORZ, ScreenWidth - ColRight - 3)
              + SepC2 + GLYPH_TEEDOWN + ANSI_RESET + FG_BORDER
              + RepeatChar(GLYPH_HORZ, ColRight) + GLYPH_TEEWEST + ANSI_RESET
    else if ShowLeftPanel then
      SepTop := FG_BORDER + GLYPH_TEEEAST + RepeatChar(GLYPH_HORZ, ColLeft)
              + SepC1 + GLYPH_TEEDOWN + ANSI_RESET + FG_BORDER
              + RepeatChar(GLYPH_HORZ, ScreenWidth - ColLeft - 3)
              + GLYPH_TEEWEST + ANSI_RESET
    else
      SepTop := FG_BORDER + GLYPH_TEEEAST
              + RepeatChar(GLYPH_HORZ, ScreenWidth - 2) + GLYPH_TEEWEST + ANSI_RESET;
    SB.Append(SepTop + NL);

    if ShowLeftPanel then LeftPane := RenderLeftPane else LeftPane := nil;
    CenterPane := RenderCenterPane;
    if ShowRightPanel then RightPane := RenderRightPane else RightPane := nil;

    for RowIndex := 0 to ContentHeight - 1 do
    begin
      SB.Append(FG_BORDER + GLYPH_VERT + ANSI_RESET);
      if ShowLeftPanel then
      begin
        if RowIndex < Length(LeftPane) then SB.Append(LeftPane[RowIndex])
        else SB.Append(PadToWidth('', ColLeft, BG_PANEL) + ANSI_RESET);
        SB.Append(SepC1 + GLYPH_VERT + ANSI_RESET);
      end;
      if RowIndex < Length(CenterPane) then SB.Append(CenterPane[RowIndex])
      else SB.Append(PadToWidth('', ColCenter - 1, BG_MAIN) + ANSI_RESET
                   + BG_MAIN + ' ' + ANSI_RESET);
      if ShowRightPanel then
      begin
        SB.Append(SepC2 + GLYPH_VERT + ANSI_RESET);
        if RowIndex < Length(RightPane) then SB.Append(RightPane[RowIndex])
        else SB.Append(PadToWidth('', ColRight, BG_PANEL) + ANSI_RESET);
      end;
      SB.Append(FG_BORDER + GLYPH_VERT + ANSI_RESET + NL);
    end;

    if H10Hot then SepBotAll := FG_CYAN else SepBotAll := FG_BORDER;
    if ShowLeftPanel and ShowRightPanel then
      SepBot := SepBotAll + GLYPH_TEEEAST + RepeatChar(GLYPH_HORZ, ColLeft)
              + TJLeft + GLYPH_TEEUP + SepBotAll
              + RepeatChar(GLYPH_HORZ, ColCenter)
              + TJRight + GLYPH_TEEUP + SepBotAll
              + RepeatChar(GLYPH_HORZ, ColRight)
              + GLYPH_TEEWEST + ANSI_RESET
    else
      SepBot := SepBotAll + GLYPH_TEEEAST
              + RepeatChar(GLYPH_HORZ, ScreenWidth - 2)
              + GLYPH_TEEWEST + ANSI_RESET;
    SB.Append(SepBot + NL);

    InputLines := BuildVisualLines(InputBuffer, InputWrapWidth);
    FirstInputRow := 5 + ContentHeight;

    CaretRow := FirstInputRow; CaretCol := 2;
    VisRow := 0; VisCol := 0;

    InputMaxScroll := Length(InputLines) - InputHeight;
    if InputMaxScroll < 0 then InputMaxScroll := 0;
    if InputScroll > InputMaxScroll then InputScroll := InputMaxScroll;
    if InputScroll < 0 then InputScroll := 0;

    if CursorVisualPos(InputLines, InputCursor, VisRow, VisCol) then
    begin
      if VisRow < InputScroll then InputScroll := VisRow;
      if VisRow >= InputScroll + InputHeight then
        InputScroll := VisRow - InputHeight + 1;
      if InputScroll < 0 then InputScroll := 0;
      if InputScroll > InputMaxScroll then InputScroll := InputMaxScroll;
    end;

    for I := 0 to InputHeight - 1 do
    begin
      if (InputScroll + I) < Length(InputLines) then
        LineText := InputLines[InputScroll + I].Text
      else LineText := '';

      if SimActive and (I = 0) then
        InputPadded := PadToWidth(
          BG_INPUT + FG_AMBER + ANSI_BOLD + '... Processing ['
          + PromptState + '] - [Ctrl+Enter] to step',
          ScreenWidth - 3, BG_INPUT)
      else
        InputPadded := PadToWidth(BG_INPUT + FG_TEXT + LineText,
          ScreenWidth - 3, BG_INPUT);

      SB.Append(FG_BORDER + GLYPH_VERT + ANSI_RESET
              + InputPadded + ANSI_RESET
              + BG_INPUT + ScrollThumbChar(InputScroll, InputMaxScroll,
                  InputHeight, I) + ANSI_RESET
              + FG_BORDER + GLYPH_VERT + ANSI_RESET + NL);
    end;

    if not SimActive and not ExitDialogVisible then
    begin
      CaretRow := FirstInputRow + (VisRow - InputScroll);
      CaretCol := 2 + VisCol;
      if CaretCol > ScreenWidth - 2 then CaretCol := ScreenWidth - 2;
      if CaretRow < FirstInputRow then CaretRow := FirstInputRow;
      if CaretRow > FirstInputRow + InputHeight - 1 then
        CaretRow := FirstInputRow + InputHeight - 1;
    end;

    SB.Append(FG_BORDER + GLYPH_TEEEAST
            + RepeatChar(GLYPH_HORZ, ScreenWidth - 2)
            + GLYPH_TEEWEST + ANSI_RESET + NL);

    case StatusKind of
      0 : TitleLine := FG_GREEN; 1 : TitleLine := FG_AMBER; else TitleLine := FG_RED;
    end;
    if MouseEnabled then MouseLabel := 'on' else MouseLabel := 'off';
    if SelActive then SelectionLabel := 'chat' else SelectionLabel := 'off';
    StatusLine := BG_BAR + ' ' + TitleLine + GLYPH_DOT + ANSI_RESET
                + BG_BAR + ' ' + FG_TEXT + 'Connected'
                + ' ' + FG_DGRAY + GLYPH_VERT + ANSI_RESET + BG_BAR + ' '
                + FG_GRAY + 'Prompt:' + TitleLine + ' ' + PromptState
                + ' ' + FG_DGRAY + GLYPH_VERT + ANSI_RESET + BG_BAR + ' '
                + FG_GRAY + 'Session:' + FG_TEXT + ' '
                + IntToStr(ActiveSessionIndex + 1) + '/'
                + IntToStr(SessionList.Count)
                + ' ' + FG_DGRAY + GLYPH_VERT + ANSI_RESET + BG_BAR + ' '
                + FG_GRAY + 'Mouse:' + FG_TEXT + ' ' + MouseLabel
                + ' ' + FG_DGRAY + GLYPH_VERT + ANSI_RESET + BG_BAR + ' '
                + FG_GRAY + 'Sel:' + FG_TEXT + ' ' + SelectionLabel
                + ' ' + FG_DGRAY + GLYPH_VERT + ANSI_RESET + BG_BAR + ' '
                + FG_GRAY + 'Perms:' + FG_CYAN + ' RWX';
    SB.Append(FG_BORDER + GLYPH_VERT + ANSI_RESET
            + PadToWidth(StatusLine, ScreenWidth - 2, BG_BAR) + ANSI_RESET
            + FG_BORDER + GLYPH_VERT + ANSI_RESET + NL);

    SB.Append(FG_BORDER + GLYPH_BOTLEFT
            + RepeatChar(GLYPH_HORZ, ScreenWidth - 2)
            + GLYPH_BOTRIGHT + ANSI_RESET);

    if not ExitDialogVisible then
    begin
      if not SimActive then
      begin
        SB.Append(ESC + '[' + IntToStr(CaretRow) + ';' + IntToStr(CaretCol) + 'H');
        SB.Append(CURSOR_SHOW);
      end else SB.Append(CURSOR_HIDE);
    end else SB.Append(CURSOR_HIDE);

    Result := SB.ToString;
  finally SB.Free; end;
end;

procedure AppendUserMessage(const Text : string);
var M : TChatMessage;
begin
  M.Role := crUser; M.Text := Text;
  M.Time := CurrentShortTime; M.Date := CurrentShortDate; M.FullStamp := CurrentFullStamp;
  ChatMessages.Add(M);
end;
procedure AppendAssistantMessage(const Text : string);
var M : TChatMessage;
begin
  M.Role := crAssistant; M.Text := Text;
  M.Time := CurrentShortTime; M.Date := CurrentShortDate; M.FullStamp := CurrentFullStamp;
  ChatMessages.Add(M);
end;

procedure BeginSimulation;
begin
  SimActive := True; SimStep := 0; SimTimer := GetTickCount;
  PromptState := 'PENDING'; StatusKind := 1; ChatScroll := 0;
  SelActive := False; SelAnchorRow := -1; SelFocusRow := -1; AutoScrollDir := 0;
  ThinkingLines.Clear;
  ThinkingLines.Add('SIR: parsing user prompt...');
  ThinkingLines.Add('Building structured representation...');
  ThinkingLines.Add('Planner: generating execution plan...');
end;

procedure AdvanceSimulation;
begin
  if not SimActive then Exit;
  Inc(SimStep);
  case SimStep of
    1: begin PromptState := 'SUBMITTING'; ThinkingLines.Clear;
             ThinkingLines.Add('INPUT_SUBMITTED (provider_native_send)');
             ThinkingLines.Add('Verifying input ownership...');
             ThinkingLines.Add('Awaiting GENERATION_STARTED...'); end;
    2: begin PromptState := 'GENERATING'; ThinkingLines.Clear;
             ThinkingLines.Add('GENERATION_STARTED - message identified');
             ThinkingLines.Add('Baseline revision captured (r=0)');
             ThinkingLines.Add('Streaming GENERATION_DELTA...');
             AppendAssistantMessage('Analyzing GRISP architecture.'); end;
    3: begin ThinkingLines.Clear;
             ThinkingLines.Add('Deltas applied: rev 1..3 (APPEND)');
             ThinkingLines.Add('Terminal stability check (1/2)...');
             ThinkingLines.Add('Fencing: prompt_request_id OK'); end;
    4: begin ThinkingLines.Clear;
             ThinkingLines.Add('Terminal stability check (2/2)...');
             ThinkingLines.Add('done=true streaming=false continuation=false');
             ThinkingLines.Add('Submitting terminal candidate to arbiter'); end;
    5: begin AppendAssistantMessage('Main components identified:');
             AppendAssistantMessage('  1. SIR - Source Intermediate Representation');
             AppendAssistantMessage('  2. Planner - Execution plan builder');
             AppendAssistantMessage('  3. Evaluator - Graph operations executor');
             AppendAssistantMessage('  4. Validator - Correctness and compliance');
             AppendAssistantMessage('  5. EIR - Optimized Execution IR');
             AppendAssistantMessage('  6. Runtime - Deterministic executor');
             AppendAssistantMessage('  7. WorldState - Persistent state');
             AppendAssistantMessage('Would you like me to generate a diagram?');
             ThinkingLines.Clear;
             ThinkingLines.Add('GENERATION_COMPLETED committed');
             ThinkingLines.Add('Terminal arbitration: winner = COMPLETED');
             PromptState := 'COMPLETED'; StatusKind := 0; SimActive := False; end;
  end;
end;

procedure SubmitPrompt;
begin
  if Trim(InputBuffer) = '' then Exit;
  AppendUserMessage(InputBuffer);
  InputBuffer := ''; InputCursor := 0; InputScroll := 0;
  BeginSimulation;
end;

procedure ClampInputCursor;
begin if InputCursor < 0 then InputCursor := 0;
  if InputCursor > Length(InputBuffer) then InputCursor := Length(InputBuffer); end;

procedure InsertAtCaret(const S : string);
begin if S = '' then Exit;
  Insert(S, InputBuffer, InputCursor + 1);
  Inc(InputCursor, Length(S)); ClampInputCursor; end;

procedure BackspaceAtCaret;
begin if InputCursor > 0 then begin Delete(InputBuffer, InputCursor, 1); Dec(InputCursor); end; end;

procedure DeleteAtCaret;
begin if InputCursor < Length(InputBuffer) then Delete(InputBuffer, InputCursor + 1, 1); end;

procedure MoveCaretLeft;  begin if InputCursor > 0 then Dec(InputCursor); end;
procedure MoveCaretRight; begin if InputCursor < Length(InputBuffer) then Inc(InputCursor); end;

procedure MoveCaretHome;
var Lines : TArray<TVisualLine>; R, C : Integer;
begin Lines := BuildVisualLines(InputBuffer, InputWrapWidth);
  if CursorVisualPos(Lines, InputCursor, R, C) then InputCursor := Lines[R].BufStart - 1;
  ClampInputCursor; end;

procedure MoveCaretEnd;
var Lines : TArray<TVisualLine>; R, C : Integer;
begin Lines := BuildVisualLines(InputBuffer, InputWrapWidth);
  if CursorVisualPos(Lines, InputCursor, R, C) then
    InputCursor := (Lines[R].BufStart - 1) + Length(Lines[R].Text);
  ClampInputCursor; end;

procedure MoveCaretVertical(const Delta : Integer);
var Lines : TArray<TVisualLine>; R, C, TR : Integer;
begin Lines := BuildVisualLines(InputBuffer, InputWrapWidth);
  if not CursorVisualPos(Lines, InputCursor, R, C) then Exit;
  TR := R + Delta; if TR < 0 then TR := 0;
  if TR > High(Lines) then TR := High(Lines);
  if C > Length(Lines[TR].Text) then C := Length(Lines[TR].Text);
  InputCursor := (Lines[TR].BufStart - 1) + C; ClampInputCursor; end;

function GetClipboardText : string;
var Data : THandle; Ptr : Pointer;
begin
  Result := '';
  if not OpenClipboard(0) then Exit;
  try
    Data := GetClipboardData(MY_CF_UNICODETEXT);
    if Data <> 0 then
    begin Ptr := GlobalLock(Data);
      if Ptr <> nil then try Result := string(PWideChar(Ptr));
      finally GlobalUnlock(Data); end; end;
  finally CloseClipboard; end;
end;

procedure PasteFromClipboard;
var Txt : string;
begin
  Txt := GetClipboardText; if Txt = '' then Exit;
  Txt := StringReplace(Txt, #13#10, #10, [rfReplaceAll]);
  Txt := StringReplace(Txt, #13, #10, [rfReplaceAll]);
  InsertAtCaret(Txt);
end;

procedure CopyTextToClipboard(const Text : string);
var Data : HGLOBAL; Ptr : Pointer; ByteCount : NativeUInt;
begin
  if Text = '' then Exit;
  ByteCount := (Length(Text) + 1) * SizeOf(WideChar);
  Data := GlobalAlloc(GMEM_MOVEABLE or GMEM_ZEROINIT, ByteCount);
  if Data = 0 then Exit;
  Ptr := GlobalLock(Data);
  if Ptr = nil then begin GlobalFree(Data); Exit; end;
  try Move(PWideChar(Text)^, Ptr^, ByteCount);
  finally GlobalUnlock(Data); end;
  if not OpenClipboard(0) then begin GlobalFree(Data); Exit; end;
  try
    EmptyClipboard;
    if SetClipboardData(MY_CF_UNICODETEXT, Data) = 0 then GlobalFree(Data);
  finally CloseClipboard; end;
end;

procedure CopyInputToClipboard;
begin CopyTextToClipboard(InputBuffer); end;

function ExtractSelectionText : string;
var R1, R2, C1, C2, R, TmpI : Integer; Plain, Trimmed : string;
begin
  Result := '';
  if not SelActive then Exit;
  R1 := SelAnchorRow; C1 := SelAnchorCol;
  R2 := SelFocusRow;  C2 := SelFocusCol;
  if (R1 > R2) or ((R1 = R2) and (C1 > C2)) then
  begin TmpI := R1; R1 := R2; R2 := TmpI; TmpI := C1; C1 := C2; C2 := TmpI; end;
  if (R1 < 0) or (R2 >= Length(ChatFullPlain)) then Exit;
  for R := R1 to R2 do
  begin
    Plain := ChatFullPlain[R];
    if R1 = R2 then Result := Result + Copy(Plain, C1 + 1, C2 - C1)
    else if R = R1 then begin Result := Result + Copy(Plain, C1 + 1, MaxInt); Result := Result + #13#10; end
    else if R = R2 then Result := Result + Copy(Plain, 1, C2)
    else begin
      Trimmed := Plain;
      while (Length(Trimmed) > 0) and (Trimmed[Length(Trimmed)] = ' ') do
        Delete(Trimmed, Length(Trimmed), 1);
      Result := Result + Trimmed + #13#10;
    end;
  end;
end;

procedure SetMouseShape(Shape : TMouseShape);
var P : HCURSOR;
begin
  case Shape of
    msSizeWE: P := LoadCursor(0, IDC_SIZEWE);
    msSizeNS: P := LoadCursor(0, IDC_SIZENS);
    msIBeam:  P := LoadCursor(0, IDC_IBEAM);
    msHand:   P := LoadCursor(0, IDC_HAND);
    else P := LoadCursor(0, IDC_ARROW);
  end;
  SetCursor(P);
end;

function RightPaneBarX : Integer;
begin if ShowRightPanel then Result := ScreenWidth - 1 else Result := 0; end;

function LeftPaneBarX : Integer;
begin if ShowLeftPanel then Result := ColLeft + 1 else Result := 0; end;

function InputBarBarX : Integer;
begin Result := ScreenWidth - 1; end;

function HitTestChat(X, Y : Integer; out FullRow, Col : Integer) : Boolean;
var ChatTop, ChatBottom, VisRow : Integer;
begin
  Result := False; FullRow := -1; Col := 0;
  ChatTop := 4 + 2;
  ChatBottom := 4 + ContentHeight - 1;
  if (Y < ChatTop) or (Y > ChatBottom) then Exit;
  VisRow := Y - ChatTop;
  FullRow := ChatWindowStart + VisRow;
  if (FullRow < 0) or (FullRow >= Length(ChatFullPlain)) then Exit;
  Col := X - ChatBodyLeftX;
  if Col < 0 then Col := 0;
  if Col > Length(ChatFullPlain[FullRow]) then Col := Length(ChatFullPlain[FullRow]);
  Result := True;
end;

procedure ResetAllUserSizes;
begin
  UserColLeft := 0; UserColRight := 0; UserInputRows := 0;
  UserLeftSplit := 0; UserPlanRows := 0; UserWorkRows := 0;
  RecomputeLayout;
end;

procedure ExecuteFunctionKey(const ParaKeyIndex : Integer);
begin
  case ParaKeyIndex of
    1: begin WantLeftPanel := not WantLeftPanel; RecomputeLayout; end;
    2: begin WantRightPanel := not WantRightPanel; RecomputeLayout; end;
    3: begin WantThinking := not WantThinking; RecomputeLayout; end;
    4: begin if SimActive then AdvanceSimulation else SubmitPrompt; end;
    5: begin
         MouseEnabled := not MouseEnabled; ApplyInputMode;
         if MouseEnabled then PromptState := 'READY' else PromptState := 'TERM-SEL';
       end;
    6: ResetAllUserSizes;
  end;
end;

function ScrollBarTargetAt(X, Y : Integer) : Integer;
var LH, RH : Integer;
begin
  Result := 0;
  LH := LeftPaneBarX;
  RH := RightPaneBarX;

  if ShowLeftPanel and (X = LH)
     and (Y >= 4 + 2) and (Y < 4 + LeftSplitRow) then
  begin Result := 30; Exit; end;

  if ShowLeftPanel and (X = LH)
     and (Y >= 4 + LeftSplitRow + 3) and (Y < 4 + ContentHeight) then
  begin Result := 31; Exit; end;

  if (X = InputBarBarX) and (Y >= 5 + ContentHeight)
     and (Y < 5 + ContentHeight + InputHeight) then
  begin Result := 32; Exit; end;

  if ShowRightPanel and (X = RH)
     and (Y >= 4 + 2) and (Y < 4 + RightPlanRows) then
  begin Result := 33; Exit; end;

  if ShowRightPanel and (X = RH)
     and (Y >= 4 + RightPlanRows + 3)
     and (Y < 4 + RightPlanRows + 1 + RightWorkRows) then
  begin Result := 34; Exit; end;

  if ShowRightPanel and (X = RH)
     and (Y >= 4 + RightPlanRows + 1 + RightWorkRows + 3)
     and (Y < 4 + ContentHeight) then
  begin Result := 35; Exit; end;

  { v0.40: chat scrollbar hit zone breder (2 kolommen). }
  if (X = ChatBarX) or (X = ChatBarX - 1)
     and (Y >= 4 + 2) and (Y < 4 + ContentHeight) then
  begin Result := 20; Exit; end;
end;

function DesiredShape(x, y : Integer) : TMouseShape;
var I, Tgt : Integer;
begin
  Result := msArrow;
  if not MouseEnabled then Exit;

  if ExitDialogVisible then
  begin
    if ExitDialogButtonAt(x, y) <> 0 then Result := msHand;
    Exit;
  end;

  if TopBarActionAt(x, y) <> 0 then begin Result := msHand; Exit; end;
  Tgt := ScrollBarTargetAt(x, y);
  if Tgt <> 0 then begin Result := msHand; Exit; end;

  if (ShowLeftPanel and (x = ColLeft + 2))
  or (ShowRightPanel and (x = ColLeft + ColCenter + 3)) then
  begin Result := msSizeWE; Exit; end;

  if y = 4 + ContentHeight then begin Result := msSizeNS; Exit; end;
  if ShowLeftPanel and (y = 4 + LeftSplitRow)
    and (x >= 2) and (x <= ColLeft + 1) then
  begin Result := msSizeNS; Exit; end;
  if ShowRightPanel and (y = 4 + RightPlanRows)
    and (x >= ColLeft + ColCenter + 4) then
  begin Result := msSizeNS; Exit; end;
  if ShowRightPanel and (y = 4 + RightPlanRows + 1 + RightWorkRows)
    and (x >= ColLeft + ColCenter + 4) then
  begin Result := msSizeNS; Exit; end;

  for I := 0 to High(TreeVisibleRows) do
    if (y = TreeVisibleRows[I]) and (x >= 2) and (x <= ColLeft + 1) then
    begin Result := msHand; Exit; end;
  for I := 0 to High(SessionTitleRows) do
    if (y = SessionTitleRows[I]) and (x >= 2) and (x <= ColLeft + 1) then
    begin Result := msHand; Exit; end;

  if (y >= 4) and (y < 4 + ContentHeight)
    and (x > ColLeft + 2) and (x < ChatBarX) then
    Result := msIBeam;
end;

procedure UpdateHoverTarget(MouseX, MouseY : Integer);
var RStart, REnd, Tgt, TopAct, DlgAct : Integer;
begin
  Tgt := ScrollBarTargetAt(MouseX, MouseY);
  HoverTarget := 0;

  if ExitDialogVisible then
  begin
    DlgAct := ExitDialogButtonAt(MouseX, MouseY);
    if DlgAct = 1 then HoverTarget := 61
    else if DlgAct = 2 then HoverTarget := 62
    else if DlgAct = 3 then HoverTarget := 63;
    Exit;
  end;

  RStart := ColLeft + ColCenter + 4;
  REnd   := ColLeft + ColCenter + ColRight + 3;
  TopAct := TopBarActionAt(MouseX, MouseY);

  if TopAct = 10 then HoverTarget := 60
  else if TopAct > 0 then HoverTarget := 40 + TopAct
  else if Tgt <> 0 then HoverTarget := Tgt
  else if ShowLeftPanel and (MouseX = ColLeft + 2) then HoverTarget := 1
  else if ShowRightPanel and (MouseX = ColLeft + ColCenter + 3) then HoverTarget := 2
  else if MouseY = 4 + ContentHeight then HoverTarget := 10
  else if ShowLeftPanel and (MouseY = 4 + LeftSplitRow)
          and (MouseX >= 2) and (MouseX <= ColLeft + 1) then HoverTarget := 11
  else if ShowRightPanel and (MouseY = 4 + RightPlanRows)
          and (MouseX >= RStart) and (MouseX <= REnd) then HoverTarget := 12
  else if ShowRightPanel
          and (MouseY = 4 + RightPlanRows + 1 + RightWorkRows)
          and (MouseX >= RStart) and (MouseX <= REnd) then HoverTarget := 13;
end;

procedure ApplyDrag(const Ev : TInputEvent);
var MyMax : Integer;
begin
  case DragTarget of
    1: begin UserColLeft := Ev.MouseX - 2;
         if UserColLeft < MIN_PANE_WIDTH then UserColLeft := MIN_PANE_WIDTH;
         if UserColLeft > ScreenWidth - MIN_CHAT_WIDTH - ColRight - 4 then
           UserColLeft := ScreenWidth - MIN_CHAT_WIDTH - ColRight - 4; end;
    2: begin UserColRight := ScreenWidth - Ev.MouseX - 1;
         if UserColRight < MIN_PANE_WIDTH then UserColRight := MIN_PANE_WIDTH;
         if UserColRight > ScreenWidth - MIN_CHAT_WIDTH - ColLeft - 4 then
           UserColRight := ScreenWidth - MIN_CHAT_WIDTH - ColLeft - 4; end;
    10: begin UserInputRows := ScreenHeight - 7 - (Ev.MouseY - 4);
          if UserInputRows < 1 then UserInputRows := 1;
          MyMax := MaxInputRows;
          if UserInputRows > MyMax then UserInputRows := MyMax; end;
    11: begin UserLeftSplit := Ev.MouseY - 4;
          if UserLeftSplit < 3 then UserLeftSplit := 3;
          if UserLeftSplit > ContentHeight - 4 then UserLeftSplit := ContentHeight - 4; end;
    12: begin UserPlanRows := Ev.MouseY - 4;
          if UserPlanRows < 3 then UserPlanRows := 3;
          if UserPlanRows > ContentHeight - 8 then UserPlanRows := ContentHeight - 8; end;
    13: begin UserWorkRows := Ev.MouseY - (4 + RightPlanRows + 1);
          if UserWorkRows < 3 then UserWorkRows := 3;
          if UserWorkRows > ContentHeight - 8 then UserWorkRows := ContentHeight - 8; end;
    20: ChatScroll := MouseToChatScroll(Ev.MouseY, 4 + 2, ContentHeight - 2, ChatMaxScroll);
    30: ResScroll := MouseToScrollTop(Ev.MouseY, 4 + 2, LeftSplitRow - 2, ResMaxScroll);
    31: SesScroll := MouseToScrollTop(Ev.MouseY, 4 + LeftSplitRow + 3,
                    ContentHeight - LeftSplitRow - 3, SesMaxScroll);
    32: InputScroll := MouseToScrollTop(Ev.MouseY, 5 + ContentHeight,
                      InputHeight, InputMaxScroll);
    33: PlanScroll := MouseToScrollTop(Ev.MouseY, 4 + 2, RightPlanRows - 2, PlanMaxScroll);
    34: WorkScroll := MouseToScrollTop(Ev.MouseY, 4 + RightPlanRows + 3,
                     RightWorkRows - 2, WorkMaxScroll);
    35: ThinkScroll := MouseToScrollTop(Ev.MouseY,
                     4 + RightPlanRows + 1 + RightWorkRows + 3,
                     ContentHeight - 2 - RightPlanRows - RightWorkRows, ThinkMaxScroll);
  end;
  RecomputeLayout;
end;

procedure HandleWheel(const Ev : TInputEvent);
var WheelLines, Tgt : Integer;
begin
  WheelLines := (Ev.WheelDelta div 120) * 3;
  Tgt := ScrollBarTargetAt(Ev.MouseX, Ev.MouseY);

  if Tgt = 0 then
  begin
    if ShowLeftPanel and (Ev.MouseX >= 2) and (Ev.MouseX <= ColLeft + 1) then
      Tgt := 30 + Ord(Ev.MouseY >= 4 + LeftSplitRow)
    else if ShowRightPanel and (Ev.MouseX >= ColLeft + ColCenter + 4) then
    begin
      if Ev.MouseY < 4 + RightPlanRows then Tgt := 33
      else if Ev.MouseY < 4 + RightPlanRows + 1 + RightWorkRows then Tgt := 34
      else Tgt := 35;
    end
    else if (Ev.MouseY >= 5 + ContentHeight) and
            (Ev.MouseY < 5 + ContentHeight + InputHeight) then Tgt := 32
    else Tgt := 20;
  end;

  case Tgt of
    20: ChatScroll  := ChatScroll  + WheelLines;
    30: ResScroll   := ResScroll   - WheelLines;
    31: SesScroll   := SesScroll   - WheelLines;
    32: InputScroll := InputScroll - WheelLines;
    33: PlanScroll  := PlanScroll  - WheelLines;
    34: WorkScroll  := WorkScroll  - WheelLines;
    35: ThinkScroll := ThinkScroll - WheelLines;
  end;

  if ChatScroll < 0 then ChatScroll := 0;
  if ChatScroll > ChatMaxScroll then ChatScroll := ChatMaxScroll;
  if ResScroll < 0 then ResScroll := 0;
  if ResScroll > ResMaxScroll then ResScroll := ResMaxScroll;
  if SesScroll < 0 then SesScroll := 0;
  if SesScroll > SesMaxScroll then SesScroll := SesMaxScroll;
  if InputScroll < 0 then InputScroll := 0;
  if InputScroll > InputMaxScroll then InputScroll := InputMaxScroll;
  if PlanScroll < 0 then PlanScroll := 0;
  if PlanScroll > PlanMaxScroll then PlanScroll := PlanMaxScroll;
  if WorkScroll < 0 then WorkScroll := 0;
  if WorkScroll > WorkMaxScroll then WorkScroll := WorkMaxScroll;
  if ThinkScroll < 0 then ThinkScroll := 0;
  if ThinkScroll > ThinkMaxScroll then ThinkScroll := ThinkMaxScroll;

  NeedsRedraw := True;
end;

procedure HandleMouseEvent(const Ev : TInputEvent);
var Tgt, TopAction, DialogAction : Integer; HitRow, HitCol : Integer;
begin
  if ExitDialogVisible then
  begin
    DialogAction := ExitDialogButtonAt(Ev.MouseX, Ev.MouseY);
    HoverTarget := 0;
    if DialogAction = 1 then HoverTarget := 61
    else if DialogAction = 2 then HoverTarget := 62
    else if DialogAction = 3 then HoverTarget := 63;
    if MouseEnabled then SetMouseShape(msArrow);
    if (Ev.MouseButton = 1) and (DialogAction <> 0) then
    begin
      if DialogAction = 1 then ConfirmExit else CancelExit;
      NeedsRedraw := True;
    end;
    Exit;
  end;

  if Ev.MouseButton = 2 then
  begin
    if SelActive then
    begin
      CopyTextToClipboard(ExtractSelectionText);
      PromptState := 'COPIED'; StatusKind := 0;
      SelActive := False; SelAnchorRow := -1; SelFocusRow := -1; AutoScrollDir := 0;
    end
    else if InputBuffer <> '' then
    begin CopyInputToClipboard; PromptState := 'COPIED'; StatusKind := 0; end;
    NeedsRedraw := True;
    Exit;
  end;

  if Ev.WheelDelta <> 0 then begin HandleWheel(Ev); NeedsRedraw := True; Exit; end;

  if IsDragging then
  begin
    if Ev.MouseButton = 1 then begin ApplyDrag(Ev); NeedsRedraw := True; end
    else begin IsDragging := False; DragTarget := 0; NeedsRedraw := True; end;
    Exit;
  end;

  if IsSelecting then
  begin
    if Ev.MouseButton = 1 then
    begin
      AutoScrollX := Ev.MouseX;
      if Ev.MouseY < 4 + 2 then AutoScrollDir := -1
      else if Ev.MouseY > 4 + ContentHeight - 1 then AutoScrollDir := +1
      else AutoScrollDir := 0;
      if HitTestChat(Ev.MouseX, Ev.MouseY, HitRow, HitCol) then
      begin
        SelFocusRow := HitRow; SelFocusCol := HitCol;
        SelActive := (SelAnchorRow <> SelFocusRow) or (SelAnchorCol <> SelFocusCol);
        NeedsRedraw := True;
      end;
    end
    else
    begin
      IsSelecting := False; AutoScrollDir := 0;
      if not SelActive then begin SelAnchorRow := -1; SelFocusRow := -1; end;
      NeedsRedraw := True;
    end;
    Exit;
  end;

  UpdateHoverTarget(Ev.MouseX, Ev.MouseY);
  CurrentMouseShape := DesiredShape(Ev.MouseX, Ev.MouseY);
  if MouseEnabled then SetMouseShape(CurrentMouseShape);

  if Ev.MouseButton = 1 then
  begin
    TopAction := TopBarActionAt(Ev.MouseX, Ev.MouseY);
    if TopAction <> 0 then
    begin
      if TopAction <= 6 then ExecuteFunctionKey(TopAction)
      else if TopAction = 7 then
      begin if SimActive then AdvanceSimulation else SubmitPrompt; end
      else if TopAction = 8 then
      begin CopyInputToClipboard; PromptState := 'COPIED'; StatusKind := 0; end
      else if (TopAction = 9) or (TopAction = 10) then RequestExit;
      NeedsRedraw := True; Exit;
    end;

    Tgt := ScrollBarTargetAt(Ev.MouseX, Ev.MouseY);
    if Tgt <> 0 then
    begin IsDragging := True; DragTarget := Tgt; ApplyDrag(Ev); NeedsRedraw := True; Exit; end;

    if (HoverTarget = 1) or (HoverTarget = 2) or (HoverTarget = 10) or
       (HoverTarget = 11) or (HoverTarget = 12) or (HoverTarget = 13) then
    begin IsDragging := True; DragTarget := HoverTarget; NeedsRedraw := True; Exit; end;

    if ShowLeftPanel and (Ev.MouseX >= 2) and (Ev.MouseX <= ColLeft + 1) then
    begin
      var I, Idx : Integer; var T : TTreeItem;
      for I := 0 to High(TreeVisibleRows) do
        if Ev.MouseY = TreeVisibleRows[I] then
        begin Idx := TreeVisibleIdx[I];
          if NodeHasVisibleChildren(Idx) then
          begin T := TreeList[Idx]; T.Expanded := not T.Expanded;
            TreeList[Idx] := T; end;
          NeedsRedraw := True; Exit; end;
      for I := 0 to High(SessionTitleRows) do
        if Ev.MouseY = SessionTitleRows[I] then
        begin SwitchSession(SessionIdxAtRow[I]); NeedsRedraw := True; Exit; end;
    end;

    if HitTestChat(Ev.MouseX, Ev.MouseY, HitRow, HitCol) then
    begin
      IsSelecting := True;
      SelAnchorRow := HitRow; SelAnchorCol := HitCol;
      SelFocusRow := HitRow; SelFocusCol := HitCol;
      SelActive := False; AutoScrollDir := 0;
      NeedsRedraw := True;
    end;
  end;
end;

function CtrlIsDown : Boolean;
begin Result := (GetKeyState(VK_CONTROL) and $8000) <> 0; end;

procedure HandleKeyEvent(const Ev : TInputEvent);
var CtrlDown : Boolean;
begin
  if ExitDialogVisible then
  begin
    if Ev.Kind = ikSpecial then
    begin
      if Ev.VK = VK_ESCAPE then CancelExit
      else if Ev.VK = VK_RETURN then ConfirmExit;
    end
    else if Ev.Kind = ikChar then
    begin
      if (Ev.Ch = 'y') or (Ev.Ch = 'Y') then ConfirmExit
      else if (Ev.Ch = 'n') or (Ev.Ch = 'N') then CancelExit
      else if (Ev.Ch = 'c') or (Ev.Ch = 'C') then CancelExit
      else if Ev.Ch = #27 then CancelExit;
    end;
    NeedsRedraw := True;
    Exit;
  end;

  if Ev.Kind = ikSpecial then
  begin
    case Ev.VK of
      VK_LEFT: MoveCaretLeft; VK_RIGHT: MoveCaretRight;
      VK_UP: MoveCaretVertical(-1); VK_DOWN: MoveCaretVertical(+1);
      VK_HOME: MoveCaretHome; VK_END: MoveCaretEnd;
      VK_DELETE: DeleteAtCaret; VK_BACK: BackspaceAtCaret;
      VK_ESCAPE:
        if SelActive then
        begin
          SelActive := False; SelAnchorRow := -1; SelFocusRow := -1; AutoScrollDir := 0;
          NeedsRedraw := True;
        end
        else RequestExit;
      VK_F1: ExecuteFunctionKey(1);
      VK_F2: ExecuteFunctionKey(2);
      VK_F3: ExecuteFunctionKey(3);
      VK_F4: ExecuteFunctionKey(4);
      VK_F5: ExecuteFunctionKey(5);
      VK_F6: ExecuteFunctionKey(6);
      VK_PRIOR: ChatScroll := ChatScroll + 5;
      VK_NEXT:  ChatScroll := ChatScroll - 5;
      VK_RETURN:
        begin if SimActive then begin AdvanceSimulation; Exit; end;
          CtrlDown := Ev.ModCtrl or CtrlIsDown;
          if CtrlDown then SubmitPrompt else InsertAtCaret(#10); end;
    end;
    Exit;
  end;
  if Ev.Kind <> ikChar then Exit;

  if Ev.ModCtrl and (not Ev.ModAlt) and (Ev.Ch = #3) then
  begin
    if SelActive then
    begin
      CopyTextToClipboard(ExtractSelectionText);
      PromptState := 'COPIED'; StatusKind := 0;
      SelActive := False; SelAnchorRow := -1; SelFocusRow := -1; AutoScrollDir := 0;
    end
    else
    begin CopyInputToClipboard; PromptState := 'COPIED'; StatusKind := 0; end;
    Exit;
  end;

  if Ev.ModCtrl and (not Ev.ModAlt) and (Ev.Ch = #$16) then
  begin if not SimActive then PasteFromClipboard; Exit; end;

  if (Ev.Ch = #13) or (Ev.Ch = #10) then
  begin if SimActive then begin AdvanceSimulation; Exit; end;
    CtrlDown := Ev.ModCtrl or CtrlIsDown;
    if CtrlDown then SubmitPrompt else InsertAtCaret(#10);
    Exit; end;

  if Ev.Ch = #8 then
  begin if not SimActive then BackspaceAtCaret; Exit; end;

  if (Ord(Ev.Ch) >= 32) and not SimActive
     and not Ev.ModCtrl and not Ev.ModAlt then InsertAtCaret(Ev.Ch);
end;

procedure RunApplication;
var Ev : TInputEvent; NewWidth, NewHeight : Integer;
    HadInput : Boolean; WaitMs : Cardinal; HoverBefore : Integer;
    Frame : string;
begin
  InitializeConsole; InitializeApplicationData;
  try
    WriteAtomic(SCREEN_ALT_ON); WriteAtomic(SCREEN_CLEAR);
    NeedsRedraw := True; ForceFullRedraw := False;
    while not QuitRequested do
    begin
      ReadTerminalSize(NewWidth, NewHeight);
      if (NewWidth <> ScreenWidth) or (NewHeight <> ScreenHeight) then
      begin
        RecomputeLayout;
        WriteAtomic(SCREEN_CLEAR);
        NeedsRedraw := True;
      end;

      HadInput := False;
      repeat
        Ev := ReadInputEvent;
        if Ev.Kind = ikNone then Break;
        HadInput := True;
        case Ev.Kind of
          ikChar, ikSpecial: begin HandleKeyEvent(Ev); NeedsRedraw := True; end;
          ikMouse:
            if MouseEnabled then
            begin HoverBefore := HoverTarget;
              HandleMouseEvent(Ev);
              if (HoverTarget <> HoverBefore) or Ev.IsMove or (Ev.WheelDelta <> 0) then
                NeedsRedraw := True;
            end;
        end;
      until False;

      if SimActive and ((GetTickCount - SimTimer) > SIM_INTERVAL_MS) then
      begin SimTimer := GetTickCount; AdvanceSimulation; NeedsRedraw := True; end;

      if (AutoScrollDir <> 0) and ((GetTickCount - AutoScrollTick) >= AUTO_SCROLL_MS) then
      begin
        AutoScrollTick := GetTickCount;
        if AutoScrollDir < 0 then
        begin
          ChatScroll := ChatScroll + 1;
          if ChatScroll > ChatMaxScroll then ChatScroll := ChatMaxScroll;
          if SelFocusRow > 0 then
          begin Dec(SelFocusRow); SelFocusCol := Length(ChatFullPlain[SelFocusRow]); end;
        end
        else
        begin
          ChatScroll := ChatScroll - 1;
          if ChatScroll < 0 then ChatScroll := 0;
          if SelFocusRow >= 0 then
          begin
            if SelFocusRow < High(ChatFullPlain) then Inc(SelFocusRow);
            SelFocusCol := AutoScrollX - ChatBodyLeftX;
            if SelFocusCol < 0 then SelFocusCol := 0;
            if SelFocusCol > Length(ChatFullPlain[SelFocusRow]) then
              SelFocusCol := Length(ChatFullPlain[SelFocusRow]);
          end;
        end;
        SelActive := (SelAnchorRow <> SelFocusRow) or (SelAnchorCol <> SelFocusCol);
        NeedsRedraw := True;
      end;

      if NeedsRedraw then
      begin
        if ForceFullRedraw then
        begin WriteAtomic(SCREEN_CLEAR); ForceFullRedraw := False; end;
        Frame := RenderFrame;
        if ExitDialogVisible then Frame := Frame + ANSI_RESET + RenderExitDialogOverlay;
        WriteAtomic(Frame);
        NeedsRedraw := False;
      end;

      if SimActive then WaitMs := 50
      else if AutoScrollDir <> 0 then WaitMs := 20
      else if HadInput then WaitMs := 1
      else WaitMs := 10;
      WaitForSingleObject(StdInHandle, WaitMs);
    end;
  finally
    MouseEnabled := False; ApplyInputMode;
    WriteAtomic(ANSI_RESET + CURSOR_SHOW + SCREEN_ALT_OFF);
    ShutdownApplicationData;
  end;
end;

begin
  try RunApplication;
  except on E : Exception do
    begin Writeln('Fatal error: ', E.Message); Halt(1); end;
  end;
end.
