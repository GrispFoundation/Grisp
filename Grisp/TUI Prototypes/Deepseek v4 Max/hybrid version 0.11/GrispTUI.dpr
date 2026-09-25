{ ============================================================================
  GRISP OS — Terminal UI  ·  v0.21
  ----------------------------------------------------------------------------
  Nieuw in v0.21
    • Input-veld heeft geen ">" prefix meer — gewoon typen langs de lijn
    • Scrollbar in chat is nu muis-bestuurbaar:
        - klik op de scrollbar → spring naar positie
        - sleep → vloeiend scrollen
        - cursor wordt handje op de scrollbar
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
  APP_VERSION = 'v0.21';

  GLYPH_DIAMOND   = #$25C8;
  GLYPH_FDIAMOND  = #$25C6;
  GLYPH_RTRI      = #$25B8;
  GLYPH_DTRI      = #$25BE;
  GLYPH_PTRI      = #$25B6;
  GLYPH_CHECKED   = #$2611;
  GLYPH_UNCHECKED = #$2610;
  GLYPH_GT        = #$203A;
  GLYPH_DOT       = #$25CF;
  GLYPH_UP        = #$25B2;
  GLYPH_SCROLL    = #$2588;

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
  MIN_CHAT_WIDTH  = 34;
  MAX_INPUT_ROWS  = 10;

  MY_CF_UNICODETEXT = 13;

  EVT_KEY           = $0001;
  EVT_MOUSE         = $0002;
  EVT_MOUSE_MOVED   = $0001;
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

  TSession = record
    Name     : string;
    Meta     : string;
    Messages : TList<TChatMessage>;
  end;

  TTreeItem = record
    Name     : string;
    Depth    : Integer;
    Perm     : string;
    Expanded : Boolean;
  end;

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
    IsMove      : Boolean;
  end;

  TVisualLine = record
    BufStart : Integer;
    Text     : string;
  end;

  TMouseShape = (msArrow, msSizeWE, msSizeNS, msIBeam, msHand);

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

  TreeVisibleRows  : TArray<Integer>;
  TreeVisibleIdx   : TArray<Integer>;
  SessionTitleRows : TArray<Integer>;
  SessionIdxAtRow  : TArray<Integer>;

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
  CurrentMouseShape : TMouseShape = msArrow;

  ChatScroll    : Integer = 0;
  ChatMaxScroll : Integer = 0;

  QuitRequested : Boolean = False;
  SimActive     : Boolean = False;
  SimStep       : Integer = 0;
  SimTimer      : Cardinal = 0;
  PromptState   : string = 'READY';
  StatusKind    : Integer = 0;

  NeedsRedraw : Boolean = True;

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
  Result.IsMove := False;

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
      if (Result.Ch = #0) and (Result.VK <> 0) then Result.Kind := ikSpecial
      else if Result.Ch <> #0 then Result.Kind := ikChar
      else Result.Kind := ikNone;
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
      begin
        WheelRaw := SmallInt(ButtonState shr 16);
        Result.WheelDelta := WheelRaw;
      end
      else Result.WheelDelta := 0;
      if (Rec.Event.MouseEvent.dwEventFlags and EVT_MOUSE_MOVED) <> 0 then
        Result.IsMove := True;
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
      begin
        Lines.Add(Current);
        Current.BufStart := I + 1; Current.Text := '';
      end
      else
      begin
        if Length(Current.Text) >= WrapWidth then
        begin
          Lines.Add(Current);
          Current.BufStart := I; Current.Text := '';
        end;
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
      Result := True; Exit;
    end
    else if Cursor < Lines[I + 1].BufStart - 1 then
    begin
      VisRow := I;
      VisCol := Cursor - (Lines[I].BufStart - 1);
      if VisCol < 0 then VisCol := 0;
      if VisCol > Length(Lines[I].Text) then VisCol := Length(Lines[I].Text);
      Result := True; Exit;
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
var Y, M, D : Word; H, Mn, S, Ms : Word;
begin
  DecodeDate(Now, Y, M, D);
  DecodeTime(Now, H, Mn, S, Ms);
  Result := Format('%d %s %d, %.2d:%.2d:%.2d',
    [D, FormatSettings.LongMonthNames[M], Y, H, Mn, S]);
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
    if ColCenter < 12 then ColCenter := 12;
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

procedure AddMsg(const Sess : TSession; const R : TChatRole; const T : string);
var M : TChatMessage;
begin M.Role := R; M.Text := T; M.Time := CurrentShortTime; Sess.Messages.Add(M); end;

procedure InitializeApplicationData;
var
  Session : TSession; Plan : TPlanItem; Work : TWorkItem; Tree : TTreeItem;
begin
  PlanItems     := TList<TPlanItem>.Create;
  WorkItems     := TList<TWorkItem>.Create;
  ThinkingLines := TList<string>.Create;
  SessionList   := TList<TSession>.Create;
  TreeList      := TList<TTreeItem>.Create;

  Tree.Name:='Local';         Tree.Depth:=0; Tree.Perm:='';    Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='Projects';      Tree.Depth:=1; Tree.Perm:='RWX'; Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='GRISP';         Tree.Depth:=2; Tree.Perm:='RWX'; Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='MME-Registry';  Tree.Depth:=2; Tree.Perm:='RW';  Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='Agent-Network'; Tree.Depth:=2; Tree.Perm:='RW';  Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='Data';          Tree.Depth:=1; Tree.Perm:='RW';  Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='Models';        Tree.Depth:=2; Tree.Perm:='RW';  Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='Downloads';     Tree.Depth:=2; Tree.Perm:='R';   Tree.Expanded:=True;  TreeList.Add(Tree);
  Tree.Name:='Cloud';         Tree.Depth:=1; Tree.Perm:='R';   Tree.Expanded:=True;  TreeList.Add(Tree);

  Session.Name:='Architecture Review'; Session.Meta:='24 sep 2026 14:30:23';
  Session.Messages := TList<TChatMessage>.Create;
  AddMsg(Session, crAssistant, 'Hello Alex, how can I help you with GRISP today?');
  AddMsg(Session, crAssistant, 'I can help with analysis, planning, or code generation. Just ask.');
  SessionList.Add(Session);

  Session.Name:='MME Schema Draft'; Session.Meta:='24 sep 2026 12:10:08';
  Session.Messages := TList<TChatMessage>.Create;
  AddMsg(Session, crAssistant, 'Schema draft loaded. 12 resource types ready for review.');
  SessionList.Add(Session);

  Session.Name:='Agent Graph'; Session.Meta:='23 sep 2026 18:22:44';
  Session.Messages := TList<TChatMessage>.Create;
  AddMsg(Session, crAssistant, 'Agent network graph is available. 7 nodes connected.');
  SessionList.Add(Session);

  Session.Name:='VFS Refactor Notes'; Session.Meta:='23 sep 2026 09:15:31';
  Session.Messages := TList<TChatMessage>.Create;
  AddMsg(Session, crAssistant, 'VFS refactor plan ready. Awaiting your go-ahead.');
  SessionList.Add(Session);

  ActiveSessionIndex := 0;
  CurrentSessionName := SessionList[0].Name;
  ChatMessages := SessionList[0].Messages;

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
var I : Integer;
begin
  for I := 0 to SessionList.Count - 1 do
    SessionList[I].Messages.Free;
  PlanItems.Free; WorkItems.Free; ThinkingLines.Free;
  SessionList.Free; TreeList.Free;
end;

procedure SwitchSession(Idx : Integer);
begin
  if (Idx < 0) or (Idx >= SessionList.Count) then Exit;
  ActiveSessionIndex := Idx;
  CurrentSessionName := SessionList[Idx].Name;
  ChatMessages := SessionList[Idx].Messages;
  ChatScroll := 0;
end;

{ ============================================================================
  SECTIE 8 — Panelen
  ============================================================================ }

function ComputeTreeVisibility : TArray<Integer>;
var
  I, D : Integer;
  Chain : array[0..15] of Boolean;
  Tmp : TList<Integer>;
begin
  Tmp := TList<Integer>.Create;
  try
    if TreeList.Count = 0 then
    begin
      SetLength(Result, 0);
      Exit;
    end;
    Chain[0] := True;

    for I := 0 to TreeList.Count - 1 do
    begin
      D := TreeList[I].Depth;
      if D > 15 then D := 15;
      if (D = 0) or Chain[D - 1] then
      begin
        Tmp.Add(I);
        Chain[D] := TreeList[I].Expanded;
      end
      else
        Chain[D] := False;
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
  Lines : TList<string>; I, Indent, NameWidth, SessRows, RowUsed : Integer;
  Buf, PermColor, NameField, DividerCol, SessionTitle, MetaStr : string;
  Visible : TArray<Integer>;
  Item : TTreeItem; Session : TSession;
  Vis : TList<Integer>; SessRowsList : TList<Integer>;

  procedure AddLine(const S : string);
  begin Lines.Add(PadToWidth(S, ColLeft, BG_PANEL) + ANSI_RESET); end;

begin
  Lines := TList<string>.Create;
  Vis := TList<Integer>.Create;
  SessRowsList := TList<Integer>.Create;
  try
    SessRows := ContentHeight - 1 - LeftSplitRow;

    AddLine(BG_PANEL + FG_CYAN + ANSI_BOLD + ' ' + GLYPH_FDIAMOND + ' RESOURCES');
    AddLine(BG_PANEL + FG_BORDER + ' ' + RepeatChar(GLYPH_HORZ, ColLeft - 2));
    RowUsed := 2;

    Visible := ComputeTreeVisibility;

    for I := 0 to High(Visible) do
    begin
      if RowUsed >= LeftSplitRow - 1 then Break;
      Item := TreeList[Visible[I]];

      Indent := 1 + Item.Depth * 2;
      NameWidth := ColLeft - Indent - 8;
      if NameWidth < 4 then NameWidth := 4;

      if Item.Perm = '' then
      begin
        if NodeHasVisibleChildren(Visible[I]) then
        begin
          if Item.Expanded then
            Buf := BG_PANEL + FG_CYAN + StringOfChar(' ', Indent)
                 + FG_CYAN + GLYPH_DTRI + ' ' + ANSI_BOLD + Item.Name
          else
            Buf := BG_PANEL + FG_CYAN + StringOfChar(' ', Indent)
                 + FG_CYAN + GLYPH_RTRI + ' ' + ANSI_BOLD + Item.Name;
        end
        else
          Buf := BG_PANEL + FG_CYAN + StringOfChar(' ', Indent)
               + GLYPH_RTRI + ' ' + ANSI_BOLD + Item.Name;
      end
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
      Vis.Add(4 + RowUsed);
      Inc(RowUsed);
    end;

    SetLength(TreeVisibleRows, Vis.Count);
    for I := 0 to Vis.Count - 1 do
      TreeVisibleRows[I] := Vis[I];
    SetLength(TreeVisibleIdx, Vis.Count);
    for I := 0 to High(TreeVisibleRows) do
      TreeVisibleIdx[I] := Visible[I];

    while RowUsed < LeftSplitRow do
    begin
      AddLine(BG_PANEL);
      Inc(RowUsed);
    end;

    if (HoverTarget = 11) or (IsDragging and (DragTarget = 11)) then
      DividerCol := FG_CYAN else DividerCol := FG_BORDER;
    Lines.Add(BG_PANEL + DividerCol + RepeatChar(GLYPH_HORZ, ColLeft) + ANSI_RESET);
    Inc(RowUsed);

    AddLine(BG_PANEL + FG_CYAN + ANSI_BOLD + ' ' + GLYPH_FDIAMOND + ' SESSIONS');
    AddLine(BG_PANEL + FG_BORDER + ' ' + RepeatChar(GLYPH_HORZ, ColLeft - 2));
    Inc(RowUsed, 2);

    for I := 0 to SessionList.Count - 1 do
    begin
      if RowUsed >= ContentHeight then Break;
      Session := SessionList[I];
      SessionTitle := GLYPH_RTRI + ' ' + Session.Name;
      MetaStr := ' (' + Session.Meta + ')';

      if VisibleLength(SessionTitle) + Length(MetaStr) + 2 <= ColLeft then
      begin
        if I = ActiveSessionIndex then
          Buf := BG_PANEL + FG_CYAN + ANSI_BOLD + ' ' + SessionTitle + MetaStr
        else
          Buf := BG_PANEL + FG_TEXT + ' ' + SessionTitle
               + FG_GRAY + MetaStr;
        AddLine(Buf);
        SessRowsList.Add(4 + RowUsed);
        Inc(RowUsed);
      end
      else
      begin
        if I = ActiveSessionIndex then
          Buf := BG_PANEL + FG_CYAN + ANSI_BOLD + ' ' + SessionTitle
        else
          Buf := BG_PANEL + FG_TEXT + ' ' + SessionTitle;
        AddLine(Buf);
        SessRowsList.Add(4 + RowUsed);
        Inc(RowUsed);
        if RowUsed < ContentHeight then
        begin
          AddLine(BG_PANEL + FG_GRAY + '   ' + Session.Meta);
          Inc(RowUsed);
        end;
      end;
    end;

    SetLength(SessionTitleRows, SessRowsList.Count);
    for I := 0 to SessRowsList.Count - 1 do
      SessionTitleRows[I] := SessRowsList[I];
    SetLength(SessionIdxAtRow, SessRowsList.Count);
    for I := 0 to High(SessionTitleRows) do SessionIdxAtRow[I] := I;

    while Lines.Count < ContentHeight do AddLine(BG_PANEL);

    SetLength(Result, Lines.Count);
    for I := 0 to Lines.Count - 1 do Result[I] := Lines[I];
  finally Lines.Free; Vis.Free; SessRowsList.Free; end;
end;

{ --- Scrollbar: X-positie en rij-bereik --- }
function ScrollbarX : Integer;
begin
  if ShowLeftPanel then Result := ColLeft + ColCenter + 2
  else Result := ColCenter + 1;
end;

function ScrollbarTop : Integer;
begin
  Result := 4 + 2;   { body begint op paneel-rij 2 }
end;

function ScrollbarBottom : Integer;
begin
  Result := 4 + ContentHeight - 1;
end;

function ChatScrollbarChar(VisRow : Integer) : string;
var
  ThumbTop, ThumbH, BodyH, Total : Integer;
begin
  BodyH := ContentHeight - 2;
  Total := ChatMaxScroll + BodyH;
  if (BodyH <= 0) or (Total <= BodyH) then
  begin
    Result := BG_MAIN + FG_DGRAY + GLYPH_VERT;
    Exit;
  end;

  ThumbH := Max(1, BodyH * BodyH div Total);
  if ThumbH > BodyH then ThumbH := BodyH;
  ThumbTop := (BodyH - ThumbH) * ChatScroll div Max(1, ChatMaxScroll);
  ThumbTop := (BodyH - ThumbH) - ThumbTop;

  if VisRow < 2 then
  begin
    Result := BG_MAIN + FG_DGRAY + GLYPH_VERT;
    Exit;
  end;

  if (VisRow - 2 >= ThumbTop) and (VisRow - 2 < ThumbTop + ThumbH) then
    Result := BG_MAIN + FG_CYAN + GLYPH_SCROLL
  else
    Result := BG_MAIN + FG_DGRAY + GLYPH_VERT;
end;

function RenderCenterPane : TArray<string>;
var
  Vis, Full : TList<string>;
  I, J, Total, WS, WE, BodyH, RightPad : Integer;
  Msg : TChatMessage; Wrapped : TArray<string>;
  Buf, SenderColor, Prefix, TimePart, Header : string;

  procedure Emit(const S : string; VisRow : Integer);
  begin
    Vis.Add(PadToWidth(S, ColCenter - 1, BG_MAIN) + ChatScrollbarChar(VisRow));
  end;

begin
  Vis := TList<string>.Create; Full := TList<string>.Create;
  try
    Header := BG_MAIN + ' ' + FG_CYAN + ANSI_BOLD + GLYPH_FDIAMOND + ' CHAT'
            + ANSI_RESET + BG_MAIN + FG_DGRAY + ' - ' + FG_TEXT + CurrentSessionName;
    if ChatScroll > 0 then
      Header := Header + ANSI_RESET + BG_MAIN + '  ' + FG_AMBER + GLYPH_UP
              + ' +' + IntToStr(ChatScroll);
    Full.Add(Header);
    Full.Add(BG_MAIN + ' ' + FG_BORDER + RepeatChar(GLYPH_HORZ, ColCenter - 3));

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
      RightPad := ColCenter - 3 - VisibleLength(Buf) - Length(TimePart);
      if RightPad < 1 then RightPad := 1;
      Buf := Buf + StringOfChar(' ', RightPad) + FG_DGRAY + TimePart + ' ';
      Full.Add(Buf);

      Wrapped := WrapParagraph(Msg.Text, ColCenter - 6);
      for J := 0 to High(Wrapped) do
      begin
        case Msg.Role of
          crUser:      Buf := BG_MAIN + '  ' + BG_USER + FG_TEXT
                            + Wrapped[J] + '  ' + ANSI_RESET + BG_MAIN;
          crAssistant: Buf := BG_MAIN + '  ' + BG_AI + FG_TEXT
                            + Wrapped[J] + '  ' + ANSI_RESET + BG_MAIN;
          else         Buf := BG_MAIN + '  ' + FG_GRAY + '  ' + Wrapped[J];
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

    for I := 0 to ContentHeight - 1 do
    begin
      if I < Full.Count - WS then
        Emit(Full[WS + I], I)
      else
        Emit(BG_MAIN, I);
    end;

    SetLength(Result, Vis.Count);
    for I := 0 to Vis.Count - 1 do Result[I] := Vis[I];
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
    Lines.Add(DivCol1 + RepeatChar(GLYPH_HORZ, ColRight) + ANSI_RESET);

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
    Lines.Add(DivCol2 + RepeatChar(GLYPH_HORZ, ColRight) + ANSI_RESET);

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

    SetLength(Result, Lines.Count);
    for I := 0 to Lines.Count - 1 do Result[I] := Lines[I];
  finally Lines.Free; end;
end;

{ ============================================================================
  SECTIE 9 — Frame
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
  V1Hot, V2Hot, H10Hot : Boolean;
  SepC1, SepC2, SepBotAll : string;
  LineText : string;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append(CURSOR_HIDE);
    SB.Append(CURSOR_HOME);

    V1Hot  := (HoverTarget = 1)  or (IsDragging and (DragTarget = 1));
    V2Hot  := (HoverTarget = 2)  or (IsDragging and (DragTarget = 2));
    H10Hot := (HoverTarget = 10) or (IsDragging and (DragTarget = 10));

    if V1Hot then SepC1 := FG_CYAN else SepC1 := FG_BORDER;
    if V2Hot then SepC2 := FG_CYAN else SepC2 := FG_BORDER;

    SB.Append(FG_BORDER + GLYPH_TOPLEFT
            + RepeatChar(GLYPH_HORZ, ScreenWidth - 2)
            + GLYPH_TOPRIGHT + ANSI_RESET + #13#10);

    if ScreenWidth >= 150 then
      Hints := '   ' + FG_DGRAY + '[Ctrl+Enter]' + FG_TEXT + ' Send'
             + '  ' + FG_DGRAY + '[Ctrl+C]' + FG_TEXT + ' Copy'
             + '  ' + FG_DGRAY + '[F5]' + FG_TEXT + ' TermSel'
             + '  ' + FG_DGRAY + '[Esc]' + FG_TEXT + ' Quit'
    else if ScreenWidth >= 110 then
      Hints := '  ' + FG_DGRAY + '[^Enter]' + FG_TEXT + 'Send'
             + ' ' + FG_DGRAY + '[^C]' + FG_TEXT + 'Cpy'
             + ' ' + FG_DGRAY + '[F5]' + FG_TEXT + 'Sel'
             + ' ' + FG_DGRAY + '[Esc]Q'
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
      SepTop := FG_BORDER + GLYPH_TEEEAST
              + RepeatChar(GLYPH_HORZ, ColLeft)
              + SepC1 + GLYPH_TEEDOWN + ANSI_RESET + FG_BORDER
              + RepeatChar(GLYPH_HORZ, ColCenter)
              + SepC2 + GLYPH_TEEDOWN + ANSI_RESET + FG_BORDER
              + RepeatChar(GLYPH_HORZ, ColRight)
              + GLYPH_TEEWEST + ANSI_RESET
    else if ShowRightPanel then
      SepTop := FG_BORDER + GLYPH_TEEEAST
              + RepeatChar(GLYPH_HORZ, ScreenWidth - ColRight - 3)
              + SepC2 + GLYPH_TEEDOWN + ANSI_RESET + FG_BORDER
              + RepeatChar(GLYPH_HORZ, ColRight) + GLYPH_TEEWEST + ANSI_RESET
    else if ShowLeftPanel then
      SepTop := FG_BORDER + GLYPH_TEEEAST
              + RepeatChar(GLYPH_HORZ, ColLeft)
              + SepC1 + GLYPH_TEEDOWN + ANSI_RESET + FG_BORDER
              + RepeatChar(GLYPH_HORZ, ScreenWidth - ColLeft - 3)
              + GLYPH_TEEWEST + ANSI_RESET
    else
      SepTop := FG_BORDER + GLYPH_TEEEAST
              + RepeatChar(GLYPH_HORZ, ScreenWidth - 2) + GLYPH_TEEWEST + ANSI_RESET;
    SB.Append(SepTop + #13#10);

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
      else SB.Append(PadToWidth('', ColCenter - 1, BG_MAIN)
                   + ChatScrollbarChar(RowIndex));
      if ShowRightPanel then
      begin
        SB.Append(SepC2 + GLYPH_VERT + ANSI_RESET);
        if RowIndex < Length(RightPane) then SB.Append(RightPane[RowIndex])
        else SB.Append(PadToWidth('', ColRight, BG_PANEL) + ANSI_RESET);
      end;
      SB.Append(FG_BORDER + GLYPH_VERT + ANSI_RESET + #13#10);
    end;

    if H10Hot then SepBotAll := FG_CYAN else SepBotAll := FG_BORDER;

    if ShowLeftPanel and ShowRightPanel then
      SepBot := SepBotAll + GLYPH_TEEEAST + RepeatChar(GLYPH_HORZ, ColLeft)
              + GLYPH_TEEUP + RepeatChar(GLYPH_HORZ, ColCenter)
              + GLYPH_TEEUP + RepeatChar(GLYPH_HORZ, ColRight)
              + GLYPH_TEEWEST + ANSI_RESET
    else
      SepBot := SepBotAll + GLYPH_TEEEAST
              + RepeatChar(GLYPH_HORZ, ScreenWidth - 2)
              + GLYPH_TEEWEST + ANSI_RESET;
    SB.Append(SepBot + #13#10);

    InputLines := BuildVisualLines(InputBuffer, InputWrapWidth);
    FirstInputRow := 5 + ContentHeight;

    CaretRow := FirstInputRow;
    CaretCol := 3;
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
      InputScroll := 0; VisRow := 0; VisCol := 0;
    end;

    for I := 0 to InputHeight - 1 do
    begin
      if (InputScroll + I) < Length(InputLines) then
        LineText := InputLines[InputScroll + I].Text
      else LineText := '';

      if SimActive then
      begin
        if I = 0 then
          InputLine := BG_INPUT + '  ' + FG_AMBER + ANSI_BOLD + '...'
                     + ANSI_RESET + BG_INPUT + FG_AMBER + ' Processing ['
                     + PromptState + '] - [Ctrl+Enter] to step'
        else InputLine := BG_INPUT;
      end
      else
        { Geen prompt-teken meer — gewoon typen langs de lijn. }
        InputLine := BG_INPUT + '  ' + FG_TEXT + LineText;

      SB.Append(FG_BORDER + GLYPH_VERT + ANSI_RESET
              + PadToWidth(InputLine, ScreenWidth - 2, BG_INPUT) + ANSI_RESET
              + FG_BORDER + GLYPH_VERT + ANSI_RESET + #13#10);
    end;

    if not SimActive then
    begin
      CaretRow := FirstInputRow + (VisRow - InputScroll);
      CaretCol := 3 + VisCol;
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
  InputBuffer := ''; InputCursor := 0; InputScroll := 0;
  BeginSimulation;
end;

{ ============================================================================
  SECTIE 11 — Input editor
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
  Inc(InputCursor, Length(S)); ClampInputCursor;
end;

procedure BackspaceAtCaret;
begin
  if InputCursor > 0 then begin Delete(InputBuffer, InputCursor, 1); Dec(InputCursor); end;
end;

procedure DeleteAtCaret;
begin
  if InputCursor < Length(InputBuffer) then Delete(InputBuffer, InputCursor + 1, 1);
end;

procedure MoveCaretLeft;  begin if InputCursor > 0 then Dec(InputCursor); end;
procedure MoveCaretRight; begin if InputCursor < Length(InputBuffer) then Inc(InputCursor); end;

procedure MoveCaretHome;
var Lines : TArray<TVisualLine>; R, C : Integer;
begin
  Lines := BuildVisualLines(InputBuffer, InputWrapWidth);
  if CursorVisualPos(Lines, InputCursor, R, C) then
    InputCursor := Lines[R].BufStart - 1;
  ClampInputCursor;
end;

procedure MoveCaretEnd;
var Lines : TArray<TVisualLine>; R, C : Integer;
begin
  Lines := BuildVisualLines(InputBuffer, InputWrapWidth);
  if CursorVisualPos(Lines, InputCursor, R, C) then
    InputCursor := (Lines[R].BufStart - 1) + Length(Lines[R].Text);
  ClampInputCursor;
end;

procedure MoveCaretVertical(const Delta : Integer);
var Lines : TArray<TVisualLine>; R, C, TR : Integer;
begin
  Lines := BuildVisualLines(InputBuffer, InputWrapWidth);
  if not CursorVisualPos(Lines, InputCursor, R, C) then Exit;
  TR := R + Delta;
  if TR < 0 then TR := 0;
  if TR > High(Lines) then TR := High(Lines);
  if C > Length(Lines[TR].Text) then C := Length(Lines[TR].Text);
  InputCursor := (Lines[TR].BufStart - 1) + C;
  ClampInputCursor;
end;

{ ============================================================================
  SECTIE 12 — Klembord
  ============================================================================ }

function GetClipboardText : string;
var Data : THandle; Ptr : Pointer;
begin
  Result := '';
  if not OpenClipboard(0) then Exit;
  try
    Data := GetClipboardData(MY_CF_UNICODETEXT);
    if Data <> 0 then
    begin
      Ptr := GlobalLock(Data);
      if Ptr <> nil then
      try Result := string(PWideChar(Ptr));
      finally GlobalUnlock(Data); end;
    end;
  finally CloseClipboard; end;
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
  SECTIE 13 — Muiscursor
  ============================================================================ }

procedure SetMouseShape(Shape : TMouseShape);
var P : HCURSOR;
begin
  case Shape of
    msSizeWE: P := LoadCursor(0, IDC_SIZEWE);
    msSizeNS: P := LoadCursor(0, IDC_SIZENS);
    msIBeam:  P := LoadCursor(0, IDC_IBEAM);
    msHand:   P := LoadCursor(0, IDC_HAND);
    else      P := LoadCursor(0, IDC_ARROW);
  end;
  SetCursor(P);
end;

function DesiredShape(x, y : Integer) : TMouseShape;
var I : Integer;
begin
  Result := msArrow;
  if not MouseEnabled then Exit;

  { Verticale scheiders → size WE }
  if (ShowLeftPanel and (x = ColLeft + 2))
  or (ShowRightPanel and (x = ColLeft + ColCenter + 3)) then
  begin Result := msSizeWE; Exit; end;

  { Horizontale scheiders → size NS }
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

  { Scrollbar → hand }
  if (x = ScrollbarX)
     and (y >= ScrollbarTop) and (y <= ScrollbarBottom) then
  begin Result := msHand; Exit; end;

  { Resources / Sessions → hand }
  for I := 0 to High(TreeVisibleRows) do
    if (y = TreeVisibleRows[I]) and (x >= 2) and (x <= ColLeft + 1) then
    begin Result := msHand; Exit; end;
  for I := 0 to High(SessionTitleRows) do
    if (y = SessionTitleRows[I]) and (x >= 2) and (x <= ColLeft + 1) then
    begin Result := msHand; Exit; end;

  { Chat-gebied → I-beam }
  if (y >= 4) and (y < 4 + ContentHeight)
    and (x > ColLeft + 2)
    and (x < ColLeft + ColCenter + 2) then
    Result := msIBeam;
end;

{ ============================================================================
  SECTIE 14 — Muis
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
          and (MouseX >= RStart) and (MouseX <= REnd) then HoverTarget := 13
  else if (MouseX = ScrollbarX)
          and (MouseY >= ScrollbarTop) and (MouseY <= ScrollbarBottom) then
    HoverTarget := 20;
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
    20: begin
          { Scrollbar-sleep: vertaal Y naar ChatScroll. }
          if (ContentHeight - 2) > 1 then
          begin
            var RelY, BodyH : Integer;
            BodyH := ContentHeight - 2;
            RelY := Ev.MouseY - ScrollbarTop;
            if RelY < 0 then RelY := 0;
            if RelY >= BodyH then RelY := BodyH - 1;
            ChatScroll := (BodyH - 1 - RelY) * ChatMaxScroll div (BodyH - 1);
            if ChatScroll < 0 then ChatScroll := 0;
            if ChatScroll > ChatMaxScroll then ChatScroll := ChatMaxScroll;
          end;
        end;
  end;
  RecomputeLayout;
end;

procedure HandleScrollbarClick(Y : Integer);
var RelY, BodyH : Integer;
begin
  BodyH := ContentHeight - 2;
  if BodyH <= 1 then Exit;
  RelY := Y - ScrollbarTop;
  if RelY < 0 then RelY := 0;
  if RelY >= BodyH then RelY := BodyH - 1;
  ChatScroll := (BodyH - 1 - RelY) * ChatMaxScroll div (BodyH - 1);
  if ChatScroll < 0 then ChatScroll := 0;
  if ChatScroll > ChatMaxScroll then ChatScroll := ChatMaxScroll;
end;

procedure HandleMouseClick(X, Y : Integer);
var
  I, Idx : Integer;
  T : TTreeItem;
begin
  { Scrollbar? }
  if (X = ScrollbarX) and (Y >= ScrollbarTop) and (Y <= ScrollbarBottom) then
  begin
    HandleScrollbarClick(Y);
    Exit;
  end;

  { Resources / Sessions? }
  if ShowLeftPanel and (X >= 2) and (X <= ColLeft + 1) then
  begin
    for I := 0 to High(TreeVisibleRows) do
    begin
      if Y = TreeVisibleRows[I] then
      begin
        Idx := TreeVisibleIdx[I];
        if NodeHasVisibleChildren(Idx) then
        begin
          T := TreeList[Idx];
          T.Expanded := not T.Expanded;
          TreeList[Idx] := T;
        end;
        Exit;
      end;
    end;
    for I := 0 to High(SessionTitleRows) do
    begin
      if Y = SessionTitleRows[I] then
      begin
        SwitchSession(SessionIdxAtRow[I]);
        Exit;
      end;
    end;
  end;

  { Gewone klik in chat → terug naar bodem }
  if (Y >= 4) and (Y < 4 + ContentHeight)
    and (X > ColLeft + 2) and (X < ScrollbarX) then
    ChatScroll := 0;
end;

procedure HandleMouseEvent(const Ev : TInputEvent);
var WheelLines : Integer;
begin
  UpdateHoverTarget(Ev.MouseX, Ev.MouseY);
  CurrentMouseShape := DesiredShape(Ev.MouseX, Ev.MouseY);
  if MouseEnabled then SetMouseShape(CurrentMouseShape);

  if Ev.WheelDelta <> 0 then
  begin
    WheelLines := (Ev.WheelDelta div 120) * 3;
    ChatScroll := ChatScroll + WheelLines;
    NeedsRedraw := True;
  end;

  if IsDragging then
  begin
    if Ev.MouseButton = 1 then
    begin
      ApplyDrag(Ev);
      NeedsRedraw := True;
    end
    else begin IsDragging := False; DragTarget := 0; NeedsRedraw := True; end;
    Exit;
  end;

  if Ev.MouseButton = 1 then
  begin
    if HoverTarget >= 1 then
    begin
      IsDragging := True;
      DragTarget := HoverTarget;

      { Scrollbar: meteen naar aangeklikte positie springen }
      if DragTarget = 20 then
        HandleScrollbarClick(Ev.MouseY);

      NeedsRedraw := True;
    end
    else
    begin
      HandleMouseClick(Ev.MouseX, Ev.MouseY);
      NeedsRedraw := True;
    end;
  end;
end;

{ ============================================================================
  SECTIE 15 — Toetsafhandeling
  ============================================================================ }

procedure ResetAllUserSizes;
begin
  UserColLeft := 0; UserColRight := 0; UserInputRows := 0;
  UserLeftSplit := 0; UserPlanRows := 0; UserWorkRows := 0;
  RecomputeLayout;
end;

function CtrlIsDown : Boolean;
begin
  Result := (GetKeyState(VK_CONTROL) and $8000) <> 0;
end;

procedure HandleKeyEvent(const Ev : TInputEvent);
var CtrlDown : Boolean;
begin
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

      VK_RETURN:
        begin
          if SimActive then begin AdvanceSimulation; Exit; end;
          CtrlDown := Ev.ModCtrl or CtrlIsDown;
          if CtrlDown then SubmitPrompt else InsertAtCaret(#10);
        end;
    end;
    Exit;
  end;

  if Ev.Kind <> ikChar then Exit;

  if Ev.ModCtrl and (not Ev.ModAlt) and (Ev.Ch = #$16) then
  begin
    if not SimActive then PasteFromClipboard;
    Exit;
  end;

  if (Ev.Ch = #13) or (Ev.Ch = #10) then
  begin
    if SimActive then begin AdvanceSimulation; Exit; end;
    CtrlDown := Ev.ModCtrl or CtrlIsDown;
    if CtrlDown then SubmitPrompt else InsertAtCaret(#10);
    Exit;
  end;

  if Ev.Ch = #8 then
  begin
    if not SimActive then BackspaceAtCaret;
    Exit;
  end;

  if (Ord(Ev.Ch) >= 32) and not SimActive
     and not Ev.ModCtrl and not Ev.ModAlt then
    InsertAtCaret(Ev.Ch);
end;

{ ============================================================================
  SECTIE 16 — Hoofdlus
  ============================================================================ }

procedure RunApplication;
var
  Ev : TInputEvent;
  NewWidth, NewHeight : Integer;
  HadInput : Boolean;
  WaitMs : Cardinal;
  HoverBefore : Integer;
begin
  InitializeConsole;
  InitializeApplicationData;
  try
    WriteAtomic(SCREEN_ALT_ON);
    WriteAtomic(ANSI_RESET + SCREEN_CLEAR);

    NeedsRedraw := True;
    while not QuitRequested do
    begin
      ReadTerminalSize(NewWidth, NewHeight);
      if (NewWidth <> ScreenWidth) or (NewHeight <> ScreenHeight) then
      begin
        RecomputeLayout;
        WriteAtomic(ANSI_RESET + SCREEN_CLEAR);
        NeedsRedraw := True;
      end;

      HadInput := False;
      repeat
        Ev := ReadInputEvent;
        if Ev.Kind = ikNone then Break;
        HadInput := True;

        case Ev.Kind of
          ikChar, ikSpecial:
            begin
              HandleKeyEvent(Ev);
              NeedsRedraw := True;
            end;
          ikMouse:
            if MouseEnabled then
            begin
              HoverBefore := HoverTarget;
              HandleMouseEvent(Ev);
              if (HoverTarget <> HoverBefore) or Ev.IsMove then
                NeedsRedraw := True;
            end;
        end;
      until False;

      if SimActive and ((GetTickCount - SimTimer) > SIM_INTERVAL_MS) then
      begin
        SimTimer := GetTickCount;
        AdvanceSimulation;
        NeedsRedraw := True;
      end;

      if NeedsRedraw then
      begin
        WriteAtomic(RenderFrame);
        NeedsRedraw := False;
      end;

      if SimActive then WaitMs := 50
      else if HadInput then WaitMs := 1
      else WaitMs := 10;
      WaitForSingleObject(StdInHandle, WaitMs);
    end;
  finally
    MouseEnabled := False;
    ApplyInputMode;
    WriteAtomic(ANSI_RESET + CURSOR_SHOW + SCREEN_ALT_OFF);
    ShutdownApplicationData;
  end;
end;

{ ============================================================================
  SECTIE 17 — Entry
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
