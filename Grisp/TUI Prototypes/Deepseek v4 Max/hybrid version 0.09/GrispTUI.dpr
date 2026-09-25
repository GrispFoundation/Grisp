{ ============================================================================
  GRISP OS — Terminal UI  ·  v0.17
  ----------------------------------------------------------------------------
  Sneltoetsen
    Enter              nieuwe regel
    Shift+Enter        nieuwe regel
    Ctrl+Enter         versturen
    Alt+Enter          versturen
    F4                 versturen (of simulatie-stap)
    Ctrl+V             plakken uit klembord
    ← → ↑ ↓            cursor in input
    Home / End         begin / einde visuele regel
    Backspace / Delete
    F1 / F2 / F3       panelen aan-uit / thinking toggle
    F5                 muis aan-uit
    F6                 alle handmatige paneelgroottes resetten
    Esc                afsluiten
    PgUp / PgDn        chat scrollen
  ============================================================================ }

program GrispTUI;

{$APPTYPE CONSOLE}
{$R *.res}

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.Math;

{ ============================================================================
  SECTIE 1 — Constanten
  ============================================================================ }

const
  APP_NAME    = 'GRISP OS';
  APP_VERSION = 'v0.17';

  GLYPH_DIAMOND   = #$25C8;
  GLYPH_FDIAMOND  = #$25C6;
  GLYPH_RTRI      = #$25B8;
  GLYPH_PTRI      = #$25B6;
  GLYPH_CHECKED   = #$2611;
  GLYPH_UNCHECKED = #$2610;
  GLYPH_GT        = #$203A;
  GLYPH_BLOCK     = #$258C;
  GLYPH_DOT       = #$25CF;
  GLYPH_UP        = #$25B2;

  GLYPH_TOPLEFT   = #$250C;
  GLYPH_TOPRIGHT  = #$2510;
  GLYPH_BOTLEFT   = #$2514;
  GLYPH_BOTRIGHT  = #$2518;
  GLYPH_HORZ      = #$2500;
  GLYPH_VERT      = #$2502;
  GLYPH_TEEDOWN   = #$252C;
  GLYPH_TEEWEST   = #$2524;
  GLYPH_TEEUP     = #$2534;
  GLYPH_TEEEAST   = #$251C;

  ESC = #27;
  ANSI_RESET = ESC + '[0m';
  ANSI_BOLD  = ESC + '[1m';

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

  BG_MAIN  = ESC + '[48;2;10;14;26m';
  BG_PANEL = ESC + '[48;2;13;21;36m';
  BG_BAR   = ESC + '[48;2;8;12;22m';
  BG_INPUT = ESC + '[48;2;16;27;48m';
  BG_USER  = ESC + '[48;2;30;58;138m';
  BG_AI    = ESC + '[48;2;22;40;66m';

  CURSOR_HIDE    = ESC + '[?25l';
  CURSOR_SHOW    = ESC + '[?25h';
  SCREEN_ALT_ON  = ESC + '[?1049h';
  SCREEN_ALT_OFF = ESC + '[?1049l';
  SCREEN_CLEAR   = ESC + '[2J' + ESC + '[H';
  CURSOR_HOME    = ESC + '[H';

  SIM_INTERVAL_MS = 900;
  MIN_W_LEFT      = 110;
  MIN_W_RIGHT     = 90;
  MIN_PANE_WIDTH  = 20;
  MIN_CHAT_WIDTH  = 30;
  MAX_INPUT_ROWS  = 10;

  MY_CF_UNICODETEXT = 13;

  EVT_KEY           = $0001;
  EVT_MOUSE         = $0002;
  EVT_MOUSE_WHEELED = $0004;

{ ============================================================================
  SECTIE 2 — Types
  ============================================================================ }

type
  TChatRole = (crUser, crAssistant, crSystem);
  TChatMessage = record Role : TChatRole; Text : string; Time : string; end;

  TPlanStatus = (psDone, psRunning, psQueued);
  TPlanItem = record Text : string; Status : TPlanStatus; end;

  TWorkPriority = (wpHigh, wpMedium, wpLow);
  TWorkItem = record Text : string; Prio : TWorkPriority; end;

  TSession = record Name : string; Meta : string; end;
  TTreeItem = record Name : string; Depth : Integer; Perm : string; end;

  TInputKind = (ikNone, ikChar, ikSpecial, ikMouse);

  TInputEvent = record
    Kind        : TInputKind;
    Ch          : WideChar;
    VK          : Word;
    ModCtrl     : Boolean;
    ModAlt      : Boolean;
    ModShift    : Boolean;
    MouseX      : Integer;
    MouseY      : Integer;
    MouseButton : Integer;
    WheelDelta  : Integer;
  end;

  TVisualLine = record
    BufStart : Integer;
    Text     : string;
  end;

{ ============================================================================
  SECTIE 3 — Globale toestand
  ============================================================================ }

var
  StdOutHandle : THandle;
  StdInHandle  : THandle;

  ScreenWidth  : Integer;
  ScreenHeight : Integer;
  ColLeft      : Integer;
  ColCenter    : Integer;
  ColRight     : Integer;

  ContentHeight : Integer;
  InputHeight   : Integer;
  LeftSplitRow  : Integer;
  RightPlanRows : Integer;
  RightWorkRows : Integer;

  ChatMessages  : TList<TChatMessage>;
  PlanItems     : TList<TPlanItem>;
  WorkItems     : TList<TWorkItem>;
  ThinkingLines : TList<string>;
  SessionList   : TList<TSession>;
  TreeList      : TList<TTreeItem>;

  CurrentSessionName : string;
  ActiveSessionIndex : Integer = 0;

  InputBuffer : string;
  InputCursor : Integer = 0;
  InputScroll : Integer = 0;

  WantLeftPanel  : Boolean = True;
  WantRightPanel : Boolean = True;
  WantThinking   : Boolean = True;
  MouseEnabled   : Boolean = True;

  ShowLeftPanel  : Boolean = True;
  ShowRightPanel : Boolean = True;
  ShowThinking   : Boolean = True;

  UserColLeft   : Integer = 0;
  UserColRight  : Integer = 0;
  UserInputRows : Integer = 0;
  UserLeftSplit : Integer = 0;
  UserPlanRows  : Integer = 0;
  UserWorkRows  : Integer = 0;

  IsDragging  : Boolean = False;
  DragTarget  : Integer = 0;
  HoverTarget : Integer = 0;

  ChatScroll    : Integer = 0;
  ChatMaxScroll : Integer = 0;

  QuitRequested : Boolean = False;
  SimActive     : Boolean = False;
  SimStep       : Integer = 0;
  SimTimer      : Cardinal = 0;
  PromptState   : string = 'READY';
  StatusKind    : Integer = 0;

{ ============================================================================
  SECTIE 4 — Console plumbing
  ============================================================================ }

procedure ReadTerminalSize(out W, H : Integer);
var Info : TConsoleScreenBufferInfo;
begin
  if GetConsoleScreenBufferInfo(StdOutHandle, Info) then
  begin
    W := Info.srWindow.Right  - Info.srWindow.Left + 1;
    H := Info.srWindow.Bottom - Info.srWindow.Top  + 1;
  end
  else begin W := 140; H := 40; end;
  if W < 60 then W := 60;
  if H < 20 then H := 20;
end;

procedure WriteAtomic(const S : string);
var Written : DWORD;
begin
  if S = '' then Exit;
  WriteConsoleW(StdOutHandle, PWideChar(S), Length(S), Written, nil);
end;

procedure ApplyInputMode;
var Mode : DWORD;
begin
  GetConsoleMode(StdInHandle, Mode);
  Mode := Mode or ENABLE_EXTENDED_FLAGS or ENABLE_WINDOW_INPUT;
  if MouseEnabled then
    Mode := (Mode or ENABLE_MOUSE_INPUT) and not ENABLE_QUICK_EDIT_MODE
  else
    Mode := (Mode and not ENABLE_MOUSE_INPUT) or ENABLE_QUICK_EDIT_MODE;
  SetConsoleMode(StdInHandle, Mode);
end;

procedure InitializeConsole;
var Mode : DWORD;
begin
  StdOutHandle := GetStdHandle(STD_OUTPUT_HANDLE);
  StdInHandle  := GetStdHandle(STD_INPUT_HANDLE);
  GetConsoleMode(StdOutHandle, Mode);
  SetConsoleMode(StdOutHandle,
    (Mode or ENABLE_VIRTUAL_TERMINAL_PROCESSING or ENABLE_PROCESSED_OUTPUT)
    and not ENABLE_WRAP_AT_EOL_OUTPUT);
  SetConsoleOutputCP(CP_UTF8);
  SetConsoleCP(CP_UTF8);
  SetConsoleTitle(PChar(APP_NAME + ' ' + APP_VERSION + ' — Terminal UI'));
  ApplyInputMode;
end;

function ReadInputEvent : TInputEvent;
var
  Available   : DWORD;
  Rec         : INPUT_RECORD;
  Read        : DWORD;
  ButtonState : DWORD;
  ControlKeys : DWORD;
  WheelRaw    : SmallInt;
begin
  Result.Kind := ikNone;

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
      Result.ModCtrl  := (ControlKeys and (LEFT_CTRL_PRESSED or RIGHT_CTRL_PRESSED)) <> 0;
      Result.ModAlt   := (ControlKeys and (LEFT_ALT_PRESSED or RIGHT_ALT_PRESSED)) <> 0;
      Result.ModShift := (ControlKeys and SHIFT_PRESSED) <> 0;

      Result.VK := Rec.Event.KeyEvent.wVirtualKeyCode;
      Result.Ch := Rec.Event.KeyEvent.UnicodeChar;

      if (Result.Ch = #0) and (Result.VK <> 0) then
        Result.Kind := ikSpecial
      else if Result.Ch <> #0 then
        Result.Kind := ikChar
      else
        Result.Kind := ikNone;

      Exit;
    end;

    if Rec.EventType = EVT_MOUSE then
    begin
      ButtonState := Rec.Event.MouseEvent.dwButtonState;
      Result.Kind := ikMouse;
      Result.MouseX := Rec.Event.MouseEvent.dwMousePosition.X + 1;
      Result.MouseY := Rec.Event.MouseEvent.dwMousePosition.Y + 1;

      if (ButtonState and FROM_LEFT_1ST_BUTTON_PRESSED) <> 0 then
        Result.MouseButton := 1
      else if (ButtonState and RIGHTMOST_BUTTON_PRESSED) <> 0 then
        Result.MouseButton := 2
      else
        Result.MouseButton := 0;

      if (Rec.Event.MouseEvent.dwEventFlags and EVT_MOUSE_WHEELED) <> 0 then
      begin
        WheelRaw := SmallInt(ButtonState shr 16);
        Result.WheelDelta := WheelRaw;
      end
      else
        Result.WheelDelta := 0;

      Exit;
    end;
  end;
end;

{ ============================================================================
  SECTIE 5 — Tekst-helpers
  ============================================================================ }

function VisibleLength(const S : string) : Integer;
var I : Integer; InEscape : Boolean;
begin
  Result := 0; InEscape := False;
  for I := 1 to Length(S) do
    if InEscape then
    begin if CharInSet(S[I], ['a'..'z', 'A'..'Z']) then InEscape := False; end
    else if S[I] = #27 then InEscape := True
    else Inc(Result);
end;

function TruncateAnsiString(const S : string; MaxVisible : Integer) : string;
var I, Vis : Integer; InEscape : Boolean;
begin
  Result := '';
  Vis := 0; InEscape := False; I := 1;
  while I <= Length(S) do
  begin
    if InEscape then
    begin
      Result := Result + S[I];
      if CharInSet(S[I], ['a'..'z', 'A'..'Z']) then InEscape := False;
      Inc(I);
    end
    else if S[I] = #27 then
    begin
      InEscape := True; Result := Result + S[I]; Inc(I);
    end
    else if Vis < MaxVisible then
    begin
      Result := Result + S[I]; Inc(Vis); Inc(I);
    end
    else
      Break;
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

function WrapParagraph(const Text : string; MaxWidth : Integer) : TArray<string>;
var L : TList<string>; W : TArray<string>; Cur : string; I : Integer;
begin
  L := TList<string>.Create;
  try
    W := Text.Split([' ']);
    Cur := '';
    for I := 0 to High(W) do
    begin
      if Cur = '' then Cur := W[I]
      else if Length(Cur) + 1 + Length(W[I]) <= MaxWidth then
        Cur := Cur + ' ' + W[I]
      else begin L.Add(Cur); Cur := W[I]; end;
    end;
    if Cur <> '' then L.Add(Cur);
    if L.Count = 0 then L.Add('');
    Result := L.ToArray;
  finally L.Free; end;
end;

function BuildVisualLines(const Buf : string; WrapWidth : Integer) : TArray<TVisualLine>;
var
  Lines   : TList<TVisualLine>;
  Current : TVisualLine;
  I       : Integer;
begin
  Lines := TList<TVisualLine>.Create;
  try
    Current.BufStart := 1;
    Current.Text := '';

    for I := 1 to Length(Buf) do
    begin
      if Buf[I] = #10 then
      begin
        Lines.Add(Current);
        Current.BufStart := I + 1;
        Current.Text := '';
      end
      else
      begin
        if Length(Current.Text) >= WrapWidth then
        begin
          Lines.Add(Current);
          Current.BufStart := I;
          Current.Text := '';
        end;
        Current.Text := Current.Text + Buf[I];
      end;
    end;

    Lines.Add(Current);
    Result := Lines.ToArray;
  finally
    Lines.Free;
  end;
end;

function CursorVisualPos(const Lines : TArray<TVisualLine>;
  Cursor : Integer; out VisRow, VisCol : Integer) : Boolean;
var I, N : Integer;
begin
  VisRow := 0; VisCol := 0; Result := False;
  N := Length(Lines);
  if N = 0 then Exit;

  for I := 0 to N - 1 do
  begin
    if I = N - 1 then
    begin
      VisRow := I;
      VisCol := Cursor - (Lines[I].BufStart - 1);
      if VisCol < 0 then VisCol := 0;
      if VisCol > Length(Lines[I].Text) then VisCol := Length(Lines[I].Text);
      Result := True;
      Exit;
    end
    else if Cursor < Lines[I + 1].BufStart - 1 then
    begin
      VisRow := I;
      VisCol := Cursor - (Lines[I].BufStart - 1);
      if VisCol < 0 then VisCol := 0;
      if VisCol > Length(Lines[I].Text) then VisCol := Length(Lines[I].Text);
      Result := True;
      Exit;
    end;
  end;
end;

function InputWrapWidth : Integer;
begin
  Result := ScreenWidth - 5;
  if Result < 5 then Result := 5;
end;

function CurrentShortTime : string;
begin Result := FormatDateTime('hh:nn', Now); end;

function CurrentLongTime : string;
var
  Y, M, D : Word; H, Mn, S, Ms : Word; H12 : Word; AP : string;
begin
  DecodeDate(Now, Y, M, D);
  DecodeTime(Now, H, Mn, S, Ms);
  if H < 12 then AP := 'am' else AP := 'pm';
  H12 := H mod 12; if H12 = 0 then H12 := 12;
  Result := Format('%d %s %d, %.2d:%.2d:%.2d %s',
    [D, FormatSettings.LongMonthNames[M], Y, H12, Mn, S, AP]);
end;

function RepeatChar(const C : Char; N : Integer) : string;
begin
  if N <= 0 then Result := '' else Result := StringOfChar(C, N);
end;

{ ============================================================================
  SECTIE 6 — Layout
  ============================================================================ }

procedure RecomputeLayout;
var AvailableRows : Integer;
begin
  ReadTerminalSize(ScreenWidth, ScreenHeight);

  ShowLeftPanel  := WantLeftPanel  and (ScreenWidth >= MIN_W_LEFT);
  ShowRightPanel := WantRightPanel and (ScreenWidth >= MIN_W_RIGHT);
  ShowThinking   := WantThinking;

  if ShowLeftPanel then
  begin
    if UserColLeft > 0 then ColLeft := UserColLeft
    else ColLeft := EnsureRange(ScreenWidth div 7, 22, 28);
    if ColLeft < MIN_PANE_WIDTH then ColLeft := MIN_PANE_WIDTH;
  end else ColLeft := 0;

  if ShowRightPanel then
  begin
    if UserColRight > 0 then ColRight := UserColRight
    else ColRight := EnsureRange(ScreenWidth div 5, 30, 40);
    if ColRight < MIN_PANE_WIDTH then ColRight := MIN_PANE_WIDTH;
  end else ColRight := 0;

  ColCenter := ScreenWidth - ColLeft - ColRight - 4;

  if ColCenter < MIN_CHAT_WIDTH then
  begin
    if ShowRightPanel then
    begin
      ColRight := ColRight - (MIN_CHAT_WIDTH - ColCenter);
      if ColRight < MIN_PANE_WIDTH then ColRight := MIN_PANE_WIDTH;
      ColCenter := ScreenWidth - ColLeft - ColRight - 4;
    end;
    if (ColCenter < MIN_CHAT_WIDTH) and ShowLeftPanel then
    begin
      ColLeft := ColLeft - (MIN_CHAT_WIDTH - ColCenter);
      if ColLeft < MIN_PANE_WIDTH then ColLeft := MIN_PANE_WIDTH;
      ColCenter := ScreenWidth - ColLeft - ColRight - 4;
    end;
    if ColCenter < 10 then ColCenter := 10;
  end;

  if UserInputRows > 0 then InputHeight := UserInputRows
  else InputHeight := 1;
  if InputHeight < 1 then InputHeight := 1;
  if InputHeight > MAX_INPUT_ROWS then InputHeight := MAX_INPUT_ROWS;
  if InputHeight > ScreenHeight div 3 then InputHeight := ScreenHeight div 3;

  ContentHeight := ScreenHeight - 7 - InputHeight;
  if ContentHeight < 6 then
  begin
    ContentHeight := 6;
    InputHeight := ScreenHeight - 7 - ContentHeight;
    if InputHeight < 1 then InputHeight := 1;
  end;

  if UserLeftSplit > 0 then LeftSplitRow := UserLeftSplit
  else LeftSplitRow := (ContentHeight - 1) div 2;
  if LeftSplitRow < 3 then LeftSplitRow := 3;
  if LeftSplitRow > ContentHeight - 4 then LeftSplitRow := ContentHeight - 4;

  AvailableRows := ContentHeight - 2;
  if UserPlanRows > 0 then RightPlanRows := UserPlanRows
  else RightPlanRows := AvailableRows div 3;
  if UserWorkRows > 0 then RightWorkRows := UserWorkRows
  else RightWorkRows := AvailableRows div 3;
  if RightPlanRows < 3 then RightPlanRows := 3;
  if RightWorkRows < 3 then RightWorkRows := 3;

  while (RightPlanRows + RightWorkRows) > AvailableRows - 3 do
  begin
    if RightWorkRows > 3 then Dec(RightWorkRows)
    else if RightPlanRows > 3 then Dec(RightPlanRows)
    else Break;
  end;
end;

{ ============================================================================
  SECTIE 7 — Data
  ============================================================================ }

procedure InitializeApplicationData;
var
  Session : TSession; Message_ : TChatMessage; Plan : TPlanItem;
  Work : TWorkItem; Tree : TTreeItem;
begin
  ChatMessages := TList<TChatMessage>.Create;
  PlanItems := TList<TPlanItem>.Create;
  WorkItems := TList<TWorkItem>.Create;
  ThinkingLines := TList<string>.Create;
  SessionList := TList<TSession>.Create;
  TreeList := TList<TTreeItem>.Create;

  CurrentSessionName := 'Architecture Review';

  Tree.Name:='Local';         Tree.Depth:=0; Tree.Perm:='';    TreeList.Add(Tree);
  Tree.Name:='Projects';      Tree.Depth:=1; Tree.Perm:='RWX'; TreeList.Add(Tree);
  Tree.Name:='GRISP';         Tree.Depth:=2; Tree.Perm:='RWX'; TreeList.Add(Tree);
  Tree.Name:='MME-Registry';  Tree.Depth:=2; Tree.Perm:='RW';  TreeList.Add(Tree);
  Tree.Name:='Agent-Network'; Tree.Depth:=2; Tree.Perm:='RW';  TreeList.Add(Tree);
  Tree.Name:='Data';          Tree.Depth:=1; Tree.Perm:='RW';  TreeList.Add(Tree);
  Tree.Name:='Models';        Tree.Depth:=2; Tree.Perm:='RW';  TreeList.Add(Tree);
  Tree.Name:='Downloads';     Tree.Depth:=2; Tree.Perm:='R';   TreeList.Add(Tree);
  Tree.Name:='Cloud';         Tree.Depth:=1; Tree.Perm:='R';   TreeList.Add(Tree);

  Session.Name:='Architecture Review'; Session.Meta:='24 Sep - 14:30'; SessionList.Add(Session);
  Session.Name:='MME Schema Draft';    Session.Meta:='24 Sep - 12:10'; SessionList.Add(Session);
  Session.Name:='Agent Graph';         Session.Meta:='23 Sep - 18:22'; SessionList.Add(Session);
  Session.Name:='VFS Refactor Notes';  Session.Meta:='23 Sep - 09:15'; SessionList.Add(Session);

  Message_.Role := crAssistant;
  Message_.Text := 'Hello Alex, how can I help you with GRISP today?';
  Message_.Time := CurrentShortTime;
  ChatMessages.Add(Message_);
  Message_.Text := 'I can help with analysis, planning, or code generation. Just ask.';
  Message_.Time := CurrentShortTime;
  ChatMessages.Add(Message_);

  Plan.Text:='Analyze VFS Layer';           Plan.Status:=psDone;    PlanItems.Add(Plan);
  Plan.Text:='Extract MME schema';          Plan.Status:=psDone;    PlanItems.Add(Plan);
  Plan.Text:='Map Agent Network';           Plan.Status:=psRunning; PlanItems.Add(Plan);
  Plan.Text:='Draft DNA report';            Plan.Status:=psQueued;  PlanItems.Add(Plan);
  Plan.Text:='Validate permissions matrix'; Plan.Status:=psQueued;  PlanItems.Add(Plan);

  Work.Text:='Implement GRISP runtime'; Work.Prio:=wpHigh;   WorkItems.Add(Work);
  Work.Text:='Add graph visualization'; Work.Prio:=wpMedium; WorkItems.Add(Work);
  Work.Text:='Write unit tests';        Work.Prio:=wpMedium; WorkItems.Add(Work);
  Work.Text:='Update LSBP integration'; Work.Prio:=wpLow;    WorkItems.Add(Work);

  ThinkingLines.Add('Waiting for user input...');
  ThinkingLines.Add('Parsing GRISP environment...');
  ThinkingLines.Add('Ready to assist.');
end;

procedure ShutdownApplicationData;
begin
  ChatMessages.Free; PlanItems.Free; WorkItems.Free;
  ThinkingLines.Free; SessionList.Free; TreeList.Free;
end;

{ ============================================================================
  SECTIE 8 — Panelen
  ============================================================================ }

function RenderLeftPane : TArray<string>;
var
  Lines : TList<string>; I, Indent, NameWidth, SessRows : Integer;
  Buf, PermColor, NameField, DividerCol : string;
  Item : TTreeItem; Session : TSession;

  procedure AddLine(const S : string);
  begin Lines.Add(PadToWidth(S, ColLeft, BG_PANEL) + ANSI_RESET); end;

begin
  Lines := TList<string>.Create;
  try
    SessRows := ContentHeight - 1 - LeftSplitRow;

    AddLine(BG_PANEL + FG_CYAN + ANSI_BOLD + ' ' + GLYPH_FDIAMOND + ' RESOURCES');
    AddLine(BG_PANEL + FG_BORDER + ' ' + RepeatChar(GLYPH_HORZ, ColLeft - 2));

    for I := 0 to LeftSplitRow - 3 do
    begin
      if I < TreeList.Count then
      begin
        Item := TreeList[I];
        Indent := 1 + Item.Depth * 2;
        NameWidth := ColLeft - Indent - 8;
        if NameWidth < 4 then NameWidth := 4;

        if Item.Perm = '' then
          Buf := BG_PANEL + FG_CYAN + StringOfChar(' ', Indent)
               + GLYPH_RTRI + ' ' + ANSI_BOLD + Item.Name
        else
        begin
          if Item.Perm = 'RWX' then PermColor := FG_CYAN
          else if Item.Perm = 'RW' then PermColor := FG_AMBER
          else PermColor := FG_GRAY;

          NameField := Item.Name;
          if Length(NameField) > NameWidth then
            NameField := Copy(NameField, 1, NameWidth);
          NameField := NameField + StringOfChar(' ', NameWidth - Length(NameField));

          Buf := BG_PANEL + StringOfChar(' ', Indent) + FG_TEXT + GLYPH_RTRI + ' '
               + NameField + ' ' + PermColor + Item.Perm;
        end;
        AddLine(Buf);
      end
      else AddLine(BG_PANEL);
    end;

    while Lines.Count < LeftSplitRow do AddLine(BG_PANEL);

    if (HoverTarget = 11) or (IsDragging and (DragTarget = 11)) then
      DividerCol := FG_CYAN else DividerCol := FG_BORDER;
    Lines.Add(BG_PANEL + DividerCol + RepeatChar(GLYPH_HORZ, ColLeft) + ANSI_RESET);

    AddLine(BG_PANEL + FG_CYAN + ANSI_BOLD + ' ' + GLYPH_FDIAMOND + ' SESSIONS');
    AddLine(BG_PANEL + FG_BORDER + ' ' + RepeatChar(GLYPH_HORZ, ColLeft - 2));

    for I := 0 to SessRows - 3 do
    begin
      if I < SessionList.Count then
      begin
        Session := SessionList[I];
        if I = ActiveSessionIndex then
          Buf := BG_PANEL + FG_CYAN + ANSI_BOLD + ' ' + GLYPH_RTRI + ' ' + Session.Name
        else
          Buf := BG_PANEL + FG_TEXT + ' ' + GLYPH_RTRI + ' ' + Session.Name;
        AddLine(Buf);
        AddLine(BG_PANEL + FG_GRAY + '    ' + Session.Meta);
      end
      else AddLine(BG_PANEL);
    end;

    while Lines.Count < ContentHeight do AddLine(BG_PANEL);
    Result := Lines.ToArray;
  finally Lines.Free; end;
end;

function RenderCenterPane : TArray<string>;
var
  Vis, Full : TList<string>;
  I, J, Total, WS, WE, BodyH, RightPad : Integer;
  Msg : TChatMessage; Wrapped : TArray<string>;
  Buf, SenderColor, Prefix, TimePart, Header : string;

  procedure Emit(const S : string);
  begin Vis.Add(PadToWidth(S, ColCenter, BG_MAIN) + ANSI_RESET); end;

begin
  Vis := TList<string>.Create; Full := TList<string>.Create;
  try
    Header := BG_MAIN + ' ' + FG_CYAN + ANSI_BOLD + GLYPH_FDIAMOND + ' CHAT'
            + ANSI_RESET + BG_MAIN + FG_DGRAY + ' - ' + FG_TEXT + CurrentSessionName;
    if ChatScroll > 0 then
      Header := Header + ANSI_RESET + BG_MAIN + '  ' + FG_AMBER + GLYPH_UP
              + ' scrolled +' + IntToStr(ChatScroll);
    Vis.Add(PadToWidth(Header, ColCenter, BG_MAIN) + ANSI_RESET);
    Vis.Add(PadToWidth(BG_MAIN + ' ' + FG_BORDER
      + RepeatChar(GLYPH_HORZ, ColCenter - 2), ColCenter, BG_MAIN) + ANSI_RESET);

    for I := 0 to ChatMessages.Count - 1 do
    begin
      Msg := ChatMessages[I];
      case Msg.Role of
        crUser: begin SenderColor := FG_USER + ANSI_BOLD; Prefix := ' You'; end;
        crAssistant: begin SenderColor := FG_CYAN + ANSI_BOLD;
                          Prefix := ' ' + GLYPH_DIAMOND + ' GRISP Assistant'; end;
        else begin SenderColor := FG_AMBER + ANSI_BOLD; Prefix := ' [sys]'; end;
      end;

      TimePart := '[' + Msg.Time + ']';
      Buf := BG_MAIN + SenderColor + Prefix;
      RightPad := ColCenter - 1 - VisibleLength(Buf) - Length(TimePart);
      if RightPad < 1 then RightPad := 1;
      Buf := Buf + StringOfChar(' ', RightPad) + FG_DGRAY + TimePart + ' ';
      Full.Add(Buf);

      Wrapped := WrapParagraph(Msg.Text, ColCenter - 8);
      for J := 0 to High(Wrapped) do
      begin
        case Msg.Role of
          crUser: Buf := BG_MAIN + '  ' + BG_USER + FG_TEXT + '  ' + Wrapped[J]
                       + '  ' + ANSI_RESET + BG_MAIN;
          crAssistant: Buf := BG_MAIN + '  ' + BG_AI + FG_SLATE + GLYPH_BLOCK
                            + BG_AI + FG_TEXT + ' ' + Wrapped[J] + '  '
                            + ANSI_RESET + BG_MAIN;
          else Buf := BG_MAIN + '  ' + FG_GRAY + '    ' + Wrapped[J];
        end;
        Full.Add(Buf);
      end;
      Full.Add(BG_MAIN);
    end;

    BodyH := ContentHeight - 2;
    if BodyH < 1 then BodyH := 1;
    Total := Full.Count;
    if Total > BodyH then ChatMaxScroll := Total - BodyH else ChatMaxScroll := 0;
    if ChatScroll > ChatMaxScroll then ChatScroll := ChatMaxScroll;
    if ChatScroll < 0 then ChatScroll := 0;
    WE := Total - ChatScroll; if WE < 0 then WE := 0;
    WS := WE - BodyH; if WS < 0 then WS := 0;
    for I := WS to WE - 1 do Emit(Full[I]);
    while Vis.Count < ContentHeight do Emit(BG_MAIN);
    Result := Vis.ToArray;
  finally Vis.Free; Full.Free; end;
end;

function RenderRightPane : TArray<string>;
var
  Lines : TList<string>; I, ThinkRows, Div1, Div2 : Integer;
  Buf, Sym, SymCol, PrioCol, PrioLabel, DivCol1, DivCol2 : string;
  Plan : TPlanItem; Work : TWorkItem;

  procedure AddLine(const S : string);
  begin Lines.Add(PadToWidth(S, ColRight, BG_PANEL) + ANSI_RESET); end;

begin
  Lines := TList<string>.Create;
  try
    ThinkRows := ContentHeight - 2 - RightPlanRows - RightWorkRows;
    if ThinkRows < 3 then ThinkRows := 3;
    Div1 := RightPlanRows;
    Div2 := RightPlanRows + 1 + RightWorkRows;

    if (HoverTarget = 12) or (IsDragging and (DragTarget = 12)) then
      DivCol1 := FG_CYAN else DivCol1 := FG_BORDER;
    if (HoverTarget = 13) or (IsDragging and (DragTarget = 13)) then
      DivCol2 := FG_CYAN else DivCol2 := FG_BORDER;

    AddLine(BG_PANEL + FG_CYAN + ANSI_BOLD + ' ' + GLYPH_FDIAMOND + ' CURRENT PLAN');
    AddLine(BG_PANEL + FG_BORDER + ' ' + RepeatChar(GLYPH_HORZ, ColRight - 2));
    for I := 0 to RightPlanRows - 3 do
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
      AddLine(Buf);
    end;
    while Lines.Count < Div1 do AddLine(BG_PANEL);
    Lines.Add(BG_PANEL + DivCol1 + RepeatChar(GLYPH_HORZ, ColRight) + ANSI_RESET);

    AddLine(BG_PANEL + FG_CYAN + ANSI_BOLD + ' ' + GLYPH_FDIAMOND + ' WORK ITEMS');
    AddLine(BG_PANEL + FG_BORDER + ' ' + RepeatChar(GLYPH_HORZ, ColRight - 2));
    for I := 0 to RightWorkRows - 3 do
    begin
      if I < WorkItems.Count then
      begin
        Work := WorkItems[I];
        case Work.Prio of
          wpHigh:   begin PrioCol := FG_RED;   PrioLabel := '[HIGH]'; end;
          wpMedium: begin PrioCol := FG_AMBER; PrioLabel := '[MED ]'; end;
          else      begin PrioCol := FG_GREEN; PrioLabel := '[LOW ]'; end;
        end;
        Buf := BG_PANEL + ' ' + FG_TEXT + Work.Text + '  ' + PrioCol + PrioLabel;
      end else Buf := BG_PANEL;
      AddLine(Buf);
    end;
    while Lines.Count < Div2 do AddLine(BG_PANEL);
    Lines.Add(BG_PANEL + DivCol2 + RepeatChar(GLYPH_HORZ, ColRight) + ANSI_RESET);

    if ShowThinking then
      AddLine(BG_PANEL + FG_PURPLE + ANSI_BOLD + ' ' + GLYPH_FDIAMOND
            + ' THINKING  ' + FG_DGRAY + '[F3]')
    else
      AddLine(BG_PANEL + FG_DGRAY + ' ' + GLYPH_FDIAMOND
            + ' THINKING  [F3 - hidden]');
    AddLine(BG_PANEL + FG_BORDER + ' ' + RepeatChar(GLYPH_HORZ, ColRight - 2));

    for I := 0 to ThinkRows - 3 do
    begin
      if ShowThinking and (I < ThinkingLines.Count) then
        Buf := BG_PANEL + ' ' + FG_BORDER + GLYPH_GT + ' ' + FG_GRAY + ThinkingLines[I]
      else Buf := BG_PANEL;
      AddLine(Buf);
    end;

    while Lines.Count < ContentHeight do AddLine(BG_PANEL);
    Result := Lines.ToArray;
  finally Lines.Free; end;
end;

{ ============================================================================
  SECTIE 9 — Frame samenstellen
  ============================================================================ }

function RenderFrame : string;
var
  SB : TStringBuilder;
  LeftPane, CenterPane, RightPane : TArray<string>;
  InputLines : TArray<TVisualLine>;
  I, RowIndex, CaretRow, CaretCol, VisRow, VisCol : Integer;
  MaxScroll, FirstInputRow : Integer;
  TitleLine, TopBar, SepTop, SepBot, InputLine, StatusLine : string;
  MouseLabel, Hints, ClockString : string;
  SepColorL, SepColorR, SepColorB : string;
  LineText, PromptPrefix : string;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append(CURSOR_HIDE);
    SB.Append(CURSOR_HOME);

    SepColorL := FG_BORDER;
    if (HoverTarget = 1) or (IsDragging and (DragTarget = 1)) then SepColorL := FG_CYAN;
    SepColorR := FG_BORDER;
    if (HoverTarget = 2) or (IsDragging and (DragTarget = 2)) then SepColorR := FG_CYAN;

    SB.Append(FG_BORDER + GLYPH_TOPLEFT
            + RepeatChar(GLYPH_HORZ, ScreenWidth - 2)
            + GLYPH_TOPRIGHT + ANSI_RESET + #13#10);

    if ScreenWidth >= 150 then
      Hints := '   ' + FG_DGRAY + '[Ctrl+Enter]' + FG_TEXT + ' Send'
             + '  ' + FG_DGRAY + '[F1]' + FG_TEXT + ' Res'
             + '  ' + FG_DGRAY + '[F2]' + FG_TEXT + ' Right'
             + '  ' + FG_DGRAY + '[F3]' + FG_TEXT + ' Think'
             + '  ' + FG_DGRAY + '[F5]' + FG_TEXT + ' Mouse'
             + '  ' + FG_DGRAY + '[F6]' + FG_TEXT + ' Reset'
             + '  ' + FG_DGRAY + '[Esc]' + FG_TEXT + ' Quit'
    else if ScreenWidth >= 110 then
      Hints := '  ' + FG_DGRAY + '[^Enter]' + FG_TEXT + 'Send'
             + ' ' + FG_DGRAY + '[F1]R' + FG_TEXT + ' '
             + FG_DGRAY + '[F2]Rt' + FG_TEXT + ' ' + FG_DGRAY + '[F3]T'
             + FG_TEXT + ' ' + FG_DGRAY + '[F5]M' + FG_TEXT + ' '
             + FG_DGRAY + '[Esc]Q'
    else Hints := '';

    TitleLine := BG_BAR + ' ' + FG_CYAN + ANSI_BOLD + GLYPH_DIAMOND + ' '
               + APP_NAME + ' ' + FG_DGRAY + APP_VERSION + ANSI_RESET + BG_BAR + Hints;
    ClockString := ' ' + CurrentLongTime + '  ';
    TopBar := PadToWidth(TitleLine, ScreenWidth - 2 - Length(ClockString), BG_BAR)
            + FG_CYAN + ClockString;
    SB.Append(FG_BORDER + GLYPH_VERT + ANSI_RESET
            + PadToWidth(TopBar, ScreenWidth - 2, BG_BAR) + ANSI_RESET
            + FG_BORDER + GLYPH_VERT + ANSI_RESET + #13#10);

    if ShowLeftPanel and ShowRightPanel then
      SepTop := GLYPH_TEEEAST + RepeatChar(GLYPH_HORZ, ColLeft)
              + SepColorL + GLYPH_TEEDOWN + FG_BORDER
              + RepeatChar(GLYPH_HORZ, ColCenter)
              + SepColorR + GLYPH_TEEDOWN + FG_BORDER
              + RepeatChar(GLYPH_HORZ, ColRight) + GLYPH_TEEWEST
    else if ShowRightPanel then
      SepTop := GLYPH_TEEEAST + RepeatChar(GLYPH_HORZ, ScreenWidth - ColRight - 3)
              + SepColorR + GLYPH_TEEDOWN + FG_BORDER
              + RepeatChar(GLYPH_HORZ, ColRight) + GLYPH_TEEWEST
    else if ShowLeftPanel then
      SepTop := GLYPH_TEEEAST + RepeatChar(GLYPH_HORZ, ColLeft)
              + SepColorL + GLYPH_TEEDOWN + FG_BORDER
              + RepeatChar(GLYPH_HORZ, ScreenWidth - ColLeft - 3) + GLYPH_TEEWEST
    else
      SepTop := GLYPH_TEEEAST + RepeatChar(GLYPH_HORZ, ScreenWidth - 2) + GLYPH_TEEWEST;
    SB.Append(FG_BORDER + SepTop + ANSI_RESET + #13#10);

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
        SB.Append(SepColorL + GLYPH_VERT + ANSI_RESET);
      end;
      if RowIndex < Length(CenterPane) then SB.Append(CenterPane[RowIndex])
      else SB.Append(PadToWidth('', ColCenter, BG_MAIN) + ANSI_RESET);
      if ShowRightPanel then
      begin
        SB.Append(SepColorR + GLYPH_VERT + ANSI_RESET);
        if RowIndex < Length(RightPane) then SB.Append(RightPane[RowIndex])
        else SB.Append(PadToWidth('', ColRight, BG_PANEL) + ANSI_RESET);
      end;
      SB.Append(FG_BORDER + GLYPH_VERT + ANSI_RESET + #13#10);
    end;

    if (HoverTarget = 10) or (IsDragging and (DragTarget = 10)) then
      SepColorB := FG_CYAN else SepColorB := FG_BORDER;

    if ShowLeftPanel and ShowRightPanel then
      SepBot := GLYPH_TEEEAST + RepeatChar(GLYPH_HORZ, ColLeft)
              + SepColorB + GLYPH_TEEUP + FG_BORDER
              + RepeatChar(GLYPH_HORZ, ColCenter)
              + SepColorB + GLYPH_TEEUP + FG_BORDER
              + RepeatChar(GLYPH_HORZ, ColRight) + GLYPH_TEEWEST
    else
      SepBot := GLYPH_TEEEAST + RepeatChar(GLYPH_HORZ, ScreenWidth - 2) + GLYPH_TEEWEST;
    SB.Append(SepColorB + SepBot + ANSI_RESET + #13#10);

    InputLines := BuildVisualLines(InputBuffer, InputWrapWidth);
    FirstInputRow := 5 + ContentHeight;

    CaretRow := FirstInputRow;
    CaretCol := 5;
    VisRow := 0; VisCol := 0;

    if CursorVisualPos(InputLines, InputCursor, VisRow, VisCol) then
    begin
      MaxScroll := Length(InputLines) - InputHeight;
      if MaxScroll < 0 then MaxScroll := 0;
      if VisRow < InputScroll then InputScroll := VisRow;
      if VisRow >= InputScroll + InputHeight then
        InputScroll := VisRow - InputHeight + 1;
      if InputScroll < 0 then InputScroll := 0;
      if InputScroll > MaxScroll then InputScroll := MaxScroll;
    end
    else
    begin
      InputScroll := 0;
      VisRow := 0; VisCol := 0;
    end;

    for I := 0 to InputHeight - 1 do
    begin
      if (InputScroll + I) < Length(InputLines) then
        LineText := InputLines[InputScroll + I].Text
      else LineText := '';

      if (InputScroll + I) = 0 then PromptPrefix := ' > '
      else PromptPrefix := '   ';

      if SimActive then
      begin
        if I = 0 then
          InputLine := BG_INPUT + ' ' + FG_AMBER + ANSI_BOLD + '...'
                     + ANSI_RESET + BG_INPUT + FG_AMBER + ' Processing ['
                     + PromptState + '] - [Ctrl+Enter] to step'
        else InputLine := BG_INPUT;
      end
      else
        InputLine := BG_INPUT + FG_CYAN + ANSI_BOLD + PromptPrefix
                   + ANSI_RESET + BG_INPUT + FG_TEXT + LineText;

      SB.Append(FG_BORDER + GLYPH_VERT + ANSI_RESET
              + PadToWidth(InputLine, ScreenWidth - 2, BG_INPUT) + ANSI_RESET
              + FG_BORDER + GLYPH_VERT + ANSI_RESET + #13#10);
    end;

    if not SimActive then
    begin
      CaretRow := FirstInputRow + (VisRow - InputScroll);
      CaretCol := 5 + VisCol;
      if CaretCol > ScreenWidth - 1 then CaretCol := ScreenWidth - 1;
      if CaretRow < FirstInputRow then CaretRow := FirstInputRow;
      if CaretRow > FirstInputRow + InputHeight - 1 then
        CaretRow := FirstInputRow + InputHeight - 1;
    end;

    SB.Append(FG_BORDER + GLYPH_TEEEAST
            + RepeatChar(GLYPH_HORZ, ScreenWidth - 2)
            + GLYPH_TEEWEST + ANSI_RESET + #13#10);

    case StatusKind of
      0 : TitleLine := FG_GREEN;
      1 : TitleLine := FG_AMBER;
      else TitleLine := FG_RED;
    end;
    if MouseEnabled then MouseLabel := 'on' else MouseLabel := 'off';

    StatusLine := BG_BAR + ' ' + TitleLine + GLYPH_DOT + ANSI_RESET
                + BG_BAR + ' ' + FG_TEXT + 'Connected'
                + ' ' + FG_DGRAY + GLYPH_VERT + ANSI_RESET
                + BG_BAR + ' ' + FG_GRAY + 'Model:' + FG_TEXT + ' GPT-5'
                + ' ' + FG_DGRAY + GLYPH_VERT + ANSI_RESET
                + BG_BAR + ' ' + FG_GRAY + 'Prompt:' + TitleLine + ' ' + PromptState
                + ' ' + FG_DGRAY + GLYPH_VERT + ANSI_RESET
                + BG_BAR + ' ' + FG_GRAY + 'Session:' + FG_TEXT + ' '
                + IntToStr(ActiveSessionIndex + 1) + '/'
                + IntToStr(SessionList.Count)
                + ' ' + FG_DGRAY + GLYPH_VERT + ANSI_RESET
                + BG_BAR + ' ' + FG_GRAY + 'Mouse:' + FG_TEXT + ' ' + MouseLabel
                + ' ' + FG_DGRAY + GLYPH_VERT + ANSI_RESET
                + BG_BAR + ' ' + FG_GRAY + 'Perms:' + FG_CYAN + ' RWX';
    SB.Append(FG_BORDER + GLYPH_VERT + ANSI_RESET
            + PadToWidth(StatusLine, ScreenWidth - 2, BG_BAR) + ANSI_RESET
            + FG_BORDER + GLYPH_VERT + ANSI_RESET + #13#10);

    SB.Append(FG_BORDER + GLYPH_BOTLEFT
            + RepeatChar(GLYPH_HORZ, ScreenWidth - 2)
            + GLYPH_BOTRIGHT + ANSI_RESET);

    if not SimActive then
    begin
      SB.Append(ESC + '[' + IntToStr(CaretRow) + ';'
              + IntToStr(CaretCol) + 'H');
      SB.Append(CURSOR_SHOW);
    end
    else SB.Append(CURSOR_HIDE);

    Result := SB.ToString;
  finally SB.Free; end;
end;

{ ============================================================================
  SECTIE 10 — Simulatie
  ============================================================================ }

procedure AppendUserMessage(const Text : string);
var M : TChatMessage;
begin M.Role := crUser; M.Text := Text; M.Time := CurrentShortTime; ChatMessages.Add(M); end;

procedure AppendAssistantMessage(const Text : string);
var M : TChatMessage;
begin M.Role := crAssistant; M.Text := Text; M.Time := CurrentShortTime; ChatMessages.Add(M); end;

procedure BeginSimulation;
begin
  SimActive := True; SimStep := 0; SimTimer := GetTickCount;
  PromptState := 'PENDING'; StatusKind := 1; ChatScroll := 0;
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
    1: begin PromptState := 'SUBMITTING';
             ThinkingLines.Clear;
             ThinkingLines.Add('INPUT_SUBMITTED (provider_native_send)');
             ThinkingLines.Add('Verifying input ownership...');
             ThinkingLines.Add('Awaiting GENERATION_STARTED...'); end;
    2: begin PromptState := 'GENERATING';
             ThinkingLines.Clear;
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
  InputBuffer := '';
  InputCursor := 0;
  InputScroll := 0;
  BeginSimulation;
end;

{ ============================================================================
  SECTIE 11 — Input editor acties
  ============================================================================ }

procedure ClampInputCursor;
begin
  if InputCursor < 0 then InputCursor := 0;
  if InputCursor > Length(InputBuffer) then InputCursor := Length(InputBuffer);
end;

procedure InsertAtCaret(const S : string);
begin
  if S = '' then Exit;
  Insert(S, InputBuffer, InputCursor + 1);
  Inc(InputCursor, Length(S));
  ClampInputCursor;
end;

procedure BackspaceAtCaret;
begin
  if InputCursor > 0 then
  begin
    Delete(InputBuffer, InputCursor, 1);
    Dec(InputCursor);
  end;
end;

procedure DeleteAtCaret;
begin
  if InputCursor < Length(InputBuffer) then
    Delete(InputBuffer, InputCursor + 1, 1);
end;

procedure MoveCaretLeft;
begin
  if InputCursor > 0 then Dec(InputCursor);
end;

procedure MoveCaretRight;
begin
  if InputCursor < Length(InputBuffer) then Inc(InputCursor);
end;

procedure MoveCaretHome;
var Lines : TArray<TVisualLine>; VisRow, VisCol : Integer;
begin
  Lines := BuildVisualLines(InputBuffer, InputWrapWidth);
  if CursorVisualPos(Lines, InputCursor, VisRow, VisCol) then
    InputCursor := Lines[VisRow].BufStart - 1;
  ClampInputCursor;
end;

procedure MoveCaretEnd;
var Lines : TArray<TVisualLine>; VisRow, VisCol : Integer;
begin
  Lines := BuildVisualLines(InputBuffer, InputWrapWidth);
  if CursorVisualPos(Lines, InputCursor, VisRow, VisCol) then
    InputCursor := (Lines[VisRow].BufStart - 1) + Length(Lines[VisRow].Text);
  ClampInputCursor;
end;

procedure MoveCaretVertical(const Delta : Integer);
var
  Lines : TArray<TVisualLine>;
  VisRow, VisCol, TargetRow, NewCursor : Integer;
begin
  Lines := BuildVisualLines(InputBuffer, InputWrapWidth);
  if not CursorVisualPos(Lines, InputCursor, VisRow, VisCol) then Exit;

  TargetRow := VisRow + Delta;
  if TargetRow < 0 then TargetRow := 0;
  if TargetRow > High(Lines) then TargetRow := High(Lines);

  if VisCol > Length(Lines[TargetRow].Text) then
    VisCol := Length(Lines[TargetRow].Text);

  NewCursor := (Lines[TargetRow].BufStart - 1) + VisCol;
  InputCursor := NewCursor;
  ClampInputCursor;
end;

function GetClipboardText : string;
var
  Data : THandle;
  Ptr  : Pointer;
begin
  Result := '';
  if not OpenClipboard(0) then Exit;
  try
    Data := GetClipboardData(MY_CF_UNICODETEXT);
    if Data <> 0 then
    begin
      Ptr := GlobalLock(Data);
      if Ptr <> nil then
      try
        Result := string(PWideChar(Ptr));
      finally
        GlobalUnlock(Data);
      end;
    end;
  finally
    CloseClipboard;
  end;
end;

procedure PasteFromClipboard;
var Txt : string;
begin
  Txt := GetClipboardText;
  if Txt = '' then Exit;
  Txt := StringReplace(Txt, #13#10, #10, [rfReplaceAll]);
  Txt := StringReplace(Txt, #13, #10, [rfReplaceAll]);
  InsertAtCaret(Txt);
end;

{ ============================================================================
  SECTIE 12 — Muisafhandeling
  ============================================================================ }

procedure UpdateHoverTarget(MouseX, MouseY : Integer);
var RStart, REnd : Integer;
begin
  HoverTarget := 0;
  RStart := ColLeft + ColCenter + 4;
  REnd   := ColLeft + ColCenter + ColRight + 3;

  if ShowLeftPanel and (MouseX = ColLeft + 2) then HoverTarget := 1
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
begin
  case DragTarget of
    1: begin
         UserColLeft := Ev.MouseX - 2;
         if UserColLeft < MIN_PANE_WIDTH then UserColLeft := MIN_PANE_WIDTH;
         if UserColLeft > ScreenWidth - MIN_CHAT_WIDTH - ColRight - 4 then
           UserColLeft := ScreenWidth - MIN_CHAT_WIDTH - ColRight - 4;
       end;
    2: begin
         UserColRight := ScreenWidth - Ev.MouseX - 1;
         if UserColRight < MIN_PANE_WIDTH then UserColRight := MIN_PANE_WIDTH;
         if UserColRight > ScreenWidth - MIN_CHAT_WIDTH - ColLeft - 4 then
           UserColRight := ScreenWidth - MIN_CHAT_WIDTH - ColLeft - 4;
       end;
    10: begin
          UserInputRows := ScreenHeight - 7 - (Ev.MouseY - 4);
          if UserInputRows < 1 then UserInputRows := 1;
          if UserInputRows > MAX_INPUT_ROWS then UserInputRows := MAX_INPUT_ROWS;
        end;
    11: begin
          UserLeftSplit := Ev.MouseY - 4;
          if UserLeftSplit < 3 then UserLeftSplit := 3;
          if UserLeftSplit > ContentHeight - 4 then UserLeftSplit := ContentHeight - 4;
        end;
    12: begin
          UserPlanRows := Ev.MouseY - 4;
          if UserPlanRows < 3 then UserPlanRows := 3;
          if UserPlanRows > ContentHeight - 8 then UserPlanRows := ContentHeight - 8;
        end;
    13: begin
          UserWorkRows := Ev.MouseY - (4 + RightPlanRows + 1);
          if UserWorkRows < 3 then UserWorkRows := 3;
          if UserWorkRows > ContentHeight - 8 then UserWorkRows := ContentHeight - 8;
        end;
  end;
  RecomputeLayout;
end;

procedure HandleMouseEvent(const Ev : TInputEvent);
var WheelLines : Integer;
begin
  UpdateHoverTarget(Ev.MouseX, Ev.MouseY);

  if Ev.WheelDelta <> 0 then
  begin
    WheelLines := (Ev.WheelDelta div 120) * 3;
    ChatScroll := ChatScroll + WheelLines;
  end;

  if IsDragging then
  begin
    if Ev.MouseButton = 1 then ApplyDrag(Ev)
    else begin IsDragging := False; DragTarget := 0; end;
    Exit;
  end;

  if Ev.MouseButton = 1 then
  begin
    if HoverTarget >= 1 then
    begin
      IsDragging := True;
      DragTarget := HoverTarget;
    end
    else if (Ev.MouseY >= 4) and (Ev.MouseY <= ScreenHeight - 2) then
      ChatScroll := 0;
  end;
end;

{ ============================================================================
  SECTIE 13 — Toetsafhandeling
  ============================================================================ }

procedure ResetAllUserSizes;
begin
  UserColLeft := 0; UserColRight := 0; UserInputRows := 0;
  UserLeftSplit := 0; UserPlanRows := 0; UserWorkRows := 0;
  RecomputeLayout;
end;

procedure HandleKeyEvent(const Ev : TInputEvent);
begin
  { ---- Speciale toetsen ---- }
  if Ev.Kind = ikSpecial then
  begin
    case Ev.VK of
      VK_LEFT:   MoveCaretLeft;
      VK_RIGHT:  MoveCaretRight;
      VK_UP:     MoveCaretVertical(-1);
      VK_DOWN:   MoveCaretVertical(+1);
      VK_HOME:   MoveCaretHome;
      VK_END:    MoveCaretEnd;
      VK_DELETE: DeleteAtCaret;
      VK_BACK:   BackspaceAtCaret;

      VK_ESCAPE: QuitRequested := True;
      VK_F1: begin WantLeftPanel := not WantLeftPanel; RecomputeLayout; end;
      VK_F2: begin WantRightPanel := not WantRightPanel; RecomputeLayout; end;
      VK_F3: WantThinking := not WantThinking;
      VK_F4: if SimActive then AdvanceSimulation else SubmitPrompt;
      VK_F5: begin MouseEnabled := not MouseEnabled; ApplyInputMode; end;
      VK_F6: ResetAllUserSizes;

      VK_PRIOR: ChatScroll := ChatScroll + 5;
      VK_NEXT:  ChatScroll := ChatScroll - 5;
    end;
    Exit;
  end;

  { ---- Gewone tekens ---- }
  if Ev.Kind <> ikChar then Exit;

  { Ctrl+V = paste }
  if Ev.ModCtrl and (not Ev.ModAlt) and (Ev.Ch = #$16) then
  begin
    if not SimActive then PasteFromClipboard;
    Exit;
  end;

  { Enter: Shift+Enter en kale Enter voegen een nieuwe regel in.
    Alleen Ctrl+Enter of Alt+Enter verstuurt het bericht. }
  if Ev.Ch = #13 then
  begin
    if SimActive then
    begin
      { Tijdens simulatie: elke Enter / Ctrl+Enter / Alt+Enter = stap. }
      if Ev.ModCtrl or Ev.ModAlt or (not Ev.ModShift) then
        AdvanceSimulation;
      Exit;
    end;

    if Ev.ModCtrl or Ev.ModAlt then
      SubmitPrompt          { Ctrl+Enter of Alt+Enter = versturen }
    else
      InsertAtCaret(#10);   { Enter of Shift+Enter = nieuwe regel }
    Exit;
  end;

  { Backspace — alleen als karakter-event. }
  if Ev.Ch = #8 then
  begin
    if not SimActive then BackspaceAtCaret;
    Exit;
  end;

  { Gewone printable tekens. }
  if (Ord(Ev.Ch) >= 32) and not SimActive
     and not Ev.ModCtrl and not Ev.ModAlt then
    InsertAtCaret(Ev.Ch);
end;

{ ============================================================================
  SECTIE 14 — Hoofdlus
  ============================================================================ }

procedure RunApplication;
var
  Ev : TInputEvent;
  NewWidth, NewHeight : Integer;
begin
  InitializeConsole;
  InitializeApplicationData;
  try
    WriteAtomic(SCREEN_ALT_ON);
    WriteAtomic(ANSI_RESET + SCREEN_CLEAR);

    while not QuitRequested do
    begin
      ReadTerminalSize(NewWidth, NewHeight);
      if (NewWidth <> ScreenWidth) or (NewHeight <> ScreenHeight) then
      begin
        RecomputeLayout;
        WriteAtomic(ANSI_RESET + SCREEN_CLEAR);
      end;

      WriteAtomic(RenderFrame);

      repeat
        Ev := ReadInputEvent;
        if Ev.Kind = ikNone then Break;
        case Ev.Kind of
          ikChar, ikSpecial: HandleKeyEvent(Ev);
          ikMouse: if MouseEnabled then HandleMouseEvent(Ev);
        end;
      until False;

      if SimActive and ((GetTickCount - SimTimer) > SIM_INTERVAL_MS) then
      begin
        SimTimer := GetTickCount;
        AdvanceSimulation;
      end;

      Sleep(25);
    end;
  finally
    MouseEnabled := False;
    ApplyInputMode;
    WriteAtomic(ANSI_RESET + CURSOR_SHOW + SCREEN_ALT_OFF);
    ShutdownApplicationData;
  end;
end;

{ ============================================================================
  SECTIE 15 — Entry point
  ============================================================================ }

begin
  try
    RunApplication;
  except
    on E : Exception do
    begin
      Writeln('Fatal error: ', E.Message);
      Halt(1);
    end;
  end;
end.
