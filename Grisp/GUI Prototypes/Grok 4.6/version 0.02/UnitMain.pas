unit UnitMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls,
  Vcl.StdCtrls, Vcl.ComCtrls, Vcl.Buttons;

type
  TFrmMain = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure btnSendClick(Sender: TObject);
    procedure edtInputKeyPress(Sender: TObject; var Key: Char);
    procedure btnToggleSessionsClick(Sender: TObject);
    procedure btnToggleExplorerClick(Sender: TObject);
    procedure btnToggleThinkClick(Sender: TObject);
  private
    // Kleuren
    C_BG, C_PANEL, C_PANEL2, C_ACCENT, C_TEXT, C_TEXT_DIM, C_GREEN: TColor;

    // Hoofdstructuur
    pnlTop: TPanel;
    pnlLeft: TPanel;
    pnlCenter: TPanel;
    pnlBottom: TPanel;

    // Left
    pnlSessions: TPanel;
    btnToggleSessions: TSpeedButton;
    lstSessions: TListBox;

    pnlExplorer: TPanel;
    btnToggleExplorer: TSpeedButton;
    tvExplorer: TTreeView;

    // Center
    pnlThink: TPanel;
    btnToggleThink: TSpeedButton;
    memThink: TMemo;

    memChat: TMemo;

    pnlWorkPlan: TPanel;
    lblWorkPlanTitle: TLabel;
    memWorkPlan: TMemo;

    // Bottom
    edtInput: TEdit;
    btnSend: TButton;
    lblTitle: TLabel;

    FSessionsCollapsed: Boolean;
    FExplorerCollapsed: Boolean;
    FThinkCollapsed: Boolean;

    procedure BuildUI;
    procedure ApplyTheme;
    procedure PopulateSessions;
    procedure PopulateExplorer;
    procedure PopulateWorkPlan;
    procedure AddChat(const AWho, AText: string);
  public
  end;

var
  FrmMain: TFrmMain;

implementation

{$R *.dfm}

procedure TFrmMain.FormCreate(Sender: TObject);
begin
  // Kleuren (BGR)
  C_BG       := $001A0F0A;  // heel donker
  C_PANEL    := $002A1A12;
  C_PANEL2   := $00332218;
  C_ACCENT   := $00F0C040;  // zacht blauw/cyaan
  C_TEXT     := $00F0E8E0;
  C_TEXT_DIM := $009A8A80;
  C_GREEN    := $0050C878;

  Caption := 'GRISP OS';
  Color := C_BG;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  Font.Color := C_TEXT;
  Position := poScreenCenter;
  Width := 1320;
  Height := 860;
  DoubleBuffered := True;

  FSessionsCollapsed := False;
  FExplorerCollapsed := False;
  FThinkCollapsed := False;

  BuildUI;
  ApplyTheme;
  PopulateSessions;
  PopulateExplorer;
  PopulateWorkPlan;

  AddChat('GRISP', 'Hello Alex,'#13#10'How can I help you with GRISP today?');
  AddChat('You', 'Create a plan for integrating the VFS layer with the existing core.');
  AddChat('GRISP', 'Understood. I''ll review the project structure and VFS layer, then propose a structured plan.');
end;

procedure TFrmMain.BuildUI;
begin
  // ========== TOP ==========
  pnlTop := TPanel.Create(Self);
  pnlTop.Parent := Self;
  pnlTop.Align := alTop;
  pnlTop.Height := 46;
  pnlTop.BevelOuter := bvNone;
  pnlTop.ParentBackground := False;

  lblTitle := TLabel.Create(Self);
  lblTitle.Parent := pnlTop;
  lblTitle.Left := 18;
  lblTitle.Top := 13;
  lblTitle.Caption := 'GRISP OS';
  lblTitle.Font.Size := 13;
  lblTitle.Font.Style := [fsBold];

  // ========== LEFT ==========
  pnlLeft := TPanel.Create(Self);
  pnlLeft.Parent := Self;
  pnlLeft.Align := alLeft;
  pnlLeft.Width := 270;
  pnlLeft.BevelOuter := bvNone;
  pnlLeft.ParentBackground := False;

  // --- Sessions ---
  pnlSessions := TPanel.Create(Self);
  pnlSessions.Parent := pnlLeft;
  pnlSessions.Align := alTop;
  pnlSessions.Height := 210;
  pnlSessions.BevelOuter := bvNone;
  pnlSessions.ParentBackground := False;

  btnToggleSessions := TSpeedButton.Create(Self);
  btnToggleSessions.Parent := pnlSessions;
  btnToggleSessions.Align := alTop;
  btnToggleSessions.Height := 30;
  btnToggleSessions.Caption := '  SESSIONS   ▲';
  btnToggleSessions.Flat := True;
  btnToggleSessions.Font.Style := [fsBold];
  btnToggleSessions.OnClick := btnToggleSessionsClick;

  lstSessions := TListBox.Create(Self);
  lstSessions.Parent := pnlSessions;
  lstSessions.Align := alClient;
  lstSessions.BorderStyle := bsNone;
  lstSessions.ItemHeight := 20;
  lstSessions.Font.Size := 9;

  // --- Explorer ---
  pnlExplorer := TPanel.Create(Self);
  pnlExplorer.Parent := pnlLeft;
  pnlExplorer.Align := alClient;
  pnlExplorer.BevelOuter := bvNone;
  pnlExplorer.ParentBackground := False;

  btnToggleExplorer := TSpeedButton.Create(Self);
  btnToggleExplorer.Parent := pnlExplorer;
  btnToggleExplorer.Align := alTop;
  btnToggleExplorer.Height := 30;
  btnToggleExplorer.Caption := '  EXPLORER   ▲';
  btnToggleExplorer.Flat := True;
  btnToggleExplorer.Font.Style := [fsBold];
  btnToggleExplorer.OnClick := btnToggleExplorerClick;

  tvExplorer := TTreeView.Create(Self);
  tvExplorer.Parent := pnlExplorer;
  tvExplorer.Align := alClient;
  tvExplorer.BorderStyle := bsNone;
  tvExplorer.ReadOnly := True;
  tvExplorer.ShowRoot := False;
  tvExplorer.Font.Size := 9;
  tvExplorer.Indent := 18;

  // ========== CENTER ==========
  pnlCenter := TPanel.Create(Self);
  pnlCenter.Parent := Self;
  pnlCenter.Align := alClient;
  pnlCenter.BevelOuter := bvNone;
  pnlCenter.ParentBackground := False;

  // Think
  pnlThink := TPanel.Create(Self);
  pnlThink.Parent := pnlCenter;
  pnlThink.Align := alTop;
  pnlThink.Height := 68;
  pnlThink.BevelOuter := bvNone;
  pnlThink.ParentBackground := False;

  btnToggleThink := TSpeedButton.Create(Self);
  btnToggleThink.Parent := pnlThink;
  btnToggleThink.Align := alTop;
  btnToggleThink.Height := 26;
  btnToggleThink.Caption := '  THINK   ▲';
  btnToggleThink.Flat := True;
  btnToggleThink.Font.Style := [fsBold];
  btnToggleThink.OnClick := btnToggleThinkClick;

  memThink := TMemo.Create(Self);
  memThink.Parent := pnlThink;
  memThink.Align := alClient;
  memThink.BorderStyle := bsNone;
  memThink.ReadOnly := True;
  memThink.Text := 'Analyzing project structure... checking VFS layer... identifying integration points...';
  memThink.Font.Size := 9;

  // Chat
  memChat := TMemo.Create(Self);
  memChat.Parent := pnlCenter;
  memChat.Align := alClient;
  memChat.BorderStyle := bsNone;
  memChat.ReadOnly := True;
  memChat.ScrollBars := ssVertical;
  memChat.Font.Name := 'Consolas';
  memChat.Font.Size := 10;

  // Work Plan Card
  pnlWorkPlan := TPanel.Create(Self);
  pnlWorkPlan.Parent := pnlCenter;
  pnlWorkPlan.Align := alBottom;
  pnlWorkPlan.Height := 155;
  pnlWorkPlan.BevelOuter := bvNone;
  pnlWorkPlan.ParentBackground := False;

  lblWorkPlanTitle := TLabel.Create(Self);
  lblWorkPlanTitle.Parent := pnlWorkPlan;
  lblWorkPlanTitle.Left := 12;
  lblWorkPlanTitle.Top := 8;
  lblWorkPlanTitle.Caption := 'Proposed Work Plan';
  lblWorkPlanTitle.Font.Style := [fsBold];
  lblWorkPlanTitle.Font.Size := 9;

  memWorkPlan := TMemo.Create(Self);
  memWorkPlan.Parent := pnlWorkPlan;
  memWorkPlan.Left := 10;
  memWorkPlan.Top := 30;
  memWorkPlan.Width := 700;
  memWorkPlan.Height := 115;
  memWorkPlan.BorderStyle := bsNone;
  memWorkPlan.ReadOnly := True;
  memWorkPlan.Font.Name := 'Consolas';
  memWorkPlan.Font.Size := 9;
  memWorkPlan.ScrollBars := ssVertical;

  // ========== BOTTOM ==========
  pnlBottom := TPanel.Create(Self);
  pnlBottom.Parent := Self;
  pnlBottom.Align := alBottom;
  pnlBottom.Height := 58;
  pnlBottom.BevelOuter := bvNone;
  pnlBottom.ParentBackground := False;

  edtInput := TEdit.Create(Self);
  edtInput.Parent := pnlBottom;
  edtInput.Left := 14;
  edtInput.Top := 13;
  edtInput.Height := 32;
  edtInput.TextHint := 'Ask GRISP anything...';
  edtInput.OnKeyPress := edtInputKeyPress;
  edtInput.Font.Size := 10;

  btnSend := TButton.Create(Self);
  btnSend.Parent := pnlBottom;
  btnSend.Width := 90;
  btnSend.Height := 32;
  btnSend.Caption := 'Send';
  btnSend.OnClick := btnSendClick;
end;

procedure TFrmMain.ApplyTheme;
begin
  pnlTop.Color := C_PANEL;
  pnlLeft.Color := C_PANEL;
  pnlCenter.Color := C_BG;
  pnlBottom.Color := C_PANEL;
  pnlSessions.Color := C_PANEL;
  pnlExplorer.Color := C_PANEL;
  pnlThink.Color := C_PANEL2;
  pnlWorkPlan.Color := C_PANEL2;

  lblTitle.Font.Color := C_TEXT;
  lblWorkPlanTitle.Font.Color := C_GREEN;

  lstSessions.Color := C_PANEL;
  lstSessions.Font.Color := C_TEXT;

  tvExplorer.Color := C_PANEL;
  tvExplorer.Font.Color := C_TEXT;

  memThink.Color := C_PANEL2;
  memThink.Font.Color := C_TEXT_DIM;

  memChat.Color := C_BG;
  memChat.Font.Color := C_TEXT;

  memWorkPlan.Color := C_PANEL2;
  memWorkPlan.Font.Color := C_TEXT;

  edtInput.Color := C_PANEL2;
  edtInput.Font.Color := C_TEXT;

  btnToggleSessions.Font.Color := C_TEXT_DIM;
  btnToggleExplorer.Font.Color := C_TEXT_DIM;
  btnToggleThink.Font.Color := C_TEXT_DIM;
end;

procedure TFrmMain.FormResize(Sender: TObject);
begin
  if Assigned(edtInput) and Assigned(btnSend) and Assigned(memWorkPlan) then
  begin
    edtInput.Width := pnlBottom.ClientWidth - 120;
    btnSend.Left := pnlBottom.ClientWidth - 104;
    btnSend.Top := 13;

    memWorkPlan.Width := pnlWorkPlan.ClientWidth - 24;
  end;
end;

procedure TFrmMain.btnToggleSessionsClick(Sender: TObject);
begin
  FSessionsCollapsed := not FSessionsCollapsed;
  if FSessionsCollapsed then
  begin
    pnlSessions.Height := 30;
    btnToggleSessions.Caption := '  SESSIONS   ▼';
  end
  else
  begin
    pnlSessions.Height := 210;
    btnToggleSessions.Caption := '  SESSIONS   ▲';
  end;
end;

procedure TFrmMain.btnToggleExplorerClick(Sender: TObject);
begin
  FExplorerCollapsed := not FExplorerCollapsed;
  tvExplorer.Visible := not FExplorerCollapsed;
  if FExplorerCollapsed then
    btnToggleExplorer.Caption := '  EXPLORER   ▼'
  else
    btnToggleExplorer.Caption := '  EXPLORER   ▲';
end;

procedure TFrmMain.btnToggleThinkClick(Sender: TObject);
begin
  FThinkCollapsed := not FThinkCollapsed;
  if FThinkCollapsed then
  begin
    pnlThink.Height := 26;
    memThink.Visible := False;
    btnToggleThink.Caption := '  THINK   ▼';
  end
  else
  begin
    pnlThink.Height := 68;
    memThink.Visible := True;
    btnToggleThink.Caption := '  THINK   ▲';
  end;
end;

procedure TFrmMain.PopulateSessions;
begin
  lstSessions.Items.Clear;
  lstSessions.Items.Add('• Architecture Analysis');
  lstSessions.Items.Add('    Today 14:32');
  lstSessions.Items.Add('○ Project Setup');
  lstSessions.Items.Add('    Yesterday 09:15');
  lstSessions.Items.Add('○ Dependency Review');
  lstSessions.Items.Add('    May 18 11:03');
  lstSessions.Items.Add('');
  lstSessions.Items.Add('+ New Session');
end;

procedure TFrmMain.PopulateExplorer;
var
  root, src: TTreeNode;
begin
  tvExplorer.Items.Clear;
  root := tvExplorer.Items.Add(nil, '📁 project-grisp          R W X');
  src := tvExplorer.Items.AddChild(root, '📁 src                   R W X');
  tvExplorer.Items.AddChild(src, '📄 vfs.c                 R - X');
  tvExplorer.Items.AddChild(src, '📄 init.c                R - X');
  tvExplorer.Items.AddChild(src, '📄 utils.h               R - X');
  tvExplorer.Items.AddChild(root, '📁 core                  R W X');
  tvExplorer.Items.AddChild(root, '📁 include               R - X');
  tvExplorer.Items.AddChild(root, '📁 docs                  R - -');
  tvExplorer.Items.AddChild(root, '📄 README.md             R - -');
  tvExplorer.FullExpand;
end;

procedure TFrmMain.PopulateWorkPlan;
begin
  memWorkPlan.Lines.Clear;
  memWorkPlan.Lines.Add('1. Analyze VFS Layer                  Pending');
  memWorkPlan.Lines.Add('2. Define Integration Points          Pending');
  memWorkPlan.Lines.Add('3. Design Abstraction Layer           Pending');
  memWorkPlan.Lines.Add('4. Implement & Refactor               Pending');
  memWorkPlan.Lines.Add('5. Validate & Test                    Pending');
  memWorkPlan.Lines.Add('');
  memWorkPlan.Lines.Add('Estimated effort: 2–3 days');
end;

procedure TFrmMain.AddChat(const AWho, AText: string);
begin
  memChat.Lines.Add('');
  memChat.Lines.Add(AWho + ':');
  memChat.Lines.Add(AText);
  memChat.Lines.Add('');
  memChat.SelStart := memChat.GetTextLen;
  memChat.SelLength := 0;
  memChat.Perform(EM_SCROLLCARET, 0, 0);
end;

procedure TFrmMain.btnSendClick(Sender: TObject);
var
  txt: string;
begin
  txt := Trim(edtInput.Text);
  if txt = '' then Exit;

  AddChat('You', txt);
  edtInput.Clear;
  AddChat('GRISP', 'Processing your request: "' + txt + '". Updating work plan...');
end;

procedure TFrmMain.edtInputKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then
  begin
    Key := #0;
    btnSendClick(Sender);
  end;
end;

end.
