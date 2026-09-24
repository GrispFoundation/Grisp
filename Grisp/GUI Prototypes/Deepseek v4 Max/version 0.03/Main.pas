unit Main;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, System.Generics.Collections, Vcl.Graphics, Vcl.Controls,
  Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.ComCtrls;

const
  APP_NAME    = 'GRISP OS';
  APP_VERSION = 'v1.0 GUI';

  CLR_MAIN     = $001A0E0A;
  CLR_PANEL    = $0024150D;
  CLR_BAR      = $00160C08;
  CLR_HEAD     = $003C2416;
  CLR_USER     = $008A3A1E;
  CLR_AI       = $003C2416;
  CLR_CYAN     = $00EED322;
  CLR_SKY      = $00F8BD38;
  CLR_BLUE     = $00F6823B;
  CLR_TEXT     = $00FFFFFF;
  CLR_GRAY     = $00B8A394;
  CLR_DGRAY    = $008B7464;
  CLR_BORDER   = $00554133;
  CLR_GREEN    = $005EC522;
  CLR_AMBER    = $000B9EF5;
  CLR_USER_TXT = $00FDC593;

type
  TBorderedPanel = class(TPanel)
  private
    FBorderColor: TColor;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    property BorderColor: TColor read FBorderColor write FBorderColor;
  end;

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

  TChatMessagePanel = class(TPanel)
  private
    FIsUser: Boolean;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    property IsUser: Boolean read FIsUser write FIsUser;
  end;

  TMainForm = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  private
    FTopBar, FStatusBar, FLeftPanel, FCenterPanel, FRightPanel: TPanel;
    FSplitterLeft, FSplitterRight: TSplitter;

    FLogo: TLabel;
    FBtnExplorer, FBtnAgents, FBtnWorkflows, FBtnKnowledge,
    FBtnModels, FBtnTools, FBtnTerminal, FBtnSettings: TNavButton;
    FClockLbl, FVersionLbl: TLabel;
    FStatusDot, FStatusText: TLabel;

    FResourcesHeader, FSessionsHeader: TBorderedPanel;
    FTree: TTreeView;
    FSessionList: TListBox;

    FChatHeader: TBorderedPanel;
    FChatScroll: TScrollBox;
    FInputBar: TPanel;
    FInput: TEdit;
    FSendBtn: TPanel;

    FRightPlanHeader, FRightWorkHeader: TBorderedPanel;
    FRightPlanBox, FRightWorkBox: TPanel;

    FTimer: TTimer;

    FShowLeftPanel, FShowRightPanel: Boolean;
    // ★ Teller voor chat-bericht positionering
    FContentHeight: Integer;

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
    procedure RelayoutLeftPanel;
    procedure RelayoutRightPanel;
    function MakeNavButton(AParent: TPanel; const ACaption: string;
      ALeft: Integer; AActive: Boolean = False): TNavButton;
    function MakeHeaderLabel(AParent: TPanel; const ACaption: string;
      ATop, AHeight: Integer): TBorderedPanel;
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
  Bg, Txt: TColor;
begin
  if FActive then Bg := CLR_HEAD
  else if FHover then Bg := CLR_PANEL
  else Bg := CLR_BAR;

  Canvas.Brush.Color := Bg;
  Canvas.FillRect(ClientRect);

  if FActive then
  begin
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

  BuildUI;
  PopulateData;

  AddMessage('GRISP Assistant',
    'Hello Alex, how can I help you with GRISP today?', False);

  AddPlanItems;
  AddWorkItems;

  ClientWidth  := 1400;
  ClientHeight := 850;
  Position := poScreenCenter;
end;

procedure TMainForm.FormResize(Sender: TObject);
begin
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
//  Helpers
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

function TMainForm.MakeHeaderLabel(AParent: TPanel; const ACaption: string;
  ATop, AHeight: Integer): TBorderedPanel;
var
  Lbl: TLabel;
begin
  Result := TBorderedPanel.Create(Self);
  Result.Parent := AParent;
  Result.Left := 0;
  Result.Top := ATop;
  Result.Height := AHeight;
  Result.Width := AParent.ClientWidth;
  Result.Anchors := [akLeft, akTop, akRight];
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
//  BuildUI
// ═══════════════════════════════════════════════════════════════════
procedure TMainForm.BuildUI;
begin
  Color := CLR_MAIN;
  DoubleBuffered := True;

  // ── Statusbar ──
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

  FLogo := TLabel.Create(FTopBar);
  FLogo.Parent := FTopBar;
  FLogo.Caption := '◈ ' + APP_NAME;
  FLogo.Left := 16;
  FLogo.Top := 14;
  FLogo.Font.Name := 'Segoe UI';
  FLogo.Font.Size := 14;
  FLogo.Font.Style := [fsBold];
  FLogo.Font.Color := CLR_CYAN;
  FLogo.Transparent := True;

  FVersionLbl := TLabel.Create(FTopBar);
  FVersionLbl.Parent := FTopBar;
  FVersionLbl.Caption := APP_VERSION;
  FVersionLbl.AutoSize := True;
  FVersionLbl.Left := FLogo.Left + 160;
  FVersionLbl.Top := 20;
  FVersionLbl.Font.Size := 8;
  FVersionLbl.Font.Color := CLR_DGRAY;
  FVersionLbl.Transparent := True;

  FBtnExplorer   := MakeNavButton(FTopBar, 'Explorer',   230, True);
  FBtnAgents     := MakeNavButton(FTopBar, 'Agents',     348);
  FBtnWorkflows  := MakeNavButton(FTopBar, 'Workflows',  466);
  FBtnKnowledge  := MakeNavButton(FTopBar, 'Knowledge',  584);
  FBtnModels     := MakeNavButton(FTopBar, 'Models',     702);
  FBtnTools      := MakeNavButton(FTopBar, 'Tools',      820);
  FBtnTerminal   := MakeNavButton(FTopBar, 'Terminal',   938);
  FBtnSettings   := MakeNavButton(FTopBar, 'Settings',  1056);

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

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 1000;
  FTimer.OnTimer := FTimerTick;
  FTimer.Enabled := True;

  // ── Rechter splitter + paneel ──
  FSplitterRight := TSplitter.Create(Self);
  FSplitterRight.Parent := Self;
  FSplitterRight.Align := alRight;
  FSplitterRight.Width := 2;
  FSplitterRight.Color := CLR_BORDER;
  FSplitterRight.MinSize := 200;

  FRightPanel := TPanel.Create(Self);
  FRightPanel.Parent := Self;
  FRightPanel.Align := alRight;
  FRightPanel.Width := 320;
  FRightPanel.BevelOuter := bvNone;
  FRightPanel.Color := CLR_PANEL;
  FRightPanel.ParentBackground := False;

  FRightPlanHeader := MakeHeaderLabel(FRightPanel, '◆  CURRENT PLAN', 0, 30);

  FRightPlanBox := TPanel.Create(FRightPanel);
  FRightPlanBox.Parent := FRightPanel;
  FRightPlanBox.Left := 0;
  FRightPlanBox.Top := 30;
  FRightPlanBox.Height := 180;
  FRightPlanBox.Width := FRightPanel.ClientWidth;
  FRightPlanBox.Anchors := [akLeft, akTop, akRight];
  FRightPlanBox.BevelOuter := bvNone;
  FRightPlanBox.Color := CLR_PANEL;
  FRightPlanBox.ParentBackground := False;

  FRightWorkHeader := MakeHeaderLabel(FRightPanel, '◆  WORK ITEMS', 210, 30);

  FRightWorkBox := TPanel.Create(FRightPanel);
  FRightWorkBox.Parent := FRightPanel;
  FRightWorkBox.Left := 0;
  FRightWorkBox.Top := 240;
  FRightWorkBox.Height := FRightPanel.ClientHeight - 240;
  FRightWorkBox.Width := FRightPanel.ClientWidth;
  FRightWorkBox.Anchors := [akLeft, akTop, akRight, akBottom];
  FRightWorkBox.BevelOuter := bvNone;
  FRightWorkBox.Color := CLR_PANEL;
  FRightWorkBox.ParentBackground := False;

  // ── Linker splitter + paneel ──
  FSplitterLeft := TSplitter.Create(Self);
  FSplitterLeft.Parent := Self;
  FSplitterLeft.Align := alLeft;
  FSplitterLeft.Width := 2;
  FSplitterLeft.Color := CLR_BORDER;
  FSplitterLeft.MinSize := 200;

  FLeftPanel := TPanel.Create(Self);
  FLeftPanel.Parent := Self;
  FLeftPanel.Align := alLeft;
  FLeftPanel.Width := 280;
  FLeftPanel.BevelOuter := bvNone;
  FLeftPanel.Color := CLR_PANEL;
  FLeftPanel.ParentBackground := False;

  FResourcesHeader := MakeHeaderLabel(FLeftPanel, '▾  RESOURCES', 0, 30);

  FTree := TTreeView.Create(FLeftPanel);
  FTree.Parent := FLeftPanel;
  FTree.Left := 0;
  FTree.Top := 30;
  FTree.Height := 220;
  FTree.Width := FLeftPanel.ClientWidth;
  FTree.Anchors := [akLeft, akTop, akRight];
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

  FSessionsHeader := MakeHeaderLabel(FLeftPanel, '▾  SESSIONS', 250, 30);

  FSessionList := TListBox.Create(FLeftPanel);
  FSessionList.Parent := FLeftPanel;
  FSessionList.Left := 0;
  FSessionList.Top := 280;
  FSessionList.Height := FLeftPanel.ClientHeight - 280;
  FSessionList.Width := FLeftPanel.ClientWidth;
  FSessionList.Anchors := [akLeft, akTop, akRight, akBottom];
  FSessionList.BorderStyle := bsNone;
  FSessionList.Color := CLR_PANEL;
  FSessionList.Font.Name := 'Segoe UI';
  FSessionList.Font.Size := 9;
  FSessionList.Font.Color := CLR_TEXT;

  // ── Center paneel ──
  FCenterPanel := TPanel.Create(Self);
  FCenterPanel.Parent := Self;
  FCenterPanel.Align := alClient;
  FCenterPanel.BevelOuter := bvNone;
  FCenterPanel.Color := CLR_MAIN;
  FCenterPanel.ParentBackground := False;

  FChatHeader := MakeHeaderLabel(FCenterPanel, '◆  CHAT · Architecture Review', 0, 30);
  FChatHeader.Color := CLR_MAIN;

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

  FChatScroll := TScrollBox.Create(FCenterPanel);
  FChatScroll.Parent := FCenterPanel;
  FChatScroll.Align := alClient;
  FChatScroll.BorderStyle := bsNone;
  FChatScroll.Color := CLR_MAIN;
  FChatScroll.ParentBackground := False;
  FChatScroll.VertScrollBar.Tracking := True;
  // ★ Reset chat-teller
  FContentHeight := 0;

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
//  Layout helpers
// ═══════════════════════════════════════════════════════════════════
procedure TMainForm.LayoutPanels;
begin
  if not Assigned(FSplitterLeft) or not Assigned(FLeftPanel) then Exit;
  if not Assigned(FSplitterRight) or not Assigned(FRightPanel) then Exit;

  FSplitterLeft.Visible  := FShowLeftPanel;
  FLeftPanel.Visible     := FShowLeftPanel;
  FSplitterRight.Visible := FShowRightPanel;
  FRightPanel.Visible    := FShowRightPanel;

  if Assigned(FClockLbl) and Assigned(FTopBar) then
    FClockLbl.Left := FTopBar.ClientWidth - 100;

  if Assigned(FSendBtn) and Assigned(FInputBar) and Assigned(FInput) then
  begin
    FSendBtn.Left := FInputBar.ClientWidth - FSendBtn.Width - 16;
    FInput.Width := FInputBar.ClientWidth - FSendBtn.Width - 48;
  end;

  RelayoutLeftPanel;
  RelayoutRightPanel;
end;

procedure TMainForm.RelayoutLeftPanel;
begin
  if not Assigned(FLeftPanel) or not Assigned(FTree) then Exit;

  FResourcesHeader.Width := FLeftPanel.ClientWidth;
  FTree.Width := FLeftPanel.ClientWidth;
  FSessionsHeader.Width := FLeftPanel.ClientWidth;
  FSessionsHeader.Top := FTree.Top + FTree.Height + 30;

  FSessionList.Width := FLeftPanel.ClientWidth;
  FSessionList.Top := FSessionsHeader.Top + FSessionsHeader.Height;
  FSessionList.Height := FLeftPanel.ClientHeight - FSessionList.Top;
end;

procedure TMainForm.RelayoutRightPanel;
begin
  if not Assigned(FRightPanel) or not Assigned(FRightPlanBox) then Exit;

  FRightPlanHeader.Width := FRightPanel.ClientWidth;
  FRightPlanBox.Width := FRightPanel.ClientWidth;
  FRightWorkHeader.Width := FRightPanel.ClientWidth;
  FRightWorkBox.Width := FRightPanel.ClientWidth;
  FRightWorkBox.Height := FRightPanel.ClientHeight - FRightWorkBox.Top;
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

    Root := FTree.Items.Add(nil, 'Local');

    Proj := FTree.Items.AddChild(Root, 'Projects   RWX');
    FTree.Items.AddChild(Proj, 'GRISP   RWX');
    FTree.Items.AddChild(Proj, 'MME-Registry   RW');
    FTree.Items.AddChild(Proj, 'Agent-Network   RW');

    Data := FTree.Items.AddChild(Root, 'Data   RW');
    FTree.Items.AddChild(Data, 'Models   RW');
    FTree.Items.AddChild(Data, 'Downloads   R');

    Cloud := FTree.Items.AddChild(Root, 'Cloud   R');

    Root.Expand(True);
    Root.Selected := True;
  finally
    FTree.Items.EndUpdate;
  end;

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
    P.Top := 6 + I * 38;
    P.Width := FRightPlanBox.ClientWidth - 16;
    P.Height := 32;
    P.BevelOuter := bvNone;
    P.Color := CLR_HEAD;
    P.ParentBackground := False;
    P.Anchors := [akLeft, akTop, akRight];

    IconLbl := TLabel.Create(P);
    IconLbl.Parent := P;
    IconLbl.Caption := Items[I].Icon;
    IconLbl.Left := 8; IconLbl.Top := 7;
    IconLbl.Font.Size := 11;
    if Items[I].Status = 'done' then IconLbl.Font.Color := CLR_GREEN
    else if Items[I].Status = 'running' then IconLbl.Font.Color := CLR_AMBER
    else IconLbl.Font.Color := CLR_DGRAY;
    IconLbl.Transparent := True;

    TextLbl := TLabel.Create(P);
    TextLbl.Parent := P;
    TextLbl.Caption := Items[I].Text;
    TextLbl.Left := 32; TextLbl.Top := 9;
    TextLbl.Font.Size := 9;
    TextLbl.Font.Color := CLR_TEXT;
    TextLbl.Transparent := True;

    StatusLbl := TLabel.Create(P);
    StatusLbl.Parent := P;
    StatusLbl.Caption := Items[I].Status;
    StatusLbl.Top := 9;
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
    P.Top := 6 + I * 42;
    P.Width := FRightWorkBox.ClientWidth - 16;
    P.Height := 36;
    P.BevelOuter := bvNone;
    P.Color := CLR_HEAD;
    P.ParentBackground := False;
    P.Anchors := [akLeft, akTop, akRight];

    TextLbl := TLabel.Create(P);
    TextLbl.Parent := P;
    TextLbl.Caption := Items[I].Text;
    TextLbl.Left := 10; TextLbl.Top := 11;
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
    PrioLbl.Top := 12;
    PrioLbl.Transparent := True;
  end;
end;

// ═══════════════════════════════════════════════════════════════════
//  Chat: bericht toevoegen — expliciete Top-positie via FContentHeight
// ═══════════════════════════════════════════════════════════════════
procedure TMainForm.AddMessage(const Sender, Text: string; IsUser: Boolean);
var
  MsgPanel, HdrPanel: TPanel;
  SenderLbl, TimeLbl: TLabel;
  BubblePanel: TChatMessagePanel;
  TextLbl: TLabel;
  Bmp: TBitmap;
  R: TRect;
  BubbleH, TextW, TextH: Integer;
begin
  TextW := FChatScroll.ClientWidth - 120;
  if TextW < 200 then TextW := 200;

  MsgPanel := TPanel.Create(FChatScroll);
  MsgPanel.Parent := FChatScroll;
  // ★ Expliciete positie — geen Align
  MsgPanel.Left := 16;
  MsgPanel.Top := FContentHeight;
  MsgPanel.Width := FChatScroll.ClientWidth - 32;
  MsgPanel.Anchors := [akLeft, akTop, akRight];
  MsgPanel.BevelOuter := bvNone;
  MsgPanel.Color := CLR_MAIN;
  MsgPanel.ParentBackground := False;

  HdrPanel := TPanel.Create(MsgPanel);
  HdrPanel.Parent := MsgPanel;
  HdrPanel.Left := 0;
  HdrPanel.Top := 0;
  HdrPanel.Width := MsgPanel.ClientWidth;
  HdrPanel.Height := 22;
  HdrPanel.Anchors := [akLeft, akTop, akRight];
  HdrPanel.BevelOuter := bvNone;
  HdrPanel.Color := CLR_MAIN;
  HdrPanel.ParentBackground := False;

  SenderLbl := TLabel.Create(HdrPanel);
  SenderLbl.Parent := HdrPanel;
  SenderLbl.Caption := '◆ ' + Sender;
  SenderLbl.Left := 4;
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
  BubblePanel.Left := 0;
  BubblePanel.Top := 26;
  BubblePanel.Width := MsgPanel.Width;
  BubblePanel.Anchors := [akLeft, akTop, akRight];
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

  MsgPanel.Height := 26 + BubbleH + 4;

  // ★ Update teller + scroll naar beneden
  FContentHeight := FContentHeight + MsgPanel.Height + 6;
  FChatScroll.VertScrollBar.Range := FContentHeight + 20;
  FChatScroll.VertScrollBar.Position := FContentHeight;
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
//  Events
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
