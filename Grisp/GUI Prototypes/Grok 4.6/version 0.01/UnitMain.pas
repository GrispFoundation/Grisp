unit UnitMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.StdCtrls,
  Vcl.ComCtrls, Vcl.Buttons;

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
    // Kleuren (BGR)
    C_BG: TColor;
    C_PANEL: TColor;
    C_PANEL2: TColor;
    C_ACCENT: TColor;
    C_TEXT: TColor;
    C_TEXT_DIM: TColor;

    // Panelen
    pnlTop: TPanel;
    pnlLeft: TPanel;
    pnlCenter: TPanel;
    pnlBottom: TPanel;
    pnlSessions: TPanel;
    pnlExplorer: TPanel;
    pnlThink: TPanel;

    // Controls
    btnToggleSessions: TSpeedButton;
    btnToggleExplorer: TSpeedButton;
    btnToggleThink: TSpeedButton;
    lstSessions: TListBox;
    tvExplorer: TTreeView;
    memThink: TMemo;
    memChat: TMemo;
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
    procedure AddChat(const AWho, AText: string; IsUser: Boolean = False);
  public
  end;

var
  FrmMain: TFrmMain;

implementation

{$R *.dfm}

procedure TFrmMain.FormCreate(Sender: TObject);
begin
  // Kleuren instellen
  C_BG       := $00140B07;  // #070B14
  C_PANEL    := $002A170F;  // #0F172A
  C_PANEL2   := $00331F14;  // #141F33
  C_ACCENT   := $00F8BD38;  // #38BDF8
  C_TEXT     := $00F0E6E2;
  C_TEXT_DIM := $00A08880;

  Caption := 'GRISP OS';
  Color := C_BG;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  Font.Color := C_TEXT;
  Position := poScreenCenter;
  Width := 1280;
  Height := 820;
  DoubleBuffered := True;

  FSessionsCollapsed := False;
  FExplorerCollapsed := False;
  FThinkCollapsed := False;

  BuildUI;
  ApplyTheme;
  PopulateSessions;
  PopulateExplorer;

  AddChat('GRISP', 'Hello Alex,'#13#10'How can I help you with GRISP today?');
  AddChat('You', 'Create a plan for integrating the VFS layer with the existing core.', True);
  AddChat('GRISP', 'Understood. I''ll review the project structure and VFS layer, then propose a structured plan.');
end;

procedure TFrmMain.BuildUI;
begin
  // ========== TOP ==========
  pnlTop := TPanel.Create(Self);
  pnlTop.Parent := Self;
  pnlTop.Align := alTop;
  pnlTop.Height := 42;
  pnlTop.BevelOuter := bvNone;
  pnlTop.ParentBackground := False;

  lblTitle := TLabel.Create(Self);
  lblTitle.Parent := pnlTop;
  lblTitle.Left := 16;
  lblTitle.Top := 12;
  lblTitle.Caption := 'GRISP OS';
  lblTitle.Font.Size := 12;
  lblTitle.Font.Style := [fsBold];

  // ========== LEFT ==========
  pnlLeft := TPanel.Create(Self);
  pnlLeft.Parent := Self;
  pnlLeft.Align := alLeft;
  pnlLeft.Width := 270;
  pnlLeft.BevelOuter := bvNone;
  pnlLeft.ParentBackground := False;

  // Sessions
  pnlSessions := TPanel.Create(Self);
  pnlSessions.Parent := pnlLeft;
  pnlSessions.Align := alTop;
  pnlSessions.Height := 210;
  pnlSessions.BevelOuter := bvNone;
  pnlSessions.ParentBackground := False;

  btnToggleSessions := TSpeedButton.Create(Self);
  btnToggleSessions.Parent := pnlSessions;
  btnToggleSessions.Align := alTop;
  btnToggleSessions.Height := 28;
  btnToggleSessions.Caption := '  SESSIONS   ▲';
  btnToggleSessions.Flat := True;
  btnToggleSessions.Font.Style := [fsBold];
  btnToggleSessions.OnClick := btnToggleSessionsClick;

  lstSessions := TListBox.Create(Self);
  lstSessions.Parent := pnlSessions;
  lstSessions.Align := alClient;
  lstSessions.BorderStyle := bsNone;
  lstSessions.ItemHeight := 22;

  // Explorer
  pnlExplorer := TPanel.Create(Self);
  pnlExplorer.Parent := pnlLeft;
  pnlExplorer.Align := alClient;
  pnlExplorer.BevelOuter := bvNone;
  pnlExplorer.ParentBackground := False;

  btnToggleExplorer := TSpeedButton.Create(Self);
  btnToggleExplorer.Parent := pnlExplorer;
  btnToggleExplorer.Align := alTop;
  btnToggleExplorer.Height := 28;
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
  pnlThink.Height := 72;
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

  // Chat
  memChat := TMemo.Create(Self);
  memChat.Parent := pnlCenter;
  memChat.Align := alClient;
  memChat.BorderStyle := bsNone;
  memChat.ReadOnly := True;
  memChat.ScrollBars := ssVertical;
  memChat.Font.Name := 'Consolas';
  memChat.Font.Size := 10;

  // ========== BOTTOM ==========
  pnlBottom := TPanel.Create(Self);
  pnlBottom.Parent := Self;
  pnlBottom.Align := alBottom;
  pnlBottom.Height := 56;
  pnlBottom.BevelOuter := bvNone;
  pnlBottom.ParentBackground := False;

  edtInput := TEdit.Create(Self);
  edtInput.Parent := pnlBottom;
  edtInput.Left := 12;
  edtInput.Top := 12;
  edtInput.Height := 32;
  edtInput.TextHint := 'Ask GRISP anything...';
  edtInput.OnKeyPress := edtInputKeyPress;

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

  lblTitle.Font.Color := C_TEXT;

  lstSessions.Color := C_PANEL;
  lstSessions.Font.Color := C_TEXT;

  tvExplorer.Color := C_PANEL;
  tvExplorer.Font.Color := C_TEXT;

  memThink.Color := C_PANEL2;
  memThink.Font.Color := C_TEXT_DIM;

  memChat.Color := C_BG;
  memChat.Font.Color := C_TEXT;

  edtInput.Color := C_PANEL2;
  edtInput.Font.Color := C_TEXT;

  btnToggleSessions.Font.Color := C_TEXT_DIM;
  btnToggleExplorer.Font.Color := C_TEXT_DIM;
  btnToggleThink.Font.Color := C_TEXT_DIM;
end;

procedure TFrmMain.FormResize(Sender: TObject);
begin
  if Assigned(edtInput) and Assigned(btnSend) then
  begin
    edtInput.Width := pnlBottom.ClientWidth - 120;
    btnSend.Left := pnlBottom.ClientWidth - 102;
    btnSend.Top := 12;
  end;
end;

procedure TFrmMain.btnToggleSessionsClick(Sender: TObject);
begin
  FSessionsCollapsed := not FSessionsCollapsed;
  if FSessionsCollapsed then
  begin
    pnlSessions.Height := 28;
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
    pnlThink.Height := 72;
    memThink.Visible := True;
    btnToggleThink.Caption := '  THINK   ▲';
  end;
end;

procedure TFrmMain.PopulateSessions;
begin
  lstSessions.Items.Clear;
  lstSessions.Items.Add('● Architecture Analysis');
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
  root := tvExplorer.Items.Add(nil, '📁 project-grisp     R W X');
  src := tvExplorer.Items.AddChild(root, '📁 src               R W X');
  tvExplorer.Items.AddChild(src, '📄 vfs.c             R - X');
  tvExplorer.Items.AddChild(src, '📄 init.c            R - X');
  tvExplorer.Items.AddChild(src, '📄 utils.h           R - X');
  tvExplorer.Items.AddChild(root, '📁 core              R W X');
  tvExplorer.Items.AddChild(root, '📁 include           R - X');
  tvExplorer.Items.AddChild(root, '📁 docs              R - -');
  tvExplorer.Items.AddChild(root, '📄 README.md         R - -');
  tvExplorer.FullExpand;
end;

procedure TFrmMain.AddChat(const AWho, AText: string; IsUser: Boolean);
begin
  memChat.Lines.Add('');
  memChat.Lines.Add(AWho + ':');
  memChat.Lines.Add(AText);
  memChat.Lines.Add('');
  // Scroll naar beneden
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
