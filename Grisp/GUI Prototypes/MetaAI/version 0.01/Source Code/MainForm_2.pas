unit MainForm;

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.Types, System.UITypes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.Buttons,
  Vcl.Imaging.pngimage,
  GRISP.Data, GRISP.Terminal;

  // Voor Delphi 13 Florence: Skia is ingebouwd maar optioneel
  // Als je Skia wilt gebruiken: Project Options > Conditional Defines > USE_SKIA
  // Dan krijg je TSkLabel en TSkPaintBox voor glow effects
{$IFDEF USE_SKIA}
  , System.Skia, Vcl.Skia
{$ENDIF}

type
  TFrmGRISP = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormResize(Sender: TObject);
  private
    pnlRoot: TPanel;
    pnlHeader: TPanel;
    pnlMain: TPanel;
    pnlLeft: TPanel;
    pnlLeftSessions: TPanel;
    pnlCenter: TPanel;
    pnlRight: TPanel;
    pnlFooter: TPanel;

    // Header
    lblLogo: TLabel;
    btnTabChat, btnTabWorkflows, btnTabKnowledge, btnTabTerminal: TSpeedButton;
    lblAgent: TLabel;
    lblTime: TLabel;
    btnToggleLeft: TSpeedButton;
    btnToggleRight: TSpeedButton;

    // Left Explorer
    lblExplorerTitle: TLabel;
    edtSearch: TEdit;
    tvExplorer: TTreeView;
    lvSessions: TListView;
    btnNewSession: TButton;

    // Center Chat
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

    // Right Plan
    lblPlanTitle: TLabel;
    lvPlan: TListView;
    lvWorkItems: TListView;
    btnExportASCII, btnExportANSI, btnExportUnicode: TButton;

    // Terminal view
    memoTerminal: TMemo;

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

    procedure ToggleLeft(Sender: TObject);
    procedure ToggleRight(Sender: TObject);
    procedure ToggleThink(Sender: TObject);
    procedure ToggleTerminal(Sender: TObject);
    procedure SendChat(Sender: TObject);
    procedure AddChat(const ARole: TChatRole; const AText, AThinking: string; HasPlan: Boolean);
    procedure PopulateExplorer;
    procedure PopulateSessions;
    procedure PopulatePlan;
    procedure PopulateWorkItems;
    procedure ExportTerminal(Mode: Integer);

    procedure TreeChange(Sender: TObject; Node: TTreeNode);
    procedure SessionClick(Sender: TObject);
  public
  end;

var
  FrmGRISP: TFrmGRISP;

implementation

{$R *.dfm}

procedure TFrmGRISP.FormCreate(Sender: TObject);
begin
  Self.Caption := 'GRISP OS - Delphi 13 Florence Prototype (VCL)';
  Self.Width := 1600;
  Self.Height := 950;
  Self.Position := poScreenCenter;
  Self.Color := TGRISPColors.BG_DARK;
  Self.Font.Name := 'Segoe UI';
  Self.Font.Size := 9;
  Self.Font.Color := TGRISPColors.TEXT_MAIN;
  Self.DoubleBuffered := True;

  pnlRoot := TPanel.Create(Self);
  pnlRoot.Parent := Self;
  pnlRoot.Align := alClient;
  pnlRoot.BevelOuter := bvNone;
  pnlRoot.Color := TGRISPColors.BG_DARK;
  pnlRoot.ParentBackground := False;

  pnlHeader := TPanel.Create(Self);
  pnlHeader.Parent := pnlRoot;
  pnlHeader.Align := alTop;
  pnlHeader.Height := 56;
  pnlHeader.BevelOuter := bvNone;
  pnlHeader.Color := TGRISPColors.BG_PANEL;
  pnlHeader.ParentBackground := False;

  pnlFooter := TPanel.Create(Self);
  pnlFooter.Parent := pnlRoot;
  pnlFooter.Align := alBottom;
  pnlFooter.Height := 32;
  pnlFooter.BevelOuter := bvNone;
  pnlFooter.Color := TGRISPColors.BG_PANEL;
  pnlFooter.ParentBackground := False;

  pnlMain := TPanel.Create(Self);
  pnlMain.Parent := pnlRoot;
  pnlMain.Align := alClient;
  pnlMain.BevelOuter := bvNone;
  pnlMain.Color := TGRISPColors.BG_DARK;
  pnlMain.ParentBackground := False;

  pnlLeft := TPanel.Create(Self);
  pnlLeft.Parent := pnlMain;
  pnlLeft.Align := alLeft;
  pnlLeft.Width := 300;
  pnlLeft.BevelOuter := bvNone;
  pnlLeft.Color := TGRISPColors.BG_PANEL;
  pnlLeft.ParentBackground := False;

  pnlRight := TPanel.Create(Self);
  pnlRight.Parent := pnlMain;
  pnlRight.Align := alRight;
  pnlRight.Width := 340;
  pnlRight.BevelOuter := bvNone;
  pnlRight.Color := TGRISPColors.BG_PANEL;
  pnlRight.ParentBackground := False;

  pnlCenter := TPanel.Create(Self);
  pnlCenter.Parent := pnlMain;
  pnlCenter.Align := alClient;
  pnlCenter.BevelOuter := bvNone;
  pnlCenter.Color := TGRISPColors.BG_DARK;
  pnlCenter.ParentBackground := False;

  BuildUI;

  PopulateExplorer;
  PopulateSessions;
  PopulatePlan;
  PopulateWorkItems;

  FThinkExpanded := True;
  AddChat(crAssistant, 'Hello Alex,' + sLineBreak + 'How can I help you with GRISP today?', '', False);
  AddChat(crUser, 'Can you help me analyze the GRISP architecture and explain the main components and how they work together?', '', False);
  AddChat(crAssistant,
    'Sure! The GRISP architecture is designed around a deterministic, graph-based execution model. Here are the main components:' + sLineBreak +
    '1. SIR (Source Intermediate Representation) - Parses and validates input' + sLineBreak +
    '2. Planner - Creates execution plan' + sLineBreak +
    '3. Evaluator - Executes graph operations' + sLineBreak +
    '4. Validator - Ensures correctness' + sLineBreak +
    '5. EIR (Execution IR) - Optimized form' + sLineBreak +
    '6. GRISP Runtime - Executes deterministically' + sLineBreak +
    '7. LSBP / WorldState - Manages state',
    'Analyzing GRISP architecture from documentation...' + sLineBreak +
    'Identified 7 main components and their relationships...' + sLineBreak +
    'Preparing structured explanation...', True);
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
  lblLogo.Left := 16;
  lblLogo.Top := 12;
  lblLogo.Caption := 'GRISP OS';
  lblLogo.Font.Size := 14;
  lblLogo.Font.Style := [fsBold];
  lblLogo.Font.Color := TGRISPColors.ACCENT_CYAN;

  btnToggleLeft := TSpeedButton.Create(Self);
  btnToggleLeft.Parent := pnlHeader;
  btnToggleLeft.Left := 140;
  btnToggleLeft.Top := 12;
  btnToggleLeft.Width := 32;
  btnToggleLeft.Height := 32;
  btnToggleLeft.Caption := '<';
  btnToggleLeft.OnClick := ToggleLeft;

  btnTabChat := TSpeedButton.Create(Self);
  btnTabChat.Parent := pnlHeader;
  btnTabChat.Left := 180;
  btnTabChat.Top := 10;
  btnTabChat.Width := 90;
  btnTabChat.Height := 36;
  btnTabChat.Caption := 'Chat';
  btnTabChat.GroupIndex := 1;
  btnTabChat.Down := True;
  btnTabChat.OnClick := ToggleTerminal;

  btnTabWorkflows := TSpeedButton.Create(Self);
  btnTabWorkflows.Parent := pnlHeader;
  btnTabWorkflows.Left := 275;
  btnTabWorkflows.Top := 10;
  btnTabWorkflows.Width := 100;
  btnTabWorkflows.Height := 36;
  btnTabWorkflows.Caption := 'Workflows';
  btnTabWorkflows.GroupIndex := 1;

  btnTabKnowledge := TSpeedButton.Create(Self);
  btnTabKnowledge.Parent := pnlHeader;
  btnTabKnowledge.Left := 380;
  btnTabKnowledge.Top := 10;
  btnTabKnowledge.Width := 100;
  btnTabKnowledge.Height := 36;
  btnTabKnowledge.Caption := 'Knowledge';
  btnTabKnowledge.GroupIndex := 1;

  btnTabTerminal := TSpeedButton.Create(Self);
  btnTabTerminal.Parent := pnlHeader;
  btnTabTerminal.Left := 485;
  btnTabTerminal.Top := 10;
  btnTabTerminal.Width := 110;
  btnTabTerminal.Height := 36;
  btnTabTerminal.Caption := 'Terminal';
  btnTabTerminal.GroupIndex := 1;
  btnTabTerminal.OnClick := ToggleTerminal;

  lblAgent := TLabel.Create(Self);
  lblAgent.Parent := pnlHeader;
  lblAgent.Anchors := [akTop, akRight];
  lblAgent.Left := pnlHeader.Width - 300;
  lblAgent.Top := 18;
  lblAgent.Caption := 'Agent: Alex Ready';
  lblAgent.Font.Color := TGRISPColors.GREEN_OK;

  lblTime := TLabel.Create(Self);
  lblTime.Parent := pnlHeader;
  lblTime.Anchors := [akTop, akRight];
  lblTime.Left := pnlHeader.Width - 140;
  lblTime.Top := 18;
  lblTime.Caption := FormatDateTime('hh:nn - dd mmm', Now);
  lblTime.Font.Color := TGRISPColors.TEXT_DIM;

  btnToggleRight := TSpeedButton.Create(Self);
  btnToggleRight.Parent := pnlHeader;
  btnToggleRight.Anchors := [akTop, akRight];
  btnToggleRight.Left := pnlHeader.Width - 40;
  btnToggleRight.Top := 12;
  btnToggleRight.Width := 32;
  btnToggleRight.Height := 32;
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
  pnlTop.Color := TGRISPColors.BG_PANEL;
  pnlTop.ParentBackground := False;

  lblExplorerTitle := TLabel.Create(Self);
  lblExplorerTitle.Parent := pnlTop;
  lblExplorerTitle.Left := 12;
  lblExplorerTitle.Top := 8;
  lblExplorerTitle.Caption := 'Explorer';
  lblExplorerTitle.Font.Style := [fsBold];
  lblExplorerTitle.Font.Color := TGRISPColors.TEXT_DIM;

  edtSearch := TEdit.Create(Self);
  edtSearch.Parent := pnlLeft;
  edtSearch.Align := alTop;
  edtSearch.Height := 30;
  edtSearch.TextHint := 'Search resources...';
  edtSearch.Color := TGRISPColors.BG_PANEL2;
  edtSearch.Font.Color := TGRISPColors.TEXT_MAIN;

  tvExplorer := TTreeView.Create(Self);
  tvExplorer.Parent := pnlLeft;
  tvExplorer.Align := alClient;
  tvExplorer.Color := TGRISPColors.BG_PANEL;
  tvExplorer.Font.Color := TGRISPColors.TEXT_MAIN;
  tvExplorer.BorderStyle := bsNone;
  tvExplorer.OnChange := TreeChange;

  pnlLeftSessions := TPanel.Create(Self);
  pnlLeftSessions.Parent := pnlLeft;
  pnlLeftSessions.Align := alBottom;
  pnlLeftSessions.Height := 260;
  pnlLeftSessions.BevelOuter := bvNone;
  pnlLeftSessions.Color := TGRISPColors.BG_PANEL2;
  pnlLeftSessions.ParentBackground := False;

  lvSessions := TListView.Create(Self);
  lvSessions.Parent := pnlLeftSessions;
  lvSessions.Align := alClient;
  lvSessions.ViewStyle := vsReport;
  lvSessions.BorderStyle := bsNone;
  lvSessions.Color := TGRISPColors.BG_PANEL2;
  lvSessions.Font.Color := TGRISPColors.TEXT_MAIN;
  lvSessions.Columns.Add.Caption := 'Session';
  lvSessions.Columns.Add.Caption := 'When';
  lvSessions.Columns[0].Width := 180;
  lvSessions.Columns[1].Width := 90;
  lvSessions.OnClick := SessionClick;
  lvSessions.ReadOnly := True;
  lvSessions.RowSelect := True;

  btnNewSession := TButton.Create(Self);
  btnNewSession.Parent := pnlLeftSessions;
  btnNewSession.Align := alBottom;
  btnNewSession.Height := 32;
  btnNewSession.Caption := '+ New Session';
end;

procedure TFrmGRISP.BuildCenter;
begin
  pnlChatHeader := TPanel.Create(Self);
  pnlChatHeader.Parent := pnlCenter;
  pnlChatHeader.Align := alTop;
  pnlChatHeader.Height := 40;
  pnlChatHeader.BevelOuter := bvNone;
  pnlChatHeader.Color := TGRISPColors.BG_PANEL;
  pnlChatHeader.ParentBackground := False;

  lblChatTitle := TLabel.Create(Self);
  lblChatTitle.Parent := pnlChatHeader;
  lblChatTitle.Left := 12;
  lblChatTitle.Top := 10;
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
  pnlThink.Color := TGRISPColors.BG_PANEL2;
  pnlThink.ParentBackground := False;

  lblThinkHeader := TLabel.Create(Self);
  lblThinkHeader.Parent := pnlThink;
  lblThinkHeader.Left := 12;
  lblThinkHeader.Top := 6;
  lblThinkHeader.Caption := 'Thinking - 3 steps';
  lblThinkHeader.Font.Color := TGRISPColors.ACCENT_CYAN;
  lblThinkHeader.Font.Style := [fsBold];

  btnToggleThink := TSpeedButton.Create(Self);
  btnToggleThink.Parent := pnlThink;
  btnToggleThink.Anchors := [akTop, akRight];
  btnToggleThink.Left := pnlThink.Width - 40;
  btnToggleThink.Top := 4;
  btnToggleThink.Width := 32;
  btnToggleThink.Height := 24;
  btnToggleThink.Caption := 'V';
  btnToggleThink.OnClick := ToggleThink;

  memoThink := TMemo.Create(Self);
  memoThink.Parent := pnlThink;
  memoThink.Align := alBottom;
  memoThink.Top := 28;
  memoThink.Height := 80;
  memoThink.BorderStyle := bsNone;
  memoThink.Color := TGRISPColors.BG_PANEL2;
  memoThink.Font.Color := TGRISPColors.TEXT_DIM;
  memoThink.Lines.Text := 'Analyzing GRISP architecture...' + sLineBreak +
                          'Identified 7 main components...' + sLineBreak +
                          'Preparing structured explanation...';

  pnlChatInput := TPanel.Create(Self);
  pnlChatInput.Parent := pnlCenter;
  pnlChatInput.Align := alBottom;
  pnlChatInput.Height := 56;
  pnlChatInput.BevelOuter := bvNone;
  pnlChatInput.Color := TGRISPColors.BG_PANEL;
  pnlChatInput.ParentBackground := False;

  edtChat := TEdit.Create(Self);
  edtChat.Parent := pnlChatInput;
  edtChat.Left := 48;
  edtChat.Top := 12;
  edtChat.Width := pnlChatInput.Width - 120;
  edtChat.Anchors := [akLeft, akTop, akRight, akBottom];
  edtChat.Height := 32;
  edtChat.TextHint := 'Type your message...';
  edtChat.Color := TGRISPColors.BG_CARD;
  edtChat.Font.Color := TGRISPColors.TEXT_MAIN;
  edtChat.OnKeyPress := procedure(Sender: TObject; var Key: Char)
    begin
      if Key = #13 then
      begin
        SendChat(Sender);
        Key := #0;
      end;
    end;

  btnSend := TButton.Create(Self);
  btnSend.Parent := pnlChatInput;
  btnSend.Anchors := [akTop, akRight];
  btnSend.Left := pnlChatInput.Width - 56;
  btnSend.Top := 12;
  btnSend.Width := 48;
  btnSend.Height := 32;
  btnSend.Caption := '>';
  btnSend.OnClick := SendChat;

  btnAttach := TSpeedButton.Create(Self);
  btnAttach.Parent := pnlChatInput;
  btnAttach.Left := 8;
  btnAttach.Top := 14;
  btnAttach.Width := 24;
  btnAttach.Height := 24;
  btnAttach.Caption := '@';

  memoChat := TRichEdit.Create(Self);
  memoChat.Parent := pnlCenter;
  memoChat.Align := alClient;
  memoChat.Color := TGRISPColors.BG_DARK;
  memoChat.Font.Color := TGRISPColors.TEXT_MAIN;
  memoChat.Font.Name := 'Segoe UI';
  memoChat.Font.Size := 10;
  memoChat.BorderStyle := bsNone;
  memoChat.ScrollBars := ssVertical;
  memoChat.ReadOnly := True;
end;

procedure TFrmGRISP.BuildRight;
var
  pnlExport: TPanel;
begin
  lblPlanTitle := TLabel.Create(Self);
  lblPlanTitle.Parent := pnlRight;
  lblPlanTitle.Align := alTop;
  lblPlanTitle.Height := 32;
  lblPlanTitle.Caption := ' Plan / Work Items';
  lblPlanTitle.Font.Style := [fsBold];
  lblPlanTitle.Font.Color := TGRISPColors.TEXT_DIM;

  lvPlan := TListView.Create(Self);
  lvPlan.Parent := pnlRight;
  lvPlan.Align := alTop;
  lvPlan.Height := 200;
  lvPlan.ViewStyle := vsReport;
  lvPlan.BorderStyle := bsNone;
  lvPlan.Color := TGRISPColors.BG_PANEL;
  lvPlan.Font.Color := TGRISPColors.TEXT_MAIN;
  lvPlan.Columns.Add.Caption := '#';
  lvPlan.Columns.Add.Caption := 'Task';
  lvPlan.Columns.Add.Caption := 'Status';
  lvPlan.Columns[0].Width := 30;
  lvPlan.Columns[1].Width := 170;
  lvPlan.Columns[2].Width := 100;
  lvPlan.RowSelect := True;

  lvWorkItems := TListView.Create(Self);
  lvWorkItems.Parent := pnlRight;
  lvWorkItems.Align := alClient;
  lvWorkItems.ViewStyle := vsReport;
  lvWorkItems.BorderStyle := bsNone;
  lvWorkItems.Color := TGRISPColors.BG_PANEL;
  lvWorkItems.Font.Color := TGRISPColors.TEXT_MAIN;
  lvWorkItems.Columns.Add.Caption := 'Work Item';
  lvWorkItems.Columns.Add.Caption := 'Prio';
  lvWorkItems.Columns[0].Width := 200;
  lvWorkItems.Columns[1].Width := 60;
  lvWorkItems.RowSelect := True;

  pnlExport := TPanel.Create(Self);
  pnlExport.Parent := pnlRight;
  pnlExport.Align := alBottom;
  pnlExport.Height := 80;
  pnlExport.BevelOuter := bvNone;
  pnlExport.Color := TGRISPColors.BG_PANEL2;
  pnlExport.ParentBackground := False;

  btnExportUnicode := TButton.Create(Self);
  btnExportUnicode.Parent := pnlExport;
  btnExportUnicode.Left := 8;
  btnExportUnicode.Top := 8;
  btnExportUnicode.Width := 100;
  btnExportUnicode.Height := 28;
  btnExportUnicode.Caption := 'Export UNICODE';
  btnExportUnicode.OnClick := procedure(Sender: TObject) begin ExportTerminal(0); end;

  btnExportASCII := TButton.Create(Self);
  btnExportASCII.Parent := pnlExport;
  btnExportASCII.Left := 116;
  btnExportASCII.Top := 8;
  btnExportASCII.Width := 100;
  btnExportASCII.Height := 28;
  btnExportASCII.Caption := 'Export ASCII';
  btnExportASCII.OnClick := procedure(Sender: TObject) begin ExportTerminal(1); end;

  btnExportANSI := TButton.Create(Self);
  btnExportANSI.Parent := pnlExport;
  btnExportANSI.Left := 8;
  btnExportANSI.Top := 40;
  btnExportANSI.Width := 100;
  btnExportANSI.Height := 28;
  btnExportANSI.Caption := 'Export ANSI';
  btnExportANSI.OnClick := procedure(Sender: TObject) begin ExportTerminal(2); end;
end;

procedure TFrmGRISP.BuildFooter;
var
  lbl: TLabel;
begin
  lbl := TLabel.Create(Self);
  lbl.Parent := pnlFooter;
  lbl.Left := 12;
  lbl.Top := 8;
  lbl.Caption := 'ACTIVE: GRISP://Workspace 42.3GB | Delphi 13 Florence | VCL | SEC No Threats';
  lbl.Font.Size := 8;
  lbl.Font.Color := TGRISPColors.TEXT_DIM;
end;

procedure TFrmGRISP.PopulateExplorer;
var
  root, proj, grisp: TTreeNode;
begin
  tvExplorer.Items.Clear;
  root := tvExplorer.Items.Add(nil, 'GRISP [Local]');
  proj := tvExplorer.Items.AddChild(root, 'Projects');
  grisp := tvExplorer.Items.AddChild(proj, 'GRISP R W X Trust:85');
  tvExplorer.Items.AddChild(grisp, 'src R W X');
  tvExplorer.Items.AddChild(grisp, 'tests R W X');
  tvExplorer.Items.AddChild(grisp, 'docs R W X');
  tvExplorer.Items.AddChild(grisp, 'MME-Registry R W X');
  tvExplorer.Items.AddChild(grisp, 'Agent-Network R W X');
  tvExplorer.Items.AddChild(proj, 'Data R W -');
  tvExplorer.Items.AddChild(nil, 'Models R W -');
  tvExplorer.Items.AddChild(nil, 'Agents R W X');
  tvExplorer.Items.AddChild(nil, 'Knowledge R W -');
  tvExplorer.Items.AddChild(nil, 'Tools R W X');
  tvExplorer.Items.AddChild(nil, 'System R W X');
  tvExplorer.Items.AddChild(nil, 'Trash R W -');
  tvExplorer.FullExpand;
end;

procedure TFrmGRISP.PopulateSessions;
begin
  lvSessions.Items.Clear;
  with lvSessions.Items.Add do
  begin
    Caption := 'Project setup and architecture';
    SubItems.Add('Today 14:12');
  end;
  with lvSessions.Items.Add do
  begin
    Caption := 'Data model discussion';
    SubItems.Add('Today 11:45');
  end;
  with lvSessions.Items.Add do
  begin
    Caption := 'Bug investigation';
    SubItems.Add('21 Sep 16:20');
  end;
  with lvSessions.Items.Add do
  begin
    Caption := 'Feature planning';
    SubItems.Add('20 Sep 10:10');
  end;
  if lvSessions.Items.Count > 0 then
    lvSessions.Items[0].Selected := True;
end;

procedure TFrmGRISP.PopulatePlan;
begin
  lvPlan.Items.Clear;
  with lvPlan.Items.Add do begin Caption := '1'; SubItems.Add('Analyze architecture'); SubItems.Add('Completed'); end;
  with lvPlan.Items.Add do begin Caption := '2'; SubItems.Add('Review component details'); SubItems.Add('In progress'); end;
  with lvPlan.Items.Add do begin Caption := '3'; SubItems.Add('Create diagram'); SubItems.Add('Pending'); end;
  with lvPlan.Items.Add do begin Caption := '4'; SubItems.Add('Update documentation'); SubItems.Add('Pending'); end;
end;

procedure TFrmGRISP.PopulateWorkItems;
begin
  lvWorkItems.Items.Clear;
  with lvWorkItems.Items.Add do begin Caption := 'Implement GRISP runtime'; SubItems.Add('High'); end;
  with lvWorkItems.Items.Add do begin Caption := 'Add graph visualization'; SubItems.Add('Medium'); end;
  with lvWorkItems.Items.Add do begin Caption := 'Write unit tests'; SubItems.Add('Medium'); end;
  with lvWorkItems.Items.Add do begin Caption := 'Update LSBP integration'; SubItems.Add('Low'); end;
end;

procedure TFrmGRISP.AddChat(const ARole: TChatRole; const AText, AThinking: string; HasPlan: Boolean);
begin
  if ARole = crUser then
    memoChat.Lines.Add('You: ' + AText + sLineBreak)
  else
  begin
    memoChat.Lines.Add('GRISP Assistant: ' + AText + sLineBreak);
    if AThinking <> '' then
      memoThink.Lines.Text := AThinking;
    if HasPlan then
      memoChat.Lines.Add('[Plan: 4 steps, see right panel]' + sLineBreak);
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
    'Analyzing: ' + txt + sLineBreak + 'Parsed to SIR' + sLineBreak + 'Created plan' + sLineBreak + 'Validated R W X', True);
end;

procedure TFrmGRISP.ToggleLeft(Sender: TObject);
begin
  FLeftCollapsed := not FLeftCollapsed;
  if FLeftCollapsed then
    pnlLeft.Width := 0
  else
    pnlLeft.Width := 300;
end;

procedure TFrmGRISP.ToggleRight(Sender: TObject);
begin
  FRightCollapsed := not FRightCollapsed;
  if FRightCollapsed then
    pnlRight.Width := 0
  else
    pnlRight.Width := 340;
end;

procedure TFrmGRISP.ToggleThink(Sender: TObject);
begin
  FThinkExpanded := not FThinkExpanded;
  if FThinkExpanded then
  begin
    pnlThink.Height := 110;
    memoThink.Visible := True;
    btnToggleThink.Caption := 'V';
  end
  else
  begin
    pnlThink.Height := 32;
    memoThink.Visible := False;
    btnToggleThink.Caption := '^';
  end;
end;

procedure TFrmGRISP.ToggleTerminal(Sender: TObject);
begin
  FTerminalMode := not FTerminalMode;
  memoTerminal.Visible := FTerminalMode;
  memoChat.Visible := not FTerminalMode;
  pnlThink.Visible := not FTerminalMode;
  if FTerminalMode then
    memoTerminal.Text := TGRISPTerminal.GenerateUnicode;
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
  if Assigned(Node) then
    lblChatTitle.Caption := 'GRISP://' + Node.Text;
end;

procedure TFrmGRISP.SessionClick(Sender: TObject);
begin
  if (lvSessions.Selected <> nil) then
    lblChatTitle.Caption := lvSessions.Selected.Caption;
end;

procedure TFrmGRISP.FormResize(Sender: TObject);
begin
  if Assigned(lblAgent) then
  begin
    lblAgent.Left := pnlHeader.Width - 300;
    lblTime.Left := pnlHeader.Width - 140;
  end;
  if Assigned(btnToggleRight) then
    btnToggleRight.Left := pnlHeader.Width - 40;
  if Assigned(btnToggleThink) then
    btnToggleThink.Left := pnlThink.Width - 40;
  if Assigned(btnSend) then
    btnSend.Left := pnlChatInput.Width - 56;
  if Assigned(edtChat) then
    edtChat.Width := pnlChatInput.Width - 120;
end;

end.
