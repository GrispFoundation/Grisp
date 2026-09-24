// Style: semantic-prefixes v2.0

unit GRISP.TUI.App;

interface

uses
    Winapi.Windows,
    System.SysUtils,
    GRISP.TUI.Console,
    GRISP.TUI.Model,
    GRISP.TUI.Renderer;

type
    TGrispTUIApplication = class
    private
        class procedure HandleKey(ParaKey: TInputRecord; ParaModel: TGrispModel; ParaRenderer: TGrispTUIRenderer; var ParaRunning: Boolean; var ParaFocusChat: Boolean); static;
        class procedure SendInput(ParaModel: TGrispModel); static;
    public
        class procedure Run; static;
    end;

implementation

class procedure TGrispTUIApplication.Run;
var
    vConsole: TGrispConsole;
    vModel: TGrispModel;
    vRenderer: TGrispTUIRenderer;
    vKey: TInputRecord;
    vRunning: Boolean;
    vFocusChat: Boolean;
begin
    vConsole := TGrispConsole.Create;
    try
        vModel := TGrispModel.Create;
        try
            vRenderer := TGrispTUIRenderer.Create(vConsole, vModel);
            try
                vRunning := True;
                vFocusChat := False;
                while vRunning do
                begin
                    vRenderer.Render;
                    if vFocusChat then
                        vConsole.ShowCursor
                    else
                        vConsole.HideCursor;
                    if vConsole.ReadKey(vKey) then
                        HandleKey(vKey, vModel, vRenderer, vRunning, vFocusChat);
                end;
            finally
                vRenderer.Free;
            end;
        finally
            vModel.Free;
        end;
    finally
        vConsole.Free;
    end;
end;

class procedure TGrispTUIApplication.HandleKey(ParaKey: TInputRecord; ParaModel: TGrispModel; ParaRenderer: TGrispTUIRenderer; var ParaRunning: Boolean; var ParaFocusChat: Boolean);
var
    vKeyEvent: TKeyEventRecord;
    vChar: WideChar;
    vControl: Boolean;
    vInputText: string;
begin
    vKeyEvent := ParaKey.Event.KeyEvent;
    vChar := vKeyEvent.UnicodeChar;
    vControl := (vKeyEvent.dwControlKeyState and (LEFT_CTRL_PRESSED or RIGHT_CTRL_PRESSED)) <> 0;

    if vKeyEvent.wVirtualKeyCode = VK_ESCAPE then
    begin
        if ParaFocusChat and (ParaModel.InputText <> '') then
        begin
            ParaModel.InputText := '';
            ParaFocusChat := False;
        end
        else
            ParaRunning := False;
        Exit;
    end;

    if vKeyEvent.wVirtualKeyCode = VK_F2 then
    begin
        ParaRenderer.ToggleExplorer;
        Exit;
    end;

    if vKeyEvent.wVirtualKeyCode = VK_F3 then
    begin
        ParaRenderer.ToggleSessions;
        Exit;
    end;

    if vKeyEvent.wVirtualKeyCode = VK_F4 then
    begin
        ParaRenderer.ToggleThink;
        Exit;
    end;

    if vKeyEvent.wVirtualKeyCode = VK_F5 then
    begin
        ParaRenderer.TogglePlan;
        Exit;
    end;

    if vControl and (vKeyEvent.wVirtualKeyCode = Ord('N')) then
    begin
        ParaModel.AddSession('New GRISP session');
        ParaModel.InputText := '';
        ParaFocusChat := True;
        Exit;
    end;

    if vControl and (vKeyEvent.wVirtualKeyCode = Ord('L')) then
    begin
        ParaModel.InputText := '';
        ParaFocusChat := True;
        Exit;
    end;

    if not ParaFocusChat then
    begin
        if vKeyEvent.wVirtualKeyCode = VK_TAB then
            ParaFocusChat := True;
        Exit;
    end;

    if vKeyEvent.wVirtualKeyCode = VK_BACK then
    begin
        vInputText := ParaModel.InputText;
        if Length(vInputText) > 0 then
        begin
            Delete(vInputText, Length(vInputText), 1);
            ParaModel.InputText := vInputText;
        end;
        Exit;
    end;

    if vKeyEvent.wVirtualKeyCode = VK_RETURN then
    begin
        SendInput(ParaModel);
        Exit;
    end;

    if vChar >= #32 then
        ParaModel.InputText := ParaModel.InputText + vChar;
end;

class procedure TGrispTUIApplication.SendInput(ParaModel: TGrispModel);
var
    vText: string;
begin
    vText := Trim(ParaModel.InputText);
    if vText = '' then
        Exit;

    ParaModel.AddUserMessage(vText);
    ParaModel.InputText := '';
    ParaModel.AddAssistantMessage([
        'Prototype response received.',
        '',
        'The next step is to connect this view model to the real GRISP session/runtime.',
        'The TUI deliberately keeps the workspace focused on conversation, resources,',
        'permissions, sessions, plans and optional reasoning.'
    ]);
end;

end.
