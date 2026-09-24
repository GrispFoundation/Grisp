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
    C_BG, C_PANEL, C_PANEL2, C_ACCENT, C_TEXT, C_TEXT_DIM, C_GREEN, C_USER: TColor;

    pnlTop, pnlLeft, pnlCenter, pnlBottom: TPanel;
    pnlSessions, pnlExplorer, pnlThink, pnlWorkPlan: TPanel;

    btnToggleSessions, btnToggleExplorer, btnToggleThink: TSpeedButton;
    lstSessions: TListBox;
    tvExplorer: TTreeView;
    memThink: TMemo;
    memChat: TRichEdit;          // <-- aangepast naar TRichEdit
    memWorkPlan: TMemo;
    edtInput: TEdit;
    btnSend: TButton;
    lblTitle, lblWorkPlanTitle: TLabel;

    FSessionsCollapsed, FExplorerCollapsed, FThinkCollapsed: Boolean;

    procedure BuildUI;
    procedure ApplyTheme;
    procedure PopulateSessions;
    procedure PopulateExplorer;
    procedure PopulateWorkPlan;
    procedure AddChat(const AWho, AText: string; IsUser: Boolean = False);
  public
  end;

var
  FrmMain: TFrmMain;

implementation

{$R *.dfm}

procedure TFrmMain.FormCreate(Sender: TObject);
begin
  C_BG       := $00140E0A;
  C_PANEL    := $00221812;
  C_PANEL2   := $002C211A;
  C_ACCENT   := $00E8B830;
  C_TEXT     := $00F2EAE2;
  C_TEXT_DIM := $009A8C82;
  C_GREEN    := $0058C878;
  C_USER     := $0078B8F0;

  Caption := 'GRISP OS';
  Color := C_BG;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  Font.Color := C_TEXT;
  Position := poScreenCenter;
  Width := 1340;
  Height := 880;
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
  AddChat('You', 'Create a plan for integrating the VFS layer with the existing core.', True);
  AddChat('GRISP', 'Understood. I''ll review the project structure and VFS layer, then propose a structured plan.');
end;

procedure TFrmMain.BuildUI;
begin
  // Top
  pnlTop := TPanel.Create(Self);
  pnlTop.Parent := Self;
  pnlTop.Align := alTop;
  pnlTop.Height := 48;
  pnlTop.BevelOuter := bvNone;
  pnlTop.ParentBackground := False;

  lblTitle := TLabel.Create(Self);
  lblTitle.Parent := pnlTop;
  lblTitle.Left := 20;
  lblTitle.Top := 14;
  lblTitle.Caption := 'GRISP OS';
  lblTitle.Font.Size := 14;
  lblTitle.Font.Style := [fsBold];

  // Left
  pnlLeft := TPanel.Create(Self);
  pnlLeft.Parent := Self;
  pnlLeft.Align := alLeft;
  pnlLeft.Width := 275;
  pnlLeft.BevelOuter := bvNone;
  pnlLeft.ParentBackground := False;

  // Sessions
  pnlSessions := TPanel.Create(Self);
  pnlSessions.Parent := pnlLeft;
  pnlSessions.Align := alTop;
  pnlSessions.Height := 215;
  pnlSessions.BevelOuter := bvNone;
  pnlSessions.ParentBackground := False;

  btnToggleSessions := TSpeedButton.Create(Self);
  btnToggleSessions.Parent := pnlSessions;
  btnToggleSessions.Align := alTop;
  btnToggleSessions.Height := 32;
  btnToggleSessions.Caption := '   SESSIONS   ▲';
  btnToggleSessions.Flat := True;
  btnToggleSessions.Font.Style := [fsBold];
  btnToggleSessions.OnClick := btnToggleSessionsClick;

  lstSessions := TListBox.Create(Self);
  lstSessions.Parent := pnlSessions;
  lstSessions.Align := alClient;
  lstSessions.BorderStyle := bsNone;
  lstSessions.ItemHeight := 21;
  lstSessions.Font.Size := 9;

  // Explorer
  pnlExplorer := TPanel.Create(Self);
  pnlExplorer.Parent := pnlLeft;
  pnlExplorer.Align := alClient;
  pnlExplorer.BevelOuter := bvNone;
  pnlExplorer.ParentBackground := False;

  btnToggleExplorer := TSpeedButton.Create(Self);
  btnToggleExplorer.Parent := pnlExplorer;
  btnToggleExplorer.Align := alTop;
  btnToggleExplorer.Height := 32;
  btnToggleExplorer.Caption := '   EXPLORER   ▲';
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
  tvExplorer.Indent := 19;

  // Center
  pnlCenter := TPanel.Create(Self);
  pnlCenter.Parent := Self;
  pnlCenter.Align := alClient;
  pnlCenter.BevelOuter := bvNone;
  pnlCenter.ParentBackground := False;

  // Think
  pnlThink := TPanel.Create(Self);
  pnlThink.Parent := pnlCenter;
  pnlThink.Align := alTop;
  pnlThink.Height := 66;
  pnlThink.BevelOuter := bvNone;
  pnlThink.ParentBackground := False;

  btnToggleThink := TSpeedButton.Create(Self);
  btnToggleThink.Parent := pnlThink;
  btnToggleThink.Align := alTop;
  btnToggleThink.Height := 28;
  btnToggleThink.Caption := '   THINK   ▲';
  btnToggleThink.Flat := True;
  btnToggleThink.Font.Style := [fsBold];
  btnToggleThink.OnClick := btnToggleThinkClick;

  memThink := TMemo.Create(Self);
  memThink.Parent := pnlThink;
  memThink.Align := alClient;
  memThink.BorderStyle := bsNone;
  memThink.ReadOnly := True;
  memThink.ScrollBars := ssNone;
  memThink.Text := 'Analyzing project structure... checking VFS layer... identifying integration points...';
  memThink.Font.Size := 9;

  // Chat - nu TRichEdit
  memChat := TRichEdit.Create(Self);
  memChat.Parent := pnlCenter;
  memChat.Align := alClient;
  memChat.BorderStyle := bsNone;
  memChat.ReadOnly := True;
  memChat.ScrollBars := ssVertical;
  memChat.Font.Name := 'Consolas';
  memChat.Font.Size := 10;
  memChat.ParentColor := False;

  // Work Plan
  pnlWorkPlan := TPanel.Create(Self);
  pnlWorkPlan.Parent := pnlCenter;
  pnlWorkPlan.Align := alBottom;
  pnlWorkPlan.Height := 148;
  pnlWorkPlan.BevelOuter := bvNone;
  pnlWorkPlan.ParentBackground := False;

  lblWorkPlanTitle := TLabel.Create(Self);
  lblWorkPlanTitle.Parent := pnlWorkPlan;
  lblWorkPlanTitle.Left := 14;
  lblWorkPlanTitle.Top := 10;
  lblWorkPlanTitle.Caption := 'Proposed Work Plan';
  lblWorkPlanTitle.Font.Style := [fsBold];
  lblWorkPlanTitle.Font.Size := 9;

  memWorkPlan := TMemo.Create(Self);
  memWorkPlan.Parent := pnlWorkPlan;
  memWorkPlan.Left := 12;
  memWorkPlan.Top := 32;
  memWorkPlan.Height := 106;
  memWorkPlan.BorderStyle := bsNone;
  memWorkPlan.ReadOnly := True;
  memWorkPlan.Font.Name := 'Consolas';
  memWorkPlan.Font.Size := 9;
  memWorkPlan.ScrollBars := ssVertical;

  // Bottom
  pnlBottom := TPanel.Create(Self);
  pnlBottom.Parent := Self;
  pnlBottom.Align := alBottom;
  pnlBottom.Height := 60;
  pnlBottom.BevelOuter := bvNone;
  pnlBottom.ParentBackground := False;

  edtInput := TEdit.Create(Self);
  edtInput.Parent := pnlBottom;
  edtInput.Left := 16;
  edtInput.Top := 14;
  edtInput.Height := 34;
  edtInput.TextHint := 'Ask GRISP anything...';
  edtInput.Font.Size := 10;
  edtInput.OnKeyPress := edtInputKeyPress;

  btnSend := TButton.Create(Self);
  btnSend.Parent := pnlBottom;
  btnSend.Width := 96;
  btnSend.Height := 34;
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
    edtInput.Width := pnlBottom.ClientWidth - 130;
    btnSend.Left := pnlBottom.ClientWidth - 112;
    btnSend.Top := 13;
    memWorkPlan.Width := pnlWorkPlan.ClientWidth - 28;
  end;
end;

procedure TFrmMain.btnToggleSessionsClick(Sender: TObject);
begin
  FSessionsCollapsed := not FSessionsCollapsed;
  if FSessionsCollapsed then
  begin
    pnlSessions.Height := 32;
    btnToggleSessions.Caption := '   SESSIONS   ▼';
  end
  else
  begin
    pnlSessions.Height := 215;
    btnToggleSessions.Caption := '   SESSIONS   ▲';
  end;
end;

procedure TFrmMain.btnToggleExplorerClick(Sender: TObject);
begin
  FExplorerCollapsed := not FExplorerCollapsed;
  tvExplorer.Visible := not FExplorerCollapsed;
  if FExplorerCollapsed then
    btnToggleExplorer.Caption := '   EXPLORER   ▼'
  else
    btnToggleExplorer.Caption := '   EXPLORER   ▲';
end;

procedure TFrmMain.btnToggleThinkClick(Sender: TObject);
begin
  FThinkCollapsed := not FThinkCollapsed;
  if FThinkCollapsed then
  begin
    pnlThink.Height := 28;
    memThink.Visible := False;
    btnToggleThink.Caption := '   THINK   ▼';
  end
  else
  begin
    pnlThink.Height := 66;
    memThink.Visible := True;
    btnToggleThink.Caption := '   THINK   ▲';
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
  root := tvExplorer.Items.Add(nil, '📁 project-grisp             R W X');
  src := tvExplorer.Items.AddChild(root, '📁 src                      R W X');
  tvExplorer.Items.AddChild(src, '📄 vfs.c                    R - X');
  tvExplorer.Items.AddChild(src, '📄 init.c                   R - X');
  tvExplorer.Items.AddChild(src, '📄 utils.h                  R - X');
  tvExplorer.Items.AddChild(root, '📁 core                     R W X');
  tvExplorer.Items.AddChild(root, '📁 include                  R - X');
  tvExplorer.Items.AddChild(root, '📁 docs                     R - -');
  tvExplorer.Items.AddChild(root, '📄 README.md                R - -');
  tvExplorer.FullExpand;
end;

procedure TFrmMain.PopulateWorkPlan;
begin
  memWorkPlan.Lines.Clear;
  memWorkPlan.Lines.Add('1. Analyze VFS Layer                       Pending');
  memWorkPlan.Lines.Add('2. Define Integration Points               Pending');
  memWorkPlan.Lines.Add('3. Design Abstraction Layer                Pending');
  memWorkPlan.Lines.Add('4. Implement & Refactor                    Pending');
  memWorkPlan.Lines.Add('5. Validate & Test                         Pending');
  memWorkPlan.Lines.Add('');
  memWorkPlan.Lines.Add('Estimated effort: 2–3 days');
end;

procedure TFrmMain.AddChat(const AWho, AText: string; IsUser: Boolean);
begin
  memChat.SelStart := memChat.GetTextLen;
  memChat.SelLength := 0;

  // Lege regel
  memChat.SelText := #13#10;

  // Naam
  memChat.SelStart := memChat.GetTextLen;
  if IsUser then
    memChat.SelAttributes.Color := C_USER
  else
    memChat.SelAttributes.Color := C_GREEN;

  memChat.SelAttributes.Style := [fsBold];
  memChat.SelText := AWho + ':';

  // Tekst
  memChat.SelStart := memChat.GetTextLen;
  memChat.SelAttributes.Color := C_TEXT;
  memChat.SelAttributes.Style := [];
  memChat.SelText := #13#10 + AText + #13#10;

  memChat.Perform(EM_SCROLLCARET, 0, 0);
end;

procedure TFrmMain.btnSendClick(Sender: TObject);
var
  txt: string;
begin
  txt := Trim(edtInput.Text);
  if txt = '' then Exit;

  AddChat('You', txt, True);
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
