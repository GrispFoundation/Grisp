unit UnitMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.ComCtrls,
  Vcl.StdCtrls, Vcl.Buttons;

type
  TFormMain = class(TForm)
    procedure FormCreate(Sender: TObject);
  private
    // UI Panels & Layout controls
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

    // Cards
    pnlThinkingCard: TPanel;
    lblThinkingTitle: TLabel;
    lblThinkingContent: TLabel;
    btnToggleThink: TSpeedButton;

    lblResponseText: TLabel;

    pnlWorkPlanCard: TPanel;
    lblWorkPlanTitle: TLabel;
    chkStep1: TCheckBox;
    chkStep2: TCheckBox;
    chkStep3: TCheckBox;

    // Chat Bar
    pnlChatBar: TPanel;
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

const
  CLR_BG_DARK      = $00121010;
  CLR_PANEL_BG     = $001C1A18;
  CLR_BORDER_CYAN  = $00FFFE00;
  CLR_TEXT_WHITE   = $00FAF8F8;
  CLR_TEXT_GRAY    = $008B7B70;
  CLR_ACCENT_BLUE  = $00F8BD38;
  CLR_ACCENT_YELLOW= $0015CCFA;
  CLR_ACCENT_GREEN = $0080DE4A;

implementation

{$R *.dfm}

procedure TFormMain.FormCreate(Sender: TObject);
begin
  SetupTheme;
  BuildUI;
  PopulateData;
end;

procedure TFormMain.SetupTheme;
begin
  Self.Caption := 'GRISP OS GUI WORKSPACE';
  Self.Width := 1100;
  Self.Height := 750;
  Self.Position := poScreenCenter;
  Self.Color := CLR_BG_DARK;
  Self.DoubleBuffered := True;
end;

procedure TFormMain.BuildUI;
begin
  // TOP HEADER BAR
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
  btnToggleSidebar.Width := 110;
  btnToggleSidebar.Caption := ' [Tab] Sidebar ';
  btnToggleSidebar.Flat := True;
  btnToggleSidebar.Font.Color := CLR_TEXT_WHITE;
  btnToggleSidebar.Font.Style := [fsBold];
  btnToggleSidebar.OnClick := OnToggleSidebarClick;

  lblHeaderTitle := TLabel.Create(pnlTopHeader);
  lblHeaderTitle.Parent := pnlTopHeader;
  lblHeaderTitle.Align := alRight;
  lblHeaderTitle.Alignment := taRightJustify;
  lblHeaderTitle.Layout := tlCenter;
  lblHeaderTitle.Caption := 'GRISP OS TERMINAL GUI ';
  lblHeaderTitle.Font.Color := CLR_BORDER_CYAN;
  lblHeaderTitle.Font.Style := [fsBold];
  lblHeaderTitle.Font.Size := 10;

  // SIDEBAR PANEL
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
  splSidebar.Width := 4;
  splSidebar.Color := CLR_BORDER_CYAN;

  lblProjHeader := TLabel.Create(pnlSidebar);
  lblProjHeader.Parent := pnlSidebar;
  lblProjHeader.Align := alTop;
  lblProjHeader.Caption := ' PROJECT EXPLORER';
  lblProjHeader.Font.Color := CLR_TEXT_WHITE;
  lblProjHeader.Font.Style := [fsBold];
  lblProjHeader.Height := 28;
  lblProjHeader.Layout := tlCenter;

  tvFiles := TTreeView.Create(pnlSidebar);
  tvFiles.Parent := pnlSidebar;
  tvFiles.Align := alTop;
  tvFiles.Height := 220;
  tvFiles.Color := CLR_PANEL_BG;
  tvFiles.Font.Color := CLR_TEXT_WHITE;
  tvFiles.BorderStyle := bsNone;
  tvFiles.ReadOnly := True;

  lblSessHeader := TLabel.Create(pnlSidebar);
  lblSessHeader.Parent := pnlSidebar;
  lblSessHeader.Align := alTop;
  lblSessHeader.Caption := ' SESSIE GESCHIEDENIS';
  lblSessHeader.Font.Color := CLR_TEXT_WHITE;
  lblSessHeader.Font.Style := [fsBold];
  lblSessHeader.Height := 32;
  lblSessHeader.Layout := tlBottom;

  lbSessions := TListBox.Create(pnlSidebar);
  lbSessions.Parent := pnlSidebar;
  lbSessions.Align := alClient;
  lbSessions.Color := CLR_PANEL_BG;
  lbSessions.Font.Color := CLR_TEXT_WHITE;
  lbSessions.BorderStyle := bsNone;

  // MAIN WORKSPACE
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
  pnlWorkspaceHeader.Font.Color := CLR_ACCENT_BLUE;
  pnlWorkspaceHeader.Font.Style := [fsBold];
  pnlWorkspaceHeader.Font.Size := 11;
  pnlWorkspaceHeader.Height := 30;

  // THINKING PROCESS CARD
  pnlThinkingCard := TPanel.Create(pnlMainWorkspace);
  pnlThinkingCard.Parent := pnlMainWorkspace;
  pnlThinkingCard.Align := alTop;
  pnlThinkingCard.Height := 75;
  pnlThinkingCard.Color := CLR_PANEL_BG;
  pnlThinkingCard.ParentBackground := False;
  pnlThinkingCard.BevelOuter := bvNone;
  pnlThinkingCard.BorderStyle := bsSingle;
  pnlThinkingCard.Padding.Left := 10;
  pnlThinkingCard.Padding.Top := 8;

  lblThinkingTitle := TLabel.Create(pnlThinkingCard);
  lblThinkingTitle.Parent := pnlThinkingCard;
  lblThinkingTitle.Align := alTop;
  lblThinkingTitle.Caption := '💭 THINKING PROCESS (Ctrl+T to toggle)';
  lblThinkingTitle.Font.Color := CLR_ACCENT_YELLOW;
  lblThinkingTitle.Font.Style := [fsBold];

  btnToggleThink := TSpeedButton.Create(pnlThinkingCard);
  btnToggleThink.Parent := pnlThinkingCard;
  btnToggleThink.Align := alRight;
  btnToggleThink.Width := 80;
  btnToggleThink.Caption := 'Inklappen';
  btnToggleThink.Flat := True;
  btnToggleThink.Font.Color := CLR_TEXT_GRAY;
  btnToggleThink.OnClick := OnToggleThinkClick;

  lblThinkingContent := TLabel.Create(pnlThinkingCard);
  lblThinkingContent.Parent := pnlThinkingCard;
  lblThinkingContent.Align := alClient;
  lblThinkingContent.Caption := '> Analyseren van AST nodes en geheugenallocaties in compiler.pas... (gecollapse)';
  lblThinkingContent.Font.Color := CLR_TEXT_GRAY;
  lblThinkingContent.Layout := tlCenter;

  lblResponseText := TLabel.Create(pnlMainWorkspace);
  lblResponseText.Parent := pnlMainWorkspace;
  lblResponseText.Align := alTop;
  lblResponseText.Caption := #13#10'Hier is de voorgestelde logica voor de compiler module:'#13#10;
  lblResponseText.Font.Color := CLR_TEXT_WHITE;
  lblResponseText.Font.Size := 10;
  lblResponseText.Height := 50;

  // INLINE WORK PLAN CARD
  pnlWorkPlanCard := TPanel.Create(pnlMainWorkspace);
  pnlWorkPlanCard.Parent := pnlMainWorkspace;
  pnlWorkPlanCard.Align := alTop;
  pnlWorkPlanCard.Height := 130;
  pnlWorkPlanCard.Color := CLR_PANEL_BG;
  pnlWorkPlanCard.ParentBackground := False;
  pnlWorkPlanCard.BevelOuter := bvNone;
  pnlWorkPlanCard.BorderStyle := bsSingle;
  pnlWorkPlanCard.Padding.Left := 12;
  pnlWorkPlanCard.Padding.Top := 8;

  lblWorkPlanTitle := TLabel.Create(pnlWorkPlanCard);
  lblWorkPlanTitle.Parent := pnlWorkPlanCard;
  lblWorkPlanTitle.Align := alTop;
  lblWorkPlanTitle.Caption := 'INLINE WORK PLAN';
  lblWorkPlanTitle.Font.Color := CLR_ACCENT_GREEN;
  lblWorkPlanTitle.Font.Style := [fsBold];
  lblWorkPlanTitle.Height := 25;

  chkStep1 := TCheckBox.Create(pnlWorkPlanCard);
  chkStep1.Parent := pnlWorkPlanCard;
  chkStep1.Align := alTop;
  chkStep1.Caption := 'Step 1: Lexer uitbreiden met nieuwe tokens';
  chkStep1.Checked := True;
  chkStep1.Font.Color := CLR_TEXT_WHITE;

  chkStep2 := TCheckBox.Create(pnlWorkPlanCard);
  chkStep2.Parent := pnlWorkPlanCard;
  chkStep2.Align := alTop;
  chkStep2.Caption := 'Step 2: Code generator aanpassen voor AST nodes';
  chkStep2.Font.Color := CLR_TEXT_WHITE;

  chkStep3 := TCheckBox.Create(pnlWorkPlanCard);
  chkStep3.Parent := pnlWorkPlanCard;
  chkStep3.Align := alTop;
  chkStep3.Caption := 'Step 3: Testsuite uitvoeren en permissies valideren';
  chkStep3.Font.Color := CLR_TEXT_WHITE;

  // CHAT BAR
  pnlChatBar := TPanel.Create(pnlMainWorkspace);
  pnlChatBar.Parent := pnlMainWorkspace;
  pnlChatBar.Align := alBottom;
  pnlChatBar.Height := 70;
  pnlChatBar.Color := CLR_PANEL_BG;
  pnlChatBar.ParentBackground := False;
  pnlChatBar.BevelOuter := bvNone;
  pnlChatBar.BorderStyle := bsSingle;
  pnlChatBar.Padding.Left := 10;
  pnlChatBar.Padding.Right := 10;
  pnlChatBar.Padding.Top := 5;

  lblChatTitle := TLabel.Create(pnlChatBar);
  lblChatTitle.Parent := pnlChatBar;
  lblChatTitle.Align := alTop;
  lblChatTitle.Caption := 'CHAT BAR (Typ bijv. /refactor, [Esc] Stop)';
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
  lblPromptSymbol.Font.Color := CLR_ACCENT_BLUE;
  lblPromptSymbol.Font.Style := [fsBold];
  lblPromptSymbol.Font.Size := 11;
  lblPromptSymbol.Layout := tlCenter;

  edtChatInput := TEdit.Create(pnlInputArea);
  edtChatInput.Parent := pnlInputArea;
  edtChatInput.Align := alClient;
  edtChatInput.Color := CLR_PANEL_BG;
  edtChatInput.Font.Color := CLR_TEXT_WHITE;
  edtChatInput.Font.Size := 10;
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
