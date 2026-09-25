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
  APP_VERSION = 'v0.15';

  S_DIAMOND   = #$25C8;  S_FDIAMOND  = #$25C6;
  S_RTRI      = #$25B8;  S_PTRI      = #$25B6;
  S_CHECKED   = #$2611;  S_UNCHECKED = #$2610;
  S_GT        = #$203A;  S_BLOCK     = #$258C;
  S_DOT       = #$25CF;
  S_UP        = #$25B2;  S_DOWN      = #$25BC;
  S_ULC = #$250C;  S_URC = #$2510;
  S_LLC = #$2514;  S_LRC = #$2518;
  S_H   = #$2500;  S_V   = #$2502;
  S_TE  = #$252C;  S_TW  = #$2524;
  S_BE  = #$2534;  S_BW  = #$251C;

  ESC  = #27;
  RST  = ESC + '[0m';
  BOLD = ESC + '[1m';

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

  HIDE_CUR = ESC + '[?25l';
  SHOW_CUR = ESC + '[?25h';
  ALT_ON   = ESC + '[?1049h';
  ALT_OFF  = ESC + '[?1049l';
  CLRSCR   = ESC + '[2J' + ESC + '[H';
  HOME     = ESC + '[H';

  SIM_INTERVAL_MS = 900;
  MIN_W_LEFT  = 110;
  MIN_W_RIGHT = 90;
  MIN_COL     = 20;   // minimale breedte per paneel
  MIN_COL_C   = 30;   // minimale breedte chat

  // Eigen event-constanten — voorkomt botsing met mouse_event API-procedure.
  MY_KEY_EVENT     = $0001;
  MY_MOUSE_EVENT   = $0002;
  MY_MOUSE_MOVED   = $0001;
  MY_MOUSE_WHEELED = $0004;

type
  TChatRole = (crUser, crAssistant, crSystem);
  TChatMessage = record Role: TChatRole; Text, Time: string; end;
  TPlanStatus = (psDone, psRunning, psQueued);
  TPlanItem = record Text: string; Status: TPlanStatus; end;
  TWorkPrio = (wpHigh, wpMedium, wpLow);
  TWorkItem = record Text: string; Prio: TWorkPrio; end;
  TSession = record Name, Meta: string; end;
  TTreeItem = record Name: string; Depth: Integer; Perm: string; end;

  TInputKind = (ikNone, ikChar, ikSpecial, ikMouse);
  TInputEvent = record
    Kind: TInputKind;
    Ch: WideChar;
    VK: Word;
    MouseX, MouseY: Integer;
    MouseButton: Integer;
    WheelDelta: Integer;
  end;

var
  hOut, hIn: THandle;
  ScreenW, ScreenH: Integer;
  ColL, ColC, ColR: Integer;

  Messages: TList<TChatMessage>;
  PlanItems: TList<TPlanItem>;
  WorkItems: TList<TWorkItem>;
  ThinkLines: TList<string>;
  Sessions: TList<TSession>;
  TreeItems: TList<TTreeItem>;

  CurrentSession: string;
  ActiveSessionIdx: Integer = 0;

  InputBuf: string;

  WantLeft:  Boolean = True;
  WantRight: Boolean = True;
  WantThink: Boolean = True;
  MouseEnabled: Boolean = True;

  EffLeft:  Boolean = True;
  EffRight: Boolean = True;
  EffThink: Boolean = True;

  // Door gebruiker ingestelde paneelbreedtes (0 = automatisch)
  ColLUser: Integer = 0;
  ColRUser: Integer = 0;

  // Drag-state
  Dragging: Boolean = False;
  DragTarget: Integer = 0;   // 1 = linker scheiding, 2 = rechter scheiding
  HoverSep: Integer = 0;     // zelfde semantiek als DragTarget

  ChatScroll: Integer = 0;
  ChatMaxScroll: Integer = 0;

  QuitFlag: Boolean = False;
  SimActive: Boolean = False;
  SimStep: Integer = 0;
  SimTimer: Cardinal = 0;
  PromptState: string = 'READY';
  StatusKind: Integer = 0;

// ═══════════════════════════════════════════════════════════════════
procedure ReadTermSize(out W, H: Integer);
var Info: TConsoleScreenBufferInfo;
begin
  if GetConsoleScreenBufferInfo(hOut, Info) then
  begin
    W := Info.srWindow.Right - Info.srWindow.Left + 1;
    H := Info.srWindow.Bottom - Info.srWindow.Top + 1;
  end
  else begin W := 140; H := 40; end;
  if W < 60 then W := 60;
  if H < 20 then H := 20;
end;

procedure RecomputeLayout;
begin
  ReadTermSize(ScreenW, ScreenH);

  EffLeft  := WantLeft  and (ScreenW >= MIN_W_LEFT);
  EffRight := WantRight and (ScreenW >= MIN_W_RIGHT);
  EffThink := WantThink;

  // Respecteer gebruikersbreedtes waar die gezet zijn.
  if EffLeft then
  begin
    if ColLUser > 0 then ColL := ColLUser
    else ColL := EnsureRange(ScreenW div 7, 22, 28);
    if ColL < MIN_COL then ColL := MIN_COL;
  end
  else ColL := 0;

  if EffRight then
  begin
    if ColRUser > 0 then ColR := ColRUser
    else ColR := EnsureRange(ScreenW div 5, 30, 40);
    if ColR < MIN_COL then ColR := MIN_COL;
  end
  else ColR := 0;

  ColC := ScreenW - ColL - ColR - 4;

  // Als de chat te krap wordt: eerst rechter paneel krimpen, dan linker.
  if ColC < MIN_COL_C then
  begin
    if EffRight then
    begin
      ColR := ColR - (MIN_COL_C - ColC);
      if ColR < MIN_COL then ColR := MIN_COL;
      ColC := ScreenW - ColL - ColR - 4;
    end;
    if (ColC < MIN_COL_C) and EffLeft then
    begin
      ColL := ColL - (MIN_COL_C - ColC);
      if ColL < MIN_COL then ColL := MIN_COL;
      ColC := ScreenW - ColL - ColR - 4;
    end;
    if ColC < 10 then ColC := 10;
  end;
end;

procedure UpdateInputMode;
var Mode: DWORD;
begin
  GetConsoleMode(hIn, Mode);
  Mode := Mode or ENABLE_EXTENDED_FLAGS or ENABLE_WINDOW_INPUT;
  if MouseEnabled then
    Mode := (Mode or ENABLE_MOUSE_INPUT) and not ENABLE_QUICK_EDIT_MODE
  else
    Mode := (Mode and not ENABLE_MOUSE_INPUT) or ENABLE_QUICK_EDIT_MODE;
  SetConsoleMode(hIn, Mode);
end;

procedure ConsoleInit;
var Mode: DWORD;
begin
  hOut := GetStdHandle(STD_OUTPUT_HANDLE);
  hIn  := GetStdHandle(STD_INPUT_HANDLE);

  GetConsoleMode(hOut, Mode);
  SetConsoleMode(hOut,
    (Mode or ENABLE_VIRTUAL_TERMINAL_PROCESSING
          or ENABLE_PROCESSED_OUTPUT)
    and not ENABLE_WRAP_AT_EOL_OUTPUT);

  SetConsoleOutputCP(CP_UTF8);
  SetConsoleCP(CP_UTF8);
  SetConsoleTitle(PChar(APP_NAME + ' ' + APP_VERSION + ' - Terminal UI'));

  UpdateInputMode;
  RecomputeLayout;
end;

procedure WriteOut(const S: string);
var N: DWORD;
begin
  if S = '' then Exit;
  WriteConsoleW(hOut, PWideChar(S), Length(S), N, nil);
end;

function ReadEv: TInputEvent;
var
  N: DWORD;
  Rec: INPUT_RECORD;
  Rd: DWORD;
  BS: DWORD;
  WheelRaw: SmallInt;
begin
  Result.Kind := ikNone;
  while True do
  begin
    N := 0;
    if not GetNumberOfConsoleInputEvents(hIn, N) then Exit;
    if N = 0 then Exit;
    if not ReadConsoleInputW(hIn, Rec, 1, Rd) then Exit;

    if Rec.EventType = MY_KEY_EVENT then
    begin
      if not Rec.Event.KeyEvent.bKeyDown then Continue;
      Result.VK := Rec.Event.KeyEvent.wVirtualKeyCode;
      Result.Ch := Rec.Event.KeyEvent.UnicodeChar;
      if (Result.Ch = #0) and (Result.VK <> 0) then Result.Kind := ikSpecial
      else if Result.Ch <> #0 then Result.Kind := ikChar
      else Result.Kind := ikNone;
      Exit;
    end;

    if Rec.EventType = MY_MOUSE_EVENT then
    begin
      BS := Rec.Event.MouseEvent.dwButtonState;
      Result.Kind := ikMouse;
      Result.MouseX := Rec.Event.MouseEvent.dwMousePosition.X + 1;
      Result.MouseY := Rec.Event.MouseEvent.dwMousePosition.Y + 1;
      if (BS and FROM_LEFT_1ST_BUTTON_PRESSED) <> 0 then
        Result.MouseButton := 1
      else if (BS and RIGHTMOST_BUTTON_PRESSED) <> 0 then
        Result.MouseButton := 2
      else
        Result.MouseButton := 0;

      if (Rec.Event.MouseEvent.dwEventFlags and MY_MOUSE_WHEELED) <> 0 then
      begin
        WheelRaw := SmallInt(BS shr 16);
        Result.WheelDelta := WheelRaw;
      end
      else
        Result.WheelDelta := 0;
      Exit;
    end;
  end;
end;

// ═══════════════════════════════════════════════════════════════════
function VisLen(const S: string): Integer;
var I: Integer; InEsc: Boolean;
begin
  Result := 0; InEsc := False;
  for I := 1 to Length(S) do
    if InEsc then
    begin
      if CharInSet(S[I], ['a'..'z','A'..'Z']) then InEsc := False;
    end
    else if S[I] = #27 then InEsc := True
    else Inc(Result);
end;

function PadTo(const S: string; TargetW: Integer;
  const PadBg: string): string;
var V: Integer;
begin
  V := VisLen(S);
  if V >= TargetW then Result := S
  else Result := S + RST + PadBg + StringOfChar(' ', TargetW - V);
end;

function WrapText(const Text: string; MaxW: Integer): TArray<string>;
var Lines: TList<string>; Words: TArray<string>; Cur: string; I: Integer;
begin
  Lines := TList<string>.Create;
  try
    Words := Text.Split([' ']);
    Cur := '';
    for I := 0 to High(Words) do
    begin
      if Cur = '' then Cur := Words[I]
      else if Length(Cur) + 1 + Length(Words[I]) <= MaxW then
        Cur := Cur + ' ' + Words[I]
      else begin Lines.Add(Cur); Cur := Words[I]; end;
    end;
    if Cur <> '' then Lines.Add(Cur);
    if Lines.Count = 0 then Lines.Add('');
    Result := Lines.ToArray;
  finally Lines.Free; end;
end;

function NowTime: string;  begin Result := FormatDateTime('hh:nn', Now); end;

function NowClock: string;
var
  Y, M, D: Word;
  H, Mn, S, Ms: Word;
  Hour12: Word;
  AmPm: string;
begin
  DecodeDate(Now, Y, M, D);
  DecodeTime(Now, H, Mn, S, Ms);
  if H < 12 then AmPm := 'am' else AmPm := 'pm';
  Hour12 := H mod 12;
  if Hour12 = 0 then Hour12 := 12;
  Result := Format('%d %s %d, %.2d:%.2d:%.2d %s',
    [D, FormatSettings.LongMonthNames[M], Y, Hour12, Mn, S, AmPm]);
end;

function Rep(const C: Char; N: Integer): string;
begin if N <= 0 then Result := '' else Result := StringOfChar(C, N); end;

// ═══════════════════════════════════════════════════════════════════
procedure AppInit;
var S: TSession; M: TChatMessage; P: TPlanItem; W: TWorkItem; T: TTreeItem;
begin
  Messages   := TList<TChatMessage>.Create;
  PlanItems  := TList<TPlanItem>.Create;
  WorkItems  := TList<TWorkItem>.Create;
  ThinkLines := TList<string>.Create;
  Sessions   := TList<TSession>.Create;
  TreeItems  := TList<TTreeItem>.Create;
  CurrentSession := 'Architecture Review';

  T.Name := 'Local';         T.Depth := 0; T.Perm := '';    TreeItems.Add(T);
  T.Name := 'Projects';      T.Depth := 1; T.Perm := 'RWX'; TreeItems.Add(T);
  T.Name := 'GRISP';         T.Depth := 2; T.Perm := 'RWX'; TreeItems.Add(T);
  T.Name := 'MME-Registry';  T.Depth := 2; T.Perm := 'RW';  TreeItems.Add(T);
  T.Name := 'Agent-Network'; T.Depth := 2; T.Perm := 'RW';  TreeItems.Add(T);
  T.Name := 'Data';          T.Depth := 1; T.Perm := 'RW';  TreeItems.Add(T);
  T.Name := 'Models';        T.Depth := 2; T.Perm := 'RW';  TreeItems.Add(T);
  T.Name := 'Downloads';     T.Depth := 2; T.Perm := 'R';   TreeItems.Add(T);
  T.Name := 'Cloud';         T.Depth := 1; T.Perm := 'R';   TreeItems.Add(T);

  S.Name := 'Architecture Review'; S.Meta := '24 Sep - 14:30'; Sessions.Add(S);
  S.Name := 'MME Schema Draft';    S.Meta := '24 Sep - 12:10'; Sessions.Add(S);
  S.Name := 'Agent Graph';         S.Meta := '23 Sep - 18:22'; Sessions.Add(S);
  S.Name := 'VFS Refactor Notes';  S.Meta := '23 Sep - 09:15'; Sessions.Add(S);

  M.Role := crAssistant;
  M.Text := 'Hello Alex, how can I help you with GRISP today?';
  M.Time := NowTime; Messages.Add(M);
  M.Text := 'I can help with analysis, planning, or code generation. Just ask.';
  M.Time := NowTime; Messages.Add(M);

  P.Text := 'Analyze VFS Layer';           P.Status := psDone;    PlanItems.Add(P);
  P.Text := 'Extract MME schema';          P.Status := psDone;    PlanItems.Add(P);
  P.Text := 'Map Agent Network';           P.Status := psRunning; PlanItems.Add(P);
  P.Text := 'Draft DNA report';            P.Status := psQueued;  PlanItems.Add(P);
  P.Text := 'Validate permissions matrix'; P.Status := psQueued;  PlanItems.Add(P);

  W.Text := 'Implement GRISP runtime'; W.Prio := wpHigh;   WorkItems.Add(W);
  W.Text := 'Add graph visualization'; W.Prio := wpMedium; WorkItems.Add(W);
  W.Text := 'Write unit tests';        W.Prio := wpMedium; WorkItems.Add(W);
  W.Text := 'Update LSBP integration'; W.Prio := wpLow;    WorkItems.Add(W);

  ThinkLines.Add('Waiting for user input...');
  ThinkLines.Add('Parsing GRISP environment...');
  ThinkLines.Add('Ready to assist.');
end;

procedure AppShutdown;
begin
  Messages.Free; PlanItems.Free; WorkItems.Free;
  ThinkLines.Free; Sessions.Free; TreeItems.Free;
end;

// ═══════════════════════════════════════════════════════════════════
function RenderLeft(Height: Integer): TArray<string>;
var
  L: TList<string>; I, Indent, NameW: Integer;
  Buf, PermCol, NameField: string;
  T: TTreeItem; S: TSession;
  procedure AddLine(const S: string);
  begin L.Add(PadTo(S, ColL, BG_PANEL) + RST); end;
begin
  L := TList<string>.Create;
  try
    AddLine(BG_PANEL + FG_CYAN + BOLD + ' ' + S_FDIAMOND + ' RESOURCES');
    AddLine(BG_PANEL + FG_BORDER + ' ' + Rep(S_H, ColL - 2));

    for I := 0 to TreeItems.Count - 1 do
    begin
      T := TreeItems[I];
      Indent := 1 + T.Depth * 2;
      NameW  := ColL - Indent - 8;
      if NameW < 4 then NameW := 4;
      if T.Perm = '' then
        Buf := BG_PANEL + FG_CYAN + StringOfChar(' ', Indent)
             + S_RTRI + ' ' + BOLD + T.Name
      else
      begin
        if T.Perm = 'RWX' then PermCol := FG_CYAN
        else if T.Perm = 'RW' then PermCol := FG_AMBER
        else PermCol := FG_GRAY;
        NameField := T.Name;
        if Length(NameField) > NameW then
          NameField := Copy(NameField, 1, NameW);
        NameField := NameField + StringOfChar(' ', NameW - Length(NameField));
        Buf := BG_PANEL + StringOfChar(' ', Indent) + FG_TEXT + S_RTRI + ' '
             + NameField + ' ' + PermCol + T.Perm;
      end;
      AddLine(Buf);
    end;

    AddLine(BG_PANEL);
    AddLine(BG_PANEL + FG_CYAN + BOLD + ' ' + S_FDIAMOND + ' SESSIONS');
    AddLine(BG_PANEL + FG_BORDER + ' ' + Rep(S_H, ColL - 2));

    for I := 0 to Sessions.Count - 1 do
    begin
      S := Sessions[I];
      if I = ActiveSessionIdx then
        Buf := BG_PANEL + FG_CYAN + BOLD + ' ' + S_RTRI + ' ' + S.Name
      else
        Buf := BG_PANEL + FG_TEXT + ' ' + S_RTRI + ' ' + S.Name;
      AddLine(Buf);
      AddLine(BG_PANEL + FG_GRAY + '    ' + S.Meta);
    end;

    while L.Count < Height do AddLine(BG_PANEL);
    Result := L.ToArray;
  finally L.Free; end;
end;

// ═══════════════════════════════════════════════════════════════════
function RenderCenter(Height: Integer): TArray<string>;
var
  L, Full: TList<string>;
  I, J, Total, WindowStart, WindowEnd, BodyH: Integer;
  M: TChatMessage;
  Wrapped: TArray<string>;
  Buf, SenderCol, Prefix, TimePart, Hdr: string;
  RightPad: Integer;
  procedure Emit(const S: string);
  begin L.Add(PadTo(S, ColC, BG_MAIN) + RST); end;
begin
  L := TList<string>.Create;
  Full := TList<string>.Create;
  try
    Hdr := BG_MAIN + ' ' + FG_CYAN + BOLD + S_FDIAMOND + ' CHAT'
         + RST + BG_MAIN + FG_DGRAY + ' - ' + FG_TEXT + CurrentSession;
    if ChatScroll > 0 then
      Hdr := Hdr + RST + BG_MAIN + '  '
           + FG_AMBER + S_UP + ' scrolled +' + IntToStr(ChatScroll);
    L.Add(PadTo(Hdr, ColC, BG_MAIN) + RST);
    L.Add(PadTo(BG_MAIN + ' ' + FG_BORDER + Rep(S_H, ColC - 2), ColC, BG_MAIN) + RST);

    for I := 0 to Messages.Count - 1 do
    begin
      M := Messages[I];
      if M.Role = crUser then
      begin SenderCol := FG_USER + BOLD; Prefix := ' You'; end
      else if M.Role = crAssistant then
      begin SenderCol := FG_CYAN + BOLD;
            Prefix    := ' ' + S_DIAMOND + ' GRISP Assistant'; end
      else
      begin SenderCol := FG_AMBER + BOLD; Prefix := ' [sys]'; end;

      TimePart := '[' + M.Time + ']';
      Buf := BG_MAIN + SenderCol + Prefix;
      RightPad := ColC - 1 - VisLen(Buf) - Length(TimePart);
      if RightPad < 1 then RightPad := 1;
      Buf := Buf + StringOfChar(' ', RightPad)
           + FG_DGRAY + TimePart + ' ';
      Full.Add(Buf);

      Wrapped := WrapText(M.Text, ColC - 8);
      for J := 0 to High(Wrapped) do
      begin
        if M.Role = crUser then
          Buf := BG_MAIN + '  ' + BG_USER + FG_TEXT
               + '  ' + Wrapped[J] + '  ' + RST + BG_MAIN
        else if M.Role = crAssistant then
          Buf := BG_MAIN + '  ' + BG_AI + FG_SLATE + S_BLOCK
               + BG_AI + FG_TEXT + ' ' + Wrapped[J] + '  ' + RST + BG_MAIN
        else
          Buf := BG_MAIN + '  ' + FG_GRAY + '    ' + Wrapped[J];
        Full.Add(Buf);
      end;
      Full.Add(BG_MAIN);
    end;

    BodyH := Height - 2;
    if BodyH < 1 then BodyH := 1;
    Total := Full.Count;
    if Total > BodyH then ChatMaxScroll := Total - BodyH
    else ChatMaxScroll := 0;
    if ChatScroll > ChatMaxScroll then ChatScroll := ChatMaxScroll;
    if ChatScroll < 0 then ChatScroll := 0;

    WindowEnd := Total - ChatScroll;
    if WindowEnd < 0 then WindowEnd := 0;
    WindowStart := WindowEnd - BodyH;
    if WindowStart < 0 then WindowStart := 0;

    for I := WindowStart to WindowEnd - 1 do
      Emit(Full[I]);

    while L.Count < Height do Emit(BG_MAIN);

    Result := L.ToArray;
  finally L.Free; Full.Free; end;
end;

// ═══════════════════════════════════════════════════════════════════
function RenderRight(Height: Integer): TArray<string>;
var
  L: TList<string>; I: Integer;
  PlanH, WorkH, ThinkH, Budget: Integer;
  Buf, Sym, SymCol, PrioCol, PrioLabel: string;
  P: TPlanItem; W: TWorkItem;
  procedure AddLine(const S: string);
  begin L.Add(PadTo(S, ColR, BG_PANEL) + RST); end;
begin
  L := TList<string>.Create;
  try
    Budget := Height - 6;
    if Budget < 6 then Budget := 6;

    PlanH  := PlanItems.Count;
    WorkH  := WorkItems.Count;
    ThinkH := ThinkLines.Count;
    if ThinkH > 8 then ThinkH := 8;

    while (PlanH + WorkH + ThinkH) > Budget do
    begin
      if ThinkH > 2 then Dec(ThinkH)
      else if WorkH > 2 then Dec(WorkH)
      else if PlanH > 2 then Dec(PlanH)
      else Break;
    end;

    AddLine(BG_PANEL + FG_CYAN + BOLD + ' ' + S_FDIAMOND + ' CURRENT PLAN');
    AddLine(BG_PANEL + FG_BORDER + ' ' + Rep(S_H, ColR - 2));
    for I := 0 to PlanH - 1 do
    begin
      if I < PlanItems.Count then
      begin
        P := PlanItems[I];
        case P.Status of
          psDone:    begin Sym := S_CHECKED;   SymCol := FG_GREEN; end;
          psRunning: begin Sym := S_PTRI;      SymCol := FG_AMBER; end;
        else         begin Sym := S_UNCHECKED; SymCol := FG_DGRAY; end;
        end;
        Buf := BG_PANEL + ' ' + SymCol + Sym + ' ' + FG_TEXT + P.Text;
      end else Buf := BG_PANEL;
      AddLine(Buf);
    end;

    AddLine(BG_PANEL + FG_CYAN + BOLD + ' ' + S_FDIAMOND + ' WORK ITEMS');
    AddLine(BG_PANEL + FG_BORDER + ' ' + Rep(S_H, ColR - 2));
    for I := 0 to WorkH - 1 do
    begin
      if I < WorkItems.Count then
      begin
        W := WorkItems[I];
        case W.Prio of
          wpHigh:   begin PrioCol := FG_RED;   PrioLabel := '[HIGH]'; end;
          wpMedium: begin PrioCol := FG_AMBER; PrioLabel := '[MED ]'; end;
        else        begin PrioCol := FG_GREEN; PrioLabel := '[LOW ]'; end;
        end;
        Buf := BG_PANEL + ' ' + FG_TEXT + W.Text + '  ' + PrioCol + PrioLabel;
      end else Buf := BG_PANEL;
      AddLine(Buf);
    end;

    if EffThink then
      AddLine(BG_PANEL + FG_PURPLE + BOLD + ' ' + S_FDIAMOND
            + ' THINKING  ' + FG_DGRAY + '[F3]')
    else
      AddLine(BG_PANEL + FG_DGRAY + ' ' + S_FDIAMOND
            + ' THINKING  [F3 - hidden]');
    AddLine(BG_PANEL + FG_BORDER + ' ' + Rep(S_H, ColR - 2));

    if EffThink then
    begin
      for I := 0 to ThinkH - 1 do
      begin
        if I < ThinkLines.Count then
          Buf := BG_PANEL + ' ' + FG_BORDER + S_GT + ' '
               + FG_GRAY + ThinkLines[I]
        else Buf := BG_PANEL;
        AddLine(Buf);
      end;
    end
    else for I := 0 to ThinkH - 1 do AddLine(BG_PANEL);

    while L.Count < Height do AddLine(BG_PANEL);
    Result := L.ToArray;
  finally L.Free; end;
end;

// ═══════════════════════════════════════════════════════════════════
function RenderFrame: string;
var
  SB: TStringBuilder;
  Left, Center, Right: TArray<string>;
  I, ContentH, InputRow, InputCol: Integer;
  Line, SepTop, SepBot, TopBar, InpBar, StatBar: string;
  MouseLabel, Hints, ClockStr, SepCol1, SepCol2, SepCol3: string;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append(HIDE_CUR);
    SB.Append(HOME);

    ContentH := ScreenH - 8;
    if ContentH < 5 then ContentH := 5;

    // Kleur van de sleepbare scheiders bij hover/drag
    SepCol1 := FG_BORDER;
    if (HoverSep = 1) or (Dragging and (DragTarget = 1)) then SepCol1 := FG_CYAN;
    SepCol2 := FG_BORDER;
    if (HoverSep = 2) or (Dragging and (DragTarget = 2)) then SepCol2 := FG_CYAN;
    SepCol3 := FG_BORDER;

    // Top border
    SB.Append(FG_BORDER + S_ULC + Rep(S_H, ScreenW - 2) + S_URC
            + RST + #13#10);

    // Title bar met hints (afhankelijk van breedte) en datum+tijd
    if ScreenW >= 150 then
      Hints := '   ' + FG_DGRAY + '[F1]' + FG_TEXT + ' Res'
             + '  ' + FG_DGRAY + '[F2]' + FG_TEXT + ' Right'
             + '  ' + FG_DGRAY + '[F3]' + FG_TEXT + ' Think'
             + '  ' + FG_DGRAY + '[F4]' + FG_TEXT + ' Send'
             + '  ' + FG_DGRAY + '[F5]' + FG_TEXT + ' Mouse'
             + '  ' + FG_DGRAY + '[Esc]' + FG_TEXT + ' Quit'
    else if ScreenW >= 110 then
      Hints := '  ' + FG_DGRAY + '[F1]R' + FG_TEXT + ' '
             + FG_DGRAY + '[F2]Rt' + FG_TEXT + ' '
             + FG_DGRAY + '[F3]T' + FG_TEXT + ' '
             + FG_DGRAY + '[F4]S' + FG_TEXT + ' '
             + FG_DGRAY + '[F5]M' + FG_TEXT + ' '
             + FG_DGRAY + '[Esc]Q'
    else
      Hints := '';

    Line := BG_BAR + ' ' + FG_CYAN + BOLD + S_DIAMOND + ' '
          + APP_NAME + ' ' + FG_DGRAY + APP_VERSION
          + RST + BG_BAR + Hints;

    ClockStr := ' ' + NowClock + '  ';
    // Reserveer ruimte voor de klok aan de rechterkant
    TopBar := PadTo(Line, ScreenW - 2 - Length(ClockStr), BG_BAR)
            + FG_CYAN + ClockStr;
    SB.Append(FG_BORDER + S_V + RST
            + PadTo(TopBar, ScreenW - 2, BG_BAR) + RST
            + FG_BORDER + S_V + RST + #13#10);

    // Pane top separator — met gekleurde scheiders
    if EffLeft and EffRight then
      SepTop := S_BW + Rep(S_H, ColL) + SepCol1 + S_TE + FG_BORDER
              + Rep(S_H, ColC) + SepCol2 + S_TE + FG_BORDER
              + Rep(S_H, ColR) + S_TW
    else if EffRight then
      SepTop := S_BW + Rep(S_H, ScreenW - ColR - 3) + SepCol2 + S_TE + FG_BORDER
              + Rep(S_H, ColR) + S_TW
    else if EffLeft then
      SepTop := S_BW + Rep(S_H, ColL) + SepCol1 + S_TE + FG_BORDER
              + Rep(S_H, ScreenW - ColL - 3) + S_TW
    else
      SepTop := S_BW + Rep(S_H, ScreenW - 2) + S_TW;
    SB.Append(FG_BORDER + SepTop + RST + #13#10);

    if EffLeft  then Left  := RenderLeft(ContentH)  else Left  := nil;
    Center := RenderCenter(ContentH);
    if EffRight then Right := RenderRight(ContentH) else Right := nil;

    for I := 0 to ContentH - 1 do
    begin
      SB.Append(FG_BORDER + S_V + RST);
      if EffLeft then
      begin
        if I < Length(Left) then SB.Append(Left[I])
        else SB.Append(PadTo('', ColL, BG_PANEL) + RST);
        SB.Append(SepCol1 + S_V + RST);
      end;
      if I < Length(Center) then SB.Append(Center[I])
      else SB.Append(PadTo('', ColC, BG_MAIN) + RST);
      if EffRight then
      begin
        SB.Append(SepCol2 + S_V + RST);
        if I < Length(Right) then SB.Append(Right[I])
        else SB.Append(PadTo('', ColR, BG_PANEL) + RST);
      end;
      SB.Append(SepCol3 + S_V + RST + #13#10);
    end;

    // Pane bottom separator
    if EffLeft and EffRight then
      SepBot := S_BW + Rep(S_H, ColL) + SepCol1 + S_BE + FG_BORDER
              + Rep(S_H, ColC) + SepCol2 + S_BE + FG_BORDER
              + Rep(S_H, ColR) + S_TW
    else if EffRight then
      SepBot := S_BW + Rep(S_H, ScreenW - ColR - 3) + SepCol2 + S_BE + FG_BORDER
              + Rep(S_H, ColR) + S_TW
    else if EffLeft then
      SepBot := S_BW + Rep(S_H, ColL) + SepCol1 + S_BE + FG_BORDER
              + Rep(S_H, ScreenW - ColL - 3) + S_TW
    else
      SepBot := S_BW + Rep(S_H, ScreenW - 2) + S_TW;
    SB.Append(FG_BORDER + SepBot + RST + #13#10);

    InputRow := ScreenH - 3;
    InputCol := 5 + Length(InputBuf);

    if SimActive then
      Line := BG_INPUT + ' ' + FG_AMBER + BOLD + '...' + RST + BG_INPUT
            + FG_AMBER + ' Processing [' + PromptState + ']'
            + ' - press [F4] to step'
    else
      Line := BG_INPUT + ' ' + FG_CYAN + BOLD + '>' + RST + BG_INPUT
            + FG_TEXT + ' ' + InputBuf;

    InpBar := PadTo(Line, ScreenW - 2, BG_INPUT);
    SB.Append(FG_BORDER + S_V + RST
            + PadTo(InpBar, ScreenW - 2, BG_INPUT) + RST
            + FG_BORDER + S_V + RST + #13#10);

    SB.Append(FG_BORDER + S_BW + Rep(S_H, ScreenW - 2) + S_TW
            + RST + #13#10);

    case StatusKind of
      0: Line := FG_GREEN;
      1: Line := FG_AMBER;
    else Line := FG_RED;
    end;

    if MouseEnabled then MouseLabel := 'on' else MouseLabel := 'off';

    StatBar := BG_BAR + ' ' + Line + S_DOT + RST + BG_BAR + ' '
             + FG_TEXT + 'Connected'
             + ' ' + FG_DGRAY + S_V + RST + BG_BAR
             + ' ' + FG_GRAY + 'Model:' + FG_TEXT + ' GPT-5'
             + ' ' + FG_DGRAY + S_V + RST + BG_BAR
             + ' ' + FG_GRAY + 'Prompt:' + Line + ' ' + PromptState
             + ' ' + FG_DGRAY + S_V + RST + BG_BAR
             + ' ' + FG_GRAY + 'Session:' + FG_TEXT + ' '
             + IntToStr(ActiveSessionIdx + 1) + '/'
             + IntToStr(Sessions.Count)
             + ' ' + FG_DGRAY + S_V + RST + BG_BAR
             + ' ' + FG_GRAY + 'Mouse:' + FG_TEXT + ' '
             + MouseLabel
             + ' ' + FG_DGRAY + S_V + RST + BG_BAR
             + ' ' + FG_GRAY + 'Perms:' + FG_CYAN + ' RWX';
    SB.Append(FG_BORDER + S_V + RST
            + PadTo(StatBar, ScreenW - 2, BG_BAR) + RST
            + FG_BORDER + S_V + RST + #13#10);

    SB.Append(FG_BORDER + S_LLC + Rep(S_H, ScreenW - 2) + S_LRC + RST);

    if not SimActive then
    begin
      SB.Append(ESC + '[' + IntToStr(InputRow) + ';'
              + IntToStr(InputCol) + 'H');
      SB.Append(SHOW_CUR);
    end
    else SB.Append(HIDE_CUR);

    Result := SB.ToString;
  finally SB.Free; end;
end;

// ═══════════════════════════════════════════════════════════════════
procedure AddUserMsg(const S: string);
var M: TChatMessage;
begin M.Role := crUser; M.Text := S; M.Time := NowTime; Messages.Add(M); end;

procedure AddAssistantMsg(const S: string);
var M: TChatMessage;
begin M.Role := crAssistant; M.Text := S; M.Time := NowTime; Messages.Add(M); end;

procedure SimBegin;
begin
  SimActive := True; SimStep := 0; SimTimer := GetTickCount;
  PromptState := 'PENDING'; StatusKind := 1;
  ChatScroll := 0;
  ThinkLines.Clear;
  ThinkLines.Add('SIR: parsing user prompt...');
  ThinkLines.Add('Building structured representation...');
  ThinkLines.Add('Planner: generating execution plan...');
end;

procedure SimTick;
begin
  if not SimActive then Exit;
  Inc(SimStep);
  case SimStep of
    1: begin
         PromptState := 'SUBMITTING';
         ThinkLines.Clear;
         ThinkLines.Add('INPUT_SUBMITTED (provider_native_send)');
         ThinkLines.Add('Verifying input ownership...');
         ThinkLines.Add('Awaiting GENERATION_STARTED...');
       end;
    2: begin
         PromptState := 'GENERATING';
         ThinkLines.Clear;
         ThinkLines.Add('GENERATION_STARTED - message identified');
         ThinkLines.Add('Baseline revision captured (r=0)');
         ThinkLines.Add('Streaming GENERATION_DELTA...');
         AddAssistantMsg('Analyzing GRISP architecture.');
       end;
    3: begin
         ThinkLines.Clear;
         ThinkLines.Add('Deltas applied: rev 1..3 (APPEND)');
         ThinkLines.Add('Terminal stability check (1/2)...');
         ThinkLines.Add('Fencing: prompt_request_id OK');
       end;
    4: begin
         ThinkLines.Clear;
         ThinkLines.Add('Terminal stability check (2/2)...');
         ThinkLines.Add('done=true streaming=false continuation=false');
         ThinkLines.Add('Submitting terminal candidate to arbiter');
       end;
    5: begin
         AddAssistantMsg('Main components identified:');
         AddAssistantMsg('  1. SIR - Source Intermediate Representation');
         AddAssistantMsg('  2. Planner - Execution plan builder');
         AddAssistantMsg('  3. Evaluator - Graph operations executor');
         AddAssistantMsg('  4. Validator - Correctness and compliance');
         AddAssistantMsg('  5. EIR - Optimized Execution IR');
         AddAssistantMsg('  6. Runtime - Deterministic executor');
         AddAssistantMsg('  7. WorldState - Persistent state');
         AddAssistantMsg('Would you like me to generate a diagram?');
         ThinkLines.Clear;
         ThinkLines.Add('GENERATION_COMPLETED committed');
         ThinkLines.Add('Terminal arbitration: winner = COMPLETED');
         PromptState := 'COMPLETED'; StatusKind := 0; SimActive := False;
       end;
  end;
end;

procedure SubmitPrompt;
begin
  if Trim(InputBuf) = '' then Exit;
  AddUserMsg(InputBuf);
  InputBuf := '';
  SimBegin;
end;

// ═══════════════════════════════════════════════════════════════════
procedure HandleMouse(const Ev: TInputEvent);
var WheelLines, X, Y: Integer;
begin
  X := Ev.MouseX;
  Y := Ev.MouseY;

  // Update hover-status
  if EffLeft and (X = ColL + 2) then HoverSep := 1
  else if EffRight and (X = ColL + ColC + 3) then HoverSep := 2
  else HoverSep := 0;

  // Muiswiel scrollt de chat
  if Ev.WheelDelta <> 0 then
  begin
    WheelLines := (Ev.WheelDelta div 120) * 3;
    ChatScroll := ChatScroll + WheelLines;
  end;

  if Dragging then
  begin
    if Ev.MouseButton = 1 then
    begin
      // Doorgaan met slepen — direct kolombreedtes aanpassen
      if DragTarget = 1 then
      begin
        ColLUser := X - 2;
        if ColLUser < MIN_COL then ColLUser := MIN_COL;
        if ColLUser > ScreenW - MIN_COL_C - ColR - 4 then
          ColLUser := ScreenW - MIN_COL_C - ColR - 4;
        RecomputeLayout;
      end
      else if DragTarget = 2 then
      begin
        ColRUser := ScreenW - X - 1;
        if ColRUser < MIN_COL then ColRUser := MIN_COL;
        if ColRUser > ScreenW - MIN_COL_C - ColL - 4 then
          ColRUser := ScreenW - MIN_COL_C - ColL - 4;
        RecomputeLayout;
      end;
    end
    else
    begin
      // Knop losgelaten → drag beëindigen
      Dragging := False;
      DragTarget := 0;
    end;
    Exit;
  end;

  // Knop ingedrukt: start drag op scheider, of klik-om-te-scrollen
  if Ev.MouseButton = 1 then
  begin
    if EffLeft and (X = ColL + 2) then
    begin
      Dragging := True;
      DragTarget := 1;
    end
    else if EffRight and (X = ColL + ColC + 3) then
    begin
      Dragging := True;
      DragTarget := 2;
    end
    else if (Y >= 4) and (Y <= ScreenH - 2) then
    begin
      // Gewone klik in een paneel → spring naar onderkant chat
      ChatScroll := 0;
    end;
  end;
end;

// ═══════════════════════════════════════════════════════════════════
procedure HandleEv(const Ev: TInputEvent);
begin
  case Ev.Kind of
    ikChar:
      if Ev.Ch = #13 then
      begin
        if SimActive then SimTick else SubmitPrompt;
      end
      else if Ev.Ch = #8 then
      begin
        if Length(InputBuf) > 0 then
          Delete(InputBuf, Length(InputBuf), 1);
      end
      else if Ord(Ev.Ch) >= 32 then
        InputBuf := InputBuf + Ev.Ch;

    ikSpecial:
      case Ev.VK of
        VK_ESCAPE: QuitFlag := True;
        VK_F1: begin WantLeft  := not WantLeft;  RecomputeLayout; end;
        VK_F2: begin WantRight := not WantRight; RecomputeLayout; end;
        VK_F3: WantThink := not WantThink;
        VK_F4: if SimActive then SimTick else SubmitPrompt;
        VK_F5: begin
                 MouseEnabled := not MouseEnabled;
                 UpdateInputMode;
               end;
        VK_UP:
          if ActiveSessionIdx > 0 then
          begin
            Dec(ActiveSessionIdx);
            CurrentSession := Sessions[ActiveSessionIdx].Name;
          end;
        VK_DOWN:
          if ActiveSessionIdx < Sessions.Count - 1 then
          begin
            Inc(ActiveSessionIdx);
            CurrentSession := Sessions[ActiveSessionIdx].Name;
          end;
        VK_PRIOR: ChatScroll := ChatScroll + 5;
        VK_NEXT:  ChatScroll := ChatScroll - 5;
        VK_HOME:  ChatScroll := ChatMaxScroll;
        VK_END:   ChatScroll := 0;
      end;

    ikMouse:
      if MouseEnabled then HandleMouse(Ev);
  end;
end;

// ═══════════════════════════════════════════════════════════════════
var
  Ev: TInputEvent;
  NewW, NewH: Integer;
begin
  ConsoleInit;
  AppInit;
  try
    WriteOut(ALT_ON);
    WriteOut(RST + CLRSCR);
    while not QuitFlag do
    begin
      ReadTermSize(NewW, NewH);
      if (NewW <> ScreenW) or (NewH <> ScreenH) then
      begin
        RecomputeLayout;
        WriteOut(RST + CLRSCR);
      end;

      WriteOut(RenderFrame);
      repeat
        Ev := ReadEv;
        if Ev.Kind <> ikNone then HandleEv(Ev);
      until Ev.Kind = ikNone;

      if SimActive and ((GetTickCount - SimTimer) > SIM_INTERVAL_MS) then
      begin
        SimTimer := GetTickCount;
        SimTick;
      end;

      Sleep(25);
    end;
  finally
    MouseEnabled := False;
    UpdateInputMode;
    WriteOut(RST + SHOW_CUR + ALT_OFF);
    AppShutdown;
  end;
end.
