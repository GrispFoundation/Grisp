unit UnitMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.ComCtrls,
  Vcl.StdCtrls, Vcl.Buttons;

const
  // Dark Slate Palette
  CLR_BG_DARK       = $001D100B; // #0B101D Main background
  CLR_PANEL_BG      = $00271B12; // #121B27 Card background
  CLR_PANEL_ACTIVE  = $00452E1B; // #1B2E45 Active tab / selection
  CLR_BORDER        = $003D2B1C; // #1C2B3D Card border
  CLR_BORDER_BLUE   = $00E0821B; // #1B82E0 Active focus border

  CLR_ACCENT_BLUE   = $00F2A138; // #38A1F2 Primary Accent Blue
  CLR_TEXT_PRIMARY  = $00F0EAE6; // #E6EAF0 Bright text
  CLR_TEXT_MUTED    = $00A59183; // #8391A5 Muted text
  CLR_STATUS_GREEN  = $0063C738; // #38C763 Green status

  FONT_MAIN         = 'Segoe UI';
  FONT_CODE         = 'Consolas';

type
  // Afgerond paneel met instelbare randen en binnenmarges
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
    // Top Navigation
    pnlTopNav: TPanel;
    lblLogo: TLabel;
    lblSubTitle: TLabel;
    pnlTabsContainer: TPanel;
    btnTabChat: TSpeedButton;
    btnTabWorkflows: TSpeedButton;
    btnTabKnowledge: TSpeedButton;
    pnlTopRightInfo: TPanel;
    lblAgentStatus: TLabel;
    lblClock: TLabel;

    // Layout Columns
    pnlLeftSidebar: TPanel;
    splLeft: TSplitter;
    pnlRightSidebar: TPanel;
    splRight: TSplitter;
    pnlMainChat: TPanel;

    // Left Column
    pnlExplorerBox: TPanel;
    lblExplorerTitle: TLabel;
    pnlSearchBox: TCustomCardPanel;
    edtSearch: TEdit;
    tvExplorer: TTreeView;

    pnlSessionsBox: TPanel;
    lblSessionsTitle: TLabel;
    lbSessions: TListBox;

    // Center Workspace
    pnlChatHeader: TPanel;
    lblChatHeaderTitle: TLabel;
    lblChatHeaderTime: TLabel;

    memoChatContent: TMemo;

    pnlActionButtons: TPanel;
    btnDiagram: TButton;
    btnExplain: TButton;
    btnMore: TButton;

    pnlThinkingCard: TCustomCardPanel;
    lblThinkingHeader: TLabel;
    lblThinkingDetails: TLabel;
    btnToggleThinking: TSpeedButton;

    pnlChatInputBar: TCustomCardPanel;
    lblInputPrompt: TLabel;
    edtChatInput: TEdit;
    btnSendMsg: TSpeedButton;

    // Right Column
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
  FCornerRadius := 8;
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
  Self.Width := 1440;
  Self.Height := 900;
  Self.Position := poScreenCenter;
  Self.Color := CLR_BG_DARK;
  Self.Font.Name := FONT_MAIN;
  Self.Font.Size := 9;
  Self.DoubleBuffered := True;
end;

procedure TFormMain.BuildUI;
begin
  // ==========================================
  // 1. TOP NAVIGATION BAR (Ruimer & ruimere tabs)
  // ==========================================
  pnlTopNav := TPanel.Create(Self);
  pnlTopNav.Parent := Self;
  pnlTopNav.Align := alTop;
  pnlTopNav.Height := 56;
  pnlTopNav.Color := CLR_BG_DARK;
  pnlTopNav.ParentBackground := False;
  pnlTopNav.BevelOuter := bvNone;

  lblLogo := TLabel.Create(pnlTopNav);
  lblLogo.Parent := pnlTopNav;
  lblLogo.Align := alLeft;
  lblLogo.Caption := '  ❖ GRISP ';
  lblLogo.Font.Name := FONT_MAIN;
  lblLogo.Font.Size := 12;
  lblLogo.Font.Style := [fsBold];
  lblLogo.Font.Color := CLR_TEXT_PRIMARY;
  lblLogo.Layout := tlCenter;

  lblSubTitle := TLabel.Create(pnlTopNav);
  lblSubTitle.Parent := pnlTopNav;
  lblSubTitle.Align := alLeft;
  lblSubTitle.Caption := 'Deterministic AI Runtime   │   ';
  lblSubTitle.Font.Name := FONT_MAIN;
  lblSubTitle.Font.Size := 9;
  lblSubTitle.Font.Color := CLR_TEXT_MUTED;
  lblSubTitle.Layout := tlCenter;

  // Tabs Container met duidelijke tussenruimtes
  pnlTabsContainer := TPanel.Create(pnlTopNav);
  pnlTabsContainer.Parent := pnlTopNav;
  pnlTabsContainer.Align := alLeft;
  pnlTabsContainer.Width := 380;
  pnlTabsContainer.BevelOuter := bvNone;
  pnlTabsContainer.Color := CLR_BG_DARK;

  btnTabChat := TSpeedButton.Create(pnlTabsContainer);
  btnTabChat.Parent := pnlTabsContainer;
  btnTabChat.Align := alLeft;
  btnTabChat.Width := 100;
  btnTabChat.Caption := '💬 Chat';
  btnTabChat.Flat := True;
  btnTabChat.Font.Color := CLR_ACCENT_BLUE;
  btnTabChat.Font.Style := [fsBold];

  btnTabWorkflows := TSpeedButton.Create(pnlTabsContainer);
  btnTabWorkflows.Parent := pnlTabsContainer;
  btnTabWorkflows.Align := alLeft;
  btnTabWorkflows.Width := 125;
  btnTabWorkflows.Caption := '⚙ Workflows';
  btnTabWorkflows.Flat := True;
  btnTabWorkflows.Font.Color := CLR_TEXT_MUTED;

  btnTabKnowledge := TSpeedButton.Create(pnlTabsContainer);
  btnTabKnowledge.Parent := pnlTabsContainer;
  btnTabKnowledge.Align := alLeft;
  btnTabKnowledge.Width := 125;
  btnTabKnowledge.Caption := '📖 Knowledge';
  btnTabKnowledge.Flat := True;
  btnTabKnowledge.Font.Color := CLR_TEXT_MUTED;

  // Top Right Info Panel
  pnlTopRightInfo := TPanel.Create(pnlTopNav);
  pnlTopRightInfo.Parent := pnlTopNav;
  pnlTopRightInfo.Align := alRight;
  pnlTopRightInfo.Width := 340;
  pnlTopRightInfo.BevelOuter := bvNone;
  pnlTopRightInfo.Color := CLR_BG_DARK;

  lblClock := TLabel.Create(pnlTopRightInfo);
  lblClock.Parent := pnlTopRightInfo;
  lblClock.Align := alRight;
  lblClock.Caption := '14:32  22 Sep 2026   ';
  lblClock.Font.Color := CLR_TEXT_MUTED;
  lblClock.Layout := tlCenter;

  lblAgentStatus := TLabel.Create(pnlTopRightInfo);
  lblAgentStatus.Parent := pnlTopRightInfo;
  lblAgentStatus.Align := alRight;
  lblAgentStatus.Caption := '● Agent: Alex Ready  ';
  lblAgentStatus.Font.Color := CLR_STATUS_GREEN;
  lblAgentStatus.Font.Style := [fsBold];
  lblAgentStatus.Layout := tlCenter;


  // ==========================================
  // 2. LEFT SIDEBAR (Verbreed naar 290px)
  // ==========================================
  pnlLeftSidebar := TPanel.Create(Self);
  pnlLeftSidebar.Parent := Self;
  pnlLeftSidebar.Align := alLeft;
  pnlLeftSidebar.Width := 290;
  pnlLeftSidebar.Color := CLR_BG_DARK;
  pnlLeftSidebar.ParentBackground := False;
  pnlLeftSidebar.BevelOuter := bvNone;

  splLeft := TSplitter.Create(Self);
  splLeft.Parent := Self;
  splLeft.Align := alLeft;
  splLeft.Width := 3;
  splLeft.Color := CLR_BORDER;

  // Explorer Box (Bovenkant)
  pnlExplorerBox := TPanel.Create(pnlLeftSidebar);
  pnlExplorerBox.Parent := pnlLeftSidebar;
  pnlExplorerBox.Align := alTop;
  pnlExplorerBox.Height := 420;
  pnlExplorerBox.Color := CLR_BG_DARK;
  pnlExplorerBox.BevelOuter := bvNone;
  pnlExplorerBox.Padding.Left := 10;
  pnlExplorerBox.Padding.Right := 10;

  lblExplorerTitle := TLabel.Create(pnlExplorerBox);
  lblExplorerTitle.Parent := pnlExplorerBox;
  lblExplorerTitle.Align := alTop;
  lblExplorerTitle.Height := 32;
  lblExplorerTitle.Caption := '📂 Explorer';
  lblExplorerTitle.Font.Style := [fsBold];
  lblExplorerTitle.Font.Color := CLR_TEXT_PRIMARY;
  lblExplorerTitle.Layout := tlCenter;

  pnlSearchBox := TCustomCardPanel.Create(pnlExplorerBox);
  pnlSearchBox.Parent := pnlExplorerBox;
  pnlSearchBox.Align := alTop;
  pnlSearchBox.Height := 34;
  pnlSearchBox.AlignWithMargins := True;
  pnlSearchBox.Margins.SetBounds(0, 4, 0, 10);
  pnlSearchBox.Padding.Left := 10;
  pnlSearchBox.Padding.Top := 7;

  edtSearch := TEdit.Create(pnlSearchBox);
  edtSearch.Parent := pnlSearchBox;
  edtSearch.Align := alClient;
  edtSearch.Text := '🔍 Search resources...';
  edtSearch.Color := CLR_PANEL_BG;
  edtSearch.Font.Color := CLR_TEXT_MUTED;
  edtSearch.BorderStyle := bsNone;

  tvExplorer := TTreeView.Create(pnlExplorerBox);
  tvExplorer.Parent := pnlExplorerBox;
  tvExplorer.Align := alClient;
  tvExplorer.Color := CLR_BG_DARK;
  tvExplorer.Font.Name := FONT_CODE;
  tvExplorer.Font.Color := CLR_TEXT_PRIMARY;
  tvExplorer.BorderStyle := bsNone;
  tvExplorer.ReadOnly := True;
  tvExplorer.Indent := 16;

  // Sessions Box (Onderkant)
  pnlSessionsBox := TPanel.Create(pnlLeftSidebar);
  pnlSessionsBox.Parent := pnlLeftSidebar;
  pnlSessionsBox.Align := alClient;
  pnlSessionsBox.Color := CLR_BG_DARK;
  pnlSessionsBox.BevelOuter := bvNone;
  pnlSessionsBox.Padding.Left := 10;
  pnlSessionsBox.Padding.Right := 10;

  lblSessionsTitle := TLabel.Create(pnlSessionsBox);
  lblSessionsTitle.Parent := pnlSessionsBox;
  lblSessionsTitle.Align := alTop;
  lblSessionsTitle.Height := 32;
  lblSessionsTitle.Caption := '💬 Sessions';
  lblSessionsTitle.Font.Style := [fsBold];
  lblSessionsTitle.Font.Color := CLR_TEXT_PRIMARY;
  lblSessionsTitle.Layout := tlCenter;

  lbSessions := TListBox.Create(pnlSessionsBox);
  lbSessions.Parent := pnlSessionsBox;
  lbSessions.Align := alClient;
  lbSessions.Color := CLR_BG_DARK;
  lbSessions.Font.Color := CLR_TEXT_PRIMARY;
  lbSessions.BorderStyle := bsNone;


  // ==========================================
  // 3. RIGHT SIDEBAR (Verbreed naar 350px)
  // ==========================================
  pnlRightSidebar := TPanel.Create(Self);
  pnlRightSidebar.Parent := Self;
  pnlRightSidebar.Align := alRight;
  pnlRightSidebar.Width := 350;
  pnlRightSidebar.Color := CLR_BG_DARK;
  pnlRightSidebar.ParentBackground := False;
  pnlRightSidebar.BevelOuter := bvNone;

  splRight := TSplitter.Create(Self);
  splRight.Parent := Self;
  splRight.Align := alRight;
  splRight.Width := 3;
  splRight.Color := CLR_BORDER;

  // Current Plan Card
  pnlPlanCard := TCustomCardPanel.Create(pnlRightSidebar);
  pnlPlanCard.Parent := pnlRightSidebar;
  pnlPlanCard.Align := alTop;
  pnlPlanCard.Height := 240;
  pnlPlanCard.AlignWithMargins := True;
  pnlPlanCard.Margins.SetBounds(12, 12, 12, 12);
  pnlPlanCard.Padding.Left := 14;
  pnlPlanCard.Padding.Top := 12;
  pnlPlanCard.Padding.Right := 12;

  lblPlanTitle := TLabel.Create(pnlPlanCard);
  lblPlanTitle.Parent := pnlPlanCard;
  lblPlanTitle.Align := alTop;
  lblPlanTitle.Caption := 'Current Plan';
  lblPlanTitle.Font.Style := [fsBold];
  lblPlanTitle.Font.Color := CLR_ACCENT_BLUE;
  lblPlanTitle.Height := 28;

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
  pnlWorkItemsCard.Height := 270;
  pnlWorkItemsCard.AlignWithMargins := True;
  pnlWorkItemsCard.Margins.SetBounds(12, 0, 12, 12);
  pnlWorkItemsCard.Padding.Left := 14;
  pnlWorkItemsCard.Padding.Top := 12;
  pnlWorkItemsCard.Padding.Right := 12;

  lblWorkItemsTitle := TLabel.Create(pnlWorkItemsCard);
  lblWorkItemsTitle.Parent := pnlWorkItemsCard;
  lblWorkItemsTitle.Align := alTop;
  lblWorkItemsTitle.Caption := 'Work Items';
  lblWorkItemsTitle.Font.Style := [fsBold];
  lblWorkItemsTitle.Font.Color := CLR_ACCENT_BLUE;
  lblWorkItemsTitle.Height := 28;

  lbWorkItems := TListBox.Create(pnlWorkItemsCard);
  lbWorkItems.Parent := pnlWorkItemsCard;
  lbWorkItems.Align := alClient;
  lbWorkItems.Color := CLR_PANEL_BG;
  lbWorkItems.Font.Color := CLR_TEXT_PRIMARY;
  lbWorkItems.BorderStyle := bsNone;


  // ==========================================
  // 4. CENTER WORKSPACE (Chat & Input)
  // ==========================================
  pnlMainChat := TPanel.Create(Self);
  pnlMainChat.Parent := Self;
  pnlMainChat.Align := alClient;
  pnlMainChat.Color := CLR_BG_DARK;
  pnlMainChat.ParentBackground := False;
  pnlMainChat.BevelOuter := bvNone;
  pnlMainChat.Padding.Left := 20;
  pnlMainChat.Padding.Right := 20;
  pnlMainChat.Padding.Bottom := 16;

  // Header Tab
  pnlChatHeader := TPanel.Create(pnlMainChat);
  pnlChatHeader.Parent := pnlMainChat;
  pnlChatHeader.Align := alTop;
  pnlChatHeader.Height := 42;
  pnlChatHeader.Color := CLR_BG_DARK;
  pnlChatHeader.BevelOuter := bvNone;

  lblChatHeaderTitle := TLabel.Create(pnlChatHeader);
  lblChatHeaderTitle.Parent := pnlChatHeader;
  lblChatHeaderTitle.Align := alLeft;
  lblChatHeaderTitle.Caption := '🗁 Project setup and architecture';
  lblChatHeaderTitle.Font.Style := [fsBold];
  lblChatHeaderTitle.Font.Size := 10;
  lblChatHeaderTitle.Font.Color := CLR_ACCENT_BLUE;
  lblChatHeaderTitle.Layout := tlCenter;

  lblChatHeaderTime := TLabel.Create(pnlChatHeader);
  lblChatHeaderTime.Parent := pnlChatHeader;
  lblChatHeaderTime.Align := alRight;
  lblChatHeaderTime.Caption := '22 Sep 2026 14:12';
  lblChatHeaderTime.Font.Color := CLR_TEXT_MUTED;
  lblChatHeaderTime.Layout := tlCenter;

  // 4a. Input Bar (Altijd vast onderaan gepositioneerd)
  pnlChatInputBar := TCustomCardPanel.Create(pnlMainChat);
  pnlChatInputBar.Parent := pnlMainChat;
  pnlChatInputBar.Align := alBottom;
  pnlChatInputBar.Height := 52;
  pnlChatInputBar.BorderColor := CLR_BORDER_BLUE;
  pnlChatInputBar.AlignWithMargins := True;
  pnlChatInputBar.Margins.SetBounds(0, 12, 0, 0);
  pnlChatInputBar.Padding.Left := 14;
  pnlChatInputBar.Padding.Right := 10;

  lblInputPrompt := TLabel.Create(pnlChatInputBar);
  lblInputPrompt.Parent := pnlChatInputBar;
  lblInputPrompt.Align := alLeft;
  lblInputPrompt.Caption := '📎   </>   ';
  lblInputPrompt.Font.Color := CLR_TEXT_MUTED;
  lblInputPrompt.Layout := tlCenter;

  btnSendMsg := TSpeedButton.Create(pnlChatInputBar);
  btnSendMsg.Parent := pnlChatInputBar;
  btnSendMsg.Align := alRight;
  btnSendMsg.Width := 48;
  btnSendMsg.Caption := '➤';
  btnSendMsg.Flat := True;
  btnSendMsg.Font.Size := 13;
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

  // 4b. Thinking Card (Direct Boven Input)
  pnlThinkingCard := TCustomCardPanel.Create(pnlMainChat);
  pnlThinkingCard.Parent := pnlMainChat;
  pnlThinkingCard.Align := alBottom;
  pnlThinkingCard.Height := 100;
  pnlThinkingCard.AlignWithMargins := True;
  pnlThinkingCard.Margins.SetBounds(0, 10, 0, 0);
  pnlThinkingCard.Padding.Left := 14;
  pnlThinkingCard.Padding.Top := 10;
  pnlThinkingCard.Padding.Right := 14;

  lblThinkingHeader := TLabel.Create(pnlThinkingCard);
  lblThinkingHeader.Parent := pnlThinkingCard;
  lblThinkingHeader.Align := alTop;
  lblThinkingHeader.Caption := '🧠 Thinking Process';
  lblThinkingHeader.Font.Style := [fsBold];
  lblThinkingHeader.Font.Color := CLR_ACCENT_BLUE;

  btnToggleThinking := TSpeedButton.Create(pnlThinkingCard);
  btnToggleThinking.Parent := pnlThinkingCard;
  btnToggleThinking.Align := alRight;
  btnToggleThinking.Width := 80;
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

  // 4c. Quick Action Buttons (Boven Thinking Card, ruim uitgelijnd)
  pnlActionButtons := TPanel.Create(pnlMainChat);
  pnlActionButtons.Parent := pnlMainChat;
  pnlActionButtons.Align := alBottom;
  pnlActionButtons.Height := 42;
  pnlActionButtons.Color := CLR_BG_DARK;
  pnlActionButtons.BevelOuter := bvNone;

  btnDiagram := TButton.Create(pnlActionButtons);
  btnDiagram.Parent := pnlActionButtons;
  btnDiagram.Align := alLeft;
  btnDiagram.Width := 200;
  btnDiagram.Caption := 'Show Architecture Diagram';

  btnExplain := TButton.Create(pnlActionButtons);
  btnExplain.Parent := pnlActionButtons;
  btnExplain.Align := alLeft;
  btnExplain.Width := 170;
  btnExplain.AlignWithMargins := True;
  btnExplain.Margins.SetBounds(10, 0, 0, 0);
  btnExplain.Caption := 'Explain a Component';

  btnMore := TButton.Create(pnlActionButtons);
  btnMore.Parent := pnlActionButtons;
  btnMore.Align := alLeft;
  btnMore.Width := 130;
  btnMore.AlignWithMargins := True;
  btnMore.Margins.SetBounds(10, 0, 0, 0);
  btnMore.Caption := '... More Details';

  // 4d. Chat Content Area
  memoChatContent := TMemo.Create(pnlMainChat);
  memoChatContent.Parent := pnlMainChat;
  memoChatContent.Align := alClient;
  memoChatContent.Color := CLR_BG_DARK;
  memoChatContent.Font.Name := FONT_MAIN;
  memoChatContent.Font.Size := 10;
  memoChatContent.Font.Color := CLR_TEXT_PRIMARY;
  memoChatContent.BorderStyle := bsNone;
  memoChatContent.ReadOnly := True;
  memoChatContent.ScrollBars := ssVertical;
end;

procedure TFormMain.PopulateData;
var
  RootNode, SubNode: TTreeNode;
begin
  // 1. Explorer TreeView
  tvExplorer.Items.Clear;
  RootNode := tvExplorer.Items.Add(nil, '▼ GRISP');
  SubNode  := tvExplorer.Items.AddChild(RootNode, '  ▼ Local');
  SubNode  := tvExplorer.Items.AddChild(SubNode, '    ▼ Projects');
  SubNode  := tvExplorer.Items.AddChild(SubNode, '      ▼ GRISP');
  tvExplorer.Items.AddChild(SubNode, '        src');
  tvExplorer.Items.AddChild(SubNode, '        tests');
  tvExplorer.Items.AddChild(SubNode, '        docs');
  tvExplorer.FullExpand;

  // 2. Sessions ListBox
  lbSessions.Items.Clear;
  lbSessions.Items.Add('💬 Project setup and architecture');
  lbSessions.Items.Add('   22 Sep 2026 14:12');
  lbSessions.Items.Add('');
  lbSessions.Items.Add('💬 Data model discussion');
  lbSessions.Items.Add('   22 Sep 2026 11:45');
  lbSessions.Items.Add('');
  lbSessions.Items.Add('💬 Bug investigation');
  lbSessions.Items.Add('   21 Sep 2026 16:20');
  lbSessions.ItemIndex := 0;

  // 3. Current Plan ListBox (Compleet leesbare teksten)
  lbPlanItems.Items.Clear;
  lbPlanItems.Items.Add('1. ✓ Analyze architecture (Completed)');
  lbPlanItems.Items.Add('2. ⚙ Review component details (In progress)');
  lbPlanItems.Items.Add('3. ○ Create diagram (Pending)');
  lbPlanItems.Items.Add('4. ○ Update documentation (Pending)');

  // 4. Work Items ListBox (Volledige badges)
  lbWorkItems.Items.Clear;
  lbWorkItems.Items.Add('Implement GRISP runtime        [ HIGH ]');
  lbWorkItems.Items.Add('Add graph visualization        [ MEDIUM ]');
  lbWorkItems.Items.Add('Write unit tests               [ MEDIUM ]');
  lbWorkItems.Items.Add('Update LSBP integration        [ LOW ]');

  // 5. Chat Content
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
    Key := #0;
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
    pnlThinkingCard.Height := 34;
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
