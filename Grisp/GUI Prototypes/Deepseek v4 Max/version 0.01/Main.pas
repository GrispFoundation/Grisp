unit Main;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, System.Generics.Collections, Vcl.Graphics, Vcl.Controls,
  Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.ComCtrls;

const
  APP_NAME    = 'GRISP OS';
  APP_VERSION = 'v1.0 GUI';

  // ══════════════════════════════════════════════════════════════
  //  DEEP SPACE palette (TColor = BGR)
  // ══════════════════════════════════════════════════════════════
  CLR_MAIN     = $001A0E0A;  // #0A0E1A
  CLR_PANEL    = $0024150D;  // #0D1524
  CLR_BAR      = $00160C08;  // #080C16
  CLR_HEAD     = $003C2416;  // #16243C
  CLR_USER     = $008A3A1E;  // #1E3A8A
  CLR_AI       = $003C2416;  // #16243C
  CLR_CYAN     = $00EED322;  // #22D3EE
  CLR_SKY      = $00F8BD38;  // #38BDF8
  CLR_BLUE     = $00F6823B;  // #3B82F6
  CLR_TEXT     = $00FFFFFF;
  CLR_GRAY     = $00B8A394;  // #94A3B8
  CLR_DGRAY    = $008B7464;  // #64748B
  CLR_BORDER   = $00554133;  // #334155
  CLR_GREEN    = $005EC522;  // #22C55E
  CLR_AMBER    = $000B9EF5;  // #F59E0B
  CLR_USER_TXT = $00FDC593;  // #93C5FD

type
  // ══════════════════════════════════════════════════════════════
  //  Custom panel dat een 1px border tekent
  // ══════════════════════════════════════════════════════════════
  TBorderedPanel = class(TPanel)
  private
    FBorderColor: TColor;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    property BorderColor: TColor read FBorderColor write FBorderColor;
  end;

  // ══════════════════════════════════════════════════════════════
  //  Nav-button in topbar (hover-highlight)
  // ══════════════════════════════════════════════════════════════
  TNavButton = class(TPanel)
  private
    FActive: Boolean;
    FHover: Boolean;
    procedure CMMouseEnter(var Msg: TMessage); message CM_MOUSEENTER;
    procedure CMMouseLeave(var Msg: TMessage); message CM_MOUSELEAVE;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    property Active: Boolean read FActive write FActive;
  end;

  // ══════════════════════════════════════════════════════════════
  //  Chat message panel (bubbel)
  // ══════════════════════════════════════════════════════════════
  TChatMessagePanel = class(TPanel)
  private
    FIsUser: Boolean;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    property IsUser: Boolean read FIsUser write FIsUser;
  end;

  // ══════════════════════════════════════════════════════════════
  //  MainForm
  // ══════════════════════════════════════════════════════════════
  TMainForm = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  private
    // Layout containers
    FTopBar: TPanel;
    FStatusBar: TPanel;
    FLeftPanel: TPanel;
    FCenterPanel: TPanel;
    FRightPanel: TPanel;
    FSplitterLeft, FSplitterRight: TSplitter;

    // Topbar components
    FLogo: TLabel;
    FBtnExplorer, FBtnAgents, FBtnWorkflows, FBtnKnowledge,
    FBtnModels, FBtnTools, FBtnTerminal, FBtnSettings: TNavButton;
    FClockLbl: TLabel;
    FStatusDot: TLabel;
    FStatusText: TLabel;

    // Left panel
    FResourcesHeader: TBorderedPanel;
    FTree: TTreeView;
    FSessionsHeader: TBorderedPanel;
    FSessionList: TListBox;

    // Center panel
    FChatHeader: TBorderedPanel;
    FChatScroll: TScrollBox;
    FInputBar: TPanel;
    FInput: TEdit;
    FSendBtn: TPanel;

    // Right panel
    FRightPlanHeader: TBorderedPanel;
    FRightPlanBox: TPanel;
    FRightWorkHeader: TBorderedPanel;
    FRightWorkBox: TPanel;

    // Timer
    FTimer: TTimer;

    // State
    FShowLeftPanel: Boolean;
    FShowRightPanel: Boolean;

    procedure BuildUI;
    procedure PopulateData;
    procedure AddMessage(const Sender, Text: string; IsUser: Boolean);
    procedure AddPlanItems;
    procedure AddWorkItems;
    procedure SendMessage;
    procedure FSendBtnClick(Sender: TObject);
    procedure FInputKeyPress(Sender: TObject; var Key: Char);
    procedure FTimerTick(Sender: TObject);
    procedure LayoutPanels;
    function MakeNavButton(AParent: TPanel; const ACaption: string;
      ALeft: Integer; AActive: Boolean = False): TNavButton;
    function MakeHeaderLabel(AParent: TPanel; const ACaption: string): TBorderedPanel;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

// ═══════════════════════════════════════════════════════════════════
//  TBorderedPanel
// ═══════════════════════════════════════════════════════════════════
constructor TBorderedPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBorderColor := CLR_BORDER;
  BevelOuter := bvNone;
  Color := CLR_PANEL;
  ParentBackground := False;
end;

procedure TBorderedPanel.Paint;
begin
  inherited;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBorderColor;
  // Teken een 1px lijn onderaan
  Canvas.FillRect(Rect(0, Height - 1, Width, Height));
end;

// ═══════════════════════════════════════════════════════════════════
//  TNavButton
// ═══════════════════════════════════════════════════════════════════
constructor TNavButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Color := CLR_BAR;
  ParentBackground := False;
  Cursor := crHandPoint;
  FActive := False;
  FHover := False;
end;

procedure TNavButton.CMMouseEnter(var Msg: TMessage);
begin
  FHover := True;
  Invalidate;
end;

procedure TNavButton.CMMouseLeave(var Msg: TMessage);
begin
  FHover := False;
  Invalidate;
end;

procedure TNavButton.Paint;
var
  Bg: TColor;
  Txt: TColor;
begin
  if FActive then Bg := CLR_HEAD
  else if FHover then Bg := CLR_PANEL
  else Bg := CLR_BAR;

  Canvas.Brush.Color := Bg;
  Canvas.FillRect(ClientRect);

  if FActive then
  begin
    // Cyan underline
    Canvas.Brush.Color := CLR_CYAN;
    Canvas.FillRect(Rect(0, Height - 2, Width, Height));
  end;

  if FActive then Txt := CLR_CYAN
  else if FHover then Txt := CLR_TEXT
  else Txt := CLR_GRAY;

  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Size := 9;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := Txt;
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut((Width - Canvas.TextWidth(Caption)) div 2,
                 (Height - Canvas.TextHeight(Caption)) div 2, Caption);
end;

// ═══════════════════════════════════════════════════════════════════
//  TChatMessagePanel
// ═══════════════════════════════════════════════════════════════════
constructor TChatMessagePanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  ParentBackground := False;
  FIsUser := False;
end;

procedure TChatMessagePanel.Paint;
var
  R: TRect;
begin
  Canvas.Brush.Color := CLR_MAIN;
  Canvas.FillRect(ClientRect);

  R := ClientRect;
  if FIsUser then
    Canvas.Brush.Color := CLR_USER
  else
    Canvas.Brush.Color := CLR_AI;
  Canvas.FillRect(R);

  // Accentbalk links
  if not FIsUser then
  begin
    Canvas.Brush.Color := CLR_SKY;
    Canvas.FillRect(Rect(0, 0, 3, Height));
  end;
end;

// ═══════════════════════════════════════════════════════════════════
//  Form
// ═══════════════════════════════════════════════════════════════════
procedure TMainForm.FormCreate(Sender: TObject);
begin
  FShowLeftPanel  := True;
  FShowRightPanel := True;

  Caption := APP_NAME + ' ' + APP_VERSION;

  // ★ EERST UI opbouwen
  BuildUI;
  PopulateData;

  // Welkomstbericht
  AddMessage('GRISP Assistant',
    'Hello Alex, how can I help you with GRISP today?', False);

  AddPlanItems;
  AddWorkItems;

  // ★ DAARNA pas de afmetingen zetten — anders triggert FormResize
  //   voordat FSplitterLeft/FSplitterRight bestaan → AV
  ClientWidth  := 1400;
  ClientHeight := 850;
  Position := poScreenCenter;
end;

procedure TMainForm.FormResize(Sender: TObject);
begin
  // ★ Guard: skip als BuildUI nog niet klaar is
  if not Assigned(FSplitterLeft) then Exit;
  LayoutPanels;
end;

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_F2: begin
      FShowLeftPanel := not FShowLeftPanel;
      LayoutPanels;
    end;
    VK_F3: begin
      FShowRightPanel := not FShowRightPanel;
      LayoutPanels;
    end;
    VK_ESCAPE: Close;
  end;
end;

// ═══════════════════════════════════════════════════════════════════
//  Nav-button helper
// ═══════════════════════════════════════════════════════════════════
function TMainForm.MakeNavButton(AParent: TPanel; const ACaption: string;
  ALeft: Integer; AActive: Boolean): TNavButton;
begin
  Result := TNavButton.Create(Self);
  Result.Parent := AParent;
  Result.Left := ALeft;
  Result.Top := 12;
  Result.Width := 110;
  Result.Height := 26;
  Result.Caption := ACaption;
  Result.Active := AActive;
end;

// ═══════════════════════════════════════════════════════════════════
//  Header-label helper
// ═══════════════════════════════════════════════════════════════════
function TMainForm.MakeHeaderLabel(AParent: TPanel;
  const ACaption: string): TBorderedPanel;
var
  Lbl: TLabel;
begin
  Result := TBorderedPanel.Create(Self);
  Result.Parent := AParent;
  Result.Align := alTop;
  Result.Height := 30;
  Result.Color := CLR_PANEL;
  Result.BorderColor := CLR_BORDER;

  Lbl := TLabel.Create(Result);
  Lbl.Parent := Result;
  Lbl.Caption := ACaption;
  Lbl.Left := 10;
  Lbl.Top := 7;
  Lbl.Font.Name := 'Segoe UI';
  Lbl.Font.Size := 9;
  Lbl.Font.Style := [fsBold];
  Lbl.Font.Color := CLR_CYAN;
  Lbl.Transparent := True;
end;

// ═══════════════════════════════════════════════════════════════════
//  UI construction
// ═══════════════════════════════════════════════════════════════════
procedure TMainForm.BuildUI;
var
  Sep1: TLabel;
begin
  Color := CLR_MAIN;
  DoubleBuffered := True;

  // ── Statusbar (eerst, plakt onderaan) ──
  FStatusBar := TPanel.Create(Self);
  FStatusBar.Parent := Self;
  FStatusBar.Align := alBottom;
  FStatusBar.Height := 30;
  FStatusBar.BevelOuter := bvNone;
  FStatusBar.Color := CLR_BAR;
  FStatusBar.ParentBackground := False;

  // ── Topbar ──
  FTopBar := TPanel.Create(Self);
  FTopBar.Parent := Self;
  FTopBar.Align := alTop;
  FTopBar.Height := 50;
  FTopBar.BevelOuter := bvNone;
  FTopBar.Color := CLR_BAR;
  FTopBar.ParentBackground := False;

  // Logo
  FLogo := TLabel.Create(FTopBar);
  FLogo.Parent := FTopBar;
  FLogo.Caption := '◈ ' + APP_NAME;
  FLogo.Left := 16;
  FLogo.Top := 15;
  FLogo.Font.Name := 'Segoe UI';
  FLogo.Font.Size := 14;
  FLogo.Font.Style := [fsBold];
  FLogo.Font.Color := CLR_CYAN;
  FLogo.Transparent := True;

  // Version
  Sep1 := TLabel.Create(FTopBar);
  Sep1.Parent := FTopBar;
  Sep1.Caption := APP_VERSION;
  Sep1.Left := 150;
  Sep1.Top := 20;
  Sep1.Font.Size := 8;
  Sep1.Font.Color := CLR_DGRAY;
  Sep1.Transparent := True;

  // Nav buttons
  FBtnExplorer   := MakeNavButton(FTopBar, 'Explorer',   230, True);
  FBtnAgents     := MakeNavButton(FTopBar, 'Agents',     348);
  FBtnWorkflows  := MakeNavButton(FTopBar, 'Workflows',  466);
  FBtnKnowledge  := MakeNavButton(FTopBar, 'Knowledge',  584);
  FBtnModels     := MakeNavButton(FTopBar, 'Models',     702);
  FBtnTools      := MakeNavButton(FTopBar, 'Tools',      820);
  FBtnTerminal   := MakeNavButton(FTopBar, 'Terminal',   938);
  FBtnSettings   := MakeNavButton(FTopBar, 'Settings',  1056);

  // Clock (rechts)
  FClockLbl := TLabel.Create(FTopBar);
  FClockLbl.Parent := FTopBar;
  FClockLbl.Caption := '00:00:00';
  FClockLbl.Width := 80;
  FClockLbl.Left := 1300;
  FClockLbl.Top := 17;
  FClockLbl.Anchors := [akTop, akRight];
  FClockLbl.Font.Name := 'Consolas';
  FClockLbl.Font.Size := 11;
  FClockLbl.Font.Color := CLR_CYAN;
  FClockLbl.Transparent := True;

  // Timer voor live klok
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 1000;
  FTimer.OnTimer := FTimerTick;
  FTimer.Enabled := True;

  // ── Splitter (rechts) ──
  FSplitterRight := TSplitter.Create(Self);
  FSplitterRight.Parent := Self;
  FSplitterRight.Align := alRight;
  FSplitterRight.Width := 2;
  FSplitterRight.Color := CLR_BORDER;
  FSplitterRight.MinSize := 200;

  // ── Right panel ──
  FRightPanel := TPanel.Create(Self);
  FRightPanel.Parent := Self;
  FRightPanel.Align := alRight;
  FRightPanel.Width := 320;
  FRightPanel.BevelOuter := bvNone;
  FRightPanel.Color := CLR_PANEL;
  FRightPanel.ParentBackground := False;

  // ── Splitter (links) ──
  FSplitterLeft := TSplitter.Create(Self);
  FSplitterLeft.Parent := Self;
  FSplitterLeft.Align := alLeft;
  FSplitterLeft.Width := 2;
  FSplitterLeft.Color := CLR_BORDER;
  FSplitterLeft.MinSize := 200;

  // ── Left panel ──
  FLeftPanel := TPanel.Create(Self);
  FLeftPanel.Parent := Self;
  FLeftPanel.Align := alLeft;
  FLeftPanel.Width := 280;
  FLeftPanel.BevelOuter := bvNone;
  FLeftPanel.Color := CLR_PANEL;
  FLeftPanel.ParentBackground := False;

  // Resources header
  FResourcesHeader := MakeHeaderLabel(FLeftPanel, '▾  RESOURCES');

  // Tree
  FTree := TTreeView.Create(FLeftPanel);
  FTree.Parent := FLeftPanel;
  FTree.Align := alTop;
  FTree.Height := 240;
  FTree.BorderStyle := bsNone;
  FTree.Color := CLR_PANEL;
  FTree.Font.Name := 'Segoe UI';
  FTree.Font.Size := 9;
  FTree.Font.Color := CLR_TEXT;
  FTree.Indent := 16;
  FTree.RowSelect := True;
  FTree.ShowLines := False;
  FTree.ShowRoot := False;
  FTree.HotTrack := True;

  // Sessions header
  FSessionsHeader := MakeHeaderLabel(FLeftPanel, '▾  SESSIONS');

  // Sessions list
  FSessionList := TListBox.Create(FLeftPanel);
  FSessionList.Parent := FLeftPanel;
  FSessionList.Align := alClient;
  FSessionList.BorderStyle := bsNone;
  FSessionList.Color := CLR_PANEL;
  FSessionList.Font.Name := 'Segoe UI';
  FSessionList.Font.Size := 9;
  FSessionList.Font.Color := CLR_TEXT;

  // ── Center panel ──
  FCenterPanel := TPanel.Create(Self);
  FCenterPanel.Parent := Self;
  FCenterPanel.Align := alClient;
  FCenterPanel.BevelOuter := bvNone;
  FCenterPanel.Color := CLR_MAIN;
  FCenterPanel.ParentBackground := False;

  // Chat header
  FChatHeader := MakeHeaderLabel(FCenterPanel, '◆  CHAT · Architecture Review');
  FChatHeader.Color := CLR_MAIN;

  // Input bar (plakt onderaan center)
  FInputBar := TPanel.Create(FCenterPanel);
  FInputBar.Parent := FCenterPanel;
  FInputBar.Align := alBottom;
  FInputBar.Height := 60;
  FInputBar.BevelOuter := bvNone;
  FInputBar.Color := CLR_PANEL;
  FInputBar.ParentBackground := False;

  FInput := TEdit.Create(FInputBar);
  FInput.Parent := FInputBar;
  FInput.Left := 16;
  FInput.Top := 14;
  FInput.Width := 500;
  FInput.Height := 32;
  FInput.Anchors := [akLeft, akTop, akRight];
  FInput.Font.Name := 'Segoe UI';
  FInput.Font.Size := 11;
  FInput.Color := CLR_MAIN;
  FInput.Font.Color := CLR_TEXT;
  FInput.TextHint := 'Type your message...';
  FInput.BorderStyle := bsNone;
  FInput.OnKeyPress := FInputKeyPress;

  FSendBtn := TPanel.Create(FInputBar);
  FSendBtn.Parent := FInputBar;
  FSendBtn.Width := 44;
  FSendBtn.Height := 32;
  FSendBtn.Top := 14;
  FSendBtn.Anchors := [akTop, akRight];
  FSendBtn.BevelOuter := bvNone;
  FSendBtn.Color := CLR_CYAN;
  FSendBtn.ParentBackground := False;
  FSendBtn.Cursor := crHandPoint;
  FSendBtn.Caption := '➤';
  FSendBtn.Font.Color := CLR_MAIN;
  FSendBtn.Font.Style := [fsBold];
  FSendBtn.Font.Size := 14;
  FSendBtn.OnClick := FSendBtnClick;

  // Chat scrollbox (vult de rest)
  FChatScroll := TScrollBox.Create(FCenterPanel);
  FChatScroll.Parent := FCenterPanel;
  FChatScroll.Align := alClient;
  FChatScroll.BorderStyle := bsNone;
  FChatScroll.Color := CLR_MAIN;
  FChatScroll.ParentBackground := False;
  FChatScroll.VertScrollBar.Tracking := True;

  // ── Right panel content ──
  FRightPlanHeader := MakeHeaderLabel(FRightPanel, '◆  CURRENT PLAN');

  FRightPlanBox := TPanel.Create(FRightPanel);
  FRightPlanBox.Parent := FRightPanel;
  FRightPlanBox.Align := alTop;
  FRightPlanBox.Height := 200;
  FRightPlanBox.BevelOuter := bvNone;
  FRightPlanBox.Color := CLR_PANEL;
  FRightPlanBox.ParentBackground := False;

  FRightWorkHeader := MakeHeaderLabel(FRightPanel, '◆  WORK ITEMS');

  FRightWorkBox := TPanel.Create(FRightPanel);
  FRightWorkBox.Parent := FRightPanel;
  FRightWorkBox.Align := alClient;
  FRightWorkBox.BevelOuter := bvNone;
  FRightWorkBox.Color := CLR_PANEL;
  FRightWorkBox.ParentBackground := False;

  // ── Statusbar content ──
  FStatusDot := TLabel.Create(FStatusBar);
  FStatusDot.Parent := FStatusBar;
  FStatusDot.Caption := '●';
  FStatusDot.Left := 16;
  FStatusDot.Top := 7;
  FStatusDot.Font.Size := 12;
  FStatusDot.Font.Color := CLR_GREEN;
  FStatusDot.Transparent := True;

  FStatusText := TLabel.Create(FStatusBar);
  FStatusText.Parent := FStatusBar;
  FStatusText.Caption :=
    'Connected   │   Model: GPT-5   │   Project: GRISP   │   ' +
    'Permissions: RWX active   │   Sessions: 1/4';
  FStatusText.Left := 32;
  FStatusText.Top := 8;
  FStatusText.Font.Size := 9;
  FStatusText.Font.Color := CLR_GRAY;
  FStatusText.Transparent := True;
end;

// ═══════════════════════════════════════════════════════════════════
//  Layout helper — met Assigned guards
// ═══════════════════════════════════════════════════════════════════
procedure TMainForm.LayoutPanels;
begin
  // ★ Guards: skip als BuildUI nog niet klaar is
  if not Assigned(FSplitterLeft) or not Assigned(FLeftPanel) then Exit;
  if not Assigned(FSplitterRight) or not Assigned(FRightPanel) then Exit;

  if not FShowLeftPanel then
  begin
    FSplitterLeft.Visible := False;
    FLeftPanel.Visible := False;
  end
  else
  begin
    FSplitterLeft.Visible := True;
    FLeftPanel.Visible := True;
  end;

  if not FShowRightPanel then
  begin
    FSplitterRight.Visible := False;
    FRightPanel.Visible := False;
  end
  else
  begin
    FSplitterRight.Visible := True;
    FRightPanel.Visible := True;
  end;

  if Assigned(FClockLbl) and Assigned(FTopBar) then
    FClockLbl.Left := FTopBar.ClientWidth - 100;

  if Assigned(FSendBtn) and Assigned(FInputBar) and Assigned(FInput) then
  begin
    FSendBtn.Left := FInputBar.ClientWidth - FSendBtn.Width - 16;
    FInput.Width := FInputBar.ClientWidth - FSendBtn.Width - 48;
  end;
end;

// ═══════════════════════════════════════════════════════════════════
//  Data
// ═══════════════════════════════════════════════════════════════════
procedure TMainForm.PopulateData;
var
  Root, Proj, Data, Cloud: TTreeNode;
begin
  FTree.Items.BeginUpdate;
  try
    FTree.Items.Clear;

    Root := FTree.Items.Add(nil, '▸ Local');
    Root.Expand(False);

    Proj := FTree.Items.AddChild(Root, '  ▸ Projects  RWX');
    FTree.Items.AddChild(Proj, '    ▸ GRISP  RWX');
    FTree.Items.AddChild(Proj, '    ▸ MME-Registry  RW');
    FTree.Items.AddChild(Proj, '    ▸ Agent-Network  RW');
    Proj.Expand(False);

    Data := FTree.Items.AddChild(Root, '  ▸ Data  RW');
    FTree.Items.AddChild(Data, '    ▸ Models  RW');
    FTree.Items.AddChild(Data, '    ▸ Downloads  R');
    Data.Expand(False);

    Cloud := FTree.Items.AddChild(Root, '  ▸ Cloud  R');
    Cloud.Expand(False);
  finally
    FTree.Items.EndUpdate;
  end;

  // Sessions
  FSessionList.Items.Add('Architecture Review');
  FSessionList.Items.Add('MME Schema Draft');
  FSessionList.Items.Add('Agent Graph');
  FSessionList.Items.Add('VFS Refactor Notes');
  FSessionList.ItemIndex := 0;
end;

// ═══════════════════════════════════════════════════════════════════
//  Plan items
// ═══════════════════════════════════════════════════════════════════
procedure TMainForm.AddPlanItems;
type
  TPlanRec = record Icon, Text, Status: string; end;
var
  Items: array[0..3] of TPlanRec;
  I: Integer;
  P: TPanel;
  IconLbl, TextLbl, StatusLbl: TLabel;
begin
  Items[0].Icon := '☑'; Items[0].Text := 'Analyze VFS Layer';  Items[0].Status := 'done';
  Items[1].Icon := '☑'; Items[1].Text := 'Extract MME schema'; Items[1].Status := 'done';
  Items[2].Icon := '▶'; Items[2].Text := 'Map Agent Network';  Items[2].Status := 'running';
  Items[3].Icon := '☐'; Items[3].Text := 'Draft DNA report';   Items[3].Status := 'queued';

  for I := 0 to 3 do
  begin
    P := TPanel.Create(FRightPlanBox);
    P.Parent := FRightPlanBox;
    P.Left := 8;
    P.Top := 8 + I * 36;
    P.Width := FRightPlanBox.ClientWidth - 16;
    P.Height := 30;
    P.BevelOuter := bvNone;
    P.Color := CLR_HEAD;
    P.ParentBackground := False;
    P.Anchors := [akLeft, akTop, akRight];

    IconLbl := TLabel.Create(P);
    IconLbl.Parent := P;
    IconLbl.Caption := Items[I].Icon;
    IconLbl.Left := 8; IconLbl.Top := 6;
    IconLbl.Font.Size := 11;
    if Items[I].Status = 'done' then IconLbl.Font.Color := CLR_GREEN
    else if Items[I].Status = 'running' then IconLbl.Font.Color := CLR_AMBER
    else IconLbl.Font.Color := CLR_DGRAY;
    IconLbl.Transparent := True;

    TextLbl := TLabel.Create(P);
    TextLbl.Parent := P;
    TextLbl.Caption := Items[I].Text;
    TextLbl.Left := 32; TextLbl.Top := 8;
    TextLbl.Font.Size := 9;
    TextLbl.Font.Color := CLR_TEXT;
    TextLbl.Transparent := True;

    StatusLbl := TLabel.Create(P);
    StatusLbl.Parent := P;
    StatusLbl.Caption := Items[I].Status;
    StatusLbl.Top := 8;
    StatusLbl.Font.Size := 8;
    StatusLbl.Font.Color := CLR_DGRAY;
    StatusLbl.Anchors := [akTop, akRight];
    StatusLbl.Left := P.ClientWidth - StatusLbl.Width - 8;
    StatusLbl.Transparent := True;
  end;
end;

// ═══════════════════════════════════════════════════════════════════
//  Work items
// ═══════════════════════════════════════════════════════════════════
procedure TMainForm.AddWorkItems;
type
  TWorkRec = record Text, Priority: string; end;
var
  Items: array[0..3] of TWorkRec;
  I: Integer;
  P: TPanel;
  TextLbl, PrioLbl: TLabel;
  PrioColor: TColor;
begin
  Items[0].Text := 'Implement GRISP runtime'; Items[0].Priority := 'High';
  Items[1].Text := 'Add graph visualization'; Items[1].Priority := 'Medium';
  Items[2].Text := 'Write unit tests';        Items[2].Priority := 'Medium';
  Items[3].Text := 'Update LSBP integration'; Items[3].Priority := 'Low';

  for I := 0 to 3 do
  begin
    P := TPanel.Create(FRightWorkBox);
    P.Parent := FRightWorkBox;
    P.Left := 8;
    P.Top := 8 + I * 40;
    P.Width := FRightWorkBox.ClientWidth - 16;
    P.Height := 34;
    P.BevelOuter := bvNone;
    P.Color := CLR_HEAD;
    P.ParentBackground := False;
    P.Anchors := [akLeft, akTop, akRight];

    TextLbl := TLabel.Create(P);
    TextLbl.Parent := P;
    TextLbl.Caption := Items[I].Text;
    TextLbl.Left := 10; TextLbl.Top := 10;
    TextLbl.Font.Size := 9;
    TextLbl.Font.Color := CLR_TEXT;
    TextLbl.Transparent := True;

    if Items[I].Priority = 'High' then PrioColor := CLR_AMBER
    else if Items[I].Priority = 'Medium' then PrioColor := CLR_SKY
    else PrioColor := CLR_GRAY;

    PrioLbl := TLabel.Create(P);
    PrioLbl.Parent := P;
    PrioLbl.Caption := Items[I].Priority;
    PrioLbl.Font.Size := 8;
    PrioLbl.Font.Style := [fsBold];
    PrioLbl.Font.Color := PrioColor;
    PrioLbl.Anchors := [akTop, akRight];
    PrioLbl.Left := P.ClientWidth - PrioLbl.Width - 12;
    PrioLbl.Top := 11;
    PrioLbl.Transparent := True;
  end;
end;

// ═══════════════════════════════════════════════════════════════════
//  Chat: bericht toevoegen
// ═══════════════════════════════════════════════════════════════════
procedure TMainForm.AddMessage(const Sender, Text: string; IsUser: Boolean);
var
  MsgPanel: TPanel;
  HdrPanel: TPanel;
  SenderLbl, TimeLbl: TLabel;
  BubblePanel: TChatMessagePanel;
  TextLbl: TLabel;
  Bmp: TBitmap;
  R: TRect;
  BubbleH, TextW, TextH: Integer;
  BubbleW: Integer;
begin
  BubbleW := FChatScroll.ClientWidth - 80;
  if BubbleW < 200 then BubbleW := 200;
  TextW := BubbleW - 28;

  MsgPanel := TPanel.Create(FChatScroll);
  MsgPanel.Parent := FChatScroll;
  MsgPanel.Align := alTop;
  MsgPanel.AlignWithMargins := True;
  MsgPanel.Margins.SetBounds(16, 8, 16, 8);
  MsgPanel.BevelOuter := bvNone;
  MsgPanel.Color := CLR_MAIN;
  MsgPanel.ParentBackground := False;

  HdrPanel := TPanel.Create(MsgPanel);
  HdrPanel.Parent := MsgPanel;
  HdrPanel.Align := alTop;
  HdrPanel.Height := 22;
  HdrPanel.BevelOuter := bvNone;
  HdrPanel.Color := CLR_MAIN;
  HdrPanel.ParentBackground := False;

  SenderLbl := TLabel.Create(HdrPanel);
  SenderLbl.Parent := HdrPanel;
  SenderLbl.Caption := '◆ ' + Sender;
  SenderLbl.Left := 0;
  SenderLbl.Top := 2;
  SenderLbl.Font.Size := 9;
  SenderLbl.Font.Style := [fsBold];
  if IsUser then SenderLbl.Font.Color := CLR_USER_TXT
  else SenderLbl.Font.Color := CLR_CYAN;
  SenderLbl.Transparent := True;

  TimeLbl := TLabel.Create(HdrPanel);
  TimeLbl.Parent := HdrPanel;
  TimeLbl.Caption := FormatDateTime('hh:nn', Now);
  TimeLbl.Font.Size := 8;
  TimeLbl.Font.Color := CLR_GRAY;
  TimeLbl.Anchors := [akTop, akRight];
  TimeLbl.Left := HdrPanel.ClientWidth - TimeLbl.Width - 4;
  TimeLbl.Transparent := True;

  BubblePanel := TChatMessagePanel.Create(MsgPanel);
  BubblePanel.Parent := MsgPanel;
  BubblePanel.Align := alTop;
  BubblePanel.AlignWithMargins := True;
  BubblePanel.Margins.SetBounds(0, 4, 0, 0);
  BubblePanel.IsUser := IsUser;

  TextLbl := TLabel.Create(BubblePanel);
  TextLbl.Parent := BubblePanel;
  TextLbl.Caption := Text;
  TextLbl.Left := 14;
  TextLbl.Top := 10;
  TextLbl.Width := TextW;
  TextLbl.AutoSize := False;
  TextLbl.WordWrap := True;
  TextLbl.Font.Name := 'Segoe UI';
  TextLbl.Font.Size := 10;
  TextLbl.Font.Color := CLR_TEXT;
  TextLbl.Transparent := True;

  Bmp := TBitmap.Create;
  try
    Bmp.Canvas.Font.Assign(TextLbl.Font);
    R := Rect(0, 0, TextW, 0);
    DrawText(Bmp.Canvas.Handle, PChar(Text), Length(Text), R,
      DT_CALCRECT or DT_WORDBREAK);
    TextH := R.Bottom - R.Top;
  finally
    Bmp.Free;
  end;

  BubbleH := TextH + 20;
  if BubbleH < 40 then BubbleH := 40;
  BubblePanel.Height := BubbleH;

  MsgPanel.Height := 22 + 4 + BubbleH + 4;

  FChatScroll.VertScrollBar.Position :=
    FChatScroll.VertScrollBar.Range;
end;

// ═══════════════════════════════════════════════════════════════════
//  Send message
// ═══════════════════════════════════════════════════════════════════
procedure TMainForm.SendMessage;
var
  UserText: string;
begin
  UserText := Trim(FInput.Text);
  if UserText = '' then Exit;

  AddMessage('You', UserText, True);
  FInput.Clear;

  AddMessage('GRISP Assistant', 'Processing: ' + UserText, False);
end;

// ═══════════════════════════════════════════════════════════════════
//  Event handlers
// ═══════════════════════════════════════════════════════════════════
procedure TMainForm.FSendBtnClick(Sender: TObject);
begin
  SendMessage;
end;

procedure TMainForm.FInputKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then
  begin
    Key := #0;
    SendMessage;
  end;
end;

procedure TMainForm.FTimerTick(Sender: TObject);
begin
  FClockLbl.Caption := FormatDateTime('hh:nn:ss', Now);
end;

end.
