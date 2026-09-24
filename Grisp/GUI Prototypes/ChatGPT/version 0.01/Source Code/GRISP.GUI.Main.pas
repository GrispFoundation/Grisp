// Style: semantic-prefixes v2.0

unit GRISP.GUI.Main;

interface

uses
    Winapi.Windows,
    Winapi.Messages,
    System.Classes,
    System.Math,
    System.SysUtils,
    System.Types,
    System.UITypes,
    Vcl.Controls,
    Vcl.Forms,
    Vcl.Graphics,
    Vcl.StdCtrls,
    Vcl.ExtCtrls;

type
    TGrispMainForm = class;

    TGrispPaintControl = class(TCustomControl)
    private
        mBorderColor: TColor;
        mFillColor: TColor;
    protected
        procedure Paint; override;
    public
        constructor Create(ParaOwner: TComponent); override;
        procedure SetColors(ParaFill, ParaBorder: TColor);
    end;

    TGrispActionButton = class(TCustomControl)
    private
        mText: string;
        mActive: Boolean;
        mHovered: Boolean;
        mOnExecute: TNotifyEvent;
        procedure WMMouseEnter(var ParaMessage: TMessage); message CM_MOUSEENTER;
        procedure WMMouseLeave(var ParaMessage: TMessage); message CM_MOUSELEAVE;
    protected
        procedure Paint; override;
        procedure Click; override;
    public
        constructor Create(ParaOwner: TComponent); override;
    published
        property Text: string read mText write mText;
        property Active: Boolean read mActive write mActive;
        property OnExecute: TNotifyEvent read mOnExecute write mOnExecute;
    end;

    TGrispExplorer = class(TGrispPaintControl)
    private
        mLines: TStringList;
    protected
        procedure Paint; override;
    public
        constructor Create(ParaOwner: TComponent); override;
        destructor Destroy; override;
    end;

    TGrispChatView = class(TGrispPaintControl)
    private
        mThinkExpanded: Boolean;
        mPlanExpanded: Boolean;
        mMessages: TStringList;
        mInput: string;
        procedure DrawWrappedText(
            ParaCanvas: TCanvas;
            const ParaText: string;
            ParaX, ParaY, ParaWidth: Integer;
            ParaColor: TColor;
            ParaBold: Boolean;
            var ParaBottom: Integer);
        procedure DrawCard(
            ParaCanvas: TCanvas;
            const ParaTitle, ParaBody: string;
            ParaX, ParaY, ParaWidth: Integer;
            ParaUser: Boolean;
            var ParaBottom: Integer);
    protected
        procedure Paint; override;
        procedure KeyPress(var Key: Char); override;
        procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    public
        constructor Create(ParaOwner: TComponent); override;
        destructor Destroy; override;
        procedure AddUserMessage(const ParaText: string);
        procedure AddAssistantMessage(const ParaText: string);
        procedure FocusInput;
        procedure ToggleThink;
        procedure TogglePlan;
    end;

    TGrispSessions = class(TGrispPaintControl)
    protected
        procedure Paint; override;
    end;

    TGrispStatusBar = class(TCustomControl)
    protected
        procedure Paint; override;
    end;

    TGrispMainForm = class(TForm)
    private
        mHeader: TPanel;
        mExplorer: TGrispExplorer;
        mChat: TGrispChatView;
        mSessions: TGrispSessions;
        mStatus: TGrispStatusBar;
        mExplorerButton: TGrispActionButton;
        mSessionsButton: TGrispActionButton;
        mThinkButton: TGrispActionButton;
        mPlanButton: TGrispActionButton;
        mNewSessionButton: TGrispActionButton;
        mMinimizeButton: TGrispActionButton;
        mCloseButton: TGrispActionButton;
        mExplorerVisible: Boolean;
        mSessionsVisible: Boolean;
        procedure ToggleExplorer(ParaSender: TObject);
        procedure ToggleSessions(ParaSender: TObject);
        procedure ToggleThink(ParaSender: TObject);
        procedure TogglePlan(ParaSender: TObject);
        procedure NewSession(ParaSender: TObject);
        procedure MinimizeWindow(ParaSender: TObject);
        procedure CloseWindow(ParaSender: TObject);
        procedure UpdateLayout;
        procedure FormResize(ParaSender: TObject);
        procedure FormKeyDown(ParaSender: TObject; var Key: Word; Shift: TShiftState);
    protected
        procedure CreateParams(var ParaParams: TCreateParams); override;
    public
        constructor Create(ParaOwner: TComponent); override;
    end;

const
    GrispBackground = $00110A02;
    GrispSurface = $001E1205;
    GrispBorder = $00784B00;
    GrispCyan = $00FFA800;
    GrispCyanBright = $00FFCD14;
    GrispText = $00FFF2E1;
    GrispTextDim = $00B9A07D;
    GrispGreen = $0096E100;
    GrispYellow = $0000BEFF;

var
    GrispMainForm: TGrispMainForm;

implementation

{$R *.dfm}

constructor TGrispPaintControl.Create(ParaOwner: TComponent);
begin
    inherited Create(ParaOwner);
    DoubleBuffered := True;
    Color := GrispSurface;
    mFillColor := GrispSurface;
    mBorderColor := GrispBorder;
    Font.Name := 'Segoe UI';
    Font.Size := 9;
end;

procedure TGrispPaintControl.SetColors(ParaFill, ParaBorder: TColor);
begin
    mFillColor := ParaFill;
    mBorderColor := ParaBorder;
    Invalidate;
end;

procedure TGrispPaintControl.Paint;
begin
    Canvas.Brush.Color := mFillColor;
    Canvas.FillRect(ClientRect);
    Canvas.Pen.Color := mBorderColor;
    Canvas.Pen.Width := 1;
    Canvas.Rectangle(0, 0, Width - 1, Height - 1);
end;

constructor TGrispActionButton.Create(ParaOwner: TComponent);
begin
    inherited Create(ParaOwner);
    DoubleBuffered := True;
    Cursor := crHandPoint;
    Width := 100;
    Height := 32;
    Font.Name := 'Segoe UI';
    Font.Size := 9;
    TabStop := True;
end;

procedure TGrispActionButton.WMMouseEnter(var ParaMessage: TMessage);
begin
    mHovered := True;
    Invalidate;
end;

procedure TGrispActionButton.WMMouseLeave(var ParaMessage: TMessage);
begin
    mHovered := False;
    Invalidate;
end;

procedure TGrispActionButton.Click;
begin
    inherited Click;
    if Assigned(mOnExecute) then
        mOnExecute(Self);
end;

procedure TGrispActionButton.Paint;
var
    vFill: TColor;
    vBorder: TColor;
    vTextRect: TRect;
begin
    if mActive then
        vFill := RGB(0, 48, 76)
    else if mHovered then
        vFill := RGB(0, 32, 52)
    else
        vFill := RGB(5, 22, 37);

    if mActive or mHovered then
        vBorder := GrispCyan
    else
        vBorder := RGB(0, 68, 105);

    Canvas.Brush.Color := vFill;
    Canvas.FillRect(ClientRect);
    Canvas.Pen.Color := vBorder;
    Canvas.Rectangle(0, 0, Width - 1, Height - 1);

    Canvas.Font.Assign(Font);
    Canvas.Font.Color := GrispText;
    Canvas.Font.Style := [];

    vTextRect := ClientRect;
    DrawText(Canvas.Handle, PChar(mText), Length(mText), vTextRect,
        DT_CENTER or DT_VCENTER or DT_SINGLELINE);
end;

constructor TGrispExplorer.Create(ParaOwner: TComponent);
begin
    inherited Create(ParaOwner);
    mLines := TStringList.Create;
    mLines.Add('▾  GRISP');
    mLines.Add('   ▾  Local');
    mLines.Add('      ▾  Projects');
    mLines.Add('         ▾  GRISP');
    mLines.Add('            ├─ src');
    mLines.Add('            ├─ tests');
    mLines.Add('            └─ docs');
    mLines.Add('         ├─ MME-Registry');
    mLines.Add('         └─ Agent-Network');
    mLines.Add('   ├─ Models');
    mLines.Add('   ├─ Agents');
    mLines.Add('   └─ Knowledge');
    Font.Name := 'Consolas';
    Font.Size := 10;
end;

destructor TGrispExplorer.Destroy;
begin
    mLines.Free;
    inherited Destroy;
end;

procedure TGrispExplorer.Paint;
var
    vIndex: Integer;
    vY: Integer;
begin
    inherited Paint;

    Canvas.Font.Name := 'Segoe UI';
    Canvas.Font.Size := 10;
    Canvas.Font.Color := GrispCyanBright;
    Canvas.Font.Style := [fsBold];
    Canvas.TextOut(16, 14, 'EXPLORER');

    Canvas.Font.Style := [];
    Canvas.Font.Color := GrispTextDim;
    Canvas.TextOut(16, 43, 'Search resources...');

    Canvas.Pen.Color := RGB(0, 55, 88);
    Canvas.MoveTo(14, 67);
    Canvas.LineTo(Width - 14, 67);

    Canvas.Font.Name := 'Consolas';
    Canvas.Font.Size := 10;
    vY := 84;

    for vIndex := 0 to mLines.Count - 1 do
    begin
        if vIndex = 3 then
        begin
            Canvas.Brush.Color := RGB(0, 44, 70);
            Canvas.FillRect(Rect(8, vY - 2, Width - 8, vY + 20));
            Canvas.Font.Color := GrispCyanBright;
        end
        else
            Canvas.Font.Color := GrispText;

        Canvas.TextOut(14, vY, mLines[vIndex]);

        if vIndex >= 3 then
        begin
            Canvas.Font.Color := GrispGreen;
            Canvas.TextOut(Width - 64, vY, 'R W');
        end;

        Inc(vY, 24);
    end;

    Canvas.Pen.Color := RGB(0, 55, 88);
    Canvas.MoveTo(14, Height - 145);
    Canvas.LineTo(Width - 14, Height - 145);

    Canvas.Font.Name := 'Segoe UI';
    Canvas.Font.Color := GrispCyanBright;
    Canvas.Font.Style := [fsBold];
    Canvas.TextOut(16, Height - 127, 'PERMISSIONS');

    Canvas.Font.Style := [];
    Canvas.Font.Color := GrispText;
    Canvas.TextOut(20, Height - 96, 'R   Read');
    Canvas.TextOut(20, Height - 72, 'W   Write');
    Canvas.TextOut(20, Height - 48, 'X   Execute');

    Canvas.Font.Color := GrispGreen;
    Canvas.TextOut(Width - 52, Height - 96, '✓');
    Canvas.TextOut(Width - 52, Height - 72, '✓');
    Canvas.TextOut(Width - 52, Height - 48, '✓');
end;

constructor TGrispChatView.Create(ParaOwner: TComponent);
begin
    inherited Create(ParaOwner);
    mMessages := TStringList.Create;
    TabStop := True;
    Color := GrispBackground;
    mThinkExpanded := False;
    mPlanExpanded := True;

    mMessages.Add('USER|14:32|Can you help me analyze the GRISP architecture and explain the main components?');
    mMessages.Add('ASSISTANT|14:32|GRISP is designed around a deterministic graph-based execution model. The main components are SIR, Planner, Evaluator, Validator, EIR, the GRISP runtime and WorldState.');
end;

destructor TGrispChatView.Destroy;
begin
    mMessages.Free;
    inherited Destroy;
end;

procedure TGrispChatView.AddUserMessage(const ParaText: string);
begin
    mMessages.Add('USER|' + FormatDateTime('hh:nn', Now) + '|' + ParaText);
    Invalidate;
end;

procedure TGrispChatView.AddAssistantMessage(const ParaText: string);
begin
    mMessages.Add('ASSISTANT|' + FormatDateTime('hh:nn', Now) + '|' + ParaText);
    Invalidate;
end;

procedure TGrispChatView.FocusInput;
begin
    SetFocus;
end;

procedure TGrispChatView.ToggleThink;
begin
    mThinkExpanded := not mThinkExpanded;
    Invalidate;
end;

procedure TGrispChatView.TogglePlan;
begin
    mPlanExpanded := not mPlanExpanded;
    Invalidate;
end;

procedure TGrispChatView.DrawWrappedText(
    ParaCanvas: TCanvas;
    const ParaText: string;
    ParaX, ParaY, ParaWidth: Integer;
    ParaColor: TColor;
    ParaBold: Boolean;
    var ParaBottom: Integer);
var
    vWords: TStringList;
    vLine: string;
    vWord: string;
    vIndex: Integer;
    vY: Integer;
begin
    vWords := TStringList.Create;
    try
        ExtractStrings([' ', #9], [], PChar(ParaText), vWords);
        vLine := '';
        vY := ParaY;
        ParaCanvas.Font.Color := ParaColor;

        if ParaBold then
            ParaCanvas.Font.Style := [fsBold]
        else
            ParaCanvas.Font.Style := [];

        for vIndex := 0 to vWords.Count - 1 do
        begin
            vWord := vWords[vIndex];

            if (vLine <> '') and
                (ParaCanvas.TextWidth(vLine + ' ' + vWord) > ParaWidth) then
            begin
                ParaCanvas.TextOut(ParaX, vY, vLine);
                Inc(vY, 19);
                vLine := vWord;
            end
            else if vLine = '' then
                vLine := vWord
            else
                vLine := vLine + ' ' + vWord;
        end;

        if vLine <> '' then
        begin
            ParaCanvas.TextOut(ParaX, vY, vLine);
            Inc(vY, 19);
        end;

        ParaBottom := vY;
    finally
        vWords.Free;
    end;
end;

procedure TGrispChatView.DrawCard(
    ParaCanvas: TCanvas;
    const ParaTitle, ParaBody: string;
    ParaX, ParaY, ParaWidth: Integer;
    ParaUser: Boolean;
    var ParaBottom: Integer);
var
    vBodyBottom: Integer;
    vHeight: Integer;
    vFill: TColor;
begin
    ParaCanvas.Font.Name := 'Segoe UI';
    ParaCanvas.Font.Size := 9;

    if ParaUser then
        vFill := RGB(6, 31, 52)
    else
        vFill := RGB(5, 23, 39);

    DrawWrappedText(
        ParaCanvas,
        ParaBody,
        ParaX + 14,
        ParaY + 34,
        ParaWidth - 28,
        GrispText,
        False,
        vBodyBottom);

    vHeight := Max(70, vBodyBottom - ParaY + 12);

    ParaCanvas.Brush.Color := vFill;
    ParaCanvas.Pen.Color := RGB(0, 74, 112);
    ParaCanvas.RoundRect(ParaX, ParaY, ParaX + ParaWidth, ParaY + vHeight, 8, 8);

    ParaCanvas.Font.Color := GrispCyanBright;
    ParaCanvas.Font.Style := [fsBold];
    ParaCanvas.TextOut(ParaX + 14, ParaY + 10, ParaTitle);

    ParaBottom := ParaY + vHeight + 14;
end;

procedure TGrispChatView.Paint;
var
    vIndex: Integer;
    vParts: TArray<string>;
    vY: Integer;
    vWidth: Integer;
    vBottom: Integer;
    vPlanHeight: Integer;
    vThinkHeight: Integer;
    vInputY: Integer;
begin
    Canvas.Brush.Color := GrispBackground;
    Canvas.FillRect(ClientRect);

    Canvas.Font.Name := 'Segoe UI';
    Canvas.Font.Size := 10;
    Canvas.Font.Color := GrispCyanBright;
    Canvas.Font.Style := [fsBold];
    Canvas.TextOut(18, 14, 'SESSION: GRISP architecture');

    Canvas.Font.Style := [];
    Canvas.Font.Color := GrispTextDim;
    Canvas.TextOut(Width - 190, 14, FormatDateTime('dd mmm yyyy hh:nn', Now));

    Canvas.Pen.Color := RGB(0, 55, 88);
    Canvas.MoveTo(14, 42);
    Canvas.LineTo(Width - 14, 42);

    vWidth := Width - 36;
    vY := 58;

    for vIndex := 0 to mMessages.Count - 1 do
    begin
        vParts := mMessages[vIndex].Split(['|']);
        if Length(vParts) >= 3 then
        begin
            DrawCard(
                Canvas,
                vParts[0] + '   ' + vParts[1],
                vParts[2],
                18,
                vY,
                vWidth,
                SameText(vParts[0], 'USER'),
                vBottom);
            vY := vBottom;
        end;
    end;

    if mPlanExpanded then
        vPlanHeight := 100
    else
        vPlanHeight := 42;

    Canvas.Brush.Color := RGB(5, 24, 41);
    Canvas.Pen.Color := RGB(0, 82, 120);
    Canvas.RoundRect(18, vY, Width - 18, vY + vPlanHeight, 8, 8);

    Canvas.Font.Color := GrispCyanBright;
    Canvas.Font.Style := [fsBold];
    Canvas.TextOut(32, vY + 12, 'PLAN / WORK ITEMS');
    Canvas.Font.Style := [];

    if mPlanExpanded then
    begin
        Canvas.Font.Color := GrispText;
        Canvas.TextOut(32, vY + 37, '[x] Analyze architecture');
        Canvas.Font.Color := GrispGreen;
        Canvas.TextOut(32, vY + 37, '[x]');
        Canvas.Font.Color := GrispText;
        Canvas.TextOut(32, vY + 59, '[>] Review component details');
        Canvas.Font.Color := GrispYellow;
        Canvas.TextOut(32, vY + 59, '[>]');
        Canvas.Font.Color := GrispText;
        Canvas.TextOut(32, vY + 81, '[ ] Update documentation');
    end;

    vY := vY + vPlanHeight + 10;

    if mThinkExpanded then
        vThinkHeight := 94
    else
        vThinkHeight := 42;

    Canvas.Brush.Color := RGB(5, 22, 38);
    Canvas.Pen.Color := RGB(0, 82, 120);
    Canvas.RoundRect(18, vY, Width - 18, vY + vThinkHeight, 8, 8);

    Canvas.Font.Color := GrispCyanBright;
    Canvas.Font.Style := [fsBold];
    Canvas.TextOut(32, vY + 12, 'THINK');
    Canvas.Font.Style := [];
    Canvas.Font.Color := GrispTextDim;

    if mThinkExpanded then
    begin
        Canvas.TextOut(88, vY + 12, 'expanded');
        Canvas.TextOut(32, vY + 37, '> Analyze architecture...');
        Canvas.TextOut(32, vY + 56, '> Identify execution stages...');
        Canvas.TextOut(32, vY + 75, '> Prepare response...');
    end
    else
        Canvas.TextOut(88, vY + 12, 'collapsed');

    vInputY := Height - 106;
    Canvas.Brush.Color := RGB(4, 20, 34);
    Canvas.Pen.Color := GrispCyan;
    Canvas.RoundRect(18, vInputY, Width - 18, Height - 18, 9, 9);

    Canvas.Font.Color := GrispTextDim;
    Canvas.Font.Style := [];
    if mInput = '' then
        Canvas.TextOut(32, vInputY + 18, 'Type your message...')
    else
    begin
        Canvas.Font.Color := GrispText;
        Canvas.TextOut(32, vInputY + 18, mInput);
    end;

    Canvas.Font.Color := GrispCyanBright;
    Canvas.Font.Style := [fsBold];
    Canvas.TextOut(Width - 72, Height - 55, 'SEND');
end;

procedure TGrispChatView.KeyPress(var Key: Char);
begin
    inherited KeyPress(Key);

    if Key = #13 then
    begin
        if Trim(mInput) <> '' then
        begin
            AddUserMessage(mInput);
            AddAssistantMessage(
                'I received the message. This prototype keeps the UI and session model separate so the real GRISP runtime can be connected next.');
            mInput := '';
            Invalidate;
        end;
        Key := #0;
        Exit;
    end;

    if Key = #8 then
    begin
        if Length(mInput) > 0 then
            Delete(mInput, Length(mInput), 1);
        Invalidate;
        Key := #0;
        Exit;
    end;

    if Ord(Key) >= 32 then
    begin
        mInput := mInput + Key;
        Invalidate;
    end;
end;

procedure TGrispChatView.MouseDown(
    Button: TMouseButton;
    Shift: TShiftState;
    X, Y: Integer);
var
    vInputY: Integer;
    vThinkY: Integer;
begin
    inherited MouseDown(Button, Shift, X, Y);

    if Button <> mbLeft then
        Exit;

    vInputY := Height - 106;
    vThinkY := vInputY - 62;

    if (Y >= vThinkY) and (Y < vThinkY + 45) then
        ToggleThink
    else if Y >= vInputY then
        FocusInput;
end;

procedure TGrispSessions.Paint;
begin
    inherited Paint;

    Canvas.Font.Name := 'Segoe UI';
    Canvas.Font.Size := 10;
    Canvas.Font.Color := GrispCyanBright;
    Canvas.Font.Style := [fsBold];
    Canvas.TextOut(16, 14, 'SESSIONS');

    Canvas.Font.Style := [];
    Canvas.Font.Color := GrispTextDim;
    Canvas.TextOut(16, 38, 'Chat history');

    Canvas.Pen.Color := RGB(0, 55, 88);
    Canvas.MoveTo(14, 62);
    Canvas.LineTo(Width - 14, 62);

    Canvas.Font.Color := GrispText;
    Canvas.TextOut(18, 82, 'GRISP architecture');
    Canvas.Font.Color := GrispTextDim;
    Canvas.TextOut(18, 101, '22 Sep 2026 14:32');

    Canvas.Font.Color := GrispText;
    Canvas.TextOut(18, 139, 'Data model discussion');
    Canvas.Font.Color := GrispTextDim;
    Canvas.TextOut(18, 158, '22 Sep 2026 11:48');

    Canvas.Font.Color := GrispText;
    Canvas.TextOut(18, 196, 'Bug investigation');
    Canvas.Font.Color := GrispTextDim;
    Canvas.TextOut(18, 215, '21 Sep 2026 16:20');

    Canvas.Font.Color := GrispText;
    Canvas.TextOut(18, 253, 'Feature planning');
    Canvas.Font.Color := GrispTextDim;
    Canvas.TextOut(18, 272, '20 Sep 2026 09:10');

    Canvas.Brush.Color := RGB(0, 39, 62);
    Canvas.Pen.Color := GrispCyan;
    Canvas.RoundRect(14, Height - 58, Width - 14, Height - 16, 7, 7);
    Canvas.Font.Color := GrispCyanBright;
    Canvas.Font.Style := [fsBold];
    Canvas.TextOut(30, Height - 45, '+ NEW SESSION');
end;

procedure TGrispStatusBar.Paint;
begin
    Canvas.Brush.Color := RGB(3, 16, 28);
    Canvas.FillRect(ClientRect);
    Canvas.Pen.Color := RGB(16, 73, 105);
    Canvas.Rectangle(0, 0, Width - 1, Height - 1);

    Canvas.Font.Name := 'Segoe UI';
    Canvas.Font.Size := 8;
    Canvas.Font.Color := GrispTextDim;

    Canvas.TextOut(14, 7, 'GRISP:/Workspace');
    Canvas.TextOut(230, 7, 'Session: GRISP architecture');
    Canvas.TextOut(480, 7, 'Model: GRISP Assistant');

    Canvas.Font.Color := GrispGreen;
    Canvas.TextOut(745, 7, 'R/W/X:  ✓  ✓  ✓');

    Canvas.Font.Color := GrispTextDim;
    Canvas.TextOut(Width - 250, 7, 'F2 Explorer   F3 Sessions   F4 Think');
end;

constructor TGrispMainForm.Create(ParaOwner: TComponent);
begin
    inherited Create(ParaOwner);

    BorderStyle := bsNone;
    Position := poScreenCenter;
    Width := 1450;
    Height := 900;
    Color := GrispBackground;
    DoubleBuffered := True;
    KeyPreview := True;
    OnResize := FormResize;
    OnKeyDown := FormKeyDown;

    mHeader := TPanel.Create(Self);
    mHeader.Parent := Self;
    mHeader.Align := alTop;
    mHeader.Height := 70;
    mHeader.BevelOuter := bvNone;
    mHeader.Color := RGB(3, 17, 30);

    mExplorer := TGrispExplorer.Create(Self);
    mExplorer.Parent := Self;

    mChat := TGrispChatView.Create(Self);
    mChat.Parent := Self;

    mSessions := TGrispSessions.Create(Self);
    mSessions.Parent := Self;

    mStatus := TGrispStatusBar.Create(Self);
    mStatus.Parent := Self;
    mStatus.DoubleBuffered := True;
    mStatus.Align := alBottom;
    mStatus.Height := 30;

    mExplorerButton := TGrispActionButton.Create(Self);
    mExplorerButton.Parent := mHeader;
    mExplorerButton.Text := 'EXPLORER';
    mExplorerButton.OnExecute := ToggleExplorer;

    mSessionsButton := TGrispActionButton.Create(Self);
    mSessionsButton.Parent := mHeader;
    mSessionsButton.Text := 'SESSIONS';
    mSessionsButton.OnExecute := ToggleSessions;

    mThinkButton := TGrispActionButton.Create(Self);
    mThinkButton.Parent := mHeader;
    mThinkButton.Text := 'THINK';
    mThinkButton.OnExecute := ToggleThink;

    mPlanButton := TGrispActionButton.Create(Self);
    mPlanButton.Parent := mHeader;
    mPlanButton.Text := 'PLAN';
    mPlanButton.OnExecute := TogglePlan;

    mNewSessionButton := TGrispActionButton.Create(Self);
    mNewSessionButton.Parent := mHeader;
    mNewSessionButton.Text := '+ NEW CHAT';
    mNewSessionButton.OnExecute := NewSession;

    mMinimizeButton := TGrispActionButton.Create(Self);
    mMinimizeButton.Parent := mHeader;
    mMinimizeButton.Text := '—';
    mMinimizeButton.OnExecute := MinimizeWindow;

    mCloseButton := TGrispActionButton.Create(Self);
    mCloseButton.Parent := mHeader;
    mCloseButton.Text := 'X';
    mCloseButton.OnExecute := CloseWindow;

    mExplorerVisible := True;
    mSessionsVisible := True;

    UpdateLayout;
end;

procedure TGrispMainForm.CreateParams(var ParaParams: TCreateParams);
begin
    inherited CreateParams(ParaParams);
    ParaParams.Style := ParaParams.Style or WS_THICKFRAME;
end;

procedure TGrispMainForm.FormResize(ParaSender: TObject);
begin
    UpdateLayout;
end;

procedure TGrispMainForm.UpdateLayout;
var
    vTop: Integer;
    vBottom: Integer;
    vExplorerWidth: Integer;
    vSessionsWidth: Integer;
    vChatLeft: Integer;
    vChatRight: Integer;
begin
    vTop := mHeader.Height + 8;
    vBottom := ClientHeight - mStatus.Height - 8;

    if mExplorerVisible then
        vExplorerWidth := 310
    else
        vExplorerWidth := 0;

    if mSessionsVisible then
        vSessionsWidth := 300
    else
        vSessionsWidth := 0;

    mExplorer.SetBounds(10, vTop, vExplorerWidth, Max(100, vBottom - vTop));
    mExplorer.Visible := mExplorerVisible;

    vChatLeft := 10 + vExplorerWidth;
    if mExplorerVisible then
        Inc(vChatLeft, 8);

    vChatRight := ClientWidth - 10 - vSessionsWidth;
    if mSessionsVisible then
        Dec(vChatRight, 8);

    mChat.SetBounds(
        vChatLeft,
        vTop,
        Max(300, vChatRight - vChatLeft),
        Max(100, vBottom - vTop));

    mSessions.SetBounds(
        vChatRight + IfThen(mSessionsVisible, 8, 0),
        vTop,
        vSessionsWidth,
        Max(100, vBottom - vTop));
    mSessions.Visible := mSessionsVisible;

    mExplorerButton.SetBounds(20, 19, 105, 34);
    mSessionsButton.SetBounds(132, 19, 105, 34);
    mThinkButton.SetBounds(244, 19, 90, 34);
    mPlanButton.SetBounds(341, 19, 90, 34);
    mNewSessionButton.SetBounds(ClientWidth - 360, 19, 120, 34);
    mMinimizeButton.SetBounds(ClientWidth - 112, 19, 40, 34);
    mCloseButton.SetBounds(ClientWidth - 66, 19, 40, 34);
end;

procedure TGrispMainForm.ToggleExplorer(ParaSender: TObject);
begin
    mExplorerVisible := not mExplorerVisible;
    UpdateLayout;
end;

procedure TGrispMainForm.ToggleSessions(ParaSender: TObject);
begin
    mSessionsVisible := not mSessionsVisible;
    UpdateLayout;
end;

procedure TGrispMainForm.ToggleThink(ParaSender: TObject);
begin
    mChat.ToggleThink;
    mThinkButton.Active := not mThinkButton.Active;
end;

procedure TGrispMainForm.TogglePlan(ParaSender: TObject);
begin
    mChat.TogglePlan;
    mPlanButton.Active := not mPlanButton.Active;
end;

procedure TGrispMainForm.NewSession(ParaSender: TObject);
begin
    mChat.AddAssistantMessage(
        'New GRISP session created. The session is ready for your next message.');
    mChat.FocusInput;
end;

procedure TGrispMainForm.MinimizeWindow(ParaSender: TObject);
begin
    Application.Minimize;
end;

procedure TGrispMainForm.CloseWindow(ParaSender: TObject);
begin
    Close;
end;

procedure TGrispMainForm.FormKeyDown(
    ParaSender: TObject;
    var Key: Word;
    Shift: TShiftState);
begin
    if Key = VK_F2 then
    begin
        ToggleExplorer(Self);
        Key := 0;
    end
    else if Key = VK_F3 then
    begin
        ToggleSessions(Self);
        Key := 0;
    end
    else if Key = VK_F4 then
    begin
        ToggleThink(Self);
        Key := 0;
    end
    else if (Key = Ord('N')) and (ssCtrl in Shift) then
    begin
        NewSession(Self);
        Key := 0;
    end;
end;

end.
