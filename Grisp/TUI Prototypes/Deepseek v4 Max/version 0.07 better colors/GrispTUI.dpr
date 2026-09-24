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
  APP_VERSION = 'v0.08';

  ESC  = #27;
  RST  = ESC + '[0m';
  BOLD = ESC + '[1m';

  // ══════════════════════════════════════════════════════════════
  //  DEEP SPACE palette — match met referentie-afbeelding
  //  High contrast, vivid cyaan, bijna-zwarte achtergrond
  //  Alle namen identiek aan v0.05, alleen waarden veranderd.
  // ══════════════════════════════════════════════════════════════

  // ── Primary accents (was: goud + cyaan → nu ALLES cyaan) ──
  FG_CYAN   = ESC + '[38;2;34;211;238m';    // #22D3EE VIVID cyaan
  FG_GOLD   = ESC + '[38;2;34;211;238m';    // #22D3EE — zelfde cyaan (was goud)
  FG_PURPLE = ESC + '[38;2;59;130;246m';    // #3B82F6 helder blauw

  // ── Structural ──
  FG_BORDER = ESC + '[38;2;51;65;85m';      // #334155 subtiele rand
  FG_USER   = ESC + '[38;2;147;197;253m';   // #93C5FD licht blauw
  FG_TEXT   = ESC + '[38;2;255;255;255m';   // #FFFFFF puur wit
  FG_GRAY   = ESC + '[38;2;148;163;184m';   // #94A3B8 slate-400
  FG_DGRAY  = ESC + '[38;2;100;116;139m';   // #64748B slate-500
  FG_GREEN  = ESC + '[38;2;34;197;94m';     // #22C55E success
  FG_AMBER  = ESC + '[38;2;245;158;11m';    // #F59E0B running
  FG_SLATE  = ESC + '[38;2;56;189;248m';    // #38BDF8 accentbalk

  // ── Backgrounds (diep, bijna zwart) ──
  BG_MAIN   = ESC + '[48;2;10;14;26m';      // #0A0E1A hoofdcanvas
  BG_PANEL  = ESC + '[48;2;13;21;36m';      // #0D1524 paneel
  BG_BAR    = ESC + '[48;2;8;12;22m';       // #080C16 top/status balk
  BG_INPUT  = ESC + '[48;2;13;21;36m';      // #0D1524 inputveld
  BG_USER   = ESC + '[48;2;30;58;138m';     // #1E3A8A user bubbel
  BG_AI     = ESC + '[48;2;22;36;60m';      // #16243C AI bubbel

  // ── Control ──
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
//  Console init
// ═══════════════════════════════════════════════════════════════════
procedure ConsoleInit;
var
  Mode: DWORD;
  Info: TConsoleScreenBufferInfo;
begin
  hOut := GetStdHandle(STD_OUTPUT_HANDLE);
  hIn  := GetStdHandle(STD_INPUT_HANDLE);

  GetConsoleMode(hOut, Mode);
  SetConsoleMode(hOut, Mode or ENABLE_VIRTUAL_TERMINAL_PROCESSING);
  SetConsoleOutputCP(CP_UTF8);
  SetConsoleTitle(PChar(APP_NAME + ' ' + APP_VERSION + ' — Terminal UI'));

  if GetConsoleScreenBufferInfo(hOut, Info) then
  begin
    ScreenW := Info.srWindow.Right - Info.srWindow.Left + 1;
    ScreenH := Info.srWindow.Bottom - Info.srWindow.Top + 1;
  end
  else
  begin
    ScreenW := 120;
    ScreenH := 30;
  end;
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
begin
  WriteConsoleW(hOut, PWideChar(S), Length(S), N, nil);
end;

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
      else
      begin
        Lines.Add(Cur);
        Cur := Words[I];
      end;
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
  L: TList<string>; I, Indent, NameW: Integer;
  Buf, PermCol, NameField: string;
  T: TTreeItem; S: TSession;

  procedure AddLine(const S: string);
  begin L.Add(PadTo(S, LEFT_W, BG_PANEL) + RST); end;

begin
  L := TList<string>.Create;
  try
    AddLine(BG_PANEL + FG_GOLD + BOLD + ' ◢ RESOURCES');
    AddLine(BG_PANEL + FG_BORDER + ' ' + StringOfChar('─', LEFT_W - 2));

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
        else if T.Perm = 'RW' then PermCol := FG_AMBER
        else PermCol := FG_GRAY;
        NameField := T.Name;
        if Length(NameField) > NameW then
          NameField := Copy(NameField, 1, NameW);
        NameField := NameField + StringOfChar(' ', NameW - Length(NameField));
        Buf := BG_PANEL + StringOfChar(' ', Indent) + FG_TEXT + '▸ '
             + NameField + ' ' + PermCol + T.Perm;
      end;
      AddLine(Buf);
    end;

    AddLine(BG_PANEL);

    AddLine(BG_PANEL + FG_GOLD + BOLD + ' ◢ SESSIONS');
    AddLine(BG_PANEL + FG_BORDER + ' ' + StringOfChar('─', LEFT_W - 2));

    for I := 0 to Sessions.Count - 1 do
    begin
      S := Sessions[I];
      if I = ActiveSessionIdx then
        Buf := BG_PANEL + FG_CYAN + BOLD + ' ▸ ' + S.Name
      else
        Buf := BG_PANEL + FG_TEXT + ' ▸ ' + S.Name;
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
  I, J: Integer;
  M: TChatMessage; P: TPlanItem;
  Wrapped: TArray<string>;
  Buf, SenderCol, Prefix: string;

  procedure AddLine(const S: string);
  begin L.Add(PadTo(S, CenterW, BG_MAIN) + RST); end;

  procedure AddPad;
  begin L.Add(PadTo(BG_MAIN, CenterW, BG_MAIN) + RST); end;

begin
  L := TList<string>.Create;
  try
    AddLine(BG_MAIN + ' ' + FG_CYAN + BOLD + '◆ CHAT'
          + RST + BG_MAIN + FG_GRAY + ' · '
          + FG_TEXT + CurrentSession);
    AddLine(BG_MAIN + ' ' + FG_BORDER + StringOfChar('─', CenterW - 2));

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
        Prefix    := ' ◈ GRISP Assistant';
      end;

      Buf := BG_MAIN + SenderCol + Prefix;
      Buf := PadTo(Buf, CenterW - 8, BG_MAIN)
           + FG_GRAY + M.Time + '  ';
      AddLine(Buf);

      Wrapped := WrapText(M.Text, CenterW - 8);
      for J := 0 to High(Wrapped) do
      begin
        if M.Role = crUser then
          Buf := BG_MAIN + '  ' + BG_USER + FG_TEXT
               + '  ' + Wrapped[J] + '  '
        else
          Buf := BG_MAIN + '  ' + BG_AI + FG_SLATE + '▌'
               + BG_AI + FG_TEXT + ' ' + Wrapped[J] + '  ';
        AddLine(Buf);
      end;

      AddPad;
    end;

    if ShowPlanPanel and (PlanItems.Count > 0) then
    begin
      AddLine(BG_MAIN + ' ' + FG_BORDER + StringOfChar('─', CenterW - 2));
      AddLine(BG_MAIN + ' ' + FG_GOLD + BOLD + '◆ PLAN'
            + RST + BG_MAIN + FG_DGRAY + '   [F4 to hide]');
      for I := 0 to PlanItems.Count - 1 do
      begin
        P := PlanItems[I];
        if P.Status = 'done' then
          Buf := BG_MAIN + '   ' + FG_GREEN + P.Icon
               + '  ' + FG_GRAY + P.Text
        else if P.Status = 'running' then
          Buf := BG_MAIN + '   ' + FG_AMBER + P.Icon
               + '  ' + FG_TEXT + P.Text
        else
          Buf := BG_MAIN + '   ' + FG_DGRAY + P.Icon
               + '  ' + FG_GRAY + P.Text;
        Buf := Buf + '  ' + FG_DGRAY + '[' + P.Status + ']';
        AddLine(Buf);
      end;
      AddPad;
    end;

    if ShowThinkPanel and (ThinkLines.Count > 0) then
    begin
      AddLine(BG_MAIN + ' ' + FG_BORDER + StringOfChar('─', CenterW - 2));
      AddLine(BG_MAIN + ' ' + FG_PURPLE + BOLD + '◆ THINK'
            + RST + BG_MAIN + FG_DGRAY + '   [F3 to hide]');
      for I := 0 to ThinkLines.Count - 1 do
        AddLine(BG_MAIN + '   ' + FG_BORDER + '› '
              + FG_GRAY + ThinkLines[I]);
    end;

    if L.Count > Height then
      while L.Count > Height do L.Delete(2)
    else
      while L.Count < Height do
        L.Insert(2, PadTo(BG_MAIN, CenterW, BG_MAIN) + RST);

    Result := L.ToArray;
  finally L.Free; end;
end;

// ═══════════════════════════════════════════════════════════════════
//  Render: complete frame
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

    SB.Append(FG_BORDER + '┌' + StringOfChar('─', ScreenW - 2)
            + '┐' + RST + #13#10);

    Line := BG_BAR + ' ' + FG_GOLD + BOLD + '◈ ' + APP_NAME
          + ' ' + FG_DGRAY + APP_VERSION
          + RST + BG_BAR
          + '   ' + FG_GRAY + '[F2]' + FG_TEXT + ' Resources'
          + '  ' + FG_GRAY + '[F3]' + FG_TEXT + ' Think'
          + '  ' + FG_GRAY + '[F4]' + FG_TEXT + ' Plan'
          + '  ' + FG_GRAY + '[Esc]' + FG_TEXT + ' Quit';
    Line := PadTo(Line, ScreenW - 12, BG_BAR)
          + FG_CYAN + NowClock + '  ';
    SB.Append(FG_BORDER + '│' + RST
            + PadTo(Line, ScreenW - 2, BG_BAR) + RST
            + FG_BORDER + '│' + RST + #13#10);

    if ShowLeftPanel then
      SB.Append(FG_BORDER + '├' + StringOfChar('─', LEFT_W)
              + '┬' + StringOfChar('─', CenterW) + '┤' + RST + #13#10)
    else
      SB.Append(FG_BORDER + '├' + StringOfChar('─', ScreenW - 2)
              + '┤' + RST + #13#10);

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
      SB.Append(FG_BORDER + '│' + RST);
      if ShowLeftPanel then
      begin
        if I < Length(Left) then SB.Append(Left[I])
        else SB.Append(PadTo('', LEFT_W, BG_PANEL) + RST);
        SB.Append(FG_BORDER + '│' + RST);
      end;
      if I < Length(Center) then SB.Append(Center[I])
      else SB.Append(PadTo('', CenterW, BG_MAIN) + RST);
      SB.Append(FG_BORDER + '│' + RST + #13#10);
    end;

    if ShowLeftPanel then
      SB.Append(FG_BORDER + '├' + StringOfChar('─', LEFT_W)
              + '┴' + StringOfChar('─', CenterW) + '┤' + RST + #13#10)
    else
      SB.Append(FG_BORDER + '├' + StringOfChar('─', ScreenW - 2)
              + '┤' + RST + #13#10);

    InputRow := ScreenH - 3;
    Line := BG_INPUT + ' ' + FG_GOLD + BOLD + '>' + RST + BG_INPUT
          + FG_TEXT + ' ' + InputBuf;
    Line := PadTo(Line, ScreenW - 2 - 8, BG_INPUT)
          + FG_DGRAY + '[Enter]' + RST + BG_INPUT + ' ';
    SB.Append(FG_BORDER + '│' + RST
            + PadTo(Line, ScreenW - 2, BG_INPUT) + RST
            + FG_BORDER + '│' + RST + #13#10);

    SB.Append(FG_BORDER + '├' + StringOfChar('─', ScreenW - 2)
            + '┤' + RST + #13#10);

    Line := BG_BAR + ' ' + FG_GREEN + '● Connected' + RST + BG_BAR
          + ' ' + FG_DGRAY + '│' + RST + BG_BAR
          + ' ' + FG_GRAY + 'Model:' + FG_TEXT + ' GPT-5'
          + ' ' + FG_DGRAY + '│' + RST + BG_BAR
          + ' ' + FG_GRAY + 'Project:' + FG_TEXT + ' GRISP'
          + ' ' + FG_DGRAY + '│' + RST + BG_BAR
          + ' ' + FG_GRAY + 'Permissions:' + FG_CYAN + ' RWX'
          + ' ' + FG_DGRAY + '│' + RST + BG_BAR
          + ' ' + FG_GRAY + 'Sessions:' + FG_TEXT + ' '
          + IntToStr(ActiveSessionIdx + 1) + '/'
          + IntToStr(Sessions.Count);
    SB.Append(FG_BORDER + '│' + RST
            + PadTo(Line, ScreenW - 2, BG_BAR) + RST
            + FG_BORDER + '│' + RST + #13#10);

    SB.Append(FG_BORDER + '└' + StringOfChar('─', ScreenW - 2)
            + '┘' + RST);

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
