program GrispTUI;

{$APPTYPE CONSOLE}

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Generics.Collections;

const
  ESC = #27;
  RST = ESC + '[0m';
  BOLD = ESC + '[1m';
  // Foreground
  FG_CYAN   = ESC + '[38;5;51m';
  FG_CYAN2  = ESC + '[38;5;38m';   // dim cyan voor randen
  FG_BLUE   = ESC + '[38;5;75m';
  FG_WHITE  = ESC + '[38;5;255m';
  FG_GRAY   = ESC + '[38;5;245m';
  FG_DGRAY  = ESC + '[38;5;240m';
  FG_GREEN  = ESC + '[38;5;46m';
  FG_ORANGE = ESC + '[38;5;214m';
  // Backgrounds
  BG_MAIN   = ESC + '[48;5;17m';   // diep marineblauw
  BG_PANEL  = ESC + '[48;5;18m';   // paneel
  BG_BAR    = ESC + '[48;5;19m';   // top/status balk
  BG_INPUT  = ESC + '[48;5;18m';
  BG_USER   = ESC + '[48;5;24m';
  BG_AI     = ESC + '[48;5;236m';
  // Control
  HIDE_CUR = ESC + '[?25l';
  SHOW_CUR = ESC + '[?25h';
  CLRSCR   = ESC + '[2J' + ESC + '[H';

  LEFT_W = 30;

type
  TChatRole = (crUser, crAssistant);
  TChatMessage = record
    Role: TChatRole;
    Sender, Text, Time: string;
  end;
  TPlanItem = record
    Icon, Text, Status: string;
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
  ScreenW, ScreenH, CenterW: Integer;
  Messages: TList<TChatMessage>;
  PlanItems: TList<TPlanItem>;
  ThinkLines: TList<string>;
  Sessions: TList<TSession>;
  TreeItems: TList<TTreeItem>;
  CurrentSession: string;
  InputBuf: string;
  ShowLeftPanel: Boolean = True;
  ShowThinkPanel: Boolean = True;
  ShowPlanPanel: Boolean = True;
  ActiveSessionIdx: Integer = 0;
  QuitFlag: Boolean = False;

// ═══════════════════════════════════════════════════════════════════
//  Console primitieven
// ═══════════════════════════════════════════════════════════════════
procedure ConsoleInit;
var Mode: DWORD; Info: TConsoleScreenBufferInfo;
begin
  hOut := GetStdHandle(STD_OUTPUT_HANDLE);
  hIn  := GetStdHandle(STD_INPUT_HANDLE);
  GetConsoleMode(hOut, Mode);
  SetConsoleMode(hOut, Mode or ENABLE_VIRTUAL_TERMINAL_PROCESSING);
  SetConsoleOutputCP(CP_UTF8);
  if GetConsoleScreenBufferInfo(hOut, Info) then
  begin
    ScreenW := Info.srWindow.Right - Info.srWindow.Left + 1;
    ScreenH := Info.srWindow.Bottom - Info.srWindow.Top + 1;
  end
  else begin ScreenW := 120; ScreenH := 30; end;
  if ScreenW < 80 then ScreenW := 80;
  if ScreenH < 20 then ScreenH := 20;
  CenterW := ScreenW - LEFT_W - 3;
  if CenterW < 40 then
  begin
    ShowLeftPanel := False;
    CenterW := ScreenW - 2;
  end;
end;

procedure WriteOut(const S: string);
var N: DWORD;
begin WriteConsoleW(hOut, PWideChar(S), Length(S), N, nil); end;

function ReadEv: TInputEvent;
var N: DWORD; Rec: INPUT_RECORD; Rd: DWORD;
begin
  Result.Kind := ikNone;
  GetNumberOfConsoleInputEvents(hIn, N);
  if N = 0 then Exit;
  if not ReadConsoleInputW(hIn, Rec, 1, Rd) then Exit;
  if Rec.EventType <> KEY_EVENT then Exit;
  if not Rec.Event.KeyEvent.bKeyDown then Exit;
  Result.VK := Rec.Event.KeyEvent.wVirtualKeyCode;
  Result.Ch := Rec.Event.KeyEvent.UnicodeChar;
  if Result.Ch = #0 then Result.Kind := ikSpecial
  else Result.Kind := ikChar;
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
      else begin Lines.Add(Cur); Cur := Words[I]; end;
    end;
    if Cur <> '' then Lines.Add(Cur);
    Result := Lines.ToArray;
  finally Lines.Free; end;
end;

function NowTime: string;  begin Result := FormatDateTime('hh:nn', Now); end;
function NowClock: string; begin Result := FormatDateTime('hh:nn:ss', Now); end;

// ═══════════════════════════════════════════════════════════════════
//  Demo data
// ═══════════════════════════════════════════════════════════════════
procedure AppInit;
var S: TSession; M: TChatMessage; P: TPlanItem; T: TTreeItem;
begin
  Messages   := TList<TChatMessage>.Create;
  PlanItems  := TList<TPlanItem>.Create;
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

  S.Name := 'Architecture Review'; S.Meta := '24 Sep · 14:30'; Sessions.Add(S);
  S.Name := 'MME Schema Draft';    S.Meta := '24 Sep · 12:10'; Sessions.Add(S);
  S.Name := 'Agent Graph';         S.Meta := '23 Sep · 18:22'; Sessions.Add(S);
  S.Name := 'VFS Refactor Notes';  S.Meta := '23 Sep · 09:15'; Sessions.Add(S);

  M.Role := crAssistant; M.Sender := 'GRISP Assistant';
  M.Text := 'Hello Alex, how can I help you with GRISP today?';
  M.Time := NowTime; Messages.Add(M);

  P.Icon := '☑'; P.Text := 'Analyze VFS Layer';  P.Status := 'done';    PlanItems.Add(P);
  P.Icon := '☑'; P.Text := 'Extract MME schema'; P.Status := 'done';    PlanItems.Add(P);
  P.Icon := '▶'; P.Text := 'Map Agent Network';  P.Status := 'running'; PlanItems.Add(P);
  P.Icon := '☐'; P.Text := 'Draft DNA report';   P.Status := 'queued';  PlanItems.Add(P);

  ThinkLines.Add('Parsing MME schema nodes...');
  ThinkLines.Add('12 resource types → mapping to VFS...');
  ThinkLines.Add('Cross-referencing Agent Network edges...');
end;

procedure AppShutdown;
begin
  Messages.Free; PlanItems.Free; ThinkLines.Free;
  Sessions.Free; TreeItems.Free;
end;

// ═══════════════════════════════════════════════════════════════════
//  Render: linkerpaneel
// ═══════════════════════════════════════════════════════════════════
function RenderLeft(Height: Integer): TArray<string>;
var
  L: TList<string>; I: Integer; Buf, PermCol, NameField: string;
  T: TTreeItem; S: TSession; Indent, NameW: Integer;

  procedure AddLine(const S: string);
  begin L.Add(PadTo(S, LEFT_W, BG_PANEL) + RST); end;

begin
  L := TList<string>.Create;
  try
    // RESOURCES header
    AddLine(BG_PANEL + FG_CYAN + BOLD + ' RESOURCES');
    AddLine(BG_PANEL + FG_CYAN2 + ' ' + StringOfChar('─', LEFT_W - 2));

    // Tree
    for I := 0 to TreeItems.Count - 1 do
    begin
      T := TreeItems[I];
      Indent := 1 + T.Depth * 2;
      NameW  := LEFT_W - Indent - 6;
      if T.Perm = '' then
        Buf := BG_PANEL + FG_CYAN + StringOfChar(' ', Indent)
             + '▸ ' + BOLD + T.Name
      else
      begin
        if T.Perm = 'RWX' then PermCol := FG_CYAN
        else if T.Perm = 'RW' then PermCol := FG_ORANGE
        else PermCol := FG_GRAY;
        NameField := T.Name;
        if Length(NameField) > NameW then
          NameField := Copy(NameField, 1, NameW);
        NameField := NameField + StringOfChar(' ', NameW - Length(NameField));
        Buf := BG_PANEL + StringOfChar(' ', Indent) + FG_WHITE + '▸ '
             + NameField + ' ' + PermCol + T.Perm;
      end;
      AddLine(Buf);
    end;

    AddLine(BG_PANEL);

    // SESSIONS header
    AddLine(BG_PANEL + FG_CYAN + BOLD + ' SESSIONS');
    AddLine(BG_PANEL + FG_CYAN2 + ' ' + StringOfChar('─', LEFT_W - 2));

    // Sessions
    for I := 0 to Sessions.Count - 1 do
    begin
      S := Sessions[I];
      if I = ActiveSessionIdx then
        Buf := BG_PANEL + FG_CYAN + BOLD + ' ▸ ' + S.Name
      else
        Buf := BG_PANEL + FG_WHITE + ' ▸ ' + S.Name;
      AddLine(Buf);
      AddLine(BG_PANEL + FG_GRAY + '   ' + S.Meta);
    end;

    while L.Count < Height do AddLine(BG_PANEL);
    Result := L.ToArray;
  finally L.Free; end;
end;

// ═══════════════════════════════════════════════════════════════════
//  Render: chatpaneel
// ═══════════════════════════════════════════════════════════════════
function RenderCenter(Height: Integer): TArray<string>;
var
  L: TList<string>;
  I, J, PrefixLen: Integer;
  M: TChatMessage; P: TPlanItem;
  Wrapped: TArray<string>;
  Buf, SenderCol, Prefix: string;

  procedure AddLine(const S: string);
  begin L.Add(PadTo(S, CenterW, BG_MAIN) + RST); end;

begin
  L := TList<string>.Create;
  try
    // Header
    AddLine(BG_MAIN + ' ' + FG_CYAN + BOLD + 'CHAT'
          + RST + BG_MAIN + FG_GRAY + ' · '
          + FG_WHITE + CurrentSession);
    AddLine(BG_MAIN + ' ' + FG_CYAN2 + StringOfChar('─', CenterW - 2));

    // Messages
    for I := 0 to Messages.Count - 1 do
    begin
      M := Messages[I];
      if M.Role = crUser then
      begin
        SenderCol := FG_BLUE + BOLD;
        Prefix    := ' You';
        PrefixLen := 4;
      end
      else
      begin
        SenderCol := FG_CYAN + BOLD;
        Prefix    := ' ◈ GRISP Assistant';
        PrefixLen := 20;
      end;

      // Sender line met tijd rechts uitgelijnd
      Buf := BG_MAIN + SenderCol + Prefix;
      Buf := PadTo(Buf, CenterW - 8, BG_MAIN)
           + FG_GRAY + M.Time + '  ';
      AddLine(Buf);

      // Bericht bubbel
      Wrapped := WrapText(M.Text, CenterW - 6);
      for J := 0 to High(Wrapped) do
      begin
        if M.Role = crUser then
          Buf := BG_MAIN + '  ' + BG_USER + FG_WHITE
               + ' ' + Wrapped[J]
        else
          Buf := BG_MAIN + '  ' + BG_AI + FG_WHITE
               + ' ' + Wrapped[J];
        AddLine(Buf);
      end;

      AddLine(BG_MAIN);
    end;

    // PLAN sectie
    if ShowPlanPanel and (PlanItems.Count > 0) then
    begin
      AddLine(BG_MAIN + ' ' + FG_CYAN2 + StringOfChar('─', CenterW - 2));
      AddLine(BG_MAIN + ' ' + FG_CYAN + BOLD + 'PLAN'
            + RST + BG_MAIN + FG_DGRAY + '   [F4 to hide]');
      for I := 0 to PlanItems.Count - 1 do
      begin
        P := PlanItems[I];
        if P.Status = 'done' then
          Buf := BG_MAIN + '   ' + FG_GREEN + P.Icon
               + '  ' + FG_GRAY + P.Text
        else if P.Status = 'running' then
          Buf := BG_MAIN + '   ' + FG_ORANGE + P.Icon
               + '  ' + FG_WHITE + P.Text
        else
          Buf := BG_MAIN + '   ' + FG_DGRAY + P.Icon
               + '  ' + FG_GRAY + P.Text;
        Buf := Buf + '  ' + FG_DGRAY + '[' + P.Status + ']';
        AddLine(Buf);
      end;
      AddLine(BG_MAIN);
    end;

    // THINK sectie
    if ShowThinkPanel and (ThinkLines.Count > 0) then
    begin
      AddLine(BG_MAIN + ' ' + FG_CYAN2 + StringOfChar('─', CenterW - 2));
      AddLine(BG_MAIN + ' ' + FG_CYAN + BOLD + 'THINK'
            + RST + BG_MAIN + FG_DGRAY + '   [F3 to hide]');
      for I := 0 to ThinkLines.Count - 1 do
        AddLine(BG_MAIN + '   ' + FG_CYAN2 + '› '
              + FG_GRAY + ThinkLines[I]);
    end;

    // Scroll: behoud header (2 regels) + laatste N content-regels
    if L.Count > Height then
      while L.Count > Height do
        L.Delete(2);

    while L.Count < Height do AddLine(BG_MAIN);
    Result := L.ToArray;
  finally L.Free; end;
end;

// ═══════════════════════════════════════════════════════════════════
//  Render: frame
// ═══════════════════════════════════════════════════════════════════
function RenderFrame: string;
var
  SB: TStringBuilder;
  Left, Center: TArray<string>;
  I, ContentH, InputRow: Integer;
  Line: string;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append(HIDE_CUR);
    SB.Append(ESC + '[1;1H');

    ContentH := ScreenH - 8;
    if ContentH < 5 then ContentH := 5;

    // ── Row 1: top border ──
    SB.Append(FG_CYAN2 + '┌' + StringOfChar('─', ScreenW - 2)
            + '┐' + RST);
    SB.Append(#13#10);

    // ── Row 2: topbar ──
    Line := BG_BAR + ' ' + FG_CYAN + BOLD + '◈ GRISP OS'
          + RST + BG_BAR
          + '   ' + FG_GRAY + '[F2]' + FG_WHITE + ' Resources'
          + '  ' + FG_GRAY + '[F3]' + FG_WHITE + ' Think'
          + '  ' + FG_GRAY + '[F4]' + FG_WHITE + ' Plan'
          + '  ' + FG_GRAY + '[Esc]' + FG_WHITE + ' Quit';
    Line := PadTo(Line, ScreenW - 12, BG_BAR)
          + FG_CYAN + NowClock + '  ';
    SB.Append(FG_CYAN2 + '│' + RST
            + PadTo(Line, ScreenW - 2, BG_BAR) + RST
            + FG_CYAN2 + '│' + RST);
    SB.Append(#13#10);

    // ── Row 3: separator ──
    if ShowLeftPanel then
      SB.Append(FG_CYAN2 + '├' + StringOfChar('─', LEFT_W)
              + '┬' + StringOfChar('─', CenterW) + '┤' + RST)
    else
      SB.Append(FG_CYAN2 + '├' + StringOfChar('─', ScreenW - 2)
              + '┤' + RST);
    SB.Append(#13#10);

    // ── Content ──
    if ShowLeftPanel then
    begin
      Left := RenderLeft(ContentH);
      Center := RenderCenter(ContentH);
    end
    else
    begin
      Left := nil;
      Center := RenderCenter(ContentH);
    end;

    for I := 0 to ContentH - 1 do
    begin
      SB.Append(FG_CYAN2 + '│' + RST);
      if ShowLeftPanel then
      begin
        if I < Length(Left) then SB.Append(Left[I])
        else SB.Append(PadTo('', LEFT_W, BG_PANEL) + RST);
        SB.Append(FG_CYAN2 + '│' + RST);
      end;
      if I < Length(Center) then SB.Append(Center[I])
      else SB.Append(PadTo('', CenterW, BG_MAIN) + RST);
      SB.Append(FG_CYAN2 + '│' + RST);
      SB.Append(#13#10);
    end;

    // ── Separator voor input ──
    if ShowLeftPanel then
      SB.Append(FG_CYAN2 + '├' + StringOfChar('─', LEFT_W)
              + '┴' + StringOfChar('─', CenterW) + '┤' + RST)
    else
      SB.Append(FG_CYAN2 + '├' + StringOfChar('─', ScreenW - 2)
              + '┤' + RST);
    SB.Append(#13#10);

    // ── Input row ──
    InputRow := ScreenH - 3;
    Line := BG_INPUT + ' ' + FG_CYAN + BOLD + '>' + RST + BG_INPUT
          + FG_WHITE + ' ' + InputBuf;
    Line := PadTo(Line, ScreenW - 2 - 8, BG_INPUT)
          + FG_DGRAY + '[Enter]' + RST + BG_INPUT + ' ';
    SB.Append(FG_CYAN2 + '│' + RST
            + PadTo(Line, ScreenW - 2, BG_INPUT) + RST
            + FG_CYAN2 + '│' + RST);
    SB.Append(#13#10);

    // ── Separator voor status ──
    SB.Append(FG_CYAN2 + '├' + StringOfChar('─', ScreenW - 2)
            + '┤' + RST);
    SB.Append(#13#10);

    // ── Status row ──
    Line := BG_BAR + ' ' + FG_GREEN + '● Connected' + RST + BG_BAR
          + ' ' + FG_DGRAY + '│' + RST + BG_BAR
          + ' ' + FG_GRAY + 'Model:' + FG_WHITE + ' GPT-5'
          + ' ' + FG_DGRAY + '│' + RST + BG_BAR
          + ' ' + FG_GRAY + 'Project:' + FG_WHITE + ' GRISP'
          + ' ' + FG_DGRAY + '│' + RST + BG_BAR
          + ' ' + FG_GRAY + 'Permissions:' + FG_CYAN + ' RWX'
          + ' ' + FG_DGRAY + '│' + RST + BG_BAR
          + ' ' + FG_GRAY + 'Sessions:' + FG_WHITE + ' '
          + IntToStr(ActiveSessionIdx + 1) + '/'
          + IntToStr(Sessions.Count);
    SB.Append(FG_CYAN2 + '│' + RST
            + PadTo(Line, ScreenW - 2, BG_BAR) + RST
            + FG_CYAN2 + '│' + RST);
    SB.Append(#13#10);

    // ── Bottom border ──
    SB.Append(FG_CYAN2 + '└' + StringOfChar('─', ScreenW - 2)
            + '┘' + RST);

    // ── Cursor naar inputpositie ──
    SB.Append(ESC + '[' + IntToStr(InputRow) + ';'
            + IntToStr(5 + Length(InputBuf)) + 'H');
    SB.Append(SHOW_CUR);

    Result := SB.ToString;
  finally SB.Free; end;
end;

// ═══════════════════════════════════════════════════════════════════
//  Input handling
// ═══════════════════════════════════════════════════════════════════
procedure SendMessage;
var M: TChatMessage; UserText: string;
begin
  if Trim(InputBuf) = '' then Exit;
  UserText := InputBuf;

  M.Role := crUser; M.Sender := 'You';
  M.Text := UserText; M.Time := NowTime;
  Messages.Add(M);
  InputBuf := '';

  M.Role := crAssistant; M.Sender := 'GRISP Assistant';
  M.Text := 'Processing: ' + UserText;
  M.Time := NowTime;
  Messages.Add(M);
end;

procedure HandleEv(const Ev: TInputEvent);
begin
  case Ev.Kind of
    ikChar:
      if Ev.Ch = #13 then SendMessage
      else if Ev.Ch = #8 then
      begin
        if Length(InputBuf) > 0 then
          Delete(InputBuf, Length(InputBuf), 1);
      end
      else if Ev.Ch >= ' ' then
        InputBuf := InputBuf + Ev.Ch;

    ikSpecial:
      case Ev.VK of
        VK_ESCAPE: QuitFlag := True;
        VK_F2: ShowLeftPanel := not ShowLeftPanel;
        VK_F3: ShowThinkPanel := not ShowThinkPanel;
        VK_F4: ShowPlanPanel := not ShowPlanPanel;
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
//  Main
// ═══════════════════════════════════════════════════════════════════
var Ev: TInputEvent;
begin
  ConsoleInit;
  AppInit;
  try
    WriteOut(CLRSCR);
    while not QuitFlag do
    begin
      WriteOut(RenderFrame);
      repeat
        Ev := ReadEv;
        if Ev.Kind <> ikNone then HandleEv(Ev);
      until Ev.Kind = ikNone;
      Sleep(30);
    end;
  finally
    WriteOut(RST + SHOW_CUR + CLRSCR);
    AppShutdown;
  end;
end.
