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
  CLR_USER_BUBBLE   = $00332217; // #172233 User message background
  CLR_AI_BUBBLE     = $002C1E14; // #141E2C AI message background
  CLR_BORDER        = $003D2B1C; // #1C2B3D Card border
  CLR_BORDER_BLUE   = $00E0821B; // #1B82E0 Input focus border

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

    sbChatScroll: TScrollBox; // Scrollable container voor chat-bubbles

    pnlChatInputBar: TCustomCardPanel;
    lblAttachBtn: TLabel;
    lblCodeBtn: TLabel;
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
    procedure AddUserBubble(const ATime, AText: string);
    procedure AddAiBubble(const ATime, AText: string; AShowThinking: Boolean = False);
    procedure SendChatMessage;
    procedure OnChatKeyPress(Sender: TObject; var Key: Char);
    procedure OnSendClick(Sender: TObject);
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
  // 1. TOP NAVIGATION BAR
  // ==========================================
  pnlTopNav := TPanel.Create(Self);
  pnlTopNav.Parent := Self;
  pnlTopNav.Align := alTop;
  pnlTopNav.Height := 54;
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

  // Tabs Container
  pnlTabsContainer := TPanel.Create(pnlTopNav);
  pnlTabsContainer.Parent := pnlTopNav;
  pnlTabsContainer.Align := alLeft;
  pnlTabsContainer.Width := 360;
  pnlTabsContainer.BevelOuter := bvNone;
  pnlTabsContainer.Color := CLR_BG_DARK;

  btnTabChat := TSpeedButton.Create(pnlTabsContainer);
  btnTabChat.Parent := pnlTabsContainer;
  btnTabChat.Align := alLeft;
  btnTabChat.Width := 90;
  btnTabChat.Caption := '💬 Chat';
  btnTabChat.Flat := True;
  btnTabChat.Font.Color := CLR_ACCENT_BLUE;
  btnTabChat.Font.Style := [fsBold];

  btnTabWorkflows := TSpeedButton.Create(pnlTabsContainer);
  btnTabWorkflows.Parent := pnlTabsContainer;
  btnTabWorkflows.Align := alLeft;
  btnTabWorkflows.Width := 120;
  btnTabWorkflows.Caption := '⚙ Workflows';
  btnTabWorkflows.Flat := True;
  btnTabWorkflows.Font.Color := CLR_TEXT_MUTED;

  btnTabKnowledge := TSpeedButton.Create(pnlTabsContainer);
  btnTabKnowledge.Parent := pnlTabsContainer;
  btnTabKnowledge.Align := alLeft;
  btnTabKnowledge.Width := 120;
  btnTabKnowledge.Caption := '📖 Knowledge';
  btnTabKnowledge.Flat := True;
  btnTabKnowledge.Font.Color := CLR_TEXT_MUTED;

  // Top Right Info
  pnlTopRightInfo := TPanel.Create(pnlTopNav);
  pnlTopRightInfo.Parent := pnlTopNav;
  pnlTopRightInfo.Align := alRight;
  pnlTopRightInfo.Width := 320;
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
  // 2. LEFT SIDEBAR (Breder & Strak)
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
  splLeft.Width := 2;
  splLeft.Color := CLR_BORDER;

  // Explorer Box
  pnlExplorerBox := TPanel.Create(pnlLeftSidebar);
  pnlExplorerBox.Parent := pnlLeftSidebar;
  pnlExplorerBox.Align := alTop;
  pnlExplorerBox.Height := 400;
  pnlExplorerBox.Color := CLR_BG_DARK;
  pnlExplorerBox.BevelOuter := bvNone;
  pnlExplorerBox.Padding.Left := 10;
  pnlExplorerBox.Padding.Right := 10;

  lblExplorerTitle := TLabel.Create(pnlExplorerBox);
  lblExplorerTitle.Parent := pnlExplorerBox;
  lblExplorerTitle.Align := alTop;
  lblExplorerTitle.Height := 30;
  lblExplorerTitle.Caption := '📂 Explorer';
  lblExplorerTitle.Font.Style := [fsBold];
  lblExplorerTitle.Font.Color := CLR_TEXT_PRIMARY;
  lblExplorerTitle.Layout := tlCenter;

  pnlSearchBox := TCustomCardPanel.Create(pnlExplorerBox);
  pnlSearchBox.Parent := pnlExplorerBox;
  pnlSearchBox.Align := alTop;
  pnlSearchBox.Height := 34;
  pnlSearchBox.AlignWithMargins := True;
  pnlSearchBox.Margins.SetBounds(0, 4, 0, 8);
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

  // Sessions Box
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
  lblSessionsTitle.Height := 30;
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
  // 3. RIGHT SIDEBAR (340px Breed)
  // ==========================================
  pnlRightSidebar := TPanel.Create(Self);
  pnlRightSidebar.Parent := Self;
  pnlRightSidebar.Align := alRight;
  pnlRightSidebar.Width := 340;
  pnlRightSidebar.Color := CLR_BG_DARK;
  pnlRightSidebar.ParentBackground := False;
  pnlRightSidebar.BevelOuter := bvNone;

  splRight := TSplitter.Create(Self);
  splRight.Parent := Self;
  splRight.Align := alRight;
  splRight.Width := 2;
  splRight.Color := CLR_BORDER;

  // Current Plan Card
  pnlPlanCard := TCustomCardPanel.Create(pnlRightSidebar);
  pnlPlanCard.Parent := pnlRightSidebar;
  pnlPlanCard.Align := alTop;
  pnlPlanCard.Height := 220;
  pnlPlanCard.AlignWithMargins := True;
  pnlPlanCard.Margins.SetBounds(10, 10, 10, 10);
  pnlPlanCard.Padding.Left := 12;
  pnlPlanCard.Padding.Top := 10;
  pnlPlanCard.Padding.Right := 10;

  lblPlanTitle := TLabel.Create(pnlPlanCard);
  lblPlanTitle.Parent := pnlPlanCard;
  lblPlanTitle.Align := alTop;
  lblPlanTitle.Caption := 'Current Plan';
  lblPlanTitle.Font.Style := [fsBold];
  lblPlanTitle.Font.Color := CLR_ACCENT_BLUE;
  lblPlanTitle.Height := 26;

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
  pnlWorkItemsCard.Height := 250;
  pnlWorkItemsCard.AlignWithMargins := True;
  pnlWorkItemsCard.Margins.SetBounds(10, 0, 10, 10);
  pnlWorkItemsCard.Padding.Left := 12;
  pnlWorkItemsCard.Padding.Top := 10;
  pnlWorkItemsCard.Padding.Right := 10;

  lblWorkItemsTitle := TLabel.Create(pnlWorkItemsCard);
  lblWorkItemsTitle.Parent := pnlWorkItemsCard;
  lblWorkItemsTitle.Align := alTop;
  lblWorkItemsTitle.Caption := 'Work Items';
  lblWorkItemsTitle.Font.Style := [fsBold];
  lblWorkItemsTitle.Font.Color := CLR_ACCENT_BLUE;
  lblWorkItemsTitle.Height := 26;

  lbWorkItems := TListBox.Create(pnlWorkItemsCard);
  lbWorkItems.Parent := pnlWorkItemsCard;
  lbWorkItems.Align := alClient;
  lbWorkItems.Color := CLR_PANEL_BG;
  lbWorkItems.Font.Color := CLR_TEXT_PRIMARY;
  lbWorkItems.BorderStyle := bsNone;


  // ==========================================
  // 4. CENTER WORKSPACE (Nieuwe Bubble Chat & Input)
  // ==========================================
  pnlMainChat := TPanel.Create(Self);
  pnlMainChat.Parent := Self;
  pnlMainChat.Align := alClient;
  pnlMainChat.Color := CLR_BG_DARK;
  pnlMainChat.ParentBackground := False;
  pnlMainChat.BevelOuter := bvNone;
  pnlMainChat.Padding.Left := 16;
  pnlMainChat.Padding.Right := 16;
  pnlMainChat.Padding.Bottom := 14;

  // Header
  pnlChatHeader := TPanel.Create(pnlMainChat);
  pnlChatHeader.Parent := pnlMainChat;
  pnlChatHeader.Align := alTop;
  pnlChatHeader.Height := 40;
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

  // Bottom Input Bar (Strak, afgerond en modern)
  pnlChatInputBar := TCustomCardPanel.Create(pnlMainChat);
  pnlChatInputBar.Parent := pnlMainChat;
  pnlChatInputBar.Align := alBottom;
  pnlChatInputBar.Height := 52;
  pnlChatInputBar.BorderColor := CLR_BORDER_BLUE;
  pnlChatInputBar.AlignWithMargins := True;
  pnlChatInputBar.Margins.SetBounds(0, 10, 0, 0);
  pnlChatInputBar.Padding.Left := 14;
  pnlChatInputBar.Padding.Right := 8;

  lblAttachBtn := TLabel.Create(pnlChatInputBar);
  lblAttachBtn.Parent := pnlChatInputBar;
  lblAttachBtn.Align := alLeft;
  lblAttachBtn.Caption := '📎  ';
  lblAttachBtn.Font.Size := 11;
  lblAttachBtn.Font.Color := CLR_TEXT_MUTED;
  lblAttachBtn.Layout := tlCenter;
  lblAttachBtn.Cursor := crHandPoint;

  lblCodeBtn := TLabel.Create(pnlChatInputBar);
  lblCodeBtn.Parent := pnlChatInputBar;
  lblCodeBtn.Align := alLeft;
  lblCodeBtn.Caption := '</>   ';
  lblCodeBtn.Font.Size := 10;
  lblCodeBtn.Font.Color := CLR_TEXT_MUTED;
  lblCodeBtn.Layout := tlCenter;
  lblCodeBtn.Cursor := crHandPoint;

  btnSendMsg := TSpeedButton.Create(pnlChatInputBar);
  btnSendMsg.Parent := pnlChatInputBar;
  btnSendMsg.Align := alRight;
  btnSendMsg.Width := 46;
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

  // ScrollBox voor Dynamische Chat Bubbles
  sbChatScroll := TScrollBox.Create(pnlMainChat);
  sbChatScroll.Parent := pnlMainChat;
  sbChatScroll.Align := alClient;
  sbChatScroll.Color := CLR_BG_DARK;
  sbChatScroll.BorderStyle := bsNone;
  sbChatScroll.VertScrollBar.Smooth := True;
  sbChatScroll.VertScrollBar.Tracking := True;
end;

// ==========================================
// DYNAMISCHE CHAT BUBBLES AANMAKEN
// ==========================================

procedure TFormMain.AddUserBubble(const ATime, AText: string);
var
  Bubble: TCustomCardPanel;
  lblHeader, lblBody: TLabel;
begin
  Bubble := TCustomCardPanel.Create(sbChatScroll);
  Bubble.Parent := sbChatScroll;
  Bubble.Align := alTop;
  Bubble.Color := CLR_USER_BUBBLE;
  Bubble.BorderColor := CLR_BORDER;
  Bubble.AlignWithMargins := True;
  Bubble.Margins.SetBounds(20, 10, 20, 6);
  Bubble.Padding.Left := 14;
  Bubble.Padding.Top := 10;
  Bubble.Padding.Right := 14;
  Bubble.Padding.Bottom := 10;

  lblHeader := TLabel.Create(Bubble);
  lblHeader.Parent := Bubble;
  lblHeader.Align := alTop;
  lblHeader.Caption := '👤 You  ' + ATime;
  lblHeader.Font.Style := [fsBold];
  lblHeader.Font.Color := CLR_ACCENT_BLUE;
  lblHeader.Height := 22;

  lblBody := TLabel.Create(Bubble);
  lblBody.Parent := Bubble;
  lblBody.Align := alTop;
  lblBody.Caption := AText;
  lblBody.Font.Color := CLR_TEXT_PRIMARY;
  lblBody.Font.Size := 10;
  lblBody.WordWrap := True;

  // Automatische hoogteberekening
  Bubble.AutoSize := False;
  Bubble.Height := lblHeader.Height + lblBody.Height + 28;
end;

procedure TFormMain.AddAiBubble(const ATime, AText: string; AShowThinking: Boolean = False);
var
  Bubble: TCustomCardPanel;
  lblHeader, lblBody: TLabel;
  pnlThink: TCustomCardPanel;
  lblThinkHeader, lblThinkText: TLabel;
  ExtraHeight: Integer;
begin
  ExtraHeight := 0;

  Bubble := TCustomCardPanel.Create(sbChatScroll);
  Bubble.Parent := sbChatScroll;
  Bubble.Align := alTop;
  Bubble.Color := CLR_AI_BUBBLE;
  Bubble.BorderColor := CLR_BORDER_BLUE; // Geef AI antwoord een subtiel blauw randje
  Bubble.AlignWithMargins := True;
  Bubble.Margins.SetBounds(0, 6, 20, 14);
  Bubble.Padding.Left := 16;
  Bubble.Padding.Top := 12;
  Bubble.Padding.Right := 16;
  Bubble.Padding.Bottom := 12;

  lblHeader := TLabel.Create(Bubble);
  lblHeader.Parent := Bubble;
  lblHeader.Align := alTop;
  lblHeader.Caption := '❖ GRISP Assistant  ' + ATime;
  lblHeader.Font.Style := [fsBold];
  lblHeader.Font.Color := CLR_ACCENT_BLUE;
  lblHeader.Height := 24;

  // Eventuele Thinking Card binnen in de bubble
  if AShowThinking then
  begin
    pnlThink := TCustomCardPanel.Create(Bubble);
    pnlThink.Parent := Bubble;
    pnlThink.Align := alTop;
    pnlThink.Color := CLR_PANEL_BG;
    pnlThink.BorderColor := CLR_BORDER;
    pnlThink.AlignWithMargins := True;
    pnlThink.Margins.SetBounds(0, 4, 0, 10);
    pnlThink.Padding.Left := 12;
    pnlThink.Padding.Top := 8;
    pnlThink.Padding.Right := 12;
    pnlThink.Height := 72;

    lblThinkHeader := TLabel.Create(pnlThink);
    lblThinkHeader.Parent := pnlThink;
    lblThinkHeader.Align := alTop;
    lblThinkHeader.Caption := '🧠 Thinking Process';
    lblThinkHeader.Font.Style := [fsBold];
    lblThinkHeader.Font.Color := CLR_TEXT_MUTED;

    lblThinkText := TLabel.Create(pnlThink);
    lblThinkText.Parent := pnlThink;
    lblThinkText.Align := alClient;
    lblThinkText.Caption :=
      '✓ Analyzing GRISP architecture from documentation...' + #13#10 +
      '✓ Identified 7 main components and their relationships...';
    lblThinkText.Font.Color := CLR_TEXT_MUTED;
    lblThinkText.Font.Size := 8;

    ExtraHeight := pnlThink.Height + 14;
  end;

  lblBody := TLabel.Create(Bubble);
  lblBody.Parent := Bubble;
  lblBody.Align := alTop;
  lblBody.Caption := AText;
  lblBody.Font.Color := CLR_TEXT_PRIMARY;
  lblBody.Font.Size := 10;
  lblBody.WordWrap := True;

  Bubble.AutoSize := False;
  Bubble.Height := lblHeader.Height + ExtraHeight + lblBody.Height + 32;
end;

procedure TFormMain.PopulateData;
var
  RootNode, SubNode: TTreeNode;
  AiText: string;
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

  // 3. Current Plan
  lbPlanItems.Items.Clear;
  lbPlanItems.Items.Add('1. ✓ Analyze architecture (Completed)');
  lbPlanItems.Items.Add('2. ⚙ Review component details (In progress)');
  lbPlanItems.Items.Add('3. ○ Create diagram (Pending)');
  lbPlanItems.Items.Add('4. ○ Update documentation (Pending)');

  // 4. Work Items
  lbWorkItems.Items.Clear;
  lbWorkItems.Items.Add('Implement GRISP runtime        [ HIGH ]');
  lbWorkItems.Items.Add('Add graph visualization        [ MEDIUM ]');
  lbWorkItems.Items.Add('Write unit tests               [ MEDIUM ]');
  lbWorkItems.Items.Add('Update LSBP integration        [ LOW ]');

  // 5. Initial Chat Data als Bubbles
  AddUserBubble('14:12', 'Can you help me analyze the GRISP architecture and explain the main components and how they work together?');

  AiText :=
    'Sure! The GRISP architecture is designed around a deterministic, graph-based execution model. Here are the main components:' + #13#10 + #13#10 +
    '1. SIR (Source Intermediate Representation)' + #13#10 +
    '   Parses and validates the input, converting it to a structured representation.' + #13#10 +
    '2. Planner' + #13#10 +
    '   Analyzes the SIR and creates an execution plan with ordered steps.' + #13#10 +
    '3. Evaluator' + #13#10 +
    '   Executes the plan, performing graph operations and rule evaluation.' + #13#10 +
    '4. Validator' + #13#10 +
    '   Ensures correctness, security and compliance with constraints.' + #13#10 +
    '5. EIR (Execution Intermediate Representation)' + #13#10 +
    '   Optimized form for the GRISP runtime.' + #13#10 +
    '6. GRISP Runtime' + #13#10 +
    '   Executes the EIR in a deterministic graph environment.' + #13#10 +
    '7. LSBP / WorldState' + #13#10 +
    '   Manages state, persistence and external integrations.';

  AddAiBubble('14:12', AiText, True);
end;

procedure TFormMain.SendChatMessage;
var
  Txt: string;
begin
  Txt := Trim(edtChatInput.Text);
  if (Txt = '') or (Txt = 'Type your message...') then Exit;

  AddUserBubble(FormatDateTime('hh:nn', Now), Txt);
  AddAiBubble(FormatDateTime('hh:nn', Now), 'Verwerkt in runtime context...');

  edtChatInput.Clear;

  // Auto scroll naar beneden
  sbChatScroll.VertScrollBar.Position := sbChatScroll.VertScrollBar.Range;
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

end.
