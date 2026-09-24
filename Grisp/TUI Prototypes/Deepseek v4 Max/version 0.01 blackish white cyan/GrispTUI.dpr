program GrispTUI;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Generics.Collections;

// ═══════════════════════════════════════════════════════════════════
//  ANSI KLEUREN & CONSTANTEN
// ═══════════════════════════════════════════════════════════════════
const
  ESC  = #27;
  RST  = ESC + '[0m';
  BOLD = ESC + '[1m';

  FG_CYAN   = ESC + '[38;5;51m';
  FG_BLUE   = ESC + '[38;5;75m';
  FG_WHITE  = ESC + '[38;5;255m';
  FG_GRAY   = ESC + '[38;5;245m';
  FG_DGRAY  = ESC + '[38;5;240m';
  FG_GREEN  = ESC + '[38;5;46m';
  FG_ORANGE = ESC + '[38;5;214m';

  BG_MAIN   = ESC + '[48;5;233m';
  BG_PANEL  = ESC + '[48;5;235m';
  BG_USER   = ESC + '[48;5;25m';
  BG_AI     = ESC + '[48;5;236m';

  HIDE_CUR = ESC + '[?25l';
  SHOW_CUR = ESC + '[?25h';
  CLRSCR   = ESC + '[2J' + ESC + '[H';

  // Box-drawing
  TL = '┌'; TR = '┐'; BL = '└'; BR = '┘';
  HZ = '─'; VT = '│';
  ML = '├'; MR = '┤'; MT = '┬'; MB = '┴'; X  = '┼';

// ═══════════════════════════════════════════════════════════════════
//  TYPES
// ═══════════════════════════════════════════════════════════════════
type
  TChatRole = (crUser, crAssistant);

  TChatMessage = record
    Role: TChatRole;
    Sender: string;
    Text: string;
    Time: string;
  end;

  TPlanItem = record
    Icon: string;
    Text: string;
    Status: string;
  end;

  TSession = record
    Name: string;
    Meta: string;
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

// ═══════════════════════════════════════════════════════════════════
//  GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════
var
  hOut, hIn: THandle;
  ScreenW, ScreenH: Integer;

  // App state
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
//  CONSOLE PRIMITIEVEN
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

  if ScreenW < 60 then ScreenW := 60;
  if ScreenH < 20 then ScreenH := 20;
end;

procedure ConsoleWrite(const S: string);
var
  Written: DWORD;
begin
  WriteConsoleW(hOut, PWideChar(S), Length(S), Written, nil);
end;

function ConsoleReadEvent: TInputEvent;
var
  N: DWORD;
  Rec: INPUT_RECORD;
  Read: DWORD;
begin
  Result.Kind := ikNone;
  GetNumberOfConsoleInputEvents(hIn, N);
  if N = 0 then Exit;
  if not ReadConsoleInputW(hIn, Rec, 1, Read) then Exit;
  if Rec.EventType <> KEY_EVENT then Exit;
  if not Rec.Event.KeyEvent.bKeyDown then Exit;

  Result.VK := Rec.Event.KeyEvent.wVirtualKeyCode;
  Result.Ch := Rec.Event.KeyEvent.UnicodeChar;
  if Result.Ch = #0 then
    Result.Kind := ikSpecial
  else
    Result.Kind := ikChar;
end;

// ═══════════════════════════════════════════════════════════════════
//  HELPERS
// ═══════════════════════════════════════════════════════════════════
function VisibleLen(const S: string): Integer;
var
  I: Integer;
  InEsc: Boolean;
begin
  Result := 0;
  InEsc := False;
  for I := 1 to Length(S) do
  begin
    if InEsc then
    begin
      if CharInSet(S[I], ['a'..'z', 'A'..'Z']) then InEsc := False;
    end
    else if S[I] = #27 then InEsc := True
    else Inc(Result);
  end;
end;

function RepStr(const S: string; N: Integer): string;
begin
  if N <= 0 then Result := ''
  else Result := StringOfChar(S[1], N); // werkt alleen voor 1-char strings
end;

function PadTo(const S: string; Width: Integer): string;
var
  V: Integer;
begin
  Result := S;
  V := VisibleLen(S);
  if V < Width then Result := S + StringOfChar(' ', Width - V)
  else if V > Width then
  begin
    // truncate visible
    Result := '';
    var I := 0; var Vis := 0; var InEsc := False;
    while (I < Length(S)) and (Vis < Width) do
    begin
      Inc(I);
      if InEsc then
      begin
        Result := Result + S[I];
        if CharInSet(S[I], ['a'..'z', 'A'..'Z']) then InEsc := False;
      end
      else if S[I] = #27 then
      begin
        InEsc := True;
        Result := Result + S[I];
      end
      else
      begin
        Result := Result + S[I];
        Inc(Vis);
      end;
    end;
  end;
end;

function PosStr(Row, Col: Integer): string;
begin
  Result := ESC + '[' + IntToStr(Row) + ';' + IntToStr(Col) + 'H';
end;

function NowTime: string;
begin
  Result := FormatDateTime('hh:nn', Now);
end;

// ═══════════════════════════════════════════════════════════════════
//  APP INIT — DEMO DATA
// ═══════════════════════════════════════════════════════════════════
procedure AppInit;
var
  S: TSession;
  M: TChatMessage;
  P: TPlanItem;
  T: TTreeItem;
begin
  Messages   := TList<TChatMessage>.Create;
  PlanItems  := TList<TPlanItem>.Create;
  ThinkLines := TList<string>.Create;
  Sessions   := TList<TSession>.Create;
  TreeItems  := TList<TTreeItem>.Create;

  CurrentSession := 'Architecture Review';

  // Tree
  T.Name := 'Local';          T.Depth := 0; T.Perm := '';    TreeItems.Add(T);
  T.Name := 'Projects';       T.Depth := 1; T.Perm := 'RWX'; TreeItems.Add(T);
  T.Name := 'GRISP';          T.Depth := 2; T.Perm := 'RWX'; TreeItems.Add(T);
  T.Name := 'MME-Registry';   T.Depth := 2; T.Perm := 'RW';  TreeItems.Add(T);
  T.Name := 'Agent-Network';  T.Depth := 2; T.Perm := 'RW';  TreeItems.Add(T);
  T.Name := 'Data';           T.Depth := 1; T.Perm := 'RW';  TreeItems.Add(T);
  T.Name := 'Models';         T.Depth := 2; T.Perm := 'RW';  TreeItems.Add(T);
  T.Name := 'Downloads';      T.Depth := 2; T.Perm := 'R';   TreeItems.Add(T);
  T.Name := 'Cloud';          T.Depth := 1; T.Perm := 'R';   TreeItems.Add(T);

  // Sessions
  S.Name := 'Architecture Review'; S.Meta := '24 Sep · 14:30'; Sessions.Add(S);
  S.Name := 'MME Schema Draft';    S.Meta := '24 Sep · 12:10'; Sessions.Add(S);
  S.Name := 'Agent Graph';         S.Meta := '23 Sep · 18:22'; Sessions.Add(S);
  S.Name := 'VFS Refactor Notes';  S.Meta := '23 Sep · 09:15'; Sessions.Add(S);

  // Messages
  M.Role := crAssistant;
  M.Sender := 'GRISP Assistant';
  M.Text := 'Hello Alex, how can I help you with GRISP today?';
  M.Time := NowTime;
  Messages.Add(M);

  // Plan
  P.Icon := '☑'; P.Text := 'Analyze VFS Layer';  P.Status := 'done';    PlanItems.Add(P);
  P.Icon := '☑'; P.Text := 'Extract MME schema'; P.Status := 'done';    PlanItems.Add(P);
  P.Icon := '▶'; P.Text := 'Map Agent Network';  P.Status := 'running'; PlanItems.Add(P);
  P.Icon := '☐'; P.Text := 'Draft DNA report';   P.Status := 'queued';  PlanItems.Add(P);

  // Think
  ThinkLines.Add('Parsing MME schema nodes...');
  ThinkLines.Add('12 resource types → mapping to VFS...');
  ThinkLines.Add('Cross-referencing Agent Network edges...');
end;

procedure AppShutdown;
begin
  Messages.Free;
  PlanItems.Free;
  ThinkLines.Free;
  Sessions.Free;
  TreeItems.Free;
end;

// ═══════════════════════════════════════════════════════════════════
//  WORD-WRAP
// ═══════════════════════════════════════════════════════════════════
function WrapText(const Text: string; MaxW: Integer): TArray<string>;
var
  Lines: TList<string>;
  Words: TArray<string>;
  Cur: string;
  W, I: Integer;
begin
  Lines := TList<string>.Create;
  try
    Words := Text.Split([' ', #9]);
    Cur := '';
    for I := 0 to High(Words) do
    begin
      W := Length(Words[I]);
      if Cur = '' then
        Cur := Words[I]
      else if Length(Cur) + 1 + W <= MaxW then
        Cur := Cur + ' ' + Words[I]
      else
      begin
        Lines.Add(Cur);
        Cur := Words[I];
      end;
    end;
    if Cur <> '' then Lines.Add(Cur);
    Result := Lines.ToArray;
  finally
    Lines.Free;
  end;
end;

// ═══════════════════════════════════════════════════════════════════
//  RENDERING
// ═══════════════════════════════════════════════════════════════════

// Bouw het linkerpaneel (resources + sessions) — geeft lijst van regels
function RenderLeftPanel(Height: Integer): TArray<string>;
var
  L: TList<string>;
  I: Integer;
  Buf: string;
  Items: TTreeItem;
  Sess: TSession;
  PermCol: string;

  procedure Add(const S: string);
  begin L.Add(S); end;

begin
  L := TList<string>.Create;
  try
    // Header
    Add(BG_PANEL + FG_CYAN + BOLD + PadTo(' RESOURCES', 26) + RST);

    // Tree items
    for I := 0 to TreeItems.Count - 1 do
    begin
      Items := TreeItems[I];
      Buf := BG_PANEL + FG_WHITE;
      Buf := Buf + StringOfChar(' ', 1 + Items.Depth * 2);
      if Items.Perm = '' then
        Buf := Buf + '▸ ' + PadTo(FG_CYAN + Items.Name + FG_WHITE, 22 - Items.Depth * 2)
      else
      begin
        if Items.Perm = 'RWX' then PermCol := FG_CYAN
        else if Items.Perm = 'RW' then PermCol := FG_ORANGE
        else PermCol := FG_GRAY;
        Buf := Buf + '▸ ' + PadTo(FG_WHITE + Items.Name + FG_WHITE, 18 - Items.Depth * 2)
              + PermCol + PadTo(Items.Perm, 4);
      end;
      Add(Buf + RST);
    end;

    // Blank + Sessions header
    Add(BG_PANEL + PadTo('', 26) + RST);
    Add(BG_PANEL + FG_CYAN + BOLD + PadTo(' SESSIONS', 26) + RST);

    // Sessions
    for I := 0 to Sessions.Count - 1 do
    begin
      Sess := Sessions[I];
      Buf := BG_PANEL;
      if I = ActiveSessionIdx then
        Buf := Buf + FG_CYAN + BOLD
      else
        Buf := Buf + FG_WHITE;
      Buf := Buf + ' ' + PadTo('▸ ' + Sess.Name, 25);
      Add(Buf + RST);
      Buf := BG_PANEL + FG_GRAY + '   ' + Sess.Meta;
      Add(PadTo(Buf, 26) + RST);
    end;

    // Vul resterende ruimte
    while L.Count < Height do
      Add(BG_PANEL + PadTo('', 26) + RST);

    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

// Bouw het chatpaneel — geeft lijst van regels (inclusief kleur-codes)
function RenderChatPanel(Width, Height: Integer): TArray<string>;
var
  L: TList<string>;
  I, J: Integer;
  M: TChatMessage;
  P: TPlanItem;
  Wrapped: TArray<string>;
  Buf, Prefix, Bubble: string;
  SenderCol, Meta: string;

  procedure Add(const S: string);
  begin L.Add(S); end;

begin
  L := TList<string>.Create;
  try
    // Header
    Add(BG_MAIN + FG_CYAN + BOLD +
        PadTo(' CHAT · ' + CurrentSession, Width) + RST);

    // Berichten
    for I := 0 to Messages.Count - 1 do
    begin
      M := Messages[I];
      if M.Role = crUser then
      begin
        SenderCol := FG_BLUE + BOLD;
        Prefix := ' You  ';
      end
      else
      begin
        SenderCol := FG_CYAN + BOLD;
        Prefix := ' GRISP Assistant  ';
      end;

      Meta := '  ' + SenderCol + Prefix + FG_GRAY + M.Time;
      Add(BG_MAIN + PadTo(Meta, Width) + RST);

      Wrapped := WrapText(M.Text, Width - 6);
      for J := 0 to High(Wrapped) do
      begin
        if M.Role = crUser then
          Bubble := BG_MAIN + '    ' + BG_USER + FG_WHITE + ' ' + Wrapped[J]
        else
          Bubble := BG_MAIN + '    ' + BG_AI + FG_WHITE + ' ' + Wrapped[J];
        Add(PadTo(Bubble, Width) + RST);
      end;

      Add(BG_MAIN + PadTo('', Width) + RST);
    end;

    // Plan paneel
    if ShowPlanPanel and (PlanItems.Count > 0) then
    begin
      Add(BG_MAIN + '  ' + FG_CYAN + BOLD + 'PLAN' + RST + BG_MAIN + PadTo('', Width - 6) + RST);
      for I := 0 to PlanItems.Count - 1 do
      begin
        P := PlanItems[I];
        if P.Status = 'done' then
          Buf := BG_MAIN + '   ' + FG_GREEN + P.Icon + '  ' + FG_GRAY + P.Text
        else if P.Status = 'running' then
          Buf := BG_MAIN + '   ' + FG_ORANGE + P.Icon + '  ' + FG_WHITE + P.Text
        else
          Buf := BG_MAIN + '   ' + FG_DGRAY + P.Icon + '  ' + FG_GRAY + P.Text;
        Buf := Buf + '  ' + FG_DGRAY + '[' + P.Status + ']';
        Add(PadTo(Buf, Width) + RST);
      end;
      Add(BG_MAIN + PadTo('', Width) + RST);
    end;

    // Think paneel
    if ShowThinkPanel and (ThinkLines.Count > 0) then
    begin
      Add(BG_MAIN + '  ' + FG_CYAN + BOLD + 'THINK [F3 to hide]' + RST
          + BG_MAIN + PadTo('', Width - 20) + RST);
      for I := 0 to ThinkLines.Count - 1 do
      begin
        Buf := BG_MAIN + '   ' + FG_GRAY + '› ' + FG_DGRAY + ThinkLines[I];
        Add(PadTo(Buf, Width) + RST);
      end;
      Add(BG_MAIN + PadTo('', Width) + RST);
    end;

    // Vul
    while L.Count < Height do
      Add(BG_MAIN + PadTo('', Width) + RST);

    // Als er te veel is, toon alleen de laatste (Height) regels
    if L.Count > Height then
    begin
      // Verwijder van boven (behoud header)
      while L.Count > Height do
        L.Delete(1);
    end;

    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

// Volledige frame opbouwen als string
function RenderFrame: string;
var
  SB: TStringBuilder;
  Left, Center: TArray<string>;
  I: Integer;
  LeftW, CenterW, ContentH: Integer;
  Line, LeftLine, CenterLine: string;
  Sep: string;
  InputLine, StatusLine: string;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append(HIDE_CUR);
    SB.Append(ESC + '[1;1H');

    LeftW := 28;
    if not ShowLeftPanel then LeftW := 0;
    if LeftW > 0 then
      CenterW := ScreenW - LeftW - 1
    else
      CenterW := ScreenW;

    ContentH := ScreenH - 3;

    // ── TOP BAR ──
    Line := BG_PANEL + FG_CYAN + BOLD + ' ⬡ GRISP OS  ' + RST + BG_PANEL;
    Line := Line + ' ' + FG_GRAY + '[F2]' + FG_WHITE + ' Resources ';
    Line := Line + FG_GRAY + '[F3]' + FG_WHITE + ' Think ';
    Line := Line + FG_GRAY + '[F4]' + FG_WHITE + ' Plan ';
    Line := Line + FG_GRAY + '[Esc]' + FG_WHITE + ' Quit';
    Line := PadTo(Line, ScreenW - 10) + FG_CYAN + NowTime + ' ' + RST;
    SB.Append(PadTo(Line, ScreenW));
    SB.Append(#13#10);

    // ── CONTENT ──
    if ShowLeftPanel then
    begin
      Left := RenderLeftPanel(ContentH);
      Center := RenderChatPanel(CenterW, ContentH);
    end
    else
    begin
      Left := nil;
      Center := RenderChatPanel(CenterW, ContentH);
    end;

    for I := 0 to ContentH - 1 do
    begin
      Line := '';
      if ShowLeftPanel and (I < Length(Left)) then
        Line := PadTo(Left[I], LeftW);
      Line := Line + BG_MAIN + FG_DGRAY + VT + RST;
      if I < Length(Center) then
        Line := Line + Center[I]
      else
        Line := Line + BG_MAIN + PadTo('', CenterW) + RST;
      SB.Append(PadTo(Line, ScreenW));
      SB.Append(#13#10);
    end;

    // ── INPUT BAR ──
    InputLine := BG_PANEL + FG_CYAN + BOLD + ' > ' + RST + BG_PANEL
                + FG_WHITE + InputBuf;
    // Pad to full width
    InputLine := InputLine + StringOfChar(' ', 200); // ruimte voor cursor
    SB.Append(PadTo(InputLine, ScreenW));
    SB.Append(#13#10);

    // ── STATUS BAR ──
    StatusLine := BG_PANEL + FG_GREEN + ' ● Connected ' + RST + BG_PANEL
                + FG_GRAY + '│ Model: ' + FG_WHITE + 'GPT-5'
                + FG_GRAY + ' │ Project: ' + FG_WHITE + 'GRISP'
                + FG_GRAY + ' │ Permissions: ' + FG_CYAN + 'RWX active';
    SB.Append(PadTo(StatusLine, ScreenW));
    SB.Append(RST);
    SB.Append(SHOW_CUR);

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// ═══════════════════════════════════════════════════════════════════
//  INPUT HANDLING
// ═══════════════════════════════════════════════════════════════════
procedure AppSendMessage;
var
  M: TChatMessage;
begin
  if Trim(InputBuf) = '' then Exit;

  M.Role := crUser;
  M.Sender := 'You';
  M.Text := InputBuf;
  M.Time := NowTime;
  Messages.Add(M);

  InputBuf := '';

  // Simuleer AI-antwoord
  M.Role := crAssistant;
  M.Sender := 'GRISP Assistant';
  M.Text := 'Working on: "' + M.Text + '"...';
  // ^ BUG: M.Text is al overschreven. Fix hieronder.
end;

// Correcte versie
procedure AppSendMessageFixed;
var
  M: TChatMessage;
  UserText: string;
begin
  if Trim(InputBuf) = '' then Exit;
  UserText := InputBuf;

  M.Role := crUser;
  M.Sender := 'You';
  M.Text := UserText;
  M.Time := NowTime;
  Messages.Add(M);

  InputBuf := '';

  M.Role := crAssistant;
  M.Sender := 'GRISP Assistant';
  M.Text := 'Processing: ' + UserText;
  M.Time := NowTime;
  Messages.Add(M);
end;

procedure AppHandleEvent(const Ev: TInputEvent);
begin
  case Ev.Kind of
    ikChar:
      begin
        if Ev.Ch = #13 then
          AppSendMessageFixed
        else if Ev.Ch = #8 then
        begin
          if Length(InputBuf) > 0 then
            Delete(InputBuf, Length(InputBuf), 1);
        end
        else if Ev.Ch >= ' ' then
          InputBuf := InputBuf + Ev.Ch;
      end;

    ikSpecial:
      case Ev.VK of
        VK_ESCAPE: QuitFlag := True;
        VK_F2:     ShowLeftPanel := not ShowLeftPanel;
        VK_F3:     ShowThinkPanel := not ShowThinkPanel;
        VK_F4:     ShowPlanPanel := not ShowPlanPanel;
      end;
  end;
end;

// ═══════════════════════════════════════════════════════════════════
//  MAIN
// ═══════════════════════════════════════════════════════════════════
var
  Ev: TInputEvent;
begin
  ConsoleInit;
  AppInit;
  try
    ConsoleWrite(CLRSCR);
    while not QuitFlag do
    begin
      ConsoleWrite(RenderFrame);
      // Non-blocking input
      repeat
        Ev := ConsoleReadEvent;
        if Ev.Kind <> ikNone then AppHandleEvent(Ev);
      until Ev.Kind = ikNone;
      Sleep(30);
    end;
  finally
    ConsoleWrite(RST + SHOW_CUR + CLRSCR);
    AppShutdown;
  end;
end.
