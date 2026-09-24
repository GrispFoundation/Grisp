unit GRISP.TUI.Renderer;

interface

uses
    System.SysUtils,
    System.Math,
    GRISP.TUI.Console,
    GRISP.TUI.Model;

type
    TGrispTUIRenderer = class
    private
        mConsole: TGrispConsole;
        mModel: TGrispModel;
        mExplorerVisible: Boolean;
        mSessionsVisible: Boolean;
        mThinkVisible: Boolean;
        mPlanVisible: Boolean;
        mPanelWidth: Integer;
        mHeaderHeight: Integer;
        mFooterHeight: Integer;
        procedure DrawBorder(ParaX, ParaY, ParaWidth, ParaHeight: Integer; const ParaTitle: string);
        procedure DrawHeader;
        procedure DrawFooter;
        procedure DrawExplorer(ParaX, ParaY, ParaWidth, ParaHeight: Integer);
        procedure DrawSessions(ParaX, ParaY, ParaWidth, ParaHeight: Integer);
        procedure DrawChat(ParaX, ParaY, ParaWidth, ParaHeight: Integer);
        procedure DrawMessage(ParaX: Integer; var ParaY: Integer; ParaWidth: Integer; const ParaMessage: TGrispMessage);
        procedure DrawPlan(ParaX: Integer; var ParaY: Integer; ParaWidth: Integer);
        procedure DrawThink(ParaX: Integer; var ParaY: Integer; ParaWidth: Integer);
        procedure DrawInput(ParaX, ParaY, ParaWidth, ParaHeight: Integer);
        function FitText(const ParaText: string; const ParaWidth: Integer): string;
        function PermissionGlyph(const ParaAllowed: Boolean): string;
        function RepeatChar(const ParaChar: string; const ParaCount: Integer): string;
    public
        constructor Create(ParaConsole: TGrispConsole; ParaModel: TGrispModel);
        procedure Render;
        procedure ToggleExplorer;
        procedure ToggleSessions;
        procedure ToggleThink;
        procedure TogglePlan;
        function ExplorerVisible: Boolean;
        function SessionsVisible: Boolean;
        function ThinkVisible: Boolean;
        function PlanVisible: Boolean;
    end;

implementation

const
    C_RESET = #27'[0m';
    C_BLUE = #27'[38;5;39m';
    C_CYAN = #27'[38;5;51m';
    C_DIM = #27'[38;5;67m';
    C_WHITE = #27'[38;5;255m';
    C_GREEN = #27'[38;5;46m';
    C_YELLOW = #27'[38;5;220m';
    C_RED = #27'[38;5;203m';
    C_BG = #27'[48;5;17m';

constructor TGrispTUIRenderer.Create(ParaConsole: TGrispConsole; ParaModel: TGrispModel);
begin
    inherited Create;
    mConsole := ParaConsole;
    mModel := ParaModel;
    mExplorerVisible := True;
    mSessionsVisible := False;
    mThinkVisible := False;
    mPlanVisible := True;
    mPanelWidth := 30;
    mHeaderHeight := 3;
    mFooterHeight := 2;
end;

function TGrispTUIRenderer.RepeatChar(const ParaChar: string; const ParaCount: Integer): string;
var
    vIndex: Integer;
begin
    if (ParaCount <= 0) or (ParaChar = '') then
        Exit('');

    Result := '';

    for vIndex := 1 to ParaCount do
        Result := Result + ParaChar;
end;

procedure TGrispTUIRenderer.DrawBorder(ParaX, ParaY, ParaWidth, ParaHeight: Integer; const ParaTitle: string);
var
    vTop: string;
    vMiddle: string;
    vBottom: string;
    vIndex: Integer;
    vTitle: string;
    vAvailable: Integer;
begin
    if (ParaWidth < 2) or (ParaHeight < 2) then
        Exit;

    vAvailable := Max(0, ParaWidth - 2);
    vTitle := ParaTitle;

    if vTitle <> '' then
    begin
        if Length(vTitle) > Max(0, vAvailable - 3) then
            vTitle := FitText(vTitle, Max(0, vAvailable - 3));
        vTop := '┌─ ' + vTitle + ' ' + RepeatChar('─', Max(0, ParaWidth - Length(vTitle) - 6)) + '┐';
    end
    else
        vTop := '┌' + RepeatChar('─', vAvailable) + '┐';

    vMiddle := '│' + RepeatChar(' ', vAvailable) + '│';
    vBottom := '└' + RepeatChar('─', vAvailable) + '┘';

    mConsole.WriteAt(ParaX, ParaY, C_BLUE + vTop + C_RESET);
    for vIndex := 1 to ParaHeight - 2 do
        mConsole.WriteAt(ParaX, ParaY + vIndex, C_BLUE + vMiddle + C_RESET);
    mConsole.WriteAt(ParaX, ParaY + ParaHeight - 1, C_BLUE + vBottom + C_RESET);
end;

procedure TGrispTUIRenderer.DrawHeader;
var
    vWidth: Integer;
    vLine: string;
begin
    vWidth := mConsole.Width;
    vLine := '╔' + RepeatChar('═', Max(0, vWidth - 2)) + '╗';
    mConsole.WriteAt(0, 0, C_BLUE + vLine + C_RESET);
    mConsole.WriteAt(2, 1, C_CYAN + '◈ GRISP OS' + C_RESET + C_DIM + '   Deterministic AI Runtime' + C_RESET);
    mConsole.WriteAt(36, 1, C_CYAN + '[ CHAT ]' + C_RESET + '  [ WORK ]  [ KNOWLEDGE ]');
    mConsole.WriteAt(Max(0, vWidth - 18), 1, C_GREEN + '● READY' + C_RESET);
    mConsole.WriteAt(0, 2, C_BLUE + '╠' + RepeatChar('═', Max(0, vWidth - 2)) + '╣' + C_RESET);
end;

procedure TGrispTUIRenderer.DrawFooter;
var
    vWidth: Integer;
    vY: Integer;
    vLine: string;
begin
    vWidth := mConsole.Width;
    vY := mConsole.Height - 2;
    vLine := '╠' + RepeatChar('═', Max(0, vWidth - 2)) + '╣';
    mConsole.WriteAt(0, vY, C_BLUE + vLine + C_RESET);
    mConsole.WriteAt(2, vY + 1,
        C_DIM + 'GRISP:/Workspace' + C_RESET +
        '   ' + C_CYAN + '[F2] Explorer' + C_RESET +
        '  [F3] Sessions  [F4] Think  [F5] Plan  [Ctrl+N] New  [ESC] Quit');
end;

procedure TGrispTUIRenderer.DrawExplorer(ParaX, ParaY, ParaWidth, ParaHeight: Integer);
var
    vIndex: Integer;
    vResource: TGrispResource;
    vLine: string;
    vIndent: string;
    vY: Integer;
begin
    DrawBorder(ParaX, ParaY, ParaWidth, ParaHeight, 'EXPLORER');
    mConsole.WriteAt(ParaX + 2, ParaY + 1, C_DIM + 'GRISP:/' + C_RESET);

    for vIndex := 0 to High(mModel.Resources) do
    begin
        if ParaY + 3 + vIndex >= ParaY + ParaHeight - 1 then
            Break;

        vResource := mModel.Resources[vIndex];
        vIndent := RepeatChar(' ', vResource.Depth * 2);

        if vResource.IsFolder then
        begin
            if vResource.Expanded then
                vLine := vIndent + '▾ ' + '■ ' + vResource.Name
            else
                vLine := vIndent + '▸ ' + '■ ' + vResource.Name;
        end
        else
            vLine := vIndent + '  · ' + vResource.Name;

        vLine := FitText(vLine, ParaWidth - 3);
        if vIndex = mModel.SelectedResource then
            vLine := C_WHITE + C_BG + ' ' + vLine + ' ' + C_RESET
        else
            vLine := C_WHITE + vLine + C_RESET;

        mConsole.WriteAt(ParaX + 1, ParaY + 2 + vIndex, vLine);
    end;

    if ParaHeight > 12 then
    begin
        vY := ParaY + ParaHeight - 5;
        mConsole.WriteAt(ParaX + 2, vY, C_DIM + 'PERMISSIONS' + C_RESET);
        vResource := mModel.Resources[mModel.SelectedResource];
        mConsole.WriteAt(ParaX + 2, vY + 1, 'R  ' + PermissionGlyph(vResource.ReadAllowed) + '  Read');
        mConsole.WriteAt(ParaX + 2, vY + 2, 'W  ' + PermissionGlyph(vResource.WriteAllowed) + '  Write');
        mConsole.WriteAt(ParaX + 2, vY + 3, 'X  ' + PermissionGlyph(vResource.ExecuteAllowed) + '  Execute');
    end;
end;

procedure TGrispTUIRenderer.DrawSessions(ParaX, ParaY, ParaWidth, ParaHeight: Integer);
var
    vIndex: Integer;
    vSession: TGrispSession;
    vLine: string;
begin
    DrawBorder(ParaX, ParaY, ParaWidth, ParaHeight, 'SESSIONS');
    for vIndex := 0 to High(mModel.Sessions) do
    begin
        if ParaY + 2 + vIndex * 2 >= ParaY + ParaHeight - 1 then
            Break;

        vSession := mModel.Sessions[vIndex];
        vLine := FitText(vSession.Title, ParaWidth - 4);

        if vIndex = mModel.SelectedSession then
            mConsole.WriteAt(ParaX + 1, ParaY + 1 + vIndex * 2, C_WHITE + C_BG + ' ' + vLine + ' ' + C_RESET)
        else
            mConsole.WriteAt(ParaX + 2, ParaY + 1 + vIndex * 2, C_CYAN + vLine + C_RESET);

        mConsole.WriteAt(ParaX + 3, ParaY + 2 + vIndex * 2, C_DIM + vSession.DateTimeText + C_RESET);
    end;
end;

procedure TGrispTUIRenderer.DrawChat(ParaX, ParaY, ParaWidth, ParaHeight: Integer);
var
    vY: Integer;
    vMessage: TGrispMessage;
    vIndex: Integer;
    vInputHeight: Integer;
    vReservedHeight: Integer;
begin
    DrawBorder(ParaX, ParaY, ParaWidth, ParaHeight, 'SESSION: ' + mModel.Sessions[mModel.SelectedSession].Title);

    vInputHeight := 4;
    vReservedHeight := vInputHeight + 1;
    vY := ParaY + 2;

    for vIndex := 0 to High(mModel.Messages) do
    begin
        vMessage := mModel.Messages[vIndex];
        if vY >= ParaY + ParaHeight - vReservedHeight - 1 then
            Break;
        DrawMessage(ParaX + 2, vY, ParaWidth - 4, vMessage);
    end;

    if mPlanVisible and (vY < ParaY + ParaHeight - vReservedHeight - 5) then
        DrawPlan(ParaX + 2, vY, ParaWidth - 4);

    if mThinkVisible and (vY < ParaY + ParaHeight - vReservedHeight - 4) then
        DrawThink(ParaX + 2, vY, ParaWidth - 4);

    DrawInput(ParaX + 2, ParaY + ParaHeight - vInputHeight - 1, ParaWidth - 4, vInputHeight);
end;

procedure TGrispTUIRenderer.DrawMessage(ParaX: Integer; var ParaY: Integer; ParaWidth: Integer; const ParaMessage: TGrispMessage);
var
    vIndex: Integer;
    vPrefix: string;
    vColor: string;
begin
    if ParaMessage.Role = 'YOU' then
    begin
        vPrefix := 'YOU';
        vColor := C_WHITE;
    end
    else
    begin
        vPrefix := 'GRISP';
        vColor := C_CYAN;
    end;

    mConsole.WriteAt(ParaX, ParaY, vColor + vPrefix + C_RESET + C_DIM + '  ' + ParaMessage.TimeText + C_RESET);
    Inc(ParaY);

    for vIndex := 0 to High(ParaMessage.Lines) do
    begin
        mConsole.WriteAt(ParaX, ParaY, C_WHITE + '│ ' + FitText(ParaMessage.Lines[vIndex], ParaWidth - 3) + C_RESET);
        Inc(ParaY);
    end;

    Inc(ParaY);
end;

procedure TGrispTUIRenderer.DrawPlan(ParaX: Integer; var ParaY: Integer; ParaWidth: Integer);
var
    vIndex: Integer;
    vItem: TGrispPlanItem;
    vMark: string;
    vColor: string;
begin
    mConsole.WriteAt(ParaX, ParaY, C_BLUE + '┌─ PLAN ' + RepeatChar('─', Max(0, ParaWidth - 8)) + '┐' + C_RESET);
    Inc(ParaY);

    for vIndex := 0 to High(mModel.Plan) do
    begin
        vItem := mModel.Plan[vIndex];

        if vItem.State = 'DONE' then
        begin
            vMark := '✓';
            vColor := C_GREEN;
        end
        else if vItem.State = 'ACTIVE' then
        begin
            vMark := '>';
            vColor := C_YELLOW;
        end
        else
        begin
            vMark := ' ';
            vColor := C_DIM;
        end;

        mConsole.WriteAt(ParaX, ParaY,
            '│ ' + vColor + vMark + C_RESET + ' ' +
            FitText(vItem.Title, Max(1, ParaWidth - Length(vItem.State) - 8)) +
            ' ' + C_DIM + vItem.State + C_RESET);
        Inc(ParaY);
    end;

    mConsole.WriteAt(ParaX, ParaY, C_BLUE + '└' + RepeatChar('─', Max(0, ParaWidth - 2)) + '┘' + C_RESET);
    Inc(ParaY);
end;

procedure TGrispTUIRenderer.DrawThink(ParaX: Integer; var ParaY: Integer; ParaWidth: Integer);
var
    vTitle: string;
    vLineWidth: Integer;
begin
    vTitle := '┌─ THINK (prototype) ';
    vLineWidth := Max(0, ParaWidth - Length(vTitle) - 1);
    mConsole.WriteAt(ParaX, ParaY, C_BLUE + vTitle + RepeatChar('─', vLineWidth) + '┐' + C_RESET);
    Inc(ParaY);
    mConsole.WriteAt(ParaX, ParaY, C_DIM + '│ > Analyze architecture' + C_RESET);
    Inc(ParaY);
    mConsole.WriteAt(ParaX, ParaY, C_DIM + '│ > Identify relevant components' + C_RESET);
    Inc(ParaY);
    mConsole.WriteAt(ParaX, ParaY, C_DIM + '│ > Construct response' + C_RESET);
    Inc(ParaY);
    mConsole.WriteAt(ParaX, ParaY, C_BLUE + '└' + RepeatChar('─', Max(0, ParaWidth - 2)) + '┘' + C_RESET);
    Inc(ParaY);
end;

procedure TGrispTUIRenderer.DrawInput(ParaX, ParaY, ParaWidth, ParaHeight: Integer);
begin
    if ParaHeight < 3 then
        Exit;

    mConsole.WriteAt(ParaX, ParaY, C_BLUE + '┌─ MESSAGE ' + RepeatChar('─', Max(0, ParaWidth - 12)) + '┐' + C_RESET);
    mConsole.WriteAt(ParaX, ParaY + 1, '│ ' + C_WHITE + FitText(mModel.InputText + '▌', Max(1, ParaWidth - 4)) + C_RESET);
    mConsole.WriteAt(ParaX, ParaY + 2, C_BLUE + '└' + RepeatChar('─', Max(0, ParaWidth - 2)) + '┘' + C_RESET);
end;

procedure TGrispTUIRenderer.Render;
var
    vWidth: Integer;
    vHeight: Integer;
    vContentY: Integer;
    vContentHeight: Integer;
    vLeftWidth: Integer;
    vChatX: Integer;
    vChatWidth: Integer;
begin
    mConsole.BeginFrame;
    vWidth := mConsole.Width;
    vHeight := mConsole.Height;

    if (vWidth < 80) or (vHeight < 20) then
    begin
        mConsole.WriteAt(0, 0, C_RED + 'GRISP TUI requires at least 80x20 terminal size.' + C_RESET);
        mConsole.EndFrame;
        Exit;
    end;

    DrawHeader;
    DrawFooter;

    vContentY := mHeaderHeight;
    vContentHeight := vHeight - mHeaderHeight - mFooterHeight;

    if mExplorerVisible or mSessionsVisible then
    begin
        vLeftWidth := Min(mPanelWidth, Max(20, vWidth div 3));
        vChatX := vLeftWidth + 1;
        vChatWidth := vWidth - vChatX;

        if mExplorerVisible then
            DrawExplorer(0, vContentY, vLeftWidth, vContentHeight)
        else
            DrawSessions(0, vContentY, vLeftWidth, vContentHeight);
    end
    else
    begin
        vChatX := 0;
        vChatWidth := vWidth;
    end;

    DrawChat(vChatX, vContentY, vChatWidth, vContentHeight);
    mConsole.EndFrame;
end;

function TGrispTUIRenderer.FitText(const ParaText: string; const ParaWidth: Integer): string;
begin
    if ParaWidth <= 0 then
        Exit('');

    if Length(ParaText) <= ParaWidth then
        Exit(ParaText);

    if ParaWidth = 1 then
        Exit('…');

    Result := Copy(ParaText, 1, ParaWidth - 1) + '…';
end;

function TGrispTUIRenderer.PermissionGlyph(const ParaAllowed: Boolean): string;
begin
    if ParaAllowed then
        Result := C_GREEN + '✓' + C_RESET
    else
        Result := C_RED + '×' + C_RESET;
end;

procedure TGrispTUIRenderer.ToggleExplorer;
begin
    mExplorerVisible := not mExplorerVisible;
    if mExplorerVisible then
        mSessionsVisible := False;
end;

procedure TGrispTUIRenderer.ToggleSessions;
begin
    mSessionsVisible := not mSessionsVisible;
    if mSessionsVisible then
        mExplorerVisible := False;
end;

procedure TGrispTUIRenderer.ToggleThink;
begin
    mThinkVisible := not mThinkVisible;
end;

procedure TGrispTUIRenderer.TogglePlan;
begin
    mPlanVisible := not mPlanVisible;
end;

function TGrispTUIRenderer.ExplorerVisible: Boolean;
begin
    Result := mExplorerVisible;
end;

function TGrispTUIRenderer.SessionsVisible: Boolean;
begin
    Result := mSessionsVisible;
end;

function TGrispTUIRenderer.ThinkVisible: Boolean;
begin
    Result := mThinkVisible;
end;

function TGrispTUIRenderer.PlanVisible: Boolean;
begin
    Result := mPlanVisible;
end;

end.

