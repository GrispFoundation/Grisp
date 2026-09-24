unit GRISP.TUI.App;

interface

uses
  Winapi.Windows, System.SysUtils,
  GRISP.TUI.Data, GRISP.TUI.Core;

type
  TGRISPTUIApp = class
  private
    FWidth, FHeight: Integer;
    FFocused: TFocusedPanel;
    FExplorer: TArray<TResourceItem>;
    FSessions: TArray<TSessionItem>;
    FChat: TArray<TChatMessage>;
    FPlan: TArray<TPlanStep>;
    FWorkItems: TArray<TWorkItem>;
    FSelExplorer: Integer;
    FSelSession: Integer;
    FSelPlan: Integer;
    FThinkExpanded: Boolean;
    FLeftCollapsed: Boolean;
    FRightCollapsed: Boolean;
    FInputBuffer: string;
    FCursorPos: Integer;
    FRunning: Boolean;
    procedure InitData;
    procedure GetConsoleSize;
    procedure DrawAll;
    procedure DrawHeader;
    procedure DrawExplorer;
    procedure DrawSessions;
    procedure DrawChat;
    procedure DrawPlan;
    procedure DrawInput;
    procedure DrawFooter;
    function ReadKey: Word;
    procedure HandleInput;
    procedure ToggleLeft;
    procedure ToggleRight;
    procedure ToggleThink;
    procedure MoveSelection(Delta: Integer);
    procedure SendCurrentInput;
  public
    constructor Create;
    procedure Run;
  end;

implementation

constructor TGRISPTUIApp.Create;
begin
  EnableConsole;
  FFocused := fpInput; // Start in Input so user can type immediately
  FSelExplorer := 0;
  FSelSession := 0;
  FSelPlan := 0;
  FThinkExpanded := True;
  FLeftCollapsed := False;
  FRightCollapsed := False;
  FInputBuffer := '';
  FCursorPos := 1;
  FRunning := True;
  InitData;
end;

procedure TGRISPTUIApp.InitData;
begin
  SetLength(FExplorer, 12);
  FExplorer[0] := TResourceItem.Create('GRISP', 0, True, [permRead, permWrite, permExecute], 90);
  FExplorer[1] := TResourceItem.Create('Local', 1, True, [permRead, permWrite, permExecute], 85);
  FExplorer[2] := TResourceItem.Create('Projects', 2, True, [permWrite], 80);
  FExplorer[3] := TResourceItem.Create('GRISP', 3, True, [permRead, permWrite, permExecute], 85);
  FExplorer[4] := TResourceItem.Create('src', 4, False, [permRead, permWrite, permExecute], 85);
  FExplorer[5] := TResourceItem.Create('tests', 4, False, [permRead, permWrite, permExecute], 80);
  FExplorer[6] := TResourceItem.Create('docs', 4, False, [permRead, permWrite, permExecute], 75);
  FExplorer[7] := TResourceItem.Create('MME-Registry', 4, False, [permRead, permWrite, permExecute], 80);
  FExplorer[8] := TResourceItem.Create('Agent-Network', 4, False, [permRead, permWrite, permExecute], 80);
  FExplorer[9] := TResourceItem.Create('Data', 2, True, [permRead, permWrite], 70);
  FExplorer[10] := TResourceItem.Create('Models', 1, True, [permRead, permWrite], 70);
  FExplorer[11] := TResourceItem.Create('Trash', 1, True, [permRead, permWrite], 30);

  SetLength(FSessions, 5);
  FSessions[0].Subject := 'Project setup and architecture'; FSessions[0].Day := 'Today'; FSessions[0].TimeStr := '14:12'; FSessions[0].MsgCount := 12; FSessions[0].IsActive := True;
  FSessions[1].Subject := 'Data model discussion'; FSessions[1].Day := 'Today'; FSessions[1].TimeStr := '11:45'; FSessions[1].MsgCount := 8;
  FSessions[2].Subject := 'Bug investigation'; FSessions[2].Day := '21 Sep'; FSessions[2].TimeStr := '16:20'; FSessions[2].MsgCount := 5;
  FSessions[3].Subject := 'Feature planning'; FSessions[3].Day := '20 Sep'; FSessions[3].TimeStr := '10:10'; FSessions[3].MsgCount := 22;
  FSessions[4].Subject := 'General questions'; FSessions[4].Day := '19 Sep'; FSessions[4].TimeStr := '14:33'; FSessions[4].MsgCount := 3;

  SetLength(FChat, 3);
  FChat[0].Role := crAssistant; FChat[0].TimeStr := '14:12'; FChat[0].Text := 'Hello Alex, How can I help you?';
  FChat[1].Role := crUser; FChat[1].TimeStr := '14:12'; FChat[1].Text := 'Can you analyze GRISP architecture?';
  FChat[2].Role := crAssistant; FChat[2].TimeStr := '14:12';
  FChat[2].Text := 'Sure! 1.SIR 2.Planner 3.Evaluator 4.Validator 5.EIR 6.Runtime 7.WorldState';
  FChat[2].Thinking := 'Analyzing... | Identified 7... | Preparing...';
  FChat[2].HasPlan := True;

  SetLength(FPlan, 4);
  FPlan[0].Title := 'Analyze architecture'; FPlan[0].Status := 2;
  FPlan[1].Title := 'Review details'; FPlan[1].Status := 1;
  FPlan[2].Title := 'Create diagram'; FPlan[2].Status := 0;
  FPlan[3].Title := 'Update docs'; FPlan[3].Status := 0;

  SetLength(FWorkItems, 4);
  FWorkItems[0].Title := 'Implement runtime'; FWorkItems[0].Priority := 2;
  FWorkItems[1].Title := 'Add graph viz'; FWorkItems[1].Priority := 1;
  FWorkItems[2].Title := 'Write tests'; FWorkItems[2].Priority := 1;
  FWorkItems[3].Title := 'Update LSBP'; FWorkItems[3].Priority := 0;
end;

procedure TGRISPTUIApp.GetConsoleSize;
var
  info: TConsoleScreenBufferInfo;
  h: THandle;
begin
  h := GetStdHandle(STD_OUTPUT_HANDLE);
  GetConsoleScreenBufferInfo(h, info);
  FWidth := info.srWindow.Right - info.srWindow.Left + 1;
  FHeight := info.srWindow.Bottom - info.srWindow.Top + 1;
  if FWidth < 80 then FWidth := 100;
  if FHeight < 25 then FHeight := 35;
end;

procedure TGRISPTUIApp.DrawAll;
begin
  GetConsoleSize;
  // NO full ClearScreen each frame - only draw boxes, no flicker
  // Clear only once at start, then overwrite
  DrawHeader;
  DrawExplorer;
  DrawSessions;
  DrawChat;
  DrawPlan;
  DrawInput;
  DrawFooter;
end;

procedure TGRISPTUIApp.DrawHeader;
begin
  DrawBoxASCII(TTUIRect.Create(1,1,FWidth,3), ' GRISP OS TUI - Agent: Alex Ready - ' + FormatDateTime('hh:nn', Now), True);
  DrawText(3, 2, '[F1]Explorer [F2]Sessions [F3]Chat [F4]Plan [F5]Think [F10]Quit Focus:' + IntToStr(Ord(FFocused)), 8);
end;

procedure TGRISPTUIApp.DrawExplorer;
var
  r: TTUIRect;
  i, y: Integer;
  focused: Boolean;
  perms: TPermissions;
begin
  if FLeftCollapsed then Exit;
  focused := FFocused = fpExplorer;
  r := TTUIRect.Create(1,4,38,12);
  DrawBoxASCII(r, 'Explorer - R W X', focused);
  for i := 0 to High(FExplorer) do
  begin
    if i > 8 then Break;
    y := r.Y + 1 + i;
    if y >= r.Y + r.H - 1 then Break;
    if i = FSelExplorer then
    begin
      GotoXY(r.X+1, y);
      SetColor(16 + 11); // blue bg + white
      Write(StringOfChar(' ', r.W-2));
    end;
    DrawText(r.X + 2 + FExplorer[i].Level*2, y, FExplorer[i].Name, 15);
    perms := [];
    if permRead in FExplorer[i].Perms then Include(perms, permRead);
    if permWrite in FExplorer[i].Perms then Include(perms, permWrite);
    if permExecute in FExplorer[i].Perms then Include(perms, permExecute);
    DrawRWX(r.X + r.W - 10, y, perms);
  end;
end;

procedure TGRISPTUIApp.DrawSessions;
var
  r: TTUIRect;
  i, y: Integer;
  focused: Boolean;
begin
  if FLeftCollapsed then Exit;
  focused := FFocused = fpSessions;
  r := TTUIRect.Create(1,16,38,9);
  DrawBoxASCII(r, 'Sessions', focused);
  for i := 0 to High(FSessions) do
  begin
    y := r.Y + 1 + i;
    if y >= r.Y + r.H - 1 then Break;
    if i = FSelSession then
    begin
      GotoXY(r.X+1, y);
      SetColor(16 + 11);
      Write(StringOfChar(' ', r.W-2));
    end;
    DrawText(r.X+2, y, Copy(FSessions[i].Subject,1,16), 15);
    DrawText(r.X+20, y, FSessions[i].Day + ' ' + FSessions[i].TimeStr, 8);
  end;
  DrawText(r.X+2, r.Y+r.H-1, '+ New Session', 10);
end;

procedure TGRISPTUIApp.DrawChat;
var
  r: TTUIRect;
  focused: Boolean;
  y, i: Integer;
  leftW, rightW: Integer;
begin
  focused := FFocused = fpChat;
  leftW := 1; if not FLeftCollapsed then leftW := 39;
  rightW := 0; if not FRightCollapsed then rightW := 36;
  r := TTUIRect.Create(leftW, 4, FWidth - leftW - rightW - 1, FHeight - 10);
  DrawBoxASCII(r, 'Chat: Project setup', focused);
  y := r.Y + 1;
  for i := 0 to High(FChat) do
  begin
    if y > r.Y + r.H - 4 then Break;
    if FChat[i].Role = crUser then
      DrawText(r.X+2, y, 'You [' + FChat[i].TimeStr + ']: ' + Copy(FChat[i].Text,1, r.W-20), 9)
    else
      DrawText(r.X+2, y, 'GRISP [' + FChat[i].TimeStr + ']: ' + Copy(FChat[i].Text,1, r.W-20), 15);
    Inc(y);
    if (FChat[i].Thinking <> '') and FThinkExpanded then
    begin
      DrawText(r.X+2, y, '  [Thinking] ' + FChat[i].Thinking, 10);
      Inc(y);
    end;
    Inc(y);
  end;
end;

procedure TGRISPTUIApp.DrawPlan;
var
  r: TTUIRect;
  i, y: Integer;
  focused: Boolean;
  status, prio: string;
begin
  if FRightCollapsed then Exit;
  focused := FFocused = fpPlan;
  r := TTUIRect.Create(FWidth - 35, 4, 35, FHeight - 10);
  DrawBoxASCII(r, 'Plan / Work Items', focused);
  y := r.Y + 1;
  for i := 0 to High(FPlan) do
  begin
    if y >= r.Y + 6 then Break;
    case FPlan[i].Status of
      0: status := '[ ]';
      1: status := '[o]';
      2: status := '[v]';
    end;
    if i = FSelPlan then
    begin
      GotoXY(r.X+1, y);
      SetColor(16 + 11);
      Write(StringOfChar(' ', r.W-2));
    end;
    DrawText(r.X+2, y, status + ' ' + Copy(FPlan[i].Title,1,18), 15);
    Inc(y);
  end;
  Inc(y);
  DrawText(r.X+2, y, 'Work Items:', 15);
  Inc(y);
  for i := 0 to High(FWorkItems) do
  begin
    if y >= r.Y + r.H - 2 then Break;
    case FWorkItems[i].Priority of
      0: prio := '[Low]';
      1: prio := '[Med]';
      2: prio := '[High]';
    end;
    DrawText(r.X+2, y, Copy(FWorkItems[i].Title,1,16), 15);
    if FWorkItems[i].Priority = 2 then DrawText(r.X+20, y, prio, 12)
    else if FWorkItems[i].Priority = 1 then DrawText(r.X+20, y, prio, 14)
    else DrawText(r.X+20, y, prio, 9);
    Inc(y);
  end;
end;

procedure TGRISPTUIApp.DrawInput;
var
  r: TTUIRect;
begin
  r := TTUIRect.Create(1, FHeight-5, FWidth, 3);
  DrawBoxASCII(r, 'Input - Enter to send (FOCUS HERE TO TYPE)', FFocused = fpInput);
  // Show input buffer with cursor
  DrawText(r.X+2, r.Y+1, 'GRISP> ' + FInputBuffer + '_', 15);
end;

procedure TGRISPTUIApp.DrawFooter;
begin
  DrawText(1, FHeight-1, ' [Tab] Switch [T] Think [C] Collapse [F10/Q] Quit | ACTIVE: GRISP://Workspace ', 8);
end;

function TGRISPTUIApp.ReadKey: Word;
var
  ir: TInputRecord;
  num: DWORD;
  hIn: THandle;
begin
  hIn := GetStdHandle(STD_INPUT_HANDLE);
  repeat
    ReadConsoleInput(hIn, ir, 1, num);
    if (ir.EventType = KEY_EVENT) and ir.Event.KeyEvent.bKeyDown then
    begin
      Result := ir.Event.KeyEvent.wVirtualKeyCode;
      // Handle typing ONLY when focused = Input
      if FFocused = fpInput then
      begin
        // Use UnicodeChar - works in Delphi 13
        if ir.Event.KeyEvent.UnicodeChar >= #32 then
        begin
          FInputBuffer := FInputBuffer + ir.Event.KeyEvent.UnicodeChar;
        end
        else if Result = VK_BACK then
        begin
          if Length(FInputBuffer) > 0 then
            SetLength(FInputBuffer, Length(FInputBuffer)-1);
        end;
      end;
      Exit;
    end;
  until False;
end;

procedure TGRISPTUIApp.HandleInput;
var
  key: Word;
begin
  key := ReadKey;
  case key of
    VK_F1: FFocused := fpExplorer;
    VK_F2: FFocused := fpSessions;
    VK_F3: FFocused := fpChat;
    VK_F4: FFocused := fpPlan;
    VK_F5: ToggleThink;
    VK_F10: FRunning := False;
    81: FRunning := False; // Q
    VK_TAB:
      begin
        if GetKeyState(VK_SHIFT) < 0 then
          FFocused := TFocusedPanel((Ord(FFocused) - 1 + 5) mod 5)
        else
          FFocused := TFocusedPanel((Ord(FFocused) + 1) mod 5);
      end;
    VK_UP: MoveSelection(-1);
    VK_DOWN: MoveSelection(1);
    VK_RETURN:
      begin
        if FFocused = fpInput then SendCurrentInput
        else if FFocused = fpPlan then
          if (FSelPlan <= High(FPlan)) then
            FPlan[FSelPlan].Status := (FPlan[FSelPlan].Status + 1) mod 3;
      end;
    84: ToggleThink; // T
    67: begin // C
        if FFocused in [fpExplorer, fpSessions] then ToggleLeft
        else if FFocused = fpPlan then ToggleRight;
      end;
  end;
end;

procedure TGRISPTUIApp.MoveSelection(Delta: Integer);
begin
  case FFocused of
    fpExplorer:
      begin
        FSelExplorer := FSelExplorer + Delta;
        if FSelExplorer < 0 then FSelExplorer := 0;
        if FSelExplorer > High(FExplorer) then FSelExplorer := High(FExplorer);
      end;
    fpSessions:
      begin
        FSelSession := FSelSession + Delta;
        if FSelSession < 0 then FSelSession := 0;
        if FSelSession > High(FSessions) then FSelSession := High(FSessions);
      end;
    fpPlan:
      begin
        FSelPlan := FSelPlan + Delta;
        if FSelPlan < 0 then FSelPlan := 0;
        if FSelPlan > High(FPlan) then FSelPlan := High(FPlan);
      end;
  end;
end;

procedure TGRISPTUIApp.ToggleLeft;
begin
  FLeftCollapsed := not FLeftCollapsed;
end;

procedure TGRISPTUIApp.ToggleRight;
begin
  FRightCollapsed := not FRightCollapsed;
end;

procedure TGRISPTUIApp.ToggleThink;
begin
  FThinkExpanded := not FThinkExpanded;
end;

procedure TGRISPTUIApp.SendCurrentInput;
var
  msg: TChatMessage;
begin
  if Trim(FInputBuffer) = '' then Exit;
  msg.Role := crUser;
  msg.Text := FInputBuffer;
  msg.TimeStr := FormatDateTime('hh:nn', Now);
  msg.Thinking := '';
  msg.HasPlan := False;
  SetLength(FChat, Length(FChat)+1);
  FChat[High(FChat)] := msg;

  msg.Role := crAssistant;
  msg.Text := 'Begrepen: "' + FInputBuffer + '" -> SIR -> Planner';
  msg.Thinking := 'Analyzing: ' + FInputBuffer;
  msg.HasPlan := True;
  SetLength(FChat, Length(FChat)+1);
  FChat[High(FChat)] := msg;
  FInputBuffer := '';
end;

procedure TGRISPTUIApp.Run;
var
  hOut: THandle;
begin
  hOut := GetStdHandle(STD_OUTPUT_HANDLE);
  // Initial clear only once
  ClearScreenNoFlicker;
  while FRunning do
  begin
    DrawAll;
    HandleInput;
  end;
  ClearScreenNoFlicker;
  ResetColor;
  Writeln('GRISP TUI gesloten.');
end;

end.
