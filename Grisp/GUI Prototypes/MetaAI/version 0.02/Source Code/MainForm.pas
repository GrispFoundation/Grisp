unit MainForm;

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Generics.Collections,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.Buttons,
  GRISP.Data, GRISP.Terminal;

type
  TFrmGRISP = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormResize(Sender: TObject);
  private
    // Main containers
    pnlRoot, pnlHeader, pnlMain, pnlLeft, pnlCenter, pnlRight, pnlFooter: TPanel;
    splitterLeft, splitterRight: TSplitter;

    // Header
    lblLogo: TLabel;
    btnTabChat, btnTabWorkflows, btnTabKnowledge, btnTabTerminal: TSpeedButton;
    lblAgentDot, lblAgent, lblTime: TLabel;
    btnToggleLeft, btnToggleRight: TSpeedButton;
    tmrClock: TTimer;

    // Left - Explorer + Sessions
    lblExplorerTitle: TLabel;
    edtSearch: TEdit;
    tvExplorer: TTreeView;
    pnlLeftSessions: TPanel;
    lvSessions: TListView;
    btnNewSession: TButton;

    // Center - Chat + Think + Input + Terminal
    pnlChatHeader: TPanel;
    lblChatTitle: TLabel;
    memoChat: TRichEdit;
    pnlThink: TPanel;
    lblThinkHeader: TLabel;
    memoThink: TMemo;
    btnToggleThink: TSpeedButton;
    pnlChatInput: TPanel;
    edtChat: TEdit;
    btnSend: TButton;
    btnAttach: TSpeedButton;
    memoTerminal: TMemo;

    // Right - Plan + Work Items + Export
    lblPlanTitle: TLabel;
    lvPlan: TListView;
    lvWorkItems: TListView;
    pnlExport: TPanel;
    btnExportUnicode, btnExportASCII, btnExportANSI: TButton;

    // State
    FThinkExpanded: Boolean;
    FLeftCollapsed: Boolean;
    FRightCollapsed: Boolean;
    FTerminalMode: Boolean;

    procedure BuildUI;
    procedure BuildHeader;
    procedure BuildLeft;
    procedure BuildCenter;
    procedure BuildRight;
    procedure BuildFooter;

    // Events
    procedure ToggleLeft(Sender: TObject);
    procedure ToggleRight(Sender: TObject);
    procedure ToggleThink(Sender: TObject);
    procedure ToggleTerminal(Sender: TObject);
    procedure SendChat(Sender: TObject);
    procedure edtChatKeyPress(Sender: TObject; var Key: Char);
    procedure btnExportUnicodeClick(Sender: TObject);
    procedure btnExportASCIIClick(Sender: TObject);
    procedure btnExportANSIClick(Sender: TObject);
    procedure TreeChange(Sender: TObject; Node: TTreeNode);
    procedure SessionClick(Sender: TObject);
    procedure ClockTick(Sender: TObject);
    procedure SearchChange(Sender: TObject);
    procedure ExplorerAdvancedCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode; State: TCustomDrawState; Stage: TCustomDrawStage; var PaintImages, DefaultDraw: Boolean);
    procedure PlanCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure PlanCustomDrawSubItem(Sender: TCustomListView; Item: TListItem; SubItem: Integer; State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure WorkItemsCustomDrawSubItem(Sender: TCustomListView; Item: TListItem; SubItem: Integer; State: TCustomDrawState; var DefaultDraw: Boolean);

    // Data
    procedure PopulateExplorer;
    procedure PopulateSessions;
    procedure PopulatePlan;
    procedure PopulateWorkItems;
    procedure AddChat(const ARole: TChatRole; const AText, AThinking: string; HasPlan: Boolean);
    procedure ExportTerminal(Mode: Integer);
    procedure StyleComponents;
  end;

var
  FrmGRISP: TFrmGRISP;

implementation

{$R *.dfm}

procedure TFrmGRISP.FormCreate(Sender: TObject);
begin
  Caption := 'GRISP OS - Delphi 13 Florence Prototype v0.02 (VCL)';
  Width := 1600;
  Height := 900;
  Position := poScreenCenter;
  Color := TColor($1C0B05);
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  DoubleBuffered := True;

  pnlRoot := TPanel.Create(Self);
  pnlRoot.Parent := Self;
  pnlRoot.Align := alClient;
  pnlRoot.BevelOuter := bvNone;
  pnlRoot.Color := TColor($1C0B05);

  pnlHeader := TPanel.Create(Self);
  pnlHeader.Parent := pnlRoot;
  pnlHeader.Align := alTop;
  pnlHeader.Height := 56;
  pnlHeader.BevelOuter := bvNone;
  pnlHeader.Color := TColor($331B0E);

  pnlFooter := TPanel.Create(Self);
  pnlFooter.Parent := pnlRoot;
  pnlFooter.Align := alBottom;
  pnlFooter.Height := 28;
  pnlFooter.BevelOuter := bvNone;
  pnlFooter.Color := TColor($331B0E);

  pnlMain := TPanel.Create(Self);
  pnlMain.Parent := pnlRoot;
  pnlMain.Align := alClient;
  pnlMain.BevelOuter := bvNone;
  pnlMain.Color := TColor($1C0B05);

  pnlLeft := TPanel.Create(Self);
  pnlLeft.Parent := pnlMain;
  pnlLeft.Align := alLeft;
  pnlLeft.Width := 320;
  pnlLeft.BevelOuter := bvNone;
  pnlLeft.Color := TColor($331B0E);

  splitterLeft := TSplitter.Create(Self);
  splitterLeft.Parent := pnlMain;
  splitterLeft.Align := alLeft;
  splitterLeft.Width := 4;
  splitterLeft.Color := TColor($1C0B05);

  pnlRight := TPanel.Create(Self);
  pnlRight.Parent := pnlMain;
  pnlRight.Align := alRight;
  pnlRight.Width := 360;
  pnlRight.BevelOuter := bvNone;
  pnlRight.Color := TColor($331B0E);

  splitterRight := TSplitter.Create(Self);
  splitterRight.Parent := pnlMain;
  splitterRight.Align := alRight;
  splitterRight.Width := 4;
  splitterRight.Color := TColor($1C0B05);

  pnlCenter := TPanel.Create(Self);
  pnlCenter.Parent := pnlMain;
  pnlCenter.Align := alClient;
  pnlCenter.BevelOuter := bvNone;
  pnlCenter.Color := TColor($1C0B05);

  BuildUI;
  StyleComponents;
  PopulateExplorer;
  PopulateSessions;
  PopulatePlan;
  PopulateWorkItems;

  FThinkExpanded := True;
  AddChat(crAssistant, 'Hello Alex,' + sLineBreak + 'How can I help you with GRISP today?', '', False);
  AddChat(crUser, 'Can you analyze the GRISP architecture?', '', False);
  AddChat(crAssistant,
    'Sure! Main components:' + sLineBreak +
    '1. SIR - Parses input' + sLineBreak +
    '2. Planner - Creates plan' + sLineBreak +
    '3. Evaluator - Executes' + sLineBreak +
    '4. Validator - Checks' + sLineBreak +
    '5. EIR - Optimized' + sLineBreak +
    '6. Runtime - Deterministic' + sLineBreak +
    '7. WorldState - State',
    'Analyzing GRISP architecture...' + sLineBreak + 'Identified 7 main components...' + sLineBreak + 'Preparing structured explanation...', True);
end;

procedure TFrmGRISP.StyleComponents;
begin
  // Fix truncated buttons from v0.01 screenshot - ensure full captions visible
  if Assigned(btnExportUnicode) then
  begin
    btnExportUnicode.Caption := 'Export UNICODE';
    btnExportUnicode.Width := 120;
  end;
  if Assigned(btnExportASCII) then
  begin
    btnExportASCII.Caption := 'Export ASCII';
    btnExportASCII.Width := 110;
  end;
  if Assigned(btnExportANSI) then
  begin
    btnExportANSI.Caption := 'Export ANSI';
    btnExportANSI.Width := 110;
  end;
end;

procedure TFrmGRISP.BuildUI;
begin
  BuildHeader;
  BuildLeft;
  BuildCenter;
  BuildRight;
  BuildFooter;
end;

procedure TFrmGRISP.BuildHeader;
begin
  lblLogo := TLabel.Create(Self);
  lblLogo.Parent := pnlHeader;
  lblLogo.Left := 16; lblLogo.Top := 12;
  lblLogo.Caption := 'GRISP OS';
  lblLogo.Font.Size := 14;
  lblLogo.Font.Style := [fsBold];
  lblLogo.Font.Color := TGRISPColors.ACCENT_CYAN;

  btnToggleLeft := TSpeedButton.Create(Self);
  btnToggleLeft.Parent := pnlHeader;
  btnToggleLeft.Left := 140; btnToggleLeft.Top := 12;
  btnToggleLeft.Width := 32; btnToggleLeft.Height := 32;
  btnToggleLeft.Caption := '<';
  btnToggleLeft.OnClick := ToggleLeft;
  btnToggleLeft.Hint := 'Toggle Explorer';

  btnTabChat := TSpeedButton.Create(Self);
  btnTabChat.Parent := pnlHeader;
  btnTabChat.Left := 180; btnTabChat.Top := 10;
  btnTabChat.Width := 80; btnTabChat.Height := 36;
  btnTabChat.Caption := 'Chat';
  btnTabChat.GroupIndex := 1; btnTabChat.Down := True;
  btnTabChat.OnClick := ToggleTerminal;

  btnTabWorkflows := TSpeedButton.Create(Self);
  btnTabWorkflows.Parent := pnlHeader;
  btnTabWorkflows.Left := 265; btnTabWorkflows.Top := 10;
  btnTabWorkflows.Width := 90; btnTabWorkflows.Height := 36;
  btnTabWorkflows.Caption := 'Workflows';
  btnTabWorkflows.GroupIndex := 1;

  btnTabKnowledge := TSpeedButton.Create(Self);
  btnTabKnowledge.Parent := pnlHeader;
  btnTabKnowledge.Left := 360; btnTabKnowledge.Top := 10;
  btnTabKnowledge.Width := 90; btnTabKnowledge.Height := 36;
  btnTabKnowledge.Caption := 'Knowledge';
  btnTabKnowledge.GroupIndex := 1;

  btnTabTerminal := TSpeedButton.Create(Self);
  btnTabTerminal.Parent := pnlHeader;
  btnTabTerminal.Left := 455; btnTabTerminal.Top := 10;
  btnTabTerminal.Width := 90; btnTabTerminal.Height := 36;
  btnTabTerminal.Caption := 'Terminal';
  btnTabTerminal.GroupIndex := 1;
  btnTabTerminal.OnClick := ToggleTerminal;

  // Agent status with green dot
  lblAgentDot := TLabel.Create(Self);
  lblAgentDot.Parent := pnlHeader;
  lblAgentDot.Anchors := [akTop, akRight];
  lblAgentDot.Left := pnlHeader.Width - 280;
  lblAgentDot.Top := 18;
  lblAgentDot.Caption := '●';
  lblAgentDot.Font.Color := TGRISPColors.GREEN_OK;
  lblAgentDot.Font.Size := 10;

  lblAgent := TLabel.Create(Self);
  lblAgent.Parent := pnlHeader;
  lblAgent.Anchors := [akTop, akRight];
  lblAgent.Left := pnlHeader.Width - 260;
  lblAgent.Top := 18;
  lblAgent.Caption := 'Agent: Alex Ready';
  lblAgent.Font.Color := TGRISPColors.GREEN_OK;

  lblTime := TLabel.Create(Self);
  lblTime.Parent := pnlHeader;
  lblTime.Anchors := [akTop, akRight];
  lblTime.Left := pnlHeader.Width - 120;
  lblTime.Top := 18;
  lblTime.Caption := FormatDateTime('hh:nn', Now);
  lblTime.Font.Color := TGRISPColors.TEXT_DIM;

  tmrClock := TTimer.Create(Self);
  tmrClock.Interval := 1000;
  tmrClock.OnTimer := ClockTick;
  tmrClock.Enabled := True;

  btnToggleRight := TSpeedButton.Create(Self);
  btnToggleRight.Parent := pnlHeader;
  btnToggleRight.Anchors := [akTop, akRight];
  btnToggleRight.Left := pnlHeader.Width - 40;
  btnToggleRight.Top := 12;
  btnToggleRight.Width := 32; btnToggleRight.Height := 32;
  btnToggleRight.Caption := '>';
  btnToggleRight.OnClick := ToggleRight;
end;

procedure TFrmGRISP.BuildLeft;
var
  pnlTop: TPanel;
begin
  pnlTop := TPanel.Create(Self);
  pnlTop.Parent := pnlLeft;
  pnlTop.Align := alTop;
  pnlTop.Height := 32;
  pnlTop.BevelOuter := bvNone;
  pnlTop.Color := TColor($331B0E);

  lblExplorerTitle := TLabel.Create(Self);
  lblExplorerTitle.Parent := pnlTop;
  lblExplorerTitle.Left := 12; lblExplorerTitle.Top := 8;
  lblExplorerTitle.Caption := 'Explorer';
  lblExplorerTitle.Font.Style := [fsBold];
  lblExplorerTitle.Font.Color := TGRISPColors.TEXT_DIM;

  edtSearch := TEdit.Create(Self);
  edtSearch.Parent := pnlLeft;
  edtSearch.Align := alTop;
  edtSearch.Height := 28;
  edtSearch.TextHint := 'Search resources...';
  edtSearch.Color := TColor($3F2312);
  edtSearch.Font.Color := TGRISPColors.TEXT_MAIN;
  edtSearch.BorderStyle := bsNone;
  edtSearch.OnChange := SearchChange;

  tvExplorer := TTreeView.Create(Self);
  tvExplorer.Parent := pnlLeft;
  tvExplorer.Align := alClient;
  tvExplorer.Color := TColor($331B0E);
  tvExplorer.Font.Color := TGRISPColors.TEXT_MAIN;
  tvExplorer.BorderStyle := bsNone;
  tvExplorer.OnChange := TreeChange;
  tvExplorer.OnAdvancedCustomDrawItem := ExplorerAdvancedCustomDrawItem;
  tvExplorer.ReadOnly := True;
  tvExplorer.HideSelection := False;
  tvExplorer.RowSelect := False;

  pnlLeftSessions := TPanel.Create(Self);
  pnlLeftSessions.Parent := pnlLeft;
  pnlLeftSessions.Align := alBottom;
  pnlLeftSessions.Height := 220;
  pnlLeftSessions.BevelOuter := bvNone;
  pnlLeftSessions.Color := TColor($3F2312);

  lvSessions := TListView.Create(Self);
  lvSessions.Parent := pnlLeftSessions;
  lvSessions.Align := alClient;
  lvSessions.ViewStyle := vsReport;
  lvSessions.BorderStyle := bsNone;
  lvSessions.Color := TColor($3F2312);
  lvSessions.Font.Color := TGRISPColors.TEXT_MAIN;
  lvSessions.Columns.Add.Caption := 'Session';
  lvSessions.Columns.Add.Caption := 'When';
  lvSessions.Columns[0].Width := 160;
  lvSessions.Columns[1].Width := 110;
  lvSessions.OnClick := SessionClick;
  lvSessions.ReadOnly := True;
  lvSessions.RowSelect := True;
  lvSessions.ShowColumnHeaders := True;

  btnNewSession := TButton.Create(Self);
  btnNewSession.Parent := pnlLeftSessions;
  btnNewSession.Align := alBottom;
  btnNewSession.Height := 32;
  btnNewSession.Caption := '+ New Session';
  btnNewSession.Style := bsCommandLink;
end;

procedure TFrmGRISP.BuildCenter;
begin
  pnlChatHeader := TPanel.Create(Self);
  pnlChatHeader.Parent := pnlCenter;
  pnlChatHeader.Align := alTop;
  pnlChatHeader.Height := 36;
  pnlChatHeader.BevelOuter := bvNone;
  pnlChatHeader.Color := TColor($331B0E);

  lblChatTitle := TLabel.Create(Self);
  lblChatTitle.Parent := pnlChatHeader;
  lblChatTitle.Left := 12; lblChatTitle.Top := 10;
  lblChatTitle.Caption := 'Project setup and architecture';
  lblChatTitle.Font.Color := TGRISPColors.TEXT_DIM;
  lblChatTitle.Font.Style := [fsBold];

  memoTerminal := TMemo.Create(Self);
  memoTerminal.Parent := pnlCenter;
  memoTerminal.Align := alClient;
  memoTerminal.Visible := False;
  memoTerminal.Font.Name := 'Consolas';
  memoTerminal.Font.Size := 9;
  memoTerminal.Color := $0C0C0C;
  memoTerminal.Font.Color := clAqua;
  memoTerminal.ScrollBars := ssBoth;
  memoTerminal.Text := TGRISPTerminal.GenerateUnicode;

  pnlThink := TPanel.Create(Self);
  pnlThink.Parent := pnlCenter;
  pnlThink.Align := alBottom;
  pnlThink.Height := 110;
  pnlThink.BevelOuter := bvNone;
  pnlThink.Color := TColor($3F2312);

  lblThinkHeader := TLabel.Create(Self);
  lblThinkHeader.Parent := pnlThink;
  lblThinkHeader.Left := 12; lblThinkHeader.Top := 6;
  lblThinkHeader.Caption := 'Thinking - 3 steps';
  lblThinkHeader.Font.Color := TGRISPColors.ACCENT_CYAN;
  lblThinkHeader.Font.Style := [fsBold];

  btnToggleThink := TSpeedButton.Create(Self);
  btnToggleThink.Parent := pnlThink;
  btnToggleThink.Anchors := [akTop, akRight];
  btnToggleThink.Left := pnlThink.Width - 40;
  btnToggleThink.Top := 4;
  btnToggleThink.Width := 32; btnToggleThink.Height := 24;
  btnToggleThink.Caption := '▼';
  btnToggleThink.OnClick := ToggleThink;

  memoThink := TMemo.Create(Self);
  memoThink.Parent := pnlThink;
  memoThink.Align := alBottom;
  memoThink.Top := 28;
  memoThink.Height := 80;
  memoThink.BorderStyle := bsNone;
  memoThink.Color := TColor($3F2312);
  memoThink.Font.Color := TGRISPColors.TEXT_DIM;
  memoThink.Lines.Text := '✓ Analyzing GRISP architecture...' + sLineBreak + '✓ Identified 7 main components...' + sLineBreak + '✓ Preparing structured explanation...';

  pnlChatInput := TPanel.Create(Self);
  pnlChatInput.Parent := pnlCenter;
  pnlChatInput.Align := alBottom;
  pnlChatInput.Height := 52;
  pnlChatInput.BevelOuter := bvNone;
  pnlChatInput.Color := TColor($331B0E);

  btnAttach := TSpeedButton.Create(Self);
  btnAttach.Parent := pnlChatInput;
  btnAttach.Left := 8; btnAttach.Top := 14; btnAttach.Width := 28; btnAttach.Height := 28;
  btnAttach.Caption := '@';
  btnAttach.Hint := 'Attach file';

  edtChat := TEdit.Create(Self);
  edtChat.Parent := pnlChatInput;
  edtChat.Left := 44; edtChat.Top := 12;
  edtChat.Width := pnlChatInput.Width - 104;
  edtChat.Anchors := [akLeft, akTop, akRight, akBottom];
  edtChat.Height := 28;
  edtChat.TextHint := 'Type your message...';
  edtChat.Color := TColor($4A2A16);
  edtChat.Font.Color := TGRISPColors.TEXT_MAIN;
  edtChat.BorderStyle := bsNone;
  edtChat.OnKeyPress := edtChatKeyPress;

  btnSend := TButton.Create(Self);
  btnSend.Parent := pnlChatInput;
  btnSend.Anchors := [akTop, akRight];
  btnSend.Left := pnlChatInput.Width - 52; btnSend.Top := 12;
  btnSend.Width := 44; btnSend.Height := 28;
  btnSend.Caption := '▶';
  btnSend.OnClick := SendChat;

  memoChat := TRichEdit.Create(Self);
  memoChat.Parent := pnlCenter;
  memoChat.Align := alClient;
  memoChat.Color := TColor($1C0B05);
  memoChat.Font.Color := TGRISPColors.TEXT_MAIN;
  memoChat.Font.Name := 'Segoe UI';
  memoChat.Font.Size := 10;
  memoChat.BorderStyle := bsNone;
  memoChat.ScrollBars := ssVertical;
  memoChat.ReadOnly := True;
  memoChat.PlainText := False;
end;

procedure TFrmGRISP.BuildRight;
begin
  lblPlanTitle := TLabel.Create(Self);
  lblPlanTitle.Parent := pnlRight;
  lblPlanTitle.Align := alTop;
  lblPlanTitle.Height := 28;
  lblPlanTitle.Caption := ' Plan / Work Items';
  lblPlanTitle.Font.Style := [fsBold];
  lblPlanTitle.Font.Color := TGRISPColors.TEXT_DIM;

  lvPlan := TListView.Create(Self);
  lvPlan.Parent := pnlRight;
  lvPlan.Align := alTop;
  lvPlan.Height := 180;
  lvPlan.ViewStyle := vsReport;
  lvPlan.BorderStyle := bsNone;
  lvPlan.Color := TColor($331B0E);
  lvPlan.Font.Color := TGRISPColors.TEXT_MAIN;
  lvPlan.Columns.Add.Caption := '#';
  lvPlan.Columns.Add.Caption := 'Task';
  lvPlan.Columns.Add.Caption := 'Status';
  lvPlan.Columns[0].Width := 30;
  lvPlan.Columns[1].Width := 180; // wider than v0.01 (was 170) - fixes truncation
  lvPlan.Columns[2].Width := 110;
  lvPlan.RowSelect := True;
  lvPlan.OwnerDraw := True;
  lvPlan.OnCustomDrawItem := PlanCustomDrawItem;
  lvPlan.OnCustomDrawSubItem := PlanCustomDrawSubItem;
  lvPlan.ShowColumnHeaders := True;

  lvWorkItems := TListView.Create(Self);
  lvWorkItems.Parent := pnlRight;
  lvWorkItems.Align := alClient;
  lvWorkItems.ViewStyle := vsReport;
  lvWorkItems.BorderStyle := bsNone;
  lvWorkItems.Color := TColor($331B0E);
  lvWorkItems.Font.Color := TGRISPColors.TEXT_MAIN;
  lvWorkItems.Columns.Add.Caption := 'Work Item';
  lvWorkItems.Columns.Add.Caption := 'Prio';
  lvWorkItems.Columns[0].Width := 210; // wider than v0.01
  lvWorkItems.Columns[1].Width := 80;
  lvWorkItems.RowSelect := True;
  lvWorkItems.OwnerDraw := True;
  lvWorkItems.OnCustomDrawSubItem := WorkItemsCustomDrawSubItem;
  lvWorkItems.ShowColumnHeaders := True;

  pnlExport := TPanel.Create(Self);
  pnlExport.Parent := pnlRight;
  pnlExport.Align := alBottom;
  pnlExport.Height := 76;
  pnlExport.BevelOuter := bvNone;
  pnlExport.Color := TColor($3F2312);

  btnExportUnicode := TButton.Create(Self);
  btnExportUnicode.Parent := pnlExport;
  btnExportUnicode.Left := 8; btnExportUnicode.Top := 8;
  btnExportUnicode.Width := 120; btnExportUnicode.Height := 28;
  btnExportUnicode.Caption := 'Export UNICODE'; // Fixed: was truncated to 'port UNICO'
  btnExportUnicode.OnClick := btnExportUnicodeClick;

  btnExportASCII := TButton.Create(Self);
  btnExportASCII.Parent := pnlExport;
  btnExportASCII.Left := 136; btnExportASCII.Top := 8;
  btnExportASCII.Width := 110; btnExportASCII.Height := 28;
  btnExportASCII.Caption := 'Export ASCII';
  btnExportASCII.OnClick := btnExportASCIIClick;

  btnExportANSI := TButton.Create(Self);
  btnExportANSI.Parent := pnlExport;
  btnExportANSI.Left := 8; btnExportANSI.Top := 40;
  btnExportANSI.Width := 110; btnExportANSI.Height := 28;
  btnExportANSI.Caption := 'Export ANSI';
  btnExportANSI.OnClick := btnExportANSIClick;
end;

procedure TFrmGRISP.BuildFooter;
var
  lbl: TLabel;
begin
  lbl := TLabel.Create(Self);
  lbl.Parent := pnlFooter;
  lbl.Left := 12; lbl.Top := 6;
  lbl.Caption := 'ACTIVE: GRISP://Workspace 42.3GB | Delphi 13 Florence v0.02 | Skia 7.3 optional | SEC ✓ No Threats';
  lbl.Font.Size := 8;
  lbl.Font.Color := TGRISPColors.TEXT_DIM;
end;

procedure TFrmGRISP.PopulateExplorer;
var
  root, proj, grisp: TTreeNode;
begin
  tvExplorer.Items.BeginUpdate;
  try
    tvExplorer.Items.Clear;
    root := tvExplorer.Items.Add(nil, 'GRISP [Local]');
    proj := tvExplorer.Items.AddChild(root, 'Projects');
    grisp := tvExplorer.Items.AddChild(proj, 'GRISP  R W X  Trust:85');
    tvExplorer.Items.AddChild(grisp, 'src  R W X');
    tvExplorer.Items.AddChild(grisp, 'tests  R W X');
    tvExplorer.Items.AddChild(grisp, 'docs  R W X');
    tvExplorer.Items.AddChild(grisp, 'MME-Registry  R W X');
    tvExplorer.Items.AddChild(grisp, 'Agent-Network  R W X');
    tvExplorer.Items.AddChild(proj, 'Data  R W -');
    tvExplorer.Items.AddChild(nil, 'Models  R W -');
    tvExplorer.Items.AddChild(nil, 'Agents  R W X');
    tvExplorer.Items.AddChild(nil, 'Knowledge  R W -');
    tvExplorer.Items.AddChild(nil, 'Tools  R W X');
    tvExplorer.Items.AddChild(nil, 'System  R W X');
    tvExplorer.Items.AddChild(nil, 'Trash  R W -');
    tvExplorer.FullExpand;
  finally
    tvExplorer.Items.EndUpdate;
  end;
end;

procedure TFrmGRISP.PopulateSessions;
begin
  lvSessions.Items.BeginUpdate;
  try
    lvSessions.Items.Clear;
    with lvSessions.Items.Add do begin Caption := 'Project setup and architecture'; SubItems.Add('Today 14:12'); end;
    with lvSessions.Items.Add do begin Caption := 'Data model discussion'; SubItems.Add('Today 11:45'); end;
    with lvSessions.Items.Add do begin Caption := 'Bug investigation'; SubItems.Add('21 Sep 16:20'); end;
    with lvSessions.Items.Add do begin Caption := 'Feature planning'; SubItems.Add('20 Sep 10:10'); end;
    with lvSessions.Items.Add do begin Caption := 'General questions'; SubItems.Add('19 Sep 14:33'); end;
    if lvSessions.Items.Count > 0 then lvSessions.Items[0].Selected := True;
  finally
    lvSessions.Items.EndUpdate;
  end;
end;

procedure TFrmGRISP.PopulatePlan;
begin
  lvPlan.Items.BeginUpdate;
  try
    lvPlan.Items.Clear;
    with lvPlan.Items.Add do begin Caption := '1'; SubItems.Add('Analyze architecture'); SubItems.Add('Completed'); end;
    with lvPlan.Items.Add do begin Caption := '2'; SubItems.Add('Review component details'); SubItems.Add('In progress'); end;
    with lvPlan.Items.Add do begin Caption := '3'; SubItems.Add('Create diagram'); SubItems.Add('Pending'); end;
    with lvPlan.Items.Add do begin Caption := '4'; SubItems.Add('Update documentation'); SubItems.Add('Pending'); end;
  finally
    lvPlan.Items.EndUpdate;
  end;
end;

procedure TFrmGRISP.PopulateWorkItems;
begin
  lvWorkItems.Items.BeginUpdate;
  try
    lvWorkItems.Items.Clear;
    with lvWorkItems.Items.Add do begin Caption := 'Implement GRISP runtime'; SubItems.Add('High'); end;
    with lvWorkItems.Items.Add do begin Caption := 'Add graph visualization'; SubItems.Add('Medium'); end;
    with lvWorkItems.Items.Add do begin Caption := 'Write unit tests'; SubItems.Add('Medium'); end;
    with lvWorkItems.Items.Add do begin Caption := 'Update LSBP integration'; SubItems.Add('Low'); end;
  finally
    lvWorkItems.Items.EndUpdate;
  end;
end;

procedure TFrmGRISP.AddChat(const ARole: TChatRole; const AText, AThinking: string; HasPlan: Boolean);
begin
  memoChat.SelStart := Length(memoChat.Text);
  if ARole = crUser then
  begin
    memoChat.SelAttributes.Color := TGRISPColors.ACCENT_BLUE;
    memoChat.SelAttributes.Style := [fsBold];
    memoChat.Lines.Add('You: ' + AText + sLineBreak);
  end
  else
  begin
    memoChat.SelAttributes.Color := TGRISPColors.TEXT_MAIN;
    memoChat.SelAttributes.Style := [fsBold];
    memoChat.Lines.Add('GRISP Assistant: ');
    memoChat.SelAttributes.Style := [];
    memoChat.Lines.Add(AText + sLineBreak);
    if AThinking <> '' then memoThink.Lines.Text := AThinking;
    if HasPlan then
    begin
      memoChat.SelAttributes.Color := TGRISPColors.ACCENT_CYAN;
      memoChat.Lines.Add('[Plan: 4 steps, see right panel]' + sLineBreak);
    end;
  end;
  memoChat.SelStart := Length(memoChat.Text);
  SendMessage(memoChat.Handle, WM_VSCROLL, SB_BOTTOM, 0);
end;

procedure TFrmGRISP.SendChat(Sender: TObject);
var
  txt: string;
begin
  txt := Trim(edtChat.Text);
  if txt = '' then Exit;
  AddChat(crUser, txt, '', False);
  edtChat.Text := '';
  AddChat(crAssistant, 'Begrepen: "' + txt + '". Ik analyseer dit via SIR -> Planner -> Evaluator...',
    'Analyzing: ' + txt + sLineBreak + '✓ Parsed to SIR' + sLineBreak + '✓ Created plan' + sLineBreak + '✓ Validated R W X', True);
end;

procedure TFrmGRISP.edtChatKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then
  begin
    SendChat(Sender);
    Key := #0;
  end;
end;

procedure TFrmGRISP.btnExportUnicodeClick(Sender: TObject);
begin
  ExportTerminal(0);
end;

procedure TFrmGRISP.btnExportASCIIClick(Sender: TObject);
begin
  ExportTerminal(1);
end;

procedure TFrmGRISP.btnExportANSIClick(Sender: TObject);
begin
  ExportTerminal(2);
end;

procedure TFrmGRISP.ToggleLeft(Sender: TObject);
begin
  FLeftCollapsed := not FLeftCollapsed;
  if FLeftCollapsed then pnlLeft.Width := 0 else pnlLeft.Width := 320;
  btnToggleLeft.Caption := '<';
  if FLeftCollapsed then btnToggleLeft.Caption := '>';
end;

procedure TFrmGRISP.ToggleRight(Sender: TObject);
begin
  FRightCollapsed := not FRightCollapsed;
  if FRightCollapsed then pnlRight.Width := 0 else pnlRight.Width := 360;
end;

procedure TFrmGRISP.ToggleThink(Sender: TObject);
begin
  FThinkExpanded := not FThinkExpanded;
  if FThinkExpanded then
  begin
    pnlThink.Height := 110;
    memoThink.Visible := True;
    btnToggleThink.Caption := '▼';
  end
  else
  begin
    pnlThink.Height := 28;
    memoThink.Visible := False;
    btnToggleThink.Caption := '▲';
  end;
end;

procedure TFrmGRISP.ToggleTerminal(Sender: TObject);
begin
  FTerminalMode := not FTerminalMode;
  memoTerminal.Visible := FTerminalMode;
  memoChat.Visible := not FTerminalMode;
  pnlThink.Visible := not FTerminalMode;
  if FTerminalMode then memoTerminal.Text := TGRISPTerminal.GenerateUnicode;
  btnTabTerminal.Down := FTerminalMode;
  btnTabChat.Down := not FTerminalMode;
end;

procedure TFrmGRISP.ExportTerminal(Mode: Integer);
var
  s, fn: string;
  sl: TStringList;
begin
  case Mode of
    0: begin s := TGRISPTerminal.GenerateUnicode; fn := 'grisp_unicode.txt'; end;
    1: begin s := TGRISPTerminal.GenerateASCII; fn := 'grisp_ascii.txt'; end;
    2: begin s := TGRISPTerminal.GenerateANSI; fn := 'grisp_ansi.bat'; end;
  else s := ''; fn := '';
  end;
  if fn <> '' then
  begin
    sl := TStringList.Create;
    try
      sl.Text := s;
      sl.SaveToFile(ExtractFilePath(ParamStr(0)) + fn, TEncoding.UTF8);
      ShowMessage('Geexporteerd naar ' + fn + ' - werkt in cmd.exe!');
    finally
      sl.Free;
    end;
  end;
end;

procedure TFrmGRISP.TreeChange(Sender: TObject; Node: TTreeNode);
begin
  if Assigned(Node) then lblChatTitle.Caption := 'GRISP://' + Node.Text;
end;

procedure TFrmGRISP.SessionClick(Sender: TObject);
begin
  if lvSessions.Selected <> nil then lblChatTitle.Caption := lvSessions.Selected.Caption;
end;

procedure TFrmGRISP.ClockTick(Sender: TObject);
begin
  if Assigned(lblTime) then lblTime.Caption := FormatDateTime('hh:nn:ss', Now);
end;

procedure TFrmGRISP.SearchChange(Sender: TObject);
var
  term: string;
begin
  term := LowerCase(edtSearch.Text);
  if term = '' then
  begin
    tvExplorer.FullExpand;
    Exit;
  end;
  // v0.02: simple highlight - expand all, search is visual only (TTreeNode has no Visible property)
  tvExplorer.FullExpand;
end;

procedure TFrmGRISP.ExplorerAdvancedCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode; State: TCustomDrawState; Stage: TCustomDrawStage; var PaintImages, DefaultDraw: Boolean);
begin
  // v0.02: custom draw for R W X - keep default draw, no ToolTip property on TTreeNode
  // Future: owner draw with TRWXHelper.PermColor
  DefaultDraw := True;
end;

procedure TFrmGRISP.PlanCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  DefaultDraw := True;
end;

procedure TFrmGRISP.PlanCustomDrawSubItem(Sender: TCustomListView; Item: TListItem; SubItem: Integer; State: TCustomDrawState; var DefaultDraw: Boolean);
var
  status: string;
begin
  if SubItem = 2 then
  begin
    status := Item.SubItems[1];
    if status = 'Completed' then Sender.Canvas.Font.Color := TGRISPColors.GREEN_OK
    else if status = 'In progress' then Sender.Canvas.Font.Color := TGRISPColors.AMBER_MED
    else Sender.Canvas.Font.Color := TGRISPColors.TEXT_DIM;
  end;
  DefaultDraw := True;
end;

procedure TFrmGRISP.WorkItemsCustomDrawSubItem(Sender: TCustomListView; Item: TListItem; SubItem: Integer; State: TCustomDrawState; var DefaultDraw: Boolean);
var
  prio: string;
begin
  if SubItem = 1 then
  begin
    prio := Item.SubItems[0];
    Sender.Canvas.Font.Color := TRWXHelper.PrioColor(prio);
    Sender.Canvas.Font.Style := [fsBold];
  end;
  DefaultDraw := True;
end;

procedure TFrmGRISP.FormResize(Sender: TObject);
begin
  if Assigned(lblAgent) then
  begin
    lblAgent.Left := pnlHeader.Width - 260;
    lblAgentDot.Left := pnlHeader.Width - 280;
    lblTime.Left := pnlHeader.Width - 120;
  end;
  if Assigned(btnToggleRight) then btnToggleRight.Left := pnlHeader.Width - 40;
  if Assigned(btnToggleThink) then btnToggleThink.Left := pnlThink.Width - 40;
  if Assigned(btnSend) then btnSend.Left := pnlChatInput.Width - 52;
  if Assigned(edtChat) then edtChat.Width := pnlChatInput.Width - 104;
end;

end.
