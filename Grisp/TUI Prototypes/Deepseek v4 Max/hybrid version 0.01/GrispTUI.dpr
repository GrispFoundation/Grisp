program GrispTUI;

{$APPTYPE CONSOLE}
{$R *.res}

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Generics.Collections;

const
  APP_NAME    = 'GRISP OS';
  APP_VERSION = 'v0.09';

  // ── Unicode symbols as codepoints (source stays ASCII-safe) ──
  S_DIAMOND   = #$25C8;  // diamond with dot
  S_FDIAMOND  = #$25C6;  // filled diamond
  S_RTRI      = #$25B8;  // small right triangle
  S_PTRI      = #$25B6;  // play triangle
  S_CHECKED   = #$2611;  // checked box
  S_UNCHECKED = #$2610;  // empty box
  S_GT        = #$203A;  // single right angle quote
  S_BLOCK     = #$258C;  // left half block
  S_DOT       = #$25CF;  // black circle
  S_ULC       = #$250C;
  S_URC       = #$2510;
  S_LLC       = #$2514;
  S_LRC       = #$2518;
  S_H         = #$2500;
  S_V         = #$2502;
  S_TE        = #$252C;
  S_TW        = #$2524;
  S_BE        = #$2534;
  S_BW        = #$251C;

  ESC  = #27;
  RST  = ESC + '[0m';
  BOLD = ESC + '[1m';

  // ── Deep space palette ──
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
  BG_INPUT  = ESC + '[48;2;13;21;36m';
  BG_USER   = ESC + '[48;2;30;58;138m';
  BG_AI     = ESC + '[48;2;22;36;60m';

  HIDE_CUR = ESC + '[?25l';
  SHOW_CUR = ESC + '[?25h';
  ALT_ON   = ESC + '[?1049h';
  ALT_OFF  = ESC + '[?1049l';
  CLRSCR   = ESC + '[2J' + ESC + '[H';
  HOME     = ESC + '[H';

  LEFT_W  = 30;
  RIGHT_W = 42;
  SIM_INTERVAL_MS = 900;

type
  TChatRole = (crUser, crAssistant, crSystem);
  TChatMessage = record
    Role: TChatRole;
    Text, Time: string;
  end;

  TPlanStatus = (psDone, psRunning, psQueued);
  TPlanItem = record
    Text: string;
    Status: TPlanStatus;
  end;

  TWorkPrio = (wpHigh, wpMedium, wpLow);
  TWorkItem = record
    Text: string;
    Prio: TWorkPrio;
  end;

  TSession = record
    Name, Meta: string;
  end;

  TTreeItem = record
    Name: string;
    Depth: Integer;
    Perm: string;
  end;

  TInputKind = (ikNone, ikChar, ikSpecial);
  TInputEvent = record
    Kind: TInputKind;
    Ch: WideChar;
    VK: Word;
  end;

var
  hOut, hIn: THandle;
  ScreenW, ScreenH: Integer;
  CenterW: Integer;

  Messages: TList<TChatMessage>;
  PlanItems: TList<TPlanItem>;
  WorkItems: TList<TWorkItem>;
  ThinkLines: TList<string>;
  Sessions: TList<TSession>;
  TreeItems: TList<TTreeItem>;

  CurrentSession: string;
  ActiveSessionIdx: Integer = 0;

  InputBuf: string;
  ShowLeftPanel: Boolean = True;
  ShowRightPanel: Boolean = True;
  ShowThinkPanel: Boolean = True;
  QuitFlag: Boolean = False;

  SimActive: Boolean = False;
  SimStep: Integer = 0;
  SimTimer: Cardinal = 0;
  PromptState: string = 'READY';
  StatusKind: Integer = 0;

// ═══════════════════════════════════════════════════════════════════
//  Console init / output
// ═══════════════════════════════════════════════════════════════════
procedure ConsoleInit;
var
  Mode: DWORD;
  Info: TConsoleScreenBufferInfo;
begin
  hOut := GetStdHandle(STD_OUTPUT_HANDLE);
  hIn  := GetStdHandle(STD_INPUT_HANDLE);

  GetConsoleMode(hOut, Mode);
  // No wrap-at-EOL: prevents column-line-dance when content hits right edge
  SetConsoleMode(hOut,
    (Mode or ENABLE_VIRTUAL_TERMINAL_PROCESSING
          or ENABLE_PROCESSED_OUTPUT)
    and not ENABLE_WRAP_AT_EOL_OUTPUT);

  SetConsoleOutputCP(CP_UTF8);
  SetConsoleCP(CP_UTF8);
  SetConsoleTitle(PChar(APP_NAME + ' ' + APP_VERSION + ' - Terminal UI'));

  if GetConsoleScreenBufferInfo(hOut, Info) then
  begin
    ScreenW := Info.srWindow.Right - Info.srWindow.Left + 1;
    ScreenH := Info.srWindow.Bottom - Info.srWindow.Top + 1;
  end
  else
  begin
    ScreenW := 140; ScreenH := 40;
  end;
  if ScreenW < 80 then ScreenW := 80;
  if ScreenH < 24 then ScreenH := 24;

  if ScreenW < LEFT_W + RIGHT_W + 50 then ShowLeftPanel := False;
  CenterW := ScreenW - LEFT_W - RIGHT_W - 4;
  if CenterW < 40 then
  begin
    ShowLeftPanel := False;
    ShowRightPanel := False;
    CenterW := ScreenW - 4;
  end;
end;

procedure WriteOut(const S: string);
var N: DWORD;
begin
  if S = '' then Exit;
  WriteConsoleW(hOut, PWideChar(S), Length(S), N, nil);
end;

function ReadEv: TInputEvent;
var N: DWORD; Rec: INPUT_RECORD; Rd: DWORD;
begin
  Result.Kind := ikNone;
  while True do
  begin
    GetNumberOfConsoleInputEvents(hIn, N);
    if N = 0 then Exit;
    if not ReadConsoleInputW(hIn, Rec, 1, Rd) then Exit;
    if Rec.EventType <> KEY_EVENT then Continue;
    if not Rec.Event.KeyEvent.bKeyDown then Continue;
    Result.VK := Rec.Event.KeyEvent.wVirtualKeyCode;
    Result.Ch := Rec.Event.KeyEvent.UnicodeChar;
    if (Result.Ch = #0) and (Result.VK <> 0) then Result.Kind := ikSpecial
    else if Result.Ch <> #0 then Result.Kind := ikChar
    else Result.Kind := ikNone;
    Exit;
  end;
end;

// ═══════════════════════════════════════════════════════════════════
//  Helpers
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
      else
      begin
        Lines.Add(Cur);
        Cur := Words[I];
      end;
    end;
    if Cur <> '' then Lines.Add(Cur);
    if Lines.Count = 0 then Lines.Add('');
    Result := Lines.ToArray;
  finally Lines.Free; end;
end;

function NowTime: string;  begin Result := FormatDateTime('hh:nn', Now); end;
function NowClock: string; begin Result := FormatDateTime('hh:nn:ss', Now); end;

function Rep(const C: Char; N: Integer): string;
begin
  if N <= 0 then Result := '' else Result := StringOfChar(C, N);
end;

// ═══════════════════════════════════════════════════════════════════
//  Demo data
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
//  Left pane: Resources + Sessions
// ═══════════════════════════════════════════════════════════════════
function RenderLeft(Height: Integer): TArray<string>;
var
  L: TList<string>; I, Indent, NameW: Integer;
  Buf, PermCol, NameField: string;
  T: TTreeItem; S: TSession;

  procedure AddLine(const S: string);
  begin L.Add(PadTo(S, LEFT_W - 1, BG_PANEL) + RST); end;

begin
  L := TList<string>.Create;
  try
    AddLine(BG_PANEL + FG_CYAN + BOLD + ' '
          + S_FDIAMOND + ' RESOURCES');
    AddLine(BG_PANEL + FG_BORDER + ' '
          + Rep(S_H, LEFT_W - 3));

    for I := 0 to TreeItems.Count - 1 do
    begin
      T := TreeItems[I];
      Indent := 1 + T.Depth * 2;
      NameW  := LEFT_W - Indent - 8;
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

    while L.Count < Height div 2 do AddLine(BG_PANEL);

    AddLine(BG_PANEL + FG_CYAN + BOLD + ' '
          + S_FDIAMOND + ' SESSIONS');
    AddLine(BG_PANEL + FG_BORDER + ' '
          + Rep(S_H, LEFT_W - 3));

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
//  Center pane: Chat
// ═══════════════════════════════════════════════════════════════════
function RenderCenter(Height: Integer): TArray<string>;
var
  L: TList<string>;
  I, J: Integer;
  M: TChatMessage;
  Wrapped: TArray<string>;
  Buf, SenderCol, Prefix: string;

  procedure AddLine(const S: string);
  begin L.Add(PadTo(S, CenterW - 1, BG_MAIN) + RST); end;

begin
  L := TList<string>.Create;
  try
    AddLine(BG_MAIN + ' ' + FG_CYAN + BOLD + S_FDIAMOND + ' CHAT'
          + RST + BG_MAIN + FG_DGRAY + ' - '
          + FG_TEXT + CurrentSession);
    AddLine(BG_MAIN + ' ' + FG_BORDER + Rep(S_H, CenterW - 3));

    for I := 0 to Messages.Count - 1 do
    begin
      M := Messages[I];
      if M.Role = crUser then
      begin
        SenderCol := FG_USER + BOLD;
        Prefix    := ' You';
      end
      else
      begin
        SenderCol := FG_CYAN + BOLD;
        Prefix    := ' ' + S_DIAMOND + ' GRISP Assistant';
      end;

      Buf := BG_MAIN + SenderCol + Prefix;
      Buf := PadTo(Buf, CenterW - 10, BG_MAIN)
           + FG_DGRAY + M.Time + '  ';
      AddLine(Buf);

      Wrapped := WrapText(M.Text, CenterW - 8);
      for J := 0 to High(Wrapped) do
      begin
        if M.Role = crUser then
          Buf := BG_MAIN + '  ' + BG_USER + FG_TEXT
               + '  ' + Wrapped[J] + '  '
        else
          Buf := BG_MAIN + '  ' + BG_AI + FG_SLATE + S_BLOCK
               + BG_AI + FG_TEXT + ' ' + Wrapped[J] + '  ';
        AddLine(Buf);
      end;
    end;

    // Keep bottom-most messages visible
    if L.Count > Height then
      while L.Count > Height do L.Delete(2);

    while L.Count < Height do
      L.Add(PadTo(BG_MAIN, CenterW - 1, BG_MAIN) + RST);

    Result := L.ToArray;
  finally L.Free; end;
end;

// ═══════════════════════════════════════════════════════════════════
//  Right pane: Plan + Work Items + Thinking
// ═══════════════════════════════════════════════════════════════════
function RenderRight(Height: Integer): TArray<string>;
var
  L: TList<string>; I: Integer;
  PlanH, WorkH, ThinkH: Integer;
  Buf, Sym, SymCol, PrioCol, PrioLabel: string;
  P: TPlanItem; W: TWorkItem;

  procedure AddLine(const S: string);
  begin L.Add(PadTo(S, RIGHT_W - 1, BG_PANEL) + RST); end;

begin
  L := TList<string>.Create;
  try
    PlanH  := (Height - 6) div 3;
    WorkH  := (Height - 6) div 3;
    ThinkH := (Height - 6) - PlanH - WorkH;

    // ── CURRENT PLAN ──
    AddLine(BG_PANEL + FG_CYAN + BOLD + ' '
          + S_FDIAMOND + ' CURRENT PLAN');
    AddLine(BG_PANEL + FG_BORDER + ' ' + Rep(S_H, RIGHT_W - 3));
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
      end
      else Buf := BG_PANEL;
      AddLine(Buf);
    end;

    // ── WORK ITEMS ──
    AddLine(BG_PANEL + FG_CYAN + BOLD + ' '
          + S_FDIAMOND + ' WORK ITEMS');
    AddLine(BG_PANEL + FG_BORDER + ' ' + Rep(S_H, RIGHT_W - 3));
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
        Buf := BG_PANEL + ' ' + FG_TEXT + W.Text
             + '  ' + PrioCol + PrioLabel;
      end
      else Buf := BG_PANEL;
      AddLine(Buf);
    end;

    // ── THINKING ──
    if ShowThinkPanel then
      AddLine(BG_PANEL + FG_PURPLE + BOLD + ' ' + S_FDIAMOND
            + ' THINKING  ' + FG_DGRAY + '[F3]')
    else
      AddLine(BG_PANEL + FG_DGRAY + ' ' + S_FDIAMOND
            + ' THINKING  ' + FG_DGRAY + '[F3 - hidden]');
    AddLine(BG_PANEL + FG_BORDER + ' ' + Rep(S_H, RIGHT_W - 3));

    if ShowThinkPanel then
    begin
      // show only last ThinkH lines
      for I := 0 to ThinkH - 1 do
      begin
        if (I < ThinkLines.Count) and (ThinkLines.Count - I <= ThinkH) then
          Buf := BG_PANEL + ' ' + FG_BORDER + S_GT + ' '
               + FG_GRAY + ThinkLines[I]
        else
          Buf := BG_PANEL;
        AddLine(Buf);
      end;
    end
    else
    begin
      for I := 0 to ThinkH - 1 do AddLine(BG_PANEL);
    end;

    while L.Count < Height do AddLine(BG_PANEL);
    Result := L.ToArray;
  finally L.Free; end;
end;

// ═══════════════════════════════════════════════════════════════════
//  Frame assembly
// ═══════════════════════════════════════════════════════════════════
function RenderFrame: string;
var
  SB: TStringBuilder;
  Left, Center, Right: TArray<string>;
  I, ContentH, InputRow, InputCol: Integer;
  Line, SepTop, SepBot, TopBar, InpBar, StatBar: string;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append(HIDE_CUR);
    SB.Append(HOME);

    ContentH := ScreenH - 8;
    if ContentH < 5 then ContentH := 5;

    // ── Row 1: top border ──
    SB.Append(FG_BORDER + S_ULC + Rep(S_H, ScreenW - 2) + S_URC
            + RST + #13#10);

    // ── Row 2: title bar ──
    Line := BG_BAR + ' ' + FG_CYAN + BOLD + S_DIAMOND + ' '
          + APP_NAME + ' ' + FG_DGRAY + APP_VERSION
          + RST + BG_BAR
          + '   ' + FG_DGRAY + '[F1]' + FG_TEXT + ' Res'
          + '  ' + FG_DGRAY + '[F2]' + FG_TEXT + ' Right'
          + '  ' + FG_DGRAY + '[F3]' + FG_TEXT + ' Think'
          + '  ' + FG_DGRAY + '[F4]' + FG_TEXT + ' Send'
          + '  ' + FG_DGRAY + '[Esc]' + FG_TEXT + ' Quit';
    TopBar := PadTo(Line, ScreenW - 14, BG_BAR)
            + FG_CYAN + NowClock + '  ';
    SB.Append(FG_BORDER + S_V + RST
            + PadTo(TopBar, ScreenW - 2, BG_BAR) + RST
            + FG_BORDER + S_V + RST + #13#10);

    // ── Row 3: pane top separator ──
    if ShowLeftPanel and ShowRightPanel then
      SepTop := S_BW + Rep(S_H, LEFT_W) + S_TE
              + Rep(S_H, CenterW) + S_TE
              + Rep(S_H, RIGHT_W) + S_TW
    else if ShowRightPanel then
      SepTop := S_BW + Rep(S_H, ScreenW - RIGHT_W - 3) + S_TE
              + Rep(S_H, RIGHT_W) + S_TW
    else if ShowLeftPanel then
      SepTop := S_BW + Rep(S_H, LEFT_W) + S_TE
              + Rep(S_H, ScreenW - LEFT_W - 3) + S_TW
    else
      SepTop := S_BW + Rep(S_H, ScreenW - 2) + S_TW;
    SB.Append(FG_BORDER + SepTop + RST + #13#10);

    // ── Rows 4..ContentH+3: pane content ──
    if ShowLeftPanel then Left := RenderLeft(ContentH) else Left := nil;
    Center := RenderCenter(ContentH);
    if ShowRightPanel then Right := RenderRight(ContentH) else Right := nil;

    for I := 0 to ContentH - 1 do
    begin
      SB.Append(FG_BORDER + S_V + RST);
      if ShowLeftPanel then
      begin
        if I < Length(Left) then SB.Append(Left[I])
        else SB.Append(PadTo('', LEFT_W - 1, BG_PANEL) + RST);
        SB.Append(FG_BORDER + S_V + RST);
      end;
      if I < Length(Center) then SB.Append(Center[I])
      else SB.Append(PadTo('', CenterW - 1, BG_MAIN) + RST);
      if ShowRightPanel then
      begin
        SB.Append(FG_BORDER + S_V + RST);
        if I < Length(Right) then SB.Append(Right[I])
        else SB.Append(PadTo('', RIGHT_W - 1, BG_PANEL) + RST);
      end;
      SB.Append(FG_BORDER + S_V + RST + #13#10);
    end;

    // ── Bottom separator for panes ──
    if ShowLeftPanel and ShowRightPanel then
      SepBot := S_BW + Rep(S_H, LEFT_W) + S_BE
              + Rep(S_H, CenterW) + S_BE
              + Rep(S_H, RIGHT_W) + S_TW
    else if ShowRightPanel then
      SepBot := S_BW + Rep(S_H, ScreenW - RIGHT_W - 3) + S_BE
              + Rep(S_H, RIGHT_W) + S_TW
    else if ShowLeftPanel then
      SepBot := S_BW + Rep(S_H, LEFT_W) + S_BE
              + Rep(S_H, ScreenW - LEFT_W - 3) + S_TW
    else
      SepBot := S_BW + Rep(S_H, ScreenW - 2) + S_TW;
    SB.Append(FG_BORDER + SepBot + RST + #13#10);

    // ── Input row ──
    InputRow := ScreenH - 3;
    InputCol := 5 + Length(InputBuf);

    if SimActive then
      Line := BG_INPUT + ' ' + FG_AMBER + BOLD + '...' + RST + BG_INPUT
            + FG_AMBER + ' Processing (' + PromptState + ') - press [F4] to step'
    else
      Line := BG_INPUT + ' ' + FG_CYAN + BOLD + '>' + RST + BG_INPUT
            + FG_TEXT + ' ' + InputBuf;

    InpBar := PadTo(Line, ScreenW - 2, BG_INPUT);
    SB.Append(FG_BORDER + S_V + RST
            + PadTo(InpBar, ScreenW - 2, BG_INPUT) + RST
            + FG_BORDER + S_V + RST + #13#10);

    // ── Separator before status ──
    SB.Append(FG_BORDER + S_BW + Rep(S_H, ScreenW - 2) + S_TW
            + RST + #13#10);

    // ── Status bar ──
    case StatusKind of
      0: Line := FG_GREEN;
      1: Line := FG_AMBER;
    else Line := FG_RED;
    end;

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
             + ' ' + FG_GRAY + 'Perms:' + FG_CYAN + ' RWX';
    SB.Append(FG_BORDER + S_V + RST
            + PadTo(StatBar, ScreenW - 2, BG_BAR) + RST
            + FG_BORDER + S_V + RST + #13#10);

    // ── Bottom border ──
    SB.Append(FG_BORDER + S_LLC + Rep(S_H, ScreenW - 2) + S_LRC + RST);

    // ── Cursor position (skip if simulating) ──
    if not SimActive then
    begin
      SB.Append(ESC + '[' + IntToStr(InputRow) + ';'
              + IntToStr(InputCol) + 'H');
      SB.Append(SHOW_CUR);
    end
    else
      SB.Append(HIDE_CUR);

    Result := SB.ToString;
  finally SB.Free; end;
end;

// ═══════════════════════════════════════════════════════════════════
//  GARP simulation
// ═══════════════════════════════════════════════════════════════════
procedure AddUserMsg(const S: string);
var M: TChatMessage;
begin
  M.Role := crUser; M.Text := S; M.Time := NowTime;
  Messages.Add(M);
end;

procedure AddAssistantMsg(const S: string);
var M: TChatMessage;
begin
  M.Role := crAssistant; M.Text := S; M.Time := NowTime;
  Messages.Add(M);
end;

procedure SimBegin;
begin
  SimActive := True;
  SimStep := 0;
  SimTimer := GetTickCount;
  PromptState := 'PENDING';
  StatusKind := 1;
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
         PromptState := 'COMPLETED';
         StatusKind := 0;
         SimActive := False;
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
//  Input handling
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
        VK_F1: ShowLeftPanel := not ShowLeftPanel;
        VK_F2: ShowRightPanel := not ShowRightPanel;
        VK_F3: ShowThinkPanel := not ShowThinkPanel;
        VK_F4: if SimActive then SimTick else SubmitPrompt;
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
      end;
  end;
end;

// ═══════════════════════════════════════════════════════════════════
//  Main loop
// ═══════════════════════════════════════════════════════════════════
var
  Ev: TInputEvent;
begin
  ConsoleInit;
  AppInit;
  try
    WriteOut(ALT_ON);    // enter alternate screen buffer
    WriteOut(CLRSCR);
    while not QuitFlag do
    begin
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
    WriteOut(RST + SHOW_CUR + ALT_OFF);
    AppShutdown;
  end;
end.
