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
  APP_NAME='GRISP OS'; APP_VERSION='v0.16';
  S_DIAMOND=#$25C8; S_FDIAMOND=#$25C6; S_RTRI=#$25B8; S_PTRI=#$25B6;
  S_CHECKED=#$2611; S_UNCHECKED=#$2610; S_GT=#$203A; S_BLOCK=#$258C;
  S_DOT=#$25CF; S_UP=#$25B2; S_DOWN=#$25BC;
  S_ULC=#$250C; S_URC=#$2510; S_LLC=#$2514; S_LRC=#$2518;
  S_H=#$2500; S_V=#$2502; S_TE=#$252C; S_TW=#$2524;
  S_BE=#$2534; S_BW=#$251C;
  ESC=#27; RST=ESC+'[0m'; BOLD=ESC+'[1m';
  FG_CYAN=ESC+'[38;2;34;211;238m'; FG_PURPLE=ESC+'[38;2;59;130;246m';
  FG_BORDER=ESC+'[38;2;51;65;85m'; FG_USER=ESC+'[38;2;147;197;253m';
  FG_TEXT=ESC+'[38;2;255;255;255m'; FG_GRAY=ESC+'[38;2;148;163;184m';
  FG_DGRAY=ESC+'[38;2;100;116;139m'; FG_GREEN=ESC+'[38;2;34;197;94m';
  FG_AMBER=ESC+'[38;2;245;158;11m'; FG_SLATE=ESC+'[38;2;56;189;248m';
  FG_RED=ESC+'[38;2;239;68;68m';
  BG_MAIN=ESC+'[48;2;10;14;26m'; BG_PANEL=ESC+'[48;2;13;21;36m';
  BG_BAR=ESC+'[48;2;8;12;22m'; BG_INPUT=ESC+'[48;2;16;27;48m';
  BG_USER=ESC+'[48;2;30;58;138m'; BG_AI=ESC+'[48;2;22;40;66m';
  HIDE_CUR=ESC+'[?25l'; SHOW_CUR=ESC+'[?25h';
  ALT_ON=ESC+'[?1049h'; ALT_OFF=ESC+'[?1049l';
  CLRSCR=ESC+'[2J'+ESC+'[H'; HOME=ESC+'[H';
  SIM_INTERVAL_MS=900; MIN_W_LEFT=110; MIN_W_RIGHT=90;
  MIN_COL=20; MIN_COL_C=30; MAX_INPUT_H=10;
  MY_KEY_EVENT=$0001; MY_MOUSE_EVENT=$0002;
  MY_MOUSE_MOVED=$0001; MY_MOUSE_WHEELED=$0004;

type
  TChatRole=(crUser, crAssistant, crSystem);
  TChatMessage=record Role:TChatRole; Text, Time:string; end;
  TPlanStatus=(psDone, psRunning, psQueued);
  TPlanItem=record Text:string; Status:TPlanStatus; end;
  TWorkPrio=(wpHigh, wpMedium, wpLow);
  TWorkItem=record Text:string; Prio:TWorkPrio; end;
  TSession=record Name, Meta:string; end;
  TTreeItem=record Name:string; Depth:Integer; Perm:string; end;
  TInputKind=(ikNone, ikChar, ikSpecial, ikMouse);
  TInputEvent=record
    Kind:TInputKind; Ch:WideChar; VK:Word;
    MouseX, MouseY:Integer; MouseButton:Integer; WheelDelta:Integer;
  end;

var
  hOut, hIn: THandle;
  ScreenW, ScreenH: Integer;
  ColL, ColC, ColR: Integer;
  ContentH: Integer;   // main pane content rows
  InputH: Integer;     // input area rows (1..MAX_INPUT_H)
  LeftResH: Integer;   // resources section rows within ContentH
  RightPlanH, RightWorkH: Integer;  // right pane section rows

  Messages: TList<TChatMessage>;
  PlanItems: TList<TPlanItem>;
  WorkItems: TList<TWorkItem>;
  ThinkLines: TList<string>;
  Sessions: TList<TSession>;
  TreeItems: TList<TTreeItem>;

  CurrentSession: string; ActiveSessionIdx: Integer = 0;
  InputBuf: string;

  WantLeft: Boolean = True; WantRight: Boolean = True;
  WantThink: Boolean = True; MouseEnabled: Boolean = True;
  EffLeft: Boolean = True; EffRight: Boolean = True; EffThink: Boolean = True;

  ColLUser: Integer = 0; ColRUser: Integer = 0;
  InputHUser: Integer = 0;
  LeftResHUser: Integer = 0;
  RightPlanHUser: Integer = 0; RightWorkHUser: Integer = 0;

  Dragging: Boolean = False; DragTarget: Integer = 0;
  HoverSep: Integer = 0;

  ChatScroll: Integer = 0; ChatMaxScroll: Integer = 0;
  QuitFlag: Boolean = False;
  SimActive: Boolean = False; SimStep: Integer = 0; SimTimer: Cardinal = 0;
  PromptState: string = 'READY'; StatusKind: Integer = 0;

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
  if W < 60 then W := 60; if H < 20 then H := 20;
end;

procedure RecomputeLayout;
var Available: Integer;
begin
  ReadTermSize(ScreenW, ScreenH);
  EffLeft := WantLeft and (ScreenW >= MIN_W_LEFT);
  EffRight := WantRight and (ScreenW >= MIN_W_RIGHT);
  EffThink := WantThink;

  if EffLeft then
  begin
    if ColLUser > 0 then ColL := ColLUser
    else ColL := EnsureRange(ScreenW div 7, 22, 28);
    if ColL < MIN_COL then ColL := MIN_COL;
  end else ColL := 0;

  if EffRight then
  begin
    if ColRUser > 0 then ColR := ColRUser
    else ColR := EnsureRange(ScreenW div 5, 30, 40);
    if ColR < MIN_COL then ColR := MIN_COL;
  end else ColR := 0;

  ColC := ScreenW - ColL - ColR - 4;
  if ColC < MIN_COL_C then
  begin
    if EffRight then begin
      ColR := ColR - (MIN_COL_C - ColC); if ColR < MIN_COL then ColR := MIN_COL;
      ColC := ScreenW - ColL - ColR - 4;
    end;
    if (ColC < MIN_COL_C) and EffLeft then begin
      ColL := ColL - (MIN_COL_C - ColC); if ColL < MIN_COL then ColL := MIN_COL;
      ColC := ScreenW - ColL - ColR - 4;
    end;
    if ColC < 10 then ColC := 10;
  end;

  // Input area hoogte
  if InputHUser > 0 then InputH := InputHUser else InputH := 1;
  if InputH < 1 then InputH := 1;
  if InputH > MAX_INPUT_H then InputH := MAX_INPUT_H;
  if InputH > ScreenH div 3 then InputH := ScreenH div 3;

  ContentH := ScreenH - 7 - InputH;
  if ContentH < 6 then
  begin
    ContentH := 6;
    InputH := ScreenH - 7 - ContentH;
    if InputH < 1 then InputH := 1;
  end;

  // Left pane split: ResRows + 1 (divider) + SessRows = ContentH
  if LeftResHUser > 0 then LeftResH := LeftResHUser
  else LeftResH := (ContentH - 1) div 2;
  if LeftResH < 3 then LeftResH := 3;
  if LeftResH > ContentH - 4 then LeftResH := ContentH - 4;

  // Right pane split: PlanH + 1 + WorkH + 1 + ThinkH = ContentH
  Available := ContentH - 2;
  if RightPlanHUser > 0 then RightPlanH := RightPlanHUser
  else RightPlanH := Available div 3;
  if RightWorkHUser > 0 then RightWorkH := RightWorkHUser
  else RightWorkH := Available div 3;
  if RightPlanH < 3 then RightPlanH := 3;
  if RightWorkH < 3 then RightWorkH := 3;
  while (RightPlanH + RightWorkH) > Available - 3 do
  begin
    if RightWorkH > 3 then Dec(RightWorkH)
    else if RightPlanH > 3 then Dec(RightPlanH)
    else Break;
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
  hIn := GetStdHandle(STD_INPUT_HANDLE);
  GetConsoleMode(hOut, Mode);
  SetConsoleMode(hOut, (Mode or ENABLE_VIRTUAL_TERMINAL_PROCESSING
    or ENABLE_PROCESSED_OUTPUT) and not ENABLE_WRAP_AT_EOL_OUTPUT);
  SetConsoleOutputCP(CP_UTF8); SetConsoleCP(CP_UTF8);
  SetConsoleTitle(PChar(APP_NAME+' '+APP_VERSION+' - Terminal UI'));
  UpdateInputMode; RecomputeLayout;
end;

procedure WriteOut(const S: string);
var N: DWORD;
begin
  if S = '' then Exit;
  WriteConsoleW(hOut, PWideChar(S), Length(S), N, nil);
end;

function ReadEv: TInputEvent;
var N: DWORD; Rec: INPUT_RECORD; Rd: DWORD; BS: DWORD; WheelRaw: SmallInt;
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
      if (BS and FROM_LEFT_1ST_BUTTON_PRESSED) <> 0 then Result.MouseButton := 1
      else if (BS and RIGHTMOST_BUTTON_PRESSED) <> 0 then Result.MouseButton := 2
      else Result.MouseButton := 0;
      if (Rec.Event.MouseEvent.dwEventFlags and MY_MOUSE_WHEELED) <> 0 then
      begin
        WheelRaw := SmallInt(BS shr 16); Result.WheelDelta := WheelRaw;
      end else Result.WheelDelta := 0;
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
    begin if CharInSet(S[I], ['a'..'z','A'..'Z']) then InEsc := False; end
    else if S[I] = #27 then InEsc := True
    else Inc(Result);
end;

function PadTo(const S: string; TargetW: Integer; const PadBg: string): string;
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

function WrapMultiline(const Text: string; MaxW: Integer): TArray<string>;
var Segs: TArray<string>; L: TList<string>; I, J: Integer; W: TArray<string>;
begin
  L := TList<string>.Create;
  try
    Segs := Text.Split([#10]);
    for I := 0 to High(Segs) do
    begin
      W := WrapText(Segs[I], MaxW);
      for J := 0 to High(W) do L.Add(W[J]);
    end;
    if L.Count = 0 then L.Add('');
    Result := L.ToArray;
  finally L.Free; end;
end;

function NowTime: string; begin Result := FormatDateTime('hh:nn', Now); end;
function NowClock: string;
var Y, M, D: Word; H, Mn, S, Ms: Word; H12: Word; AP: string;
begin
  DecodeDate(Now, Y, M, D); DecodeTime(Now, H, Mn, S, Ms);
  if H < 12 then AP := 'am' else AP := 'pm';
  H12 := H mod 12; if H12 = 0 then H12 := 12;
  Result := Format('%d %s %d, %.2d:%.2d:%.2d %s',
    [D, FormatSettings.LongMonthNames[M], Y, H12, Mn, S, AP]);
end;

function Rep(const C: Char; N: Integer): string;
begin if N <= 0 then Result := '' else Result := StringOfChar(C, N); end;

// ═══════════════════════════════════════════════════════════════════
procedure AppInit;
var S: TSession; M: TChatMessage; P: TPlanItem; W: TWorkItem; T: TTreeItem;
begin
  Messages := TList<TChatMessage>.Create;
  PlanItems := TList<TPlanItem>.Create;
  WorkItems := TList<TWorkItem>.Create;
  ThinkLines := TList<string>.Create;
  Sessions := TList<TSession>.Create;
  TreeItems := TList<TTreeItem>.Create;
  CurrentSession := 'Architecture Review';

  T.Name:='Local'; T.Depth:=0; T.Perm:=''; TreeItems.Add(T);
  T.Name:='Projects'; T.Depth:=1; T.Perm:='RWX'; TreeItems.Add(T);
  T.Name:='GRISP'; T.Depth:=2; T.Perm:='RWX'; TreeItems.Add(T);
  T.Name:='MME-Registry'; T.Depth:=2; T.Perm:='RW'; TreeItems.Add(T);
  T.Name:='Agent-Network'; T.Depth:=2; T.Perm:='RW'; TreeItems.Add(T);
  T.Name:='Data'; T.Depth:=1; T.Perm:='RW'; TreeItems.Add(T);
  T.Name:='Models'; T.Depth:=2; T.Perm:='RW'; TreeItems.Add(T);
  T.Name:='Downloads'; T.Depth:=2; T.Perm:='R'; TreeItems.Add(T);
  T.Name:='Cloud'; T.Depth:=1; T.Perm:='R'; TreeItems.Add(T);

  S.Name:='Architecture Review'; S.Meta:='24 Sep - 14:30'; Sessions.Add(S);
  S.Name:='MME Schema Draft'; S.Meta:='24 Sep - 12:10'; Sessions.Add(S);
  S.Name:='Agent Graph'; S.Meta:='23 Sep - 18:22'; Sessions.Add(S);
  S.Name:='VFS Refactor Notes'; S.Meta:='23 Sep - 09:15'; Sessions.Add(S);

  M.Role:=crAssistant;
  M.Text:='Hello Alex, how can I help you with GRISP today?';
  M.Time:=NowTime; Messages.Add(M);
  M.Text:='I can help with analysis, planning, or code generation. Just ask.';
  M.Time:=NowTime; Messages.Add(M);

  P.Text:='Analyze VFS Layer'; P.Status:=psDone; PlanItems.Add(P);
  P.Text:='Extract MME schema'; P.Status:=psDone; PlanItems.Add(P);
  P.Text:='Map Agent Network'; P.Status:=psRunning; PlanItems.Add(P);
  P.Text:='Draft DNA report'; P.Status:=psQueued; PlanItems.Add(P);
  P.Text:='Validate permissions matrix'; P.Status:=psQueued; PlanItems.Add(P);

  W.Text:='Implement GRISP runtime'; W.Prio:=wpHigh; WorkItems.Add(W);
  W.Text:='Add graph visualization'; W.Prio:=wpMedium; WorkItems.Add(W);
  W.Text:='Write unit tests'; W.Prio:=wpMedium; WorkItems.Add(W);
  W.Text:='Update LSBP integration'; W.Prio:=wpLow; WorkItems.Add(W);

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
//  LEFT PANE — Resources + Sessions with divider
// ═══════════════════════════════════════════════════════════════════
function RenderLeft: TArray<string>;
var
  L: TList<string>; I, Indent, NameW, SessRows, DivRow: Integer;
  Buf, PermCol, NameField, DivCol: string;
  T: TTreeItem; S: TSession;
  procedure AddLine(const S: string);
  begin L.Add(PadTo(S, ColL, BG_PANEL) + RST); end;
begin
  L := TList<string>.Create;
  try
    DivRow := LeftResH;
    SessRows := ContentH - 1 - LeftResH;

    // Resources section
    AddLine(BG_PANEL + FG_CYAN + BOLD + ' ' + S_FDIAMOND + ' RESOURCES');
    AddLine(BG_PANEL + FG_BORDER + ' ' + Rep(S_H, ColL - 2));
    for I := 0 to LeftResH - 3 do
    begin
      if I < TreeItems.Count then
      begin
        T := TreeItems[I];
        Indent := 1 + T.Depth * 2;
        NameW := ColL - Indent - 8;
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
          if Length(NameField) > NameW then NameField := Copy(NameField,1,NameW);
          NameField := NameField + StringOfChar(' ', NameW-Length(NameField));
          Buf := BG_PANEL + StringOfChar(' ', Indent) + FG_TEXT + S_RTRI + ' '
               + NameField + ' ' + PermCol + T.Perm;
        end;
        AddLine(Buf);
      end else AddLine(BG_PANEL);
    end;
    // Pad resources to DivRow-1 rows then divider at DivRow
    while L.Count < DivRow do AddLine(BG_PANEL);

    // Divider row
    if (HoverSep = 11) or (Dragging and (DragTarget = 11)) then DivCol := FG_CYAN
    else DivCol := FG_BORDER;
    L.Add(BG_PANEL + DivCol + Rep(S_H, ColL) + RST);

    // Sessions section
    AddLine(BG_PANEL + FG_CYAN + BOLD + ' ' + S_FDIAMOND + ' SESSIONS');
    AddLine(BG_PANEL + FG_BORDER + ' ' + Rep(S_H, ColL - 2));
    for I := 0 to SessRows - 3 do
    begin
      if I < Sessions.Count then
      begin
        S := Sessions[I];
        if I = ActiveSessionIdx then
          Buf := BG_PANEL + FG_CYAN + BOLD + ' ' + S_RTRI + ' ' + S.Name
        else Buf := BG_PANEL + FG_TEXT + ' ' + S_RTRI + ' ' + S.Name;
        AddLine(Buf);
        AddLine(BG_PANEL + FG_GRAY + '    ' + S.Meta);
      end else AddLine(BG_PANEL);
    end;

    while L.Count < ContentH do AddLine(BG_PANEL);
    Result := L.ToArray;
  finally L.Free; end;
end;

// ═══════════════════════════════════════════════════════════════════
//  CENTER PANE — chat
// ═══════════════════════════════════════════════════════════════════
function RenderCenter: TArray<string>;
var
  L, Full: TList<string>;
  I, J, Total, WS, WE, BodyH: Integer;
  M: TChatMessage; Wrapped: TArray<string>;
  Buf, SenderCol, Prefix, TimePart, Hdr: string; RightPad: Integer;
  procedure Emit(const S: string);
  begin L.Add(PadTo(S, ColC, BG_MAIN) + RST); end;
begin
  L := TList<string>.Create; Full := TList<string>.Create;
  try
    Hdr := BG_MAIN + ' ' + FG_CYAN + BOLD + S_FDIAMOND + ' CHAT'
         + RST + BG_MAIN + FG_DGRAY + ' - ' + FG_TEXT + CurrentSession;
    if ChatScroll > 0 then
      Hdr := Hdr + RST + BG_MAIN + '  ' + FG_AMBER + S_UP
           + ' scrolled +' + IntToStr(ChatScroll);
    L.Add(PadTo(Hdr, ColC, BG_MAIN) + RST);
    L.Add(PadTo(BG_MAIN + ' ' + FG_BORDER + Rep(S_H, ColC - 2), ColC, BG_MAIN) + RST);

    for I := 0 to Messages.Count - 1 do
    begin
      M := Messages[I];
      if M.Role = crUser then begin SenderCol := FG_USER + BOLD; Prefix := ' You'; end
      else if M.Role = crAssistant then
      begin SenderCol := FG_CYAN + BOLD; Prefix := ' ' + S_DIAMOND + ' GRISP Assistant'; end
      else begin SenderCol := FG_AMBER + BOLD; Prefix := ' [sys]'; end;

      TimePart := '[' + M.Time + ']';
      Buf := BG_MAIN + SenderCol + Prefix;
      RightPad := ColC - 1 - VisLen(Buf) - Length(TimePart);
      if RightPad < 1 then RightPad := 1;
      Buf := Buf + StringOfChar(' ', RightPad) + FG_DGRAY + TimePart + ' ';
      Full.Add(Buf);

      Wrapped := WrapText(M.Text, ColC - 8);
      for J := 0 to High(Wrapped) do
      begin
        if M.Role = crUser then
          Buf := BG_MAIN + '  ' + BG_USER + FG_TEXT + '  ' + Wrapped[J] + '  ' + RST + BG_MAIN
        else if M.Role = crAssistant then
          Buf := BG_MAIN + '  ' + BG_AI + FG_SLATE + S_BLOCK
               + BG_AI + FG_TEXT + ' ' + Wrapped[J] + '  ' + RST + BG_MAIN
        else Buf := BG_MAIN + '  ' + FG_GRAY + '    ' + Wrapped[J];
        Full.Add(Buf);
      end;
      Full.Add(BG_MAIN);
    end;

    BodyH := ContentH - 2; if BodyH < 1 then BodyH := 1;
    Total := Full.Count;
    if Total > BodyH then ChatMaxScroll := Total - BodyH else ChatMaxScroll := 0;
    if ChatScroll > ChatMaxScroll then ChatScroll := ChatMaxScroll;
    if ChatScroll < 0 then ChatScroll := 0;
    WE := Total - ChatScroll; if WE < 0 then WE := 0;
    WS := WE - BodyH; if WS < 0 then WS := 0;
    for I := WS to WE - 1 do Emit(Full[I]);
    while L.Count < ContentH do Emit(BG_MAIN);
    Result := L.ToArray;
  finally L.Free; Full.Free; end;
end;

// ═══════════════════════════════════════════════════════════════════
//  RIGHT PANE — Plan / Work / Think with 2 dividers
// ═══════════════════════════════════════════════════════════════════
function RenderRight: TArray<string>;
var
  L: TList<string>; I, ThinkH, Div1, Div2: Integer;
  Buf, Sym, SymCol, PrioCol, PrioLabel, DivCol1, DivCol2: string;
  P: TPlanItem; W: TWorkItem;
  procedure AddLine(const S: string);
  begin L.Add(PadTo(S, ColR, BG_PANEL) + RST); end;
begin
  L := TList<string>.Create;
  try
    ThinkH := ContentH - 2 - RightPlanH - RightWorkH;
    if ThinkH < 3 then ThinkH := 3;
    Div1 := RightPlanH;
    Div2 := RightPlanH + 1 + RightWorkH;

    if (HoverSep = 12) or (Dragging and (DragTarget = 12)) then DivCol1 := FG_CYAN
    else DivCol1 := FG_BORDER;
    if (HoverSep = 13) or (Dragging and (DragTarget = 13)) then DivCol2 := FG_CYAN
    else DivCol2 := FG_BORDER;

    // CURRENT PLAN
    AddLine(BG_PANEL + FG_CYAN + BOLD + ' ' + S_FDIAMOND + ' CURRENT PLAN');
    AddLine(BG_PANEL + FG_BORDER + ' ' + Rep(S_H, ColR - 2));
    for I := 0 to RightPlanH - 3 do
    begin
      if I < PlanItems.Count then
      begin
        P := PlanItems[I];
        case P.Status of
          psDone: begin Sym := S_CHECKED; SymCol := FG_GREEN; end;
          psRunning: begin Sym := S_PTRI; SymCol := FG_AMBER; end;
        else begin Sym := S_UNCHECKED; SymCol := FG_DGRAY; end;
        end;
        Buf := BG_PANEL + ' ' + SymCol + Sym + ' ' + FG_TEXT + P.Text;
      end else Buf := BG_PANEL;
      AddLine(Buf);
    end;
    while L.Count < Div1 do AddLine(BG_PANEL);

    // Divider 1
    L.Add(BG_PANEL + DivCol1 + Rep(S_H, ColR) + RST);

    // WORK ITEMS
    AddLine(BG_PANEL + FG_CYAN + BOLD + ' ' + S_FDIAMOND + ' WORK ITEMS');
    AddLine(BG_PANEL + FG_BORDER + ' ' + Rep(S_H, ColR - 2));
    for I := 0 to RightWorkH - 3 do
    begin
      if I < WorkItems.Count then
      begin
        W := WorkItems[I];
        case W.Prio of
          wpHigh: begin PrioCol := FG_RED; PrioLabel := '[HIGH]'; end;
          wpMedium: begin PrioCol := FG_AMBER; PrioLabel := '[MED ]'; end;
        else begin PrioCol := FG_GREEN; PrioLabel := '[LOW ]'; end;
        end;
        Buf := BG_PANEL + ' ' + FG_TEXT + W.Text + '  ' + PrioCol + PrioLabel;
      end else Buf := BG_PANEL;
      AddLine(Buf);
    end;
    while L.Count < Div2 do AddLine(BG_PANEL);

    // Divider 2
    L.Add(BG_PANEL + DivCol2 + Rep(S_H, ColR) + RST);

    // THINKING
    if EffThink then
      AddLine(BG_PANEL + FG_PURPLE + BOLD + ' ' + S_FDIAMOND
            + ' THINKING  ' + FG_DGRAY + '[F3]')
    else
      AddLine(BG_PANEL + FG_DGRAY + ' ' + S_FDIAMOND
            + ' THINKING  [F3 - hidden]');
    AddLine(BG_PANEL + FG_BORDER + ' ' + Rep(S_H, ColR - 2));
    for I := 0 to ThinkH - 3 do
    begin
      if EffThink and (I < ThinkLines.Count) then
        Buf := BG_PANEL + ' ' + FG_BORDER + S_GT + ' ' + FG_GRAY + ThinkLines[I]
      else Buf := BG_PANEL;
      AddLine(Buf);
    end;

    while L.Count < ContentH do AddLine(BG_PANEL);
    Result := L.ToArray;
  finally L.Free; end;
end;

// ═══════════════════════════════════════════════════════════════════
//  FRAME
// ═══════════════════════════════════════════════════════════════════
function RenderFrame: string;
var
  SB: TStringBuilder;
  Left, Center, Right: TArray<string>;
  I, InputRow, CaretRow, CaretCol, AvailW, VS, LnIdx, TopRow: Integer;
  Line, SepTop, SepBot, TopBar, InpBar, StatBar: string;
  MouseLabel, Hints, ClockStr, SepCol1, SepCol2, SepCol3: string;
  AllLines: TArray<string>;
  LineText, PromptStr, PrefixStr: string;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append(HIDE_CUR); SB.Append(HOME);

    SepCol1 := FG_BORDER;
    if (HoverSep = 1) or (Dragging and (DragTarget = 1)) then SepCol1 := FG_CYAN;
    SepCol2 := FG_BORDER;
    if (HoverSep = 2) or (Dragging and (DragTarget = 2)) then SepCol2 := FG_CYAN;
    SepCol3 := FG_BORDER;

    SB.Append(FG_BORDER + S_ULC + Rep(S_H, ScreenW - 2) + S_URC + RST + #13#10);

    if ScreenW >= 150 then
      Hints := '   ' + FG_DGRAY + '[F1]' + FG_TEXT + ' Res'
             + '  ' + FG_DGRAY + '[F2]' + FG_TEXT + ' Right'
             + '  ' + FG_DGRAY + '[F3]' + FG_TEXT + ' Think'
             + '  ' + FG_DGRAY + '[F4]' + FG_TEXT + ' Send'
             + '  ' + FG_DGRAY + '[F5]' + FG_TEXT + ' Mouse'
             + '  ' + FG_DGRAY + '[F6]' + FG_TEXT + ' Reset'
             + '  ' + FG_DGRAY + '[Esc]' + FG_TEXT + ' Quit'
    else if ScreenW >= 110 then
      Hints := '  ' + FG_DGRAY + '[F1]R' + FG_TEXT + ' ' + FG_DGRAY + '[F2]Rt'
             + FG_TEXT + ' ' + FG_DGRAY + '[F3]T' + FG_TEXT + ' '
             + FG_DGRAY + '[F4]S' + FG_TEXT + ' ' + FG_DGRAY + '[F5]M'
             + FG_TEXT + ' ' + FG_DGRAY + '[Esc]Q'
    else Hints := '';

    Line := BG_BAR + ' ' + FG_CYAN + BOLD + S_DIAMOND + ' '
          + APP_NAME + ' ' + FG_DGRAY + APP_VERSION + RST + BG_BAR + Hints;
    ClockStr := ' ' + NowClock + '  ';
    TopBar := PadTo(Line, ScreenW - 2 - Length(ClockStr), BG_BAR)
            + FG_CYAN + ClockStr;
    SB.Append(FG_BORDER + S_V + RST + PadTo(TopBar, ScreenW - 2, BG_BAR) + RST
            + FG_BORDER + S_V + RST + #13#10);

    // Pane top separator
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
    else SepTop := S_BW + Rep(S_H, ScreenW - 2) + S_TW;
    SB.Append(FG_BORDER + SepTop + RST + #13#10);

    if EffLeft then Left := RenderLeft else Left := nil;
    Center := RenderCenter;
    if EffRight then Right := RenderRight else Right := nil;

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

    // Pane bottom separator (draggable for input height)
    if (HoverSep = 10) or (Dragging and (DragTarget = 10)) then SepCol1 := FG_CYAN
    else SepCol1 := FG_BORDER;
    if EffLeft and EffRight then
      SepBot := S_BW + Rep(S_H, ColL) + SepCol1 + S_TE + FG_BORDER
              + Rep(S_H, ColC) + SepCol1 + S_TE + FG_BORDER
              + Rep(S_H, ColR) + S_TW
    else SepBot := S_BW + Rep(S_H, ScreenW - 2) + S_TW;
    SB.Append(SepCol1 + SepBot + RST + #13#10);

    // Multi-line input
    AvailW := ScreenW - 5;
    if AvailW < 5 then AvailW := 5;
    AllLines := WrapMultiline(InputBuf, AvailW);
    if Length(AllLines) > InputH then VS := Length(AllLines) - InputH
    else VS := 0;

    TopRow := 5 + ContentH;
    for I := 0 to InputH - 1 do
    begin
      LnIdx := VS + I;
      if LnIdx < Length(AllLines) then LineText := AllLines[LnIdx]
      else LineText := '';
      if (LnIdx = 0) and (VS = 0) then PromptStr := ' > ' else PromptStr := '   ';

      if SimActive then
      begin
        if I = 0 then
          InpBar := BG_INPUT + ' ' + FG_AMBER + BOLD + '...' + RST + BG_INPUT
                  + FG_AMBER + ' Processing [' + PromptState + ']'
          else InpBar := BG_INPUT;
      end
      else
        InpBar := BG_INPUT + FG_CYAN + BOLD + PromptStr + RST + BG_INPUT
                + FG_TEXT + LineText;

      SB.Append(FG_BORDER + S_V + RST
              + PadTo(InpBar, ScreenW - 2, BG_INPUT) + RST
              + FG_BORDER + S_V + RST + #13#10);
    end;

    // Caret position (end of last wrapped line)
    if Length(AllLines) = 0 then
    begin CaretRow := TopRow; CaretCol := 5; end
    else
    begin
      CaretRow := TopRow + (Length(AllLines) - 1 - VS);
      CaretCol := 5 + Length(AllLines[High(AllLines)]);
      if CaretCol > ScreenW - 2 then CaretCol := ScreenW - 2;
    end;

    // Status separator
    SB.Append(FG_BORDER + S_BW + Rep(S_H, ScreenW - 2) + S_TW + RST + #13#10);

    // Status bar
    case StatusKind of
      0: Line := FG_GREEN; 1: Line := FG_AMBER; else Line := FG_RED;
    end;
    if MouseEnabled then MouseLabel := 'on' else MouseLabel := 'off';
    StatBar := BG_BAR + ' ' + Line + S_DOT + RST + BG_BAR + ' ' + FG_TEXT + 'Connected'
             + ' ' + FG_DGRAY + S_V + RST + BG_BAR + ' ' + FG_GRAY + 'Model:'
             + FG_TEXT + ' GPT-5' + ' ' + FG_DGRAY + S_V + RST + BG_BAR
             + ' ' + FG_GRAY + 'Prompt:' + Line + ' ' + PromptState
             + ' ' + FG_DGRAY + S_V + RST + BG_BAR + ' ' + FG_GRAY + 'Session:'
             + FG_TEXT + ' ' + IntToStr(ActiveSessionIdx + 1) + '/'
             + IntToStr(Sessions.Count) + ' ' + FG_DGRAY + S_V + RST + BG_BAR
             + ' ' + FG_GRAY + 'Mouse:' + FG_TEXT + ' ' + MouseLabel
             + ' ' + FG_DGRAY + S_V + RST + BG_BAR + ' ' + FG_GRAY + 'Perms:'
             + FG_CYAN + ' RWX';
    SB.Append(FG_BORDER + S_V + RST + PadTo(StatBar, ScreenW - 2, BG_BAR) + RST
            + FG_BORDER + S_V + RST + #13#10);

    SB.Append(FG_BORDER + S_LLC + Rep(S_H, ScreenW - 2) + S_LRC + RST);

    if not SimActive then
    begin
      SB.Append(ESC + '[' + IntToStr(CaretRow) + ';' + IntToStr(CaretCol) + 'H');
      SB.Append(SHOW_CUR);
    end else SB.Append(HIDE_CUR);

    Result := SB.ToString;
  finally SB.Free; end;
end;

// ═══════════════════════════════════════════════════════════════════
procedure AddUserMsg(const S: string);
var M: TChatMessage;
begin M.Role:=crUser; M.Text:=S; M.Time:=NowTime; Messages.Add(M); end;

procedure AddAssistantMsg(const S: string);
var M: TChatMessage;
begin M.Role:=crAssistant; M.Text:=S; M.Time:=NowTime; Messages.Add(M); end;

procedure SimBegin;
begin
  SimActive := True; SimStep := 0; SimTimer := GetTickCount;
  PromptState := 'PENDING'; StatusKind := 1; ChatScroll := 0;
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
    1: begin PromptState:='SUBMITTING'; ThinkLines.Clear;
         ThinkLines.Add('INPUT_SUBMITTED (provider_native_send)');
         ThinkLines.Add('Verifying input ownership...');
         ThinkLines.Add('Awaiting GENERATION_STARTED...'); end;
    2: begin PromptState:='GENERATING'; ThinkLines.Clear;
         ThinkLines.Add('GENERATION_STARTED - message identified');
         ThinkLines.Add('Baseline revision captured (r=0)');
         ThinkLines.Add('Streaming GENERATION_DELTA...');
         AddAssistantMsg('Analyzing GRISP architecture.'); end;
    3: begin ThinkLines.Clear;
         ThinkLines.Add('Deltas applied: rev 1..3 (APPEND)');
         ThinkLines.Add('Terminal stability check (1/2)...');
         ThinkLines.Add('Fencing: prompt_request_id OK'); end;
    4: begin ThinkLines.Clear;
         ThinkLines.Add('Terminal stability check (2/2)...');
         ThinkLines.Add('done=true streaming=false continuation=false');
         ThinkLines.Add('Submitting terminal candidate to arbiter'); end;
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
         PromptState := 'COMPLETED'; StatusKind := 0; SimActive := False; end;
  end;
end;

procedure SubmitPrompt;
begin
  if Trim(InputBuf) = '' then Exit;
  AddUserMsg(InputBuf); InputBuf := ''; SimBegin;
end;

// ═══════════════════════════════════════════════════════════════════
procedure HandleMouse(const Ev: TInputEvent);
var WheelLines, X, Y, RStart, REnd: Integer;
begin
  X := Ev.MouseX; Y := Ev.MouseY;
  RStart := ColL + ColC + 4;
  REnd := ColL + ColC + ColR + 3;

  // Determine hover
  HoverSep := 0;
  if EffLeft and (X = ColL + 2) then HoverSep := 1
  else if EffRight and (X = ColL + ColC + 3) then HoverSep := 2
  else if Y = 4 + ContentH then HoverSep := 10
  else if EffLeft and (Y = 4 + LeftResH) and (X >= 2) and (X <= ColL + 1) then
    HoverSep := 11
  else if EffRight and (Y = 4 + RightPlanH) and (X >= RStart) and (X <= REnd) then
    HoverSep := 12
  else if EffRight and (Y = 4 + RightPlanH + 1 + RightWorkH)
    and (X >= RStart) and (X <= REnd) then HoverSep := 13;

  if Ev.WheelDelta <> 0 then
  begin
    WheelLines := (Ev.WheelDelta div 120) * 3;
    ChatScroll := ChatScroll + WheelLines;
  end;

  if Dragging then
  begin
    if Ev.MouseButton = 1 then
    begin
      case DragTarget of
        1: begin
             ColLUser := X - 2;
             if ColLUser < MIN_COL then ColLUser := MIN_COL;
             if ColLUser > ScreenW - MIN_COL_C - ColR - 4 then
               ColLUser := ScreenW - MIN_COL_C - ColR - 4;
           end;
        2: begin
             ColRUser := ScreenW - X - 1;
             if ColRUser < MIN_COL then ColRUser := MIN_COL;
             if ColRUser > ScreenW - MIN_COL_C - ColL - 4 then
               ColRUser := ScreenW - MIN_COL_C - ColL - 4;
           end;
        10: begin
              InputHUser := ScreenH - 7 - (Y - 4);
              if InputHUser < 1 then InputHUser := 1;
              if InputHUser > MAX_INPUT_H then InputHUser := MAX_INPUT_H;
            end;
        11: begin
              LeftResHUser := Y - 4;
              if LeftResHUser < 3 then LeftResHUser := 3;
              if LeftResHUser > ContentH - 4 then LeftResHUser := ContentH - 4;
            end;
        12: begin
              RightPlanHUser := Y - 4;
              if RightPlanHUser < 3 then RightPlanHUser := 3;
              if RightPlanHUser > ContentH - 8 then RightPlanHUser := ContentH - 8;
            end;
        13: begin
              RightWorkHUser := Y - (4 + RightPlanH + 1);
              if RightWorkHUser < 3 then RightWorkHUser := 3;
              if RightWorkHUser > ContentH - 8 then RightWorkHUser := ContentH - 8;
            end;
      end;
      RecomputeLayout;
    end
    else begin Dragging := False; DragTarget := 0; end;
    Exit;
  end;

  if Ev.MouseButton = 1 then
  begin
    if (HoverSep = 1) or (HoverSep = 2) or (HoverSep >= 10) then
    begin Dragging := True; DragTarget := HoverSep; end
    else if (Y >= 4) and (Y <= ScreenH - 2) then ChatScroll := 0;
  end;
end;

procedure HandleEv(const Ev: TInputEvent);
begin
  case Ev.Kind of
    ikChar:
      if Ev.Ch = #13 then begin
        if SimActive then SimTick else SubmitPrompt;
      end
      else if Ev.Ch = #8 then begin
        if Length(InputBuf) > 0 then Delete(InputBuf, Length(InputBuf), 1);
      end
      else if Ord(Ev.Ch) >= 32 then InputBuf := InputBuf + Ev.Ch;

    ikSpecial:
      case Ev.VK of
        VK_ESCAPE: QuitFlag := True;
        VK_F1: begin WantLeft := not WantLeft; RecomputeLayout; end;
        VK_F2: begin WantRight := not WantRight; RecomputeLayout; end;
        VK_F3: WantThink := not WantThink;
        VK_F4: if SimActive then SimTick else SubmitPrompt;
        VK_F5: begin MouseEnabled := not MouseEnabled; UpdateInputMode; end;
        VK_F6: begin
                 ColLUser := 0; ColRUser := 0; InputHUser := 0;
                 LeftResHUser := 0; RightPlanHUser := 0; RightWorkHUser := 0;
                 RecomputeLayout;
               end;
        VK_UP: if ActiveSessionIdx > 0 then begin
                 Dec(ActiveSessionIdx);
                 CurrentSession := Sessions[ActiveSessionIdx].Name; end;
        VK_DOWN: if ActiveSessionIdx < Sessions.Count - 1 then begin
                   Inc(ActiveSessionIdx);
                   CurrentSession := Sessions[ActiveSessionIdx].Name; end;
        VK_PRIOR: ChatScroll := ChatScroll + 5;
        VK_NEXT: ChatScroll := ChatScroll - 5;
        VK_HOME: ChatScroll := ChatMaxScroll;
        VK_END: ChatScroll := 0;
      end;

    ikMouse: if MouseEnabled then HandleMouse(Ev);
  end;
end;

// ═══════════════════════════════════════════════════════════════════
var
  Ev: TInputEvent; NewW, NewH: Integer;
begin
  ConsoleInit; AppInit;
  try
    WriteOut(ALT_ON); WriteOut(RST + CLRSCR);
    while not QuitFlag do
    begin
      ReadTermSize(NewW, NewH);
      if (NewW <> ScreenW) or (NewH <> ScreenH) then
      begin RecomputeLayout; WriteOut(RST + CLRSCR); end;
      WriteOut(RenderFrame);
      repeat
        Ev := ReadEv;
        if Ev.Kind <> ikNone then HandleEv(Ev);
      until Ev.Kind = ikNone;
      if SimActive and ((GetTickCount - SimTimer) > SIM_INTERVAL_MS) then
      begin SimTimer := GetTickCount; SimTick; end;
      Sleep(25);
    end;
  finally
    MouseEnabled := False; UpdateInputMode;
    WriteOut(RST + SHOW_CUR + ALT_OFF); AppShutdown;
  end;
end.
