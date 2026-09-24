unit UnitMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.ComCtrls,
  Vcl.StdCtrls, Vcl.Buttons;

const
  // Dark Slate Palette ($00BBGGRR format matching GRISP AI Runtime UI)
  CLR_BG_DARK       = $001D100B; // #0B101D Main dark background
  CLR_PANEL_BG      = $00271B12; // #121B27 Secondary panel / card background
  CLR_PANEL_ACTIVE  = $00452E1B; // #1B2E45 Selected item highlight
  CLR_BORDER        = $003D2B1C; // #1C2B3D Subtle card border
  CLR_BORDER_BLUE   = $00E0821B; // #1B82E0 Blue highlight border

  CLR_ACCENT_BLUE   = $00F2A138; // #38A1F2 Primary Blue Text / Buttons
  CLR_ACCENT_CYAN   = $00C0E500; // #00E5C0 Permissions Teal
  CLR_TEXT_PRIMARY  = $00F0EAE6; // #E6EAF0 Bright text
  CLR_TEXT_MUTED    = $00A59183; // #8391A5 Muted gray text
  CLR_TEXT_DIM      = $0063544B; // #4B5463 Dark gray

  CLR_STATUS_GREEN  = $0063C738; // #38C763 Completed / Ready
  CLR_BADGE_HIGH    = $0038208A; // #8A2038 High priority (Red)
  CLR_BADGE_MED     = $001A60B8; // #B8601A Medium priority (Orange)
  CLR_BADGE_LOW     = $00704818; // #184870 Low priority (Blue)

  FONT_MAIN         = 'Segoe UI';
  FONT_CODE         = 'Consolas';

type
  // Afgerond paneel voor kaarten en secties
  TCustomCardPanel = class(TPanel)
  private
    FBorderColor: TColor;
    FCornerRadius: Integer;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    property BorderColor: TColor read FBorderColor write FBorderColor;
    property CornerRadius: Integer read FCornerRadius write FCornerRadius;
  end;

  TFormMain = class(TForm)
    procedure FormCreate(Sender: TObject);
  private
    // Top Navigation Bar
    pnlTopNav: TPanel;
    lblLogo: TLabel;
    lblSubTitle: TLabel;
    btnTabChat: TSpeedButton;
    btnTabWorkflows: TSpeedButton;
    btnTabKnowledge: TSpeedButton;
    lblAgentStatus: TLabel;
    lblClock: TLabel;

    // Main Columns
    pnlLeftSidebar: TPanel;
    splLeft: TSplitter;
    pnlRightSidebar: TPanel;
    splRight: TSplitter;
    pnlMainChat: TPanel;

    // Left Column: Explorer & Sessions
    pnlExplorerHeader: TPanel;
    lblExplorerTitle: TLabel;
    edtSearch: TEdit;
    tvExplorer: TTreeView;

    pnlSessionsHeader: TPanel;
    lblSessionsTitle: TLabel;
    lbSessions: TListBox;

    // Center Column: Workspace Chat
    pnlChatHeader: TPanel;
    lblChatHeaderTitle: TLabel;
    lblChatHeaderTime: TLabel;

    sbChat: TScrollBox;
    memoChatContent: TMemo;

    pnlThinkingCard: TCustomCardPanel;
    lblThinkingHeader: TLabel;
    lblThinkingDetails: TLabel;
    btnToggleThinking: TSpeedButton;

    pnlActionButtons: TPanel;
    btnDiagram: TButton;
    btnExplain: TButton;
    btnMore: TButton;

    pnlChatInputBar: TCustomCardPanel;
    lblInputPrompt: TLabel;
    edtChatInput: TEdit;
    btnSendMsg: TSpeedButton;

    // Right Column: Plan & Work Items
    pnlPlanCard: TCustomCardPanel;
    lblPlanTitle: TLabel;
    lbPlanItems: TListBox;

    pnlWorkItemsCard: TCustomCardPanel;
    lblWorkItemsTitle: TLabel;
    lbWorkItems: TListBox;

    procedure SetupTheme;
    procedure BuildUI;
    procedure PopulateData;
    procedure SendChatMessage;
    procedure OnChatKeyPress(Sender: TObject; var Key: Char);
    procedure OnSendClick(Sender: TObject);
    procedure OnThinkingToggleClick(Sender: TObject);
  public
  end;

var
  FormMain: TFormMain;

implementation

{$R *.dfm}

{ TCustomCardPanel }

constructor TCustomCardPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBorderColor := CLR_BORDER;
  FCornerRadius := 6;
  BevelOuter := bvNone;
  Color := CLR_PANEL_BG;
  ParentBackground := False;
end;

procedure TCustomCardPanel.Paint;
var
  R: TRect;
begin
  Canvas.Brush.Color := Self.Color;
  Canvas.Brush.Style := bsSolid;
  Canvas.Pen.Color := FBorderColor;
  Canvas.Pen.Width := 1;

  R := ClientRect;
  if FCornerRadius > 0 then
    Canvas.RoundRect(R.Left, R.Top, R.Right - 1, R.Bottom - 1, FCornerRadius, FCornerRadius)
  else
    Canvas.Rectangle(R);
end;

{ TFormMain }

procedure TFormMain.FormCreate(Sender: TObject);
begin
  SetupTheme;
  BuildUI;
  PopulateData;
end;

procedure TFormMain.SetupTheme;
begin
  Self.Caption := 'GRISP - Deterministic AI Runtime';
  Self.Width := 1300;
  Self.Height := 820;
  Self.Position := poScreenCenter;
  Self.Color := CLR_BG_DARK;
  Self.Font.Name := FONT_MAIN;
  Self.Font.Size := 9;
  Self.DoubleBuffered := True;
end;

procedure TFormMain.BuildUI;
begin
  // ==========================================
  // 1. TOP NAVIGATION BAR
  // ==========================================
  pnlTopNav := TPanel.Create(Self);
  pnlTopNav.Parent := Self;
  pnlTopNav.Align := alTop;
  pnlTopNav.Height := 48;
  pnlTopNav.Color := CLR_BG_DARK;
  pnlTopNav.ParentBackground := False;
  pnlTopNav.BevelOuter := bvNone;

  lblLogo := TLabel.Create(pnlTopNav);
  lblLogo.Parent := pnlTopNav;
  lblLogo.Align := alLeft;
  lblLogo.Caption := ' ❖  GRISP ';
  lblLogo.Font.Name := FONT_MAIN;
  lblLogo.Font.Size := 12;
  lblLogo.Font.Style := [fsBold];
  lblLogo.Font.Color := CLR_TEXT_PRIMARY;
  lblLogo.Layout := tlCenter;

  lblSubTitle := TLabel.Create(pnlTopNav);
  lblSubTitle.Parent := pnlTopNav;
  lblSubTitle.Align := alLeft;
  lblSubTitle.Caption := 'Deterministic AI Runtime   ';
  lblSubTitle.Font.Name := FONT_MAIN;
  lblSubTitle.Font.Size := 8;
  lblSubTitle.Font.Color := CLR_TEXT_MUTED;
  lblSubTitle.Layout := tlCenter;

  // Tabs
  btnTabChat := TSpeedButton.Create(pnlTopNav);
  btnTabChat.Parent := pnlTopNav;
  btnTabChat.Align := alLeft;
  btnTabChat.Width := 80;
  btnTabChat.Caption := '💬 Chat';
  btnTabChat.Flat := True;
  btnTabChat.Font.Color := CLR_ACCENT_BLUE;

  btnTabWorkflows := TSpeedButton.Create(pnlTopNav);
  btnTabWorkflows.Parent := pnlTopNav;
  btnTabWorkflows.Align := alLeft;
  btnTabWorkflows.Width := 90;
  btnTabWorkflows.Caption := '⚙ Workflows';
  btnTabWorkflows.Flat := True;
  btnTabWorkflows.Font.Color := CLR_TEXT_MUTED;

  btnTabKnowledge := TSpeedButton.Create(pnlTopNav);
  btnTabKnowledge.Parent := pnlTopNav;
  btnTabKnowledge.Align := alLeft;
  btnTabKnowledge.Width := 90;
  btnTabKnowledge.Caption := '📖 Knowledge';
  btnTabKnowledge.Flat := True;
  btnTabKnowledge.Font.Color := CLR_TEXT_MUTED;

  // Top Right Info
  lblClock := TLabel.Create(pnlTopNav);
  lblClock.Parent := pnlTopNav;
  lblClock.Align := alRight;
  lblClock.Caption := '14:32  22 Sep 2026   ';
  lblClock.Font.Color := CLR_TEXT_MUTED;
  lblClock.Layout := tlCenter;

  lblAgentStatus := TLabel.Create(pnlTopNav);
  lblAgentStatus.Parent := pnlTopNav;
  lblAgentStatus.Align := alRight;
  lblAgentStatus.Caption := '● Agent: Alex Ready     ';
  lblAgentStatus.Font.Color := CLR_STATUS_GREEN;
  lblAgentStatus.Font.Style := [fsBold];
  lblAgentStatus.Layout := tlCenter;


  // ==========================================
  // 2. LEFT SIDEBAR (Explorer & Sessions)
  // ==========================================
  pnlLeftSidebar := TPanel.Create(Self);
  pnlLeftSidebar.Parent := Self;
  pnlLeftSidebar.Align := alLeft;
  pnlLeftSidebar.Width := 250;
  pnlLeftSidebar.Color := CLR_BG_DARK;
  pnlLeftSidebar.ParentBackground := False;
  pnlLeftSidebar.BevelOuter := bvNone;

  splLeft := TSplitter.Create(Self);
  splLeft.Parent := Self;
  splLeft.Align := alLeft;
  splLeft.Width := 2;
  splLeft.Color := CLR_BORDER;

  // Explorer Header
  pnlExplorerHeader := TPanel.Create(pnlLeftSidebar);
  pnlExplorerHeader.Parent := pnlLeftSidebar;
  pnlExplorerHeader.Align := alTop;
  pnlExplorerHeader.Height := 32;
  pnlExplorerHeader.Color := CLR_BG_DARK;
  pnlExplorerHeader.BevelOuter := bvNone;

  lblExplorerTitle := TLabel.Create(pnlExplorerHeader);
  lblExplorerTitle.Parent := pnlExplorerHeader;
  lblExplorerTitle.Align := alLeft;
  lblExplorerTitle.Caption := ' 📂 Explorer';
  lblExplorerTitle.Font.Style := [fsBold];
  lblExplorerTitle.Font.Color := CLR_TEXT_PRIMARY;
  lblExplorerTitle.Layout := tlCenter;

  edtSearch := TEdit.Create(pnlLeftSidebar);
  edtSearch.Parent := pnlLeftSidebar;
  edtSearch.Align := alTop;
  edtSearch.Text := '🔍 Search resources...';
  edtSearch.Color := CLR_PANEL_BG;
  edtSearch.Font.Color := CLR_TEXT_MUTED;
  edtSearch.BorderStyle := bsNone;

  tvExplorer := TTreeView.Create(pnlLeftSidebar);
  tvExplorer.Parent := pnlLeftSidebar;
  tvExplorer.Align := alTop;
  tvExplorer.Height := 350;
  tvExplorer.Color := CLR_BG_DARK;
  tvExplorer.Font.Name := FONT_CODE;
  tvExplorer.Font.Color := CLR_TEXT_PRIMARY;
  tvExplorer.BorderStyle := bsNone;
  tvExplorer.ReadOnly := True;

  // Sessions Header
  pnlSessionsHeader := TPanel.Create(pnlLeftSidebar);
  pnlSessionsHeader.Parent := pnlLeftSidebar;
  pnlSessionsHeader.Align := alTop;
  pnlSessionsHeader.Height := 30;
  pnlSessionsHeader.Color := CLR_BG_DARK;
  pnlSessionsHeader.BevelOuter := bvNone;

  lblSessionsTitle := TLabel.Create(pnlSessionsHeader);
  lblSessionsTitle.Parent := pnlSessionsHeader;
  lblSessionsTitle.Align := alLeft;
  lblSessionsTitle.Caption := ' 💬 Sessions';
  lblSessionsTitle.Font.Style := [fsBold];
  lblSessionsTitle.Font.Color := CLR_TEXT_PRIMARY;
  lblSessionsTitle.Layout := tlCenter;

  lbSessions := TListBox.Create(pnlLeftSidebar);
  lbSessions.Parent := pnlLeftSidebar;
  lbSessions.Align := alClient;
  lbSessions.Color := CLR_BG_DARK;
  lbSessions.Font.Color := CLR_TEXT_PRIMARY;
  lbSessions.BorderStyle := bsNone;


  // ==========================================
  // 3. RIGHT SIDEBAR (Plan & Work Items)
  // ==========================================
  pnlRightSidebar := TPanel.Create(Self);
  pnlRightSidebar.Parent := Self;
  pnlRightSidebar.Align := alRight;
  pnlRightSidebar.Width := 280;
  pnlRightSidebar.Color := CLR_BG_DARK;
  pnlRightSidebar.ParentBackground := False;
  pnlRightSidebar.BevelOuter := bvNone;
  pnlRightSidebar.Padding.Left := 8;
  pnlRightSidebar.Padding.Right := 8;
  pnlRightSidebar.Padding.Top := 8;

  splRight := TSplitter.Create(Self);
  splRight.Parent := Self;
  splRight.Align := alRight;
  splRight.Width := 2;
  splRight.Color := CLR_BORDER;

  // Current Plan Card
  pnlPlanCard := TCustomCardPanel.Create(pnlRightSidebar);
  pnlPlanCard.Parent := pnlRightSidebar;
  pnlPlanCard.Align := alTop;
  pnlPlanCard.Height := 200;
  pnlPlanCard.Padding.Left := 10;
  pnlPlanCard.Padding.Top := 8;

  lblPlanTitle := TLabel.Create(pnlPlanCard);
  lblPlanTitle.Parent := pnlPlanCard;
  lblPlanTitle.Align := alTop;
  lblPlanTitle.Caption := 'Current Plan';
  lblPlanTitle.Font.Style := [fsBold];
  lblPlanTitle.Font.Color := CLR_ACCENT_BLUE;

  lbPlanItems := TListBox.Create(pnlPlanCard);
  lbPlanItems.Parent := pnlPlanCard;
  lbPlanItems.Align := alClient;
  lbPlanItems.Color := CLR_PANEL_BG;
  lbPlanItems.Font.Color := CLR_TEXT_PRIMARY;
  lbPlanItems.BorderStyle := bsNone;

  // Work Items Card
  pnlWorkItemsCard := TCustomCardPanel.Create(pnlRightSidebar);
  pnlWorkItemsCard.Parent := pnlRightSidebar;
  pnlWorkItemsCard.Align := alTop;
  pnlWorkItemsCard.Height := 220;
  pnlWorkItemsCard.Padding.Left := 10;
  pnlWorkItemsCard.Padding.Top := 8;

  lblWorkItemsTitle := TLabel.Create(pnlWorkItemsCard);
  lblWorkItemsTitle.Parent := pnlWorkItemsCard;
  lblWorkItemsTitle.Align := alTop;
  lblWorkItemsTitle.Caption := 'Work Items';
  lblWorkItemsTitle.Font.Style := [fsBold];
  lblWorkItemsTitle.Font.Color := CLR_ACCENT_BLUE;

  lbWorkItems := TListBox.Create(pnlWorkItemsCard);
  lbWorkItems.Parent := pnlWorkItemsCard;
  lbWorkItems.Align := alClient;
  lbWorkItems.Color := CLR_PANEL_BG;
  lbWorkItems.Font.Color := CLR_TEXT_PRIMARY;
  lbWorkItems.BorderStyle := bsNone;


  // ==========================================
  // 4. CENTER WORKSPACE (Main AI Chat)
  // ==========================================
  pnlMainChat := TPanel.Create(Self);
  pnlMainChat.Parent := Self;
  pnlMainChat.Align := alClient;
  pnlMainChat.Color := CLR_BG_DARK;
  pnlMainChat.ParentBackground := False;
  pnlMainChat.BevelOuter := bvNone;
  pnlMainChat.Padding.Left := 12;
  pnlMainChat.Padding.Right := 12;
  pnlMainChat.Padding.Bottom := 12;

  // Workspace Header Tab
  pnlChatHeader := TPanel.Create(pnlMainChat);
  pnlChatHeader.Parent := pnlMainChat;
  pnlChatHeader.Align := alTop;
  pnlChatHeader.Height := 32;
  pnlChatHeader.Color := CLR_BG_DARK;
  pnlChatHeader.BevelOuter := bvNone;

  lblChatHeaderTitle := TLabel.Create(pnlChatHeader);
  lblChatHeaderTitle.Parent := pnlChatHeader;
  lblChatHeaderTitle.Align := alLeft;
  lblChatHeaderTitle.Caption := ' 🗁 Project setup and architecture';
  lblChatHeaderTitle.Font.Style := [fsBold];
  lblChatHeaderTitle.Font.Color := CLR_ACCENT_BLUE;
  lblChatHeaderTitle.Layout := tlCenter;

  lblChatHeaderTime := TLabel.Create(pnlChatHeader);
  lblChatHeaderTime.Parent := pnlChatHeader;
  lblChatHeaderTime.Align := alRight;
  lblChatHeaderTime.Caption := '22 Sep 2026 14:12 ';
  lblChatHeaderTime.Font.Color := CLR_TEXT_MUTED;
  lblChatHeaderTime.Layout := tlCenter;

  // Chat Input Bar (Bottom) - GEEN POPUP MEER!
  pnlChatInputBar := TCustomCardPanel.Create(pnlMainChat);
  pnlChatInputBar.Parent := pnlMainChat;
  pnlChatInputBar.Align := alBottom;
  pnlChatInputBar.Height := 48;
  pnlChatInputBar.BorderColor := CLR_BORDER_BLUE;
  pnlChatInputBar.Padding.Left := 12;
  pnlChatInputBar.Padding.Right := 8;

  lblInputPrompt := TLabel.Create(pnlChatInputBar);
  lblInputPrompt.Parent := pnlChatInputBar;
  lblInputPrompt.Align := alLeft;
  lblInputPrompt.Caption := '📎  </>   ';
  lblInputPrompt.Font.Color := CLR_TEXT_MUTED;
  lblInputPrompt.Layout := tlCenter;

  btnSendMsg := TSpeedButton.Create(pnlChatInputBar);
  btnSendMsg.Parent := pnlChatInputBar;
  btnSendMsg.Align := alRight;
  btnSendMsg.Width := 40;
  btnSendMsg.Caption := '➤';
  btnSendMsg.Flat := True;
  btnSendMsg.Font.Size := 12;
  btnSendMsg.Font.Color := CLR_ACCENT_BLUE;
  btnSendMsg.OnClick := OnSendClick;

  edtChatInput := TEdit.Create(pnlChatInputBar);
  edtChatInput.Parent := pnlChatInputBar;
  edtChatInput.Align := alClient;
  edtChatInput.Text := 'Type your message...';
  edtChatInput.Color := CLR_PANEL_BG;
  edtChatInput.Font.Color := CLR_TEXT_PRIMARY;
  edtChatInput.BorderStyle := bsNone;
  edtChatInput.OnKeyPress := OnChatKeyPress;

  // Scrollable Chat Area
  sbChat := TScrollBox.Create(pnlMainChat);
  sbChat.Parent := pnlMainChat;
  sbChat.Align := alClient;
  sbChat.Color := CLR_BG_DARK;
  sbChat.BorderStyle := bsNone;

  // Dynamic Chat Content Memo
  memoChatContent := TMemo.Create(sbChat);
  memoChatContent.Parent := sbChat;
  memoChatContent.Align := alTop;
  memoChatContent.Height := 380;
  memoChatContent.Color := CLR_BG_DARK;
  memoChatContent.Font.Name := FONT_MAIN;
  memoChatContent.Font.Size := 9;
  memoChatContent.Font.Color := CLR_TEXT_PRIMARY;
  memoChatContent.BorderStyle := bsNone;
  memoChatContent.ReadOnly := True;

  // Action Buttons Bar
  pnlActionButtons := TPanel.Create(sbChat);
  pnlActionButtons.Parent := sbChat;
  pnlActionButtons.Align := alTop;
  pnlActionButtons.Height := 36;
  pnlActionButtons.Color := CLR_BG_DARK;
  pnlActionButtons.BevelOuter := bvNone;

  btnDiagram := TButton.Create(pnlActionButtons);
  btnDiagram.Parent := pnlActionButtons;
  btnDiagram.Align := alLeft;
  btnDiagram.Width := 170;
  btnDiagram.Caption := 'Show Architecture Diagram';

  btnExplain := TButton.Create(pnlActionButtons);
  btnExplain.Parent := pnlActionButtons;
  btnExplain.Align := alLeft;
  btnExplain.Width := 150;
  btnExplain.Caption := 'Explain a Component';

  btnMore := TButton.Create(pnlActionButtons);
  btnMore.Parent := pnlActionButtons;
  btnMore.Align := alLeft;
  btnMore.Width := 110;
  btnMore.Caption := '... More Details';

  // Thinking Process Card
  pnlThinkingCard := TCustomCardPanel.Create(sbChat);
  pnlThinkingCard.Parent := sbChat;
  pnlThinkingCard.Align := alTop;
  pnlThinkingCard.Height := 100;
  pnlThinkingCard.Padding.Left := 12;
  pnlThinkingCard.Padding.Top := 8;

  lblThinkingHeader := TLabel.Create(pnlThinkingCard);
  lblThinkingHeader.Parent := pnlThinkingCard;
  lblThinkingHeader.Align := alTop;
  lblThinkingHeader.Caption := '🧠 Thinking Process';
  lblThinkingHeader.Font.Style := [fsBold];
  lblThinkingHeader.Font.Color := CLR_ACCENT_BLUE;

  btnToggleThinking := TSpeedButton.Create(pnlThinkingCard);
  btnToggleThinking.Parent := pnlThinkingCard;
  btnToggleThinking.Align := alRight;
  btnToggleThinking.Width := 60;
  btnToggleThinking.Caption := '14:12  ▼';
  btnToggleThinking.Flat := True;
  btnToggleThinking.Font.Color := CLR_TEXT_MUTED;
  btnToggleThinking.OnClick := OnThinkingToggleClick;

  lblThinkingDetails := TLabel.Create(pnlThinkingCard);
  lblThinkingDetails.Parent := pnlThinkingCard;
  lblThinkingDetails.Align := alClient;
  lblThinkingDetails.Caption :=
    '✓ Analyzing GRISP architecture from documentation...' + #13#10 +
    '✓ Identified 7 main components and their relationships...' + #13#10 +
    '✓ Preparing structured explanation...';
  lblThinkingDetails.Font.Color := CLR_TEXT_MUTED;
end;

procedure TFormMain.PopulateData;
var
  RootNode, SubNode: TTreeNode;
begin
  // 1. Explorer TreeView
  tvExplorer.Items.Clear;
  RootNode := tvExplorer.Items.Add(nil, '▼ GRISP');
  SubNode  := tvExplorer.Items.AddChild(RootNode, ' ▼ Local');
  SubNode  := tvExplorer.Items.AddChild(SubNode, '  ▼ Projects     W -');
  SubNode  := tvExplorer.Items.AddChild(SubNode, '   ▼ GRISP');
  tvExplorer.Items.AddChild(SubNode, '     src        R W X');
  tvExplorer.Items.AddChild(SubNode, '     tests      R W X');
  tvExplorer.Items.AddChild(SubNode, '     docs       R W X');
  tvExplorer.FullExpand;

  // 2. Sessions ListBox
  lbSessions.Items.Clear;
  lbSessions.Items.Add(' 💬 Project setup and architecture');
  lbSessions.Items.Add('    22 Sep 2026 14:12');
  lbSessions.Items.Add(' 💬 Data model discussion');
  lbSessions.Items.Add('    22 Sep 2026 11:45');
  lbSessions.Items.Add(' 💬 Bug investigation');
  lbSessions.Items.Add('    21 Sep 2026 16:20');
  lbSessions.ItemIndex := 0;

  // 3. Plan ListBox
  lbPlanItems.Items.Clear;
  lbPlanItems.Items.Add('1.  ✓  Analyze architecture (Completed)');
  lbPlanItems.Items.Add('2.  ⚙  Review component details (In progress)');
  lbPlanItems.Items.Add('3.  ○  Create diagram (Pending)');
  lbPlanItems.Items.Add('4.  ○  Update documentation (Pending)');

  // 4. Work Items ListBox
  lbWorkItems.Items.Clear;
  lbWorkItems.Items.Add('Implement GRISP runtime      [ HIGH ]');
  lbWorkItems.Items.Add('Add graph visualization      [ MEDIUM ]');
  lbWorkItems.Items.Add('Write unit tests             [ MEDIUM ]');
  lbWorkItems.Items.Add('Update LSBP integration      [ LOW ]');

  // 5. Initial Chat Content
  memoChatContent.Lines.Clear;
  memoChatContent.Lines.Add('👤 You  14:12');
  memoChatContent.Lines.Add('Can you help me analyze the GRISP architecture and explain the main components and how they work together?');
  memoChatContent.Lines.Add('');
  memoChatContent.Lines.Add('❖ GRISP Assistant  14:12');
  memoChatContent.Lines.Add('Sure! The GRISP architecture is designed around a deterministic, graph-based execution model. Here are the main components and how they work together:');
  memoChatContent.Lines.Add('');
  memoChatContent.Lines.Add('1. SIR (Source Intermediate Representation)');
  memoChatContent.Lines.Add('   Parses and validates the input, converting it to a structured representation.');
  memoChatContent.Lines.Add('2. Planner');
  memoChatContent.Lines.Add('   Analyzes the SIR and creates an execution plan with ordered steps.');
  memoChatContent.Lines.Add('3. Evaluator');
  memoChatContent.Lines.Add('   Executes the plan, performing graph operations and rule evaluation.');
  memoChatContent.Lines.Add('4. Validator');
  memoChatContent.Lines.Add('   Ensures correctness, security and compliance with constraints.');
  memoChatContent.Lines.Add('5. EIR (Execution Intermediate Representation)');
  memoChatContent.Lines.Add('   Optimized form for the GRISP runtime.');
  memoChatContent.Lines.Add('6. GRISP Runtime');
  memoChatContent.Lines.Add('   Executes the EIR in a deterministic graph environment.');
  memoChatContent.Lines.Add('7. LSBP / WorldState');
  memoChatContent.Lines.Add('   Manages state, persistence and external integrations.');
  memoChatContent.Lines.Add('');
  memoChatContent.Lines.Add('Would you like me to show you a visual diagram of the architecture or focus on a specific component?');
end;

// RECHTSTREEKSE CHAT AFHANDELING ZONDER POP-UP DIALOG
procedure TFormMain.SendChatMessage;
var
  Txt: string;
begin
  Txt := Trim(edtChatInput.Text);
  if (Txt = '') or (Txt = 'Type your message...') then Exit;

  memoChatContent.Lines.Add('');
  memoChatContent.Lines.Add('👤 You  ' + FormatDateTime('hh:nn', Now));
  memoChatContent.Lines.Add(Txt);
  memoChatContent.Lines.Add('');
  memoChatContent.Lines.Add('❖ GRISP Assistant  ' + FormatDateTime('hh:nn', Now));
  memoChatContent.Lines.Add('Verwerkt in runtime context...');

  edtChatInput.Clear;
end;

procedure TFormMain.OnChatKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then
  begin
    Key := #0; // Voorkom Windows pieptoon
    SendChatMessage;
  end;
end;

procedure TFormMain.OnSendClick(Sender: TObject);
begin
  SendChatMessage;
end;

procedure TFormMain.OnThinkingToggleClick(Sender: TObject);
begin
  if pnlThinkingCard.Height = 100 then
  begin
    pnlThinkingCard.Height := 32;
    lblThinkingDetails.Visible := False;
    btnToggleThinking.Caption := '14:12  ▲';
  end
  else
  begin
    pnlThinkingCard.Height := 100;
    lblThinkingDetails.Visible := True;
    btnToggleThinking.Caption := '14:12  ▼';
  end;
end;

end.
