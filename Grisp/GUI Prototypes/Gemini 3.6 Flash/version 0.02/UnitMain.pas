unit UnitMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.ComCtrls,
  Vcl.StdCtrls, Vcl.Buttons;

const
  CLR_BG_DARK      = $00121010;
  CLR_PANEL_BG     = $001C1A18;
  CLR_BORDER_CYAN  = $00FFFE00; // Cyan (BBGGRR)
  CLR_TEXT_WHITE   = $00FAF8F8;
  CLR_TEXT_GRAY    = $008B7B70;
  CLR_ACCENT_BLUE  = $00F8BD38;
  CLR_ACCENT_YELLOW= $0015CCFA;
  CLR_ACCENT_GREEN = $0080DE4A;
  FONT_TERMINAL    = 'Consolas';

type
  // Subclass voor panelen met een cyaan rand
  TCyanPanel = class(TPanel)
  protected
    procedure Paint; override;
  end;

  TFormMain = class(TForm)
    procedure FormCreate(Sender: TObject);
  private
    pnlTopHeader: TPanel;
    btnToggleSidebar: TSpeedButton;
    lblHeaderTitle: TLabel;

    pnlSidebar: TPanel;
    splSidebar: TSplitter;
    lblProjHeader: TLabel;
    tvFiles: TTreeView;
    lblSessHeader: TLabel;
    lbSessions: TListBox;

    pnlMainWorkspace: TPanel;
    pnlWorkspaceHeader: TLabel;

    pnlThinkingCard: TCyanPanel;
    lblThinkingTitle: TLabel;
    lblThinkingContent: TLabel;
    btnToggleThink: TSpeedButton;

    lblResponseText: TLabel;

    pnlWorkPlanCard: TCyanPanel;
    lblWorkPlanTitle: TLabel;
    chkStep1: TCheckBox;
    chkStep2: TCheckBox;
    chkStep3: TCheckBox;

    pnlChatBar: TCyanPanel;
    lblChatTitle: TLabel;
    pnlInputArea: TPanel;
    lblPromptSymbol: TLabel;
    edtChatInput: TEdit;

    procedure SetupTheme;
    procedure BuildUI;
    procedure PopulateData;
    procedure OnToggleSidebarClick(Sender: TObject);
    procedure OnToggleThinkClick(Sender: TObject);
    procedure OnChatInputKeyPress(Sender: TObject; var Key: Char);
  public
  end;

var
  FormMain: TFormMain;

implementation

{$R *.dfm}

{ TCyanPanel }

procedure TCyanPanel.Paint;
begin
  inherited Paint;
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Color := CLR_BORDER_CYAN;
  Canvas.Pen.Width := 1;
  Canvas.Rectangle(0, 0, Width, Height);
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
  Self.Caption := 'GRISP OS GUI WORKSPACE';
  Self.Width := 1150;
  Self.Height := 750;
  Self.Position := poScreenCenter;
  Self.Color := CLR_BG_DARK;
  Self.Font.Name := FONT_TERMINAL;
  Self.Font.Size := 10;
  Self.DoubleBuffered := True;
end;

procedure TFormMain.BuildUI;
begin
  // --- TOP HEADER BAR ---
  pnlTopHeader := TPanel.Create(Self);
  pnlTopHeader.Parent := Self;
  pnlTopHeader.Align := alTop;
  pnlTopHeader.Height := 40;
  pnlTopHeader.Color := CLR_PANEL_BG;
  pnlTopHeader.ParentBackground := False;
  pnlTopHeader.BevelOuter := bvNone;

  btnToggleSidebar := TSpeedButton.Create(pnlTopHeader);
  btnToggleSidebar.Parent := pnlTopHeader;
  btnToggleSidebar.Align := alLeft;
  btnToggleSidebar.Width := 140;
  btnToggleSidebar.Caption := '[Tab] Sidebar';
  btnToggleSidebar.Flat := True;
  btnToggleSidebar.Font.Name := FONT_TERMINAL;
  btnToggleSidebar.Font.Color := CLR_TEXT_WHITE;
  btnToggleSidebar.Font.Style := [fsBold];
  btnToggleSidebar.OnClick := OnToggleSidebarClick;

  lblHeaderTitle := TLabel.Create(pnlTopHeader);
  lblHeaderTitle.Parent := pnlTopHeader;
  lblHeaderTitle.Align := alRight;
  lblHeaderTitle.Alignment := taRightJustify;
  lblHeaderTitle.Layout := tlCenter;
  lblHeaderTitle.Caption := 'GRISP OS TERMINAL GUI ';
  lblHeaderTitle.Font.Name := FONT_TERMINAL;
  lblHeaderTitle.Font.Color := CLR_BORDER_CYAN;
  lblHeaderTitle.Font.Style := [fsBold];

  // --- SIDEBAR PANEL ---
  pnlSidebar := TPanel.Create(Self);
  pnlSidebar.Parent := Self;
  pnlSidebar.Align := alLeft;
  pnlSidebar.Width := 320;
  pnlSidebar.Color := CLR_BG_DARK;
  pnlSidebar.ParentBackground := False;
  pnlSidebar.BevelOuter := bvNone;

  splSidebar := TSplitter.Create(Self);
  splSidebar.Parent := Self;
  splSidebar.Align := alLeft;
  splSidebar.Width := 3;
  splSidebar.Color := CLR_BORDER_CYAN;

  // 1. Project Explorer Header (BOVENAAN)
  lblProjHeader := TLabel.Create(pnlSidebar);
  lblProjHeader.Parent := pnlSidebar;
  lblProjHeader.Align := alTop;
  lblProjHeader.Caption := ' PROJECT EXPLORER';
  lblProjHeader.Font.Name := FONT_TERMINAL;
  lblProjHeader.Font.Color := CLR_TEXT_WHITE;
  lblProjHeader.Font.Style := [fsBold];
  lblProjHeader.Height := 28;
  lblProjHeader.Layout := tlCenter;

  // 2. TreeView voor bestanden
  tvFiles := TTreeView.Create(pnlSidebar);
  tvFiles.Parent := pnlSidebar;
  tvFiles.Align := alTop;
  tvFiles.Height := 220;
  tvFiles.Color := CLR_PANEL_BG;
  tvFiles.Font.Name := FONT_TERMINAL;
  tvFiles.Font.Color := CLR_TEXT_WHITE;
  tvFiles.BorderStyle := bsNone;
  tvFiles.ReadOnly := True;

  // 3. Session History Header (ONDER DE TREEVIEW)
  lblSessHeader := TLabel.Create(pnlSidebar);
  lblSessHeader.Parent := pnlSidebar;
  lblSessHeader.Align := alTop;
  lblSessHeader.Caption := ' SESSIE GESCHIEDENIS';
  lblSessHeader.Font.Name := FONT_TERMINAL;
  lblSessHeader.Font.Color := CLR_TEXT_WHITE;
  lblSessHeader.Font.Style := [fsBold];
  lblSessHeader.Height := 32;
  lblSessHeader.Layout := tlBottom;

  // 4. ListBox voor sessies
  lbSessions := TListBox.Create(pnlSidebar);
  lbSessions.Parent := pnlSidebar;
  lbSessions.Align := alClient;
  lbSessions.Color := CLR_PANEL_BG;
  lbSessions.Font.Name := FONT_TERMINAL;
  lbSessions.Font.Color := CLR_TEXT_WHITE;
  lbSessions.BorderStyle := bsNone;

  // --- MAIN WORKSPACE ---
  pnlMainWorkspace := TPanel.Create(Self);
  pnlMainWorkspace.Parent := Self;
  pnlMainWorkspace.Align := alClient;
  pnlMainWorkspace.Color := CLR_BG_DARK;
  pnlMainWorkspace.ParentBackground := False;
  pnlMainWorkspace.BevelOuter := bvNone;
  pnlMainWorkspace.Padding.Left := 15;
  pnlMainWorkspace.Padding.Right := 15;
  pnlMainWorkspace.Padding.Top := 10;
  pnlMainWorkspace.Padding.Bottom := 10;

  pnlWorkspaceHeader := TLabel.Create(pnlMainWorkspace);
  pnlWorkspaceHeader.Parent := pnlMainWorkspace;
  pnlWorkspaceHeader.Align := alTop;
  pnlWorkspaceHeader.Caption := 'AI ASSISTANT WORKSPACE';
  pnlWorkspaceHeader.Font.Name := FONT_TERMINAL;
  pnlWorkspaceHeader.Font.Color := CLR_ACCENT_BLUE;
  pnlWorkspaceHeader.Font.Style := [fsBold];
  pnlWorkspaceHeader.Height := 30;

  // --- THINKING PROCESS CARD ---
  pnlThinkingCard := TCyanPanel.Create(pnlMainWorkspace);
  pnlThinkingCard.Parent := pnlMainWorkspace;
  pnlThinkingCard.Align := alTop;
  pnlThinkingCard.Height := 75;
  pnlThinkingCard.Color := CLR_PANEL_BG;
  pnlThinkingCard.ParentBackground := False;
  pnlThinkingCard.BevelOuter := bvNone;
  pnlThinkingCard.Padding.Left := 10;
  pnlThinkingCard.Padding.Top := 8;

  lblThinkingTitle := TLabel.Create(pnlThinkingCard);
  lblThinkingTitle.Parent := pnlThinkingCard;
  lblThinkingTitle.Align := alTop;
  lblThinkingTitle.Caption := '💭 THINKING PROCESS (Ctrl+T to toggle)';
  lblThinkingTitle.Font.Name := FONT_TERMINAL;
  lblThinkingTitle.Font.Color := CLR_ACCENT_YELLOW;
  lblThinkingTitle.Font.Style := [fsBold];

  btnToggleThink := TSpeedButton.Create(pnlThinkingCard);
  btnToggleThink.Parent := pnlThinkingCard;
  btnToggleThink.Align := alRight;
  btnToggleThink.Width := 90;
  btnToggleThink.Caption := 'Inklappen';
  btnToggleThink.Flat := True;
  btnToggleThink.Font.Name := FONT_TERMINAL;
  btnToggleThink.Font.Color := CLR_TEXT_GRAY;
  btnToggleThink.OnClick := OnToggleThinkClick;

  lblThinkingContent := TLabel.Create(pnlThinkingCard);
  lblThinkingContent.Parent := pnlThinkingCard;
  lblThinkingContent.Align := alClient;
  lblThinkingContent.Caption := '> Analyseren van AST nodes en geheugenallocaties in compiler.pas... (gecollapse)';
  lblThinkingContent.Font.Name := FONT_TERMINAL;
  lblThinkingContent.Font.Color := CLR_TEXT_GRAY;
  lblThinkingContent.Layout := tlCenter;

  lblResponseText := TLabel.Create(pnlMainWorkspace);
  lblResponseText.Parent := pnlMainWorkspace;
  lblResponseText.Align := alTop;
  lblResponseText.Caption := #13#10'Hier is de voorgestelde logica voor de compiler module:'#13#10;
  lblResponseText.Font.Name := FONT_TERMINAL;
  lblResponseText.Font.Color := CLR_TEXT_WHITE;
  lblResponseText.Height := 50;

  // --- INLINE WORK PLAN CARD ---
  pnlWorkPlanCard := TCyanPanel.Create(pnlMainWorkspace);
  pnlWorkPlanCard.Parent := pnlMainWorkspace;
  pnlWorkPlanCard.Align := alTop;
  pnlWorkPlanCard.Height := 130;
  pnlWorkPlanCard.Color := CLR_PANEL_BG;
  pnlWorkPlanCard.ParentBackground := False;
  pnlWorkPlanCard.BevelOuter := bvNone;
  pnlWorkPlanCard.Padding.Left := 12;
  pnlWorkPlanCard.Padding.Top := 8;

  lblWorkPlanTitle := TLabel.Create(pnlWorkPlanCard);
  lblWorkPlanTitle.Parent := pnlWorkPlanCard;
  lblWorkPlanTitle.Align := alTop;
  lblWorkPlanTitle.Caption := 'INLINE WORK PLAN';
  lblWorkPlanTitle.Font.Name := FONT_TERMINAL;
  lblWorkPlanTitle.Font.Color := CLR_ACCENT_GREEN;
  lblWorkPlanTitle.Font.Style := [fsBold];
  lblWorkPlanTitle.Height := 25;

  chkStep1 := TCheckBox.Create(pnlWorkPlanCard);
  chkStep1.Parent := pnlWorkPlanCard;
  chkStep1.Align := alTop;
  chkStep1.Caption := '[X] Step 1: Lexer uitbreiden met nieuwe tokens';
  chkStep1.Checked := True;
  chkStep1.Font.Name := FONT_TERMINAL;
  chkStep1.Font.Color := CLR_ACCENT_GREEN;

  chkStep2 := TCheckBox.Create(pnlWorkPlanCard);
  chkStep2.Parent := pnlWorkPlanCard;
  chkStep2.Align := alTop;
  chkStep2.Caption := '[ ] Step 2: Code generator aanpassen voor AST nodes';
  chkStep2.Font.Name := FONT_TERMINAL;
  chkStep2.Font.Color := CLR_TEXT_WHITE;

  chkStep3 := TCheckBox.Create(pnlWorkPlanCard);
  chkStep3.Parent := pnlWorkPlanCard;
  chkStep3.Align := alTop;
  chkStep3.Caption := '[ ] Step 3: Testsuite uitvoeren en permissies valideren';
  chkStep3.Font.Name := FONT_TERMINAL;
  chkStep3.Font.Color := CLR_TEXT_WHITE;

  // --- CHAT BAR ---
  pnlChatBar := TCyanPanel.Create(pnlMainWorkspace);
  pnlChatBar.Parent := pnlMainWorkspace;
  pnlChatBar.Align := alBottom;
  pnlChatBar.Height := 65;
  pnlChatBar.Color := CLR_PANEL_BG;
  pnlChatBar.ParentBackground := False;
  pnlChatBar.BevelOuter := bvNone;
  pnlChatBar.Padding.Left := 10;
  pnlChatBar.Padding.Right := 10;
  pnlChatBar.Padding.Top := 5;

  lblChatTitle := TLabel.Create(pnlChatBar);
  lblChatTitle.Parent := pnlChatBar;
  lblChatTitle.Align := alTop;
  lblChatTitle.Caption := 'CHAT BAR (Typ bijv. /refactor, [Esc] Stop)';
  lblChatTitle.Font.Name := FONT_TERMINAL;
  lblChatTitle.Font.Color := CLR_TEXT_WHITE;
  lblChatTitle.Font.Style := [fsBold];
  lblChatTitle.Height := 20;

  pnlInputArea := TPanel.Create(pnlChatBar);
  pnlInputArea.Parent := pnlChatBar;
  pnlInputArea.Align := alClient;
  pnlInputArea.BevelOuter := bvNone;
  pnlInputArea.Color := CLR_PANEL_BG;

  lblPromptSymbol := TLabel.Create(pnlInputArea);
  lblPromptSymbol.Parent := pnlInputArea;
  lblPromptSymbol.Align := alLeft;
  lblPromptSymbol.Caption := '> ';
  lblPromptSymbol.Font.Name := FONT_TERMINAL;
  lblPromptSymbol.Font.Color := CLR_ACCENT_BLUE;
  lblPromptSymbol.Font.Style := [fsBold];
  lblPromptSymbol.Layout := tlCenter;

  edtChatInput := TEdit.Create(pnlInputArea);
  edtChatInput.Parent := pnlInputArea;
  edtChatInput.Align := alClient;
  edtChatInput.Color := CLR_PANEL_BG;
  edtChatInput.Font.Name := FONT_TERMINAL;
  edtChatInput.Font.Color := CLR_TEXT_WHITE;
  edtChatInput.BorderStyle := bsNone;
  edtChatInput.OnKeyPress := OnChatInputKeyPress;
end;

procedure TFormMain.PopulateData;
var
  RootNode: TTreeNode;
begin
  tvFiles.Items.Clear;
  RootNode := tvFiles.Items.Add(nil, '▼ src/');
  tvFiles.Items.AddChild(RootNode, '   main.pas                [rwx]');
  tvFiles.Items.AddChild(RootNode, '   compiler.pas            [r-x]');
  tvFiles.Items.AddChild(RootNode, '   types.pas               [rw-]');
  tvFiles.Items.AddChild(RootNode, '   build.cmd               [--x]');
  tvFiles.FullExpand;

  lbSessions.Items.Clear;
  lbSessions.Items.Add(' ├── AST Parser Refactor');
  lbSessions.Items.Add(' │   2026-09-24  14:10');
  lbSessions.Items.Add(' ├── Memory Bugfix');
  lbSessions.Items.Add(' │   2026-09-23  09:45');
  lbSessions.Items.Add(' └── GRISP Canvas Integration');
  lbSessions.Items.Add('     2026-09-21  16:30');
end;

procedure TFormMain.OnToggleSidebarClick(Sender: TObject);
begin
  pnlSidebar.Visible := not pnlSidebar.Visible;
  splSidebar.Visible := pnlSidebar.Visible;
end;

procedure TFormMain.OnToggleThinkClick(Sender: TObject);
begin
  if pnlThinkingCard.Height = 75 then
  begin
    pnlThinkingCard.Height := 32;
    btnToggleThink.Caption := 'Uitklappen';
    lblThinkingContent.Visible := False;
  end
  else
  begin
    pnlThinkingCard.Height := 75;
    btnToggleThink.Caption := 'Inklappen';
    lblThinkingContent.Visible := True;
  end;
end;

procedure TFormMain.OnChatInputKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then
  begin
    Key := #0;
    if Trim(edtChatInput.Text) <> '' then
    begin
      ShowMessage('Commando verstuurd: ' + edtChatInput.Text);
      edtChatInput.Clear;
    end;
  end;
end;

end.
