program GrispTUI;

{$APPTYPE CONSOLE}
{$R *.res}

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.StrUtils,
  System.Math,
  Winapi.Windows;

// ============================================================================
// ANSI Escape Codes
// ============================================================================
const
  ESC = #27;
  RST        = ESC + '[0m';
  BOLD       = ESC + '[1m';
  F_RED      = ESC + '[91m';
  F_GRN      = ESC + '[92m';
  F_YEL      = ESC + '[93m';
  F_BLU      = ESC + '[94m';
  F_MAG      = ESC + '[95m';
  F_CYN      = ESC + '[96m';
  F_WHT      = ESC + '[97m';
  F_GRAY     = ESC + '[90m';
  F_BCYN     = ESC + '[36m';
  F_BGRN     = ESC + '[32m';

  B_DBLU     = ESC + '[48;5;17m';
  B_DCYN     = ESC + '[48;5;23m';

  CLR        = ESC + '[2J' + ESC + '[H';
  HOME       = ESC + '[H';
  HIDE_CUR   = ESC + '[?25l';
  SHOW_CUR   = ESC + '[?25h';

// ============================================================================
// Helpers
// ============================================================================
function VisibleLen(const S: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  I := 1;
  while I <= Length(S) do
  begin
    if S[I] = #27 then
    begin
      Inc(I);
      while (I <= Length(S)) and not CharInSet(S[I], ['A'..'Z','a'..'z']) do
        Inc(I);
      Inc(I);
      Continue;
    end;
    Inc(Result);
    Inc(I);
  end;
end;

function Rep(C: Char; N: Integer): string;
begin
  if N <= 0 then Result := '' else Result := StringOfChar(C, N);
end;

function PadR(const S: string; N: Integer): string;
begin
  Result := S;
  while VisibleLen(Result) < N do Result := Result + ' ';
end;

function FitW(const S: string; W: Integer): string;
begin
  Result := S;
  while VisibleLen(Result) < W do Result := Result + ' ';
end;

// ============================================================================
// Types
// ============================================================================
type
  TMsgKind = (mkUser, mkAssistant, mkSystem);
  TChatMsg = record
    Kind: TMsgKind;
    Text: string;
    Time: string;
  end;

  TPlanStatus = (psDone, psRunning, psPending);
  TPlanItem = record
    Title: string;
    Status: TPlanStatus;
  end;

  TWorkPrio = (wpHigh, wpMedium, wpLow);
  TWorkItem = record
    Title: string;
    Prio: TWorkPrio;
  end;

  TActivePane = (apLeft, apCenter, apRight);

  TKeyEvent = record
    IsSpecial: Boolean;
    Ch: Char;
    VK: Word;
  end;

// ============================================================================
// Application
// ============================================================================
  TGrispApp = class
  private
    FWidth, FHeight: Integer;
    FChat: TList<TChatMsg>;
    FPlan: TList<TPlanItem>;
    FWork: TList<TWorkItem>;
    FSessions: TList<string>;
    FExplorer: TList<string>;
    FInputBuf: string;
    FShowLeft, FShowRight, FThinkingOpen: Boolean;
    FThinkingLines: TList<string>;
    FActivePane: TActivePane;
    FStatusMsg: string;
    FStatusKind: Integer;
    FQuit: Boolean;
    FSimActive: Boolean;
    FSimStep: Integer;
    FSimTimer: Cardinal;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Run;

    function  RenderScreen: string;
    procedure DrawHeader(Lines: TStrings);
    procedure DrawFooter(Lines: TStrings);
    procedure DrawLeftPane(Lines: TStrings; W, H: Integer);
    procedure DrawChatPane(Lines: TStrings; W, H: Integer);
    procedure DrawRightPane(Lines: TStrings; W, H: Integer);

    procedure HandleKeyEvent(const Ev: TKeyEvent);
    procedure HandleSpecialVK(VK: Word);
    procedure SubmitPrompt;
    procedure BeginSimulation;
    procedure TickSimulation;

    procedure AddUser(const S: string);
    procedure AddAssistant(const S: string);

    function  NowTime: string;
    function  WrapText(const S: string; W: Integer): TArray<string>;
  end;

// ============================================================================
// Console helpers
// ============================================================================
procedure EnableVT;
var
  H: THandle;
  Mode: DWORD;
begin
  H := GetStdHandle(STD_OUTPUT_HANDLE);
  if GetConsoleMode(H, Mode) then
    SetConsoleMode(H, Mode or ENABLE_VIRTUAL_TERMINAL_PROCESSING);
end;

procedure SetUTF8CP;
begin
  SetConsoleOutputCP(CP_UTF8);
  SetConsoleCP(CP_UTF8);
end;

procedure SetCursorVis(Visible: Boolean);
var
  H: THandle;
  CCI: TConsoleCursorInfo;
begin
  H := GetStdHandle(STD_OUTPUT_HANDLE);
  if GetConsoleCursorInfo(H, CCI) then
  begin
    CCI.bVisible := Visible;
    SetConsoleCursorInfo(H, CCI);
  end;
end;

function GetTermSize(out W, H: Integer): Boolean;
var
  Info: TConsoleScreenBufferInfo;
begin
  Result := GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), Info);
  if Result then
  begin
    W := Info.srWindow.Right - Info.srWindow.Left + 1;
    H := Info.srWindow.Bottom - Info.srWindow.Top + 1;
  end
  else
  begin
    W := 120; H := 40;
  end;
end;

function TryReadKey(out Ev: TKeyEvent): Boolean;
var
  H: THandle;
  Rec: TInputRecord;
  NumRead: DWORD;
begin
  Result := False;
  H := GetStdHandle(STD_INPUT_HANDLE);
  while True do
  begin
    if not PeekConsoleInput(H, Rec, 1, NumRead) then Exit;
    if NumRead = 0 then Exit;
    if not ReadConsoleInput(H, Rec, 1, NumRead) then Exit;
    if Rec.EventType <> KEY_EVENT then Continue;
    if not Rec.Event.KeyEvent.bKeyDown then Continue;
    Ev.VK := Rec.Event.KeyEvent.wVirtualKeyCode;
    Ev.Ch := Rec.Event.KeyEvent.UnicodeChar;   // <-- fixed
    Ev.IsSpecial := (Ev.VK <> 0) and (Ev.Ch = #0);
    Result := True;
    Exit;
  end;
end;

// ============================================================================
// TGrispApp
// ============================================================================
constructor TGrispApp.Create;
var P: TPlanItem; W: TWorkItem;
begin
  inherited;
  FChat          := TList<TChatMsg>.Create;
  FPlan          := TList<TPlanItem>.Create;
  FWork          := TList<TWorkItem>.Create;
  FSessions      := TList<string>.Create;
  FExplorer      := TList<string>.Create;
  FThinkingLines := TList<string>.Create;

  FShowLeft     := True;
  FShowRight    := True;
  FThinkingOpen := True;
  FActivePane   := apCenter;
  FStatusKind   := 0;
  FStatusMsg    := 'Connected | Permissions: RWX | Prompt: READY';

  FSessions.Add('> Architecture Review      Today 14:12');
  FSessions.Add('  Project Setup            Today 11:45');
  FSessions.Add('  Data model discussion    Today 11:20');
  FSessions.Add('  Bug investigation        21 Sep 16:20');
  FSessions.Add('  Feature planning         20 Sep 10:10');

  FExplorer.Add('> GRISP                    R W X');
  FExplorer.Add('  src                      R W X');
  FExplorer.Add('  tests                    R W X');
  FExplorer.Add('  docs                     R - -');
  FExplorer.Add('  MME-Registry             R W X');
  FExplorer.Add('  Agent-Network            R W X');
  FExplorer.Add('  Models                   R W -');
  FExplorer.Add('  Knowledge                R W -');
  FExplorer.Add('  System                   R W X');

  P.Title := 'Analyze VFS Layer';           P.Status := psDone;    FPlan.Add(P);
  P.Title := 'Extract MME schema';          P.Status := psDone;    FPlan.Add(P);
  P.Title := 'Map Agent Network';           P.Status := psRunning; FPlan.Add(P);
  P.Title := 'Draft DNA report';            P.Status := psPending; FPlan.Add(P);
  P.Title := 'Validate permissions matrix'; P.Status := psPending; FPlan.Add(P);

  W.Title := 'Implement GRISP runtime';  W.Prio := wpHigh;   FWork.Add(W);
  W.Title := 'Add graph visualization';  W.Prio := wpMedium; FWork.Add(W);
  W.Title := 'Write unit tests';         W.Prio := wpMedium; FWork.Add(W);
  W.Title := 'Update LSBP integration';  W.Prio := wpLow;    FWork.Add(W);

  FThinkingLines.Add('> Waiting for user input...');
  FThinkingLines.Add('> Parsing GRISP environment...');
  FThinkingLines.Add('> Ready to assist.');

  AddAssistant('Hello Alex, how can I help you with GRISP today?');
  AddAssistant('I can help with analysis, planning, or code generation. Just ask.');
end;

destructor TGrispApp.Destroy;
begin
  FChat.Free;
  FPlan.Free;
  FWork.Free;
  FSessions.Free;
  FExplorer.Free;
  FThinkingLines.Free;
  inherited;
end;

function TGrispApp.NowTime: string;
begin
  Result := FormatDateTime('hh:nn', Now);
end;

procedure TGrispApp.AddUser(const S: string);
var M: TChatMsg;
begin
  M.Kind := mkUser; M.Text := S; M.Time := NowTime;
  FChat.Add(M);
end;

procedure TGrispApp.AddAssistant(const S: string);
var M: TChatMsg;
begin
  M.Kind := mkAssistant; M.Text := S; M.Time := NowTime;
  FChat.Add(M);
end;

function TGrispApp.WrapText(const S: string; W: Integer): TArray<string>;
var
  Parts: TArray<string>;
  Cur, Word: string;
  I: Integer;
begin
  SetLength(Result, 0);
  if W <= 0 then Exit;
  Parts := S.Split([' '], TStringSplitOptions.ExcludeEmpty);
  Cur := '';
  for I := 0 to High(Parts) do
  begin
    Word := Parts[I];
    if Cur = '' then
    begin
      while Length(Word) > W do
      begin
        SetLength(Result, Length(Result)+1);
        Result[High(Result)] := Copy(Word, 1, W);
        Word := Copy(Word, W+1, MaxInt);
      end;
      Cur := Word;
    end
    else if Length(Cur) + 1 + Length(Word) <= W then
      Cur := Cur + ' ' + Word
    else
    begin
      SetLength(Result, Length(Result)+1);
      Result[High(Result)] := Cur;
      Cur := Word;
    end;
  end;
  if Cur <> '' then
  begin
    SetLength(Result, Length(Result)+1);
    Result[High(Result)] := Cur;
  end;
end;

// ============================================================================
// Panes
// ============================================================================
procedure TGrispApp.DrawHeader(Lines: TStrings);
var
  Line, Left, Right: string;
  Pad: Integer;
begin
  Left := B_DBLU + F_BCYN + BOLD + ' GRISP OS TUI ' + RST +
          B_DBLU + F_GRAY + '| Agent: ' + F_BGRN + 'Alex Ready' +
          F_GRAY + ' | Project: GRISP | Perms: ' + F_GRN + 'RWX' +
          F_GRAY + ' | Model: GPT-5 | Sessions: 1/4' + RST;
  Right := '';
  Pad := FWidth - VisibleLen(Left) - VisibleLen(Right);
  if Pad < 0 then Pad := 0;
  Line := Left + B_DBLU + Rep(' ', Pad) + RST;
  Lines.Add(Line);
  Lines.Add(F_GRAY + Rep('-', FWidth) + RST);
end;

procedure TGrispApp.DrawFooter(Lines: TStrings);
var
  Color: string;
begin
  Lines.Add(F_GRAY + Rep('-', FWidth) + RST);
  case FStatusKind of
    0: Color := F_BGRN;
    1: Color := F_YEL;
  else Color := F_RED;
  end;
  Lines.Add(FitW(' ' + Color + FStatusMsg + RST, FWidth));
  Lines.Add(FitW(F_GRAY + ' [Tab] Switch  [F1] Explorer  [F2] Plan  [F3] Thinking  [F4] Send  [Esc] Quit' + RST, FWidth));
end;

procedure TGrispApp.DrawLeftPane(Lines: TStrings; W, H: Integer);
var
  I: Integer;
  BC, S, Line: string;
  Half: Integer;
begin
  BC := F_GRAY;
  if FActivePane = apLeft then BC := F_BCYN;

  Lines.Add(BC + '+' + ' EXPLORER ' + F_GRAY + Rep('-', W - 11) + BC + '+' + RST);

  Half := (H - 2) div 2;
  for I := 0 to Half - 1 do
  begin
    if I < FExplorer.Count then
    begin
      S := FExplorer[I];
      if Copy(Trim(S), 1, 5) = 'GRISP' then
        Line := ' ' + F_BCYN + BOLD + S + RST
      else if Pos('R W X', S) > 0 then
        Line := ' ' + F_WHT + S + RST
      else
        Line := ' ' + F_GRAY + S + RST;
    end
    else Line := '';
    Lines.Add(BC + '|' + FitW(Line, W-2) + BC + '|' + RST);
  end;

  Lines.Add(BC + '+' + F_BCYN + BOLD + ' SESSIONS ' + F_GRAY + Rep('-', W - 11) + BC + '+' + RST);
  for I := 0 to (H - 2) - Half - 2 do
  begin
    if I < FSessions.Count then
    begin
      S := FSessions[I];
      if Copy(S, 1, 1) = '>' then
        Line := B_DCYN + F_WHT + ' ' + S + RST
      else
        Line := ' ' + F_GRAY + S + RST;
    end
    else Line := '';
    Lines.Add(BC + '|' + FitW(Line, W-2) + BC + '|' + RST);
  end;
  Lines.Add(BC + '+' + Rep('-', W-2) + '+' + RST);
end;

procedure TGrispApp.DrawChatPane(Lines: TStrings; W, H: Integer);
var
  I, J, VisibleRows, StartIdx, BodyW: Integer;
  BC, Title, Line, Prefix, TimeStr: string;
  Wrapped: TArray<string>;
  Rendered: TStringList;
begin
  BC := F_GRAY;
  if FActivePane = apCenter then BC := F_BCYN;

  Title := ' CHAT WORKSPACE ';
  Lines.Add(BC + '+' + Title + F_GRAY + Rep('-', W - Length(Title) - 2) + BC + '+' + RST);

  BodyW := W - 4;
  VisibleRows := H - 4;

  Rendered := TStringList.Create;
  try
    for I := 0 to FChat.Count - 1 do
    begin
      case FChat[I].Kind of
        mkUser:      Prefix := F_BCYN + BOLD + 'You: ' + RST + F_WHT;
        mkAssistant: Prefix := F_BGRN + BOLD + 'GRISP: ' + RST + F_WHT;
        mkSystem:    Prefix := F_YEL + '[sys] ' + RST + F_GRAY;
      end;
      TimeStr := F_GRAY + '[' + FChat[I].Time + ']' + RST;
      Wrapped := WrapText(FChat[I].Text, BodyW - 3);
      if Length(Wrapped) = 0 then
      begin
        SetLength(Wrapped, 1);
        Wrapped[0] := '';
      end;
      for J := 0 to High(Wrapped) do
        if J = 0 then
          Rendered.Add(Prefix + Wrapped[J] + RST + '  ' + TimeStr)
        else
          Rendered.Add('  ' + F_WHT + Wrapped[J] + RST);
      Rendered.Add('');
    end;

    StartIdx := Rendered.Count - VisibleRows;
    if StartIdx < 0 then StartIdx := 0;

    for I := 0 to VisibleRows - 1 do
    begin
      if (StartIdx + I) < Rendered.Count then
        Line := Rendered[StartIdx + I]
      else
        Line := '';
      Lines.Add(BC + '|' + FitW(Line, W-2) + BC + '|' + RST);
    end;
  finally
    Rendered.Free;
  end;

  Lines.Add(BC + '+' + Rep('-', W-2) + '+' + RST);
  if FSimActive then
    Line := F_YEL + ' Processing... press [F4] to advance simulation' + RST
  else
    Line := ' ' + F_BCYN + '> ' + RST + F_WHT + FInputBuf + '_' + RST;
  Lines.Add(BC + '|' + FitW(Line, W-2) + BC + '|' + RST);
end;

procedure TGrispApp.DrawRightPane(Lines: TStrings; W, H: Integer);
var
  I, Quart: Integer;
  BC, Title, Line, Sym, SymCol, PrioCol, PrioLabel: string;
begin
  BC := F_GRAY;
  if FActivePane = apRight then BC := F_BCYN;

  Title := ' CURRENT PLAN ';
  Lines.Add(BC + '+' + Title + F_GRAY + Rep('-', W - Length(Title) - 2) + BC + '+' + RST);

  Quart := (H - 4) div 3;

  for I := 0 to Quart - 1 do
  begin
    if I < FPlan.Count then
    begin
      case FPlan[I].Status of
        psDone:    begin Sym := '[v]'; SymCol := F_BGRN; end;
        psRunning: begin Sym := '[>]'; SymCol := F_YEL;  end;
      else         begin Sym := '[ ]'; SymCol := F_GRAY; end;
      end;
      Line := ' ' + SymCol + Sym + ' ' + F_WHT + FPlan[I].Title + RST;
    end
    else Line := '';
    Lines.Add(BC + '|' + FitW(Line, W-2) + BC + '|' + RST);
  end;

  Lines.Add(BC + '+' + F_BCYN + BOLD + ' WORK ITEMS ' + F_GRAY + Rep('-', W - 13) + BC + '+' + RST);
  for I := 0 to Quart - 1 do
  begin
    if I < FWork.Count then
    begin
      case FWork[I].Prio of
        wpHigh:   begin PrioCol := F_RED; PrioLabel := 'High';   end;
        wpMedium: begin PrioCol := F_YEL; PrioLabel := 'Medium'; end;
      else        begin PrioCol := F_GRN; PrioLabel := 'Low';    end;
      end;
      Line := ' ' + F_WHT + FWork[I].Title + RST + '  ' + PrioCol + PrioLabel + RST;
    end
    else Line := '';
    Lines.Add(BC + '|' + FitW(Line, W-2) + BC + '|' + RST);
  end;

  Lines.Add(BC + '+' + F_MAG + BOLD + ' THINKING ' + F_GRAY + Rep('-', W - 11) + BC + '+' + RST);
  for I := 0 to Quart - 1 do
  begin
    if FThinkingOpen and (I < FThinkingLines.Count) then
      Line := ' ' + F_GRAY + FThinkingLines[I] + RST
    else
      Line := '';
    Lines.Add(BC + '|' + FitW(Line, W-2) + BC + '|' + RST);
  end;
  Lines.Add(BC + '+' + Rep('-', W-2) + '+' + RST);
end;

// ============================================================================
// Render
// ============================================================================
function TGrispApp.RenderScreen: string;
var
  LeftW, RightW, ChatW, PaneH, I: Integer;
  L, C, R, Hdr, Ftr: TStringList;
  SB: TStringBuilder;
begin
  GetTermSize(FWidth, FHeight);
  if FWidth  < 80 then FWidth  := 80;
  if FHeight < 24 then FHeight := 24;

  if FShowLeft and FShowRight then
  begin
    LeftW := 30; RightW := 42; ChatW := FWidth - LeftW - RightW;
  end
  else if FShowLeft then
  begin
    LeftW := 30; RightW := 0; ChatW := FWidth - LeftW;
  end
  else if FShowRight then
  begin
    RightW := 42; LeftW := 0; ChatW := FWidth - RightW;
  end
  else
  begin
    LeftW := 0; RightW := 0; ChatW := FWidth;
  end;

  PaneH := FHeight - 5;

  L := TStringList.Create;
  C := TStringList.Create;
  R := TStringList.Create;
  Hdr := TStringList.Create;
  Ftr := TStringList.Create;
  SB := TStringBuilder.Create;
  try
    DrawHeader(Hdr);
    DrawFooter(Ftr);
    if FShowLeft  then DrawLeftPane(L, LeftW, PaneH);
    DrawChatPane(C, ChatW, PaneH);
    if FShowRight then DrawRightPane(R, RightW, PaneH);

    SB.Append(HOME);
    for I := 0 to Hdr.Count - 1 do SB.Append(Hdr[I] + #13#10);
    for I := 0 to PaneH - 1 do
    begin
      if FShowLeft  and (I < L.Count) then SB.Append(L[I]);
      if I < C.Count then SB.Append(C[I]);
      if FShowRight and (I < R.Count) then SB.Append(R[I]);
      SB.Append(#13#10);
    end;
    for I := 0 to Ftr.Count - 1 do
    begin
      SB.Append(Ftr[I]);
      if I < Ftr.Count - 1 then SB.Append(#13#10);
    end;

    Result := SB.ToString;
  finally
    L.Free; C.Free; R.Free; Hdr.Free; Ftr.Free; SB.Free;
  end;
end;

// ============================================================================
// Simulation
// ============================================================================
procedure TGrispApp.SubmitPrompt;
begin
  if Trim(FInputBuf) = '' then Exit;
  AddUser(FInputBuf);
  BeginSimulation;
  FInputBuf := '';
end;

procedure TGrispApp.BeginSimulation;
begin
  FSimActive := True;
  FSimStep := 0;
  FSimTimer := GetTickCount;
  FStatusMsg := 'Connected | Permissions: RWX | Prompt: PENDING -> SUBMITTING';
  FStatusKind := 1;
  FThinkingLines.Clear;
  FThinkingLines.Add('> Parsing user prompt...');
  FThinkingLines.Add('> SIR: building structured representation...');
  FThinkingLines.Add('> Planner: generating execution plan...');
end;

procedure TGrispApp.TickSimulation;
begin
  if not FSimActive then Exit;
  Inc(FSimStep);
  case FSimStep of
    1: begin
         FStatusMsg := 'Connected | Permissions: RWX | Prompt: SUBMITTING';
         FThinkingLines.Clear;
         FThinkingLines.Add('> INPUT_SUBMITTED (provider_native_send)');
         FThinkingLines.Add('> Verifying input ownership...');
         FThinkingLines.Add('> Awaiting GENERATION_STARTED...');
       end;
    2: begin
         FStatusMsg := 'Connected | Permissions: RWX | Prompt: GENERATING';
         FThinkingLines.Clear;
         FThinkingLines.Add('> GENERATION_STARTED: message identified');
         FThinkingLines.Add('> Baseline revision captured (r=0)');
         FThinkingLines.Add('> Streaming GENERATION_DELTA...');
         AddAssistant('Analyzing GRISP architecture. Referencing SIR, Planner, and Evaluator stages.');
       end;
    3: begin
         FThinkingLines.Clear;
         FThinkingLines.Add('> Deltas applied: rev 1..3 (APPEND)');
         FThinkingLines.Add('> Terminal stability check (1/2)');
         FThinkingLines.Add('> Fencing: prompt_request_id OK');
       end;
    4: begin
         FThinkingLines.Clear;
         FThinkingLines.Add('> Terminal stability check (2/2)');
         FThinkingLines.Add('> done=true streaming=false continuation=false');
         FThinkingLines.Add('> Submitting terminal candidate to arbiter...');
       end;
    5: begin
         AddAssistant('Main components identified:');
         AddAssistant('  1. SIR - Source Intermediate Representation');
         AddAssistant('  2. Planner - Execution plan builder');
         AddAssistant('  3. Evaluator - Graph operations executor');
         AddAssistant('  4. Validator - Correctness and compliance');
         AddAssistant('  5. EIR - Optimized Execution IR');
         AddAssistant('  6. Runtime - Deterministic executor');
         AddAssistant('  7. WorldState - Persistent state');
         AddAssistant('Would you like me to generate a diagram?');
         FThinkingLines.Clear;
         FThinkingLines.Add('> GENERATION_COMPLETED committed');
         FThinkingLines.Add('> Terminal arbitration: winner = COMPLETED');
         FThinkingLines.Add('> Session returned to READY');
         FStatusMsg := 'Connected | Permissions: RWX | Prompt: COMPLETED';
         FStatusKind := 0;
         FSimActive := False;
       end;
  end;
end;

// ============================================================================
// Key handling
// ============================================================================
procedure TGrispApp.HandleSpecialVK(VK: Word);
begin
  case VK of
    VK_F1: FShowLeft := not FShowLeft;
    VK_F2: FShowRight := not FShowRight;
    VK_F3: FThinkingOpen := not FThinkingOpen;
    VK_F4: if FSimActive then TickSimulation else SubmitPrompt;
  end;
end;

procedure TGrispApp.HandleKeyEvent(const Ev: TKeyEvent);
begin
  if Ev.IsSpecial then
  begin
    HandleSpecialVK(Ev.VK);
    Exit;
  end;
  case Ev.Ch of
    #27: FQuit := True;
    #9:  case FActivePane of
           apLeft:   FActivePane := apCenter;
           apCenter: if FShowRight then FActivePane := apRight else FActivePane := apLeft;
           apRight:  FActivePane := apLeft;
         end;
    #13: if FSimActive then TickSimulation else SubmitPrompt;
    #8:  if Length(FInputBuf) > 0 then
           FInputBuf := Copy(FInputBuf, 1, Length(FInputBuf) - 1);
  else
    if (Ord(Ev.Ch) >= 32) and (Ord(Ev.Ch) <= 126) then
      FInputBuf := FInputBuf + Ev.Ch;
  end;
end;

// ============================================================================
// Main loop
// ============================================================================
procedure TGrispApp.Run;
var
  Ev: TKeyEvent;
  Frame: Cardinal;
begin
  SetUTF8CP;
  EnableVT;
  SetCursorVis(False);
  Write(CLR);

  try
    FQuit := False;
    while not FQuit do
    begin
      Write(RenderScreen);

      Frame := GetTickCount;
      while (GetTickCount - Frame) < 50 do
      begin
        if TryReadKey(Ev) then
        begin
          HandleKeyEvent(Ev);
          if FQuit then Break;
        end
        else
          Sleep(5);
      end;

      if FSimActive and ((GetTickCount - FSimTimer) > 900) then
      begin
        FSimTimer := GetTickCount;
        TickSimulation;
      end;
    end;
  finally
    SetCursorVis(True);
    Write(RST, SHOW_CUR, CLR);
  end;
end;

// ============================================================================
// Main
// ============================================================================
var
  App: TGrispApp;
begin
  try
    App := TGrispApp.Create;
    try
      App.Run;
    finally
      App.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln('Fatal error: ', E.Message);
      Halt(1);
    end;
  end;
end.
