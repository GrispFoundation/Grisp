// Style: semantic-prefixes v2.0

unit GRISP.TUI.Console;

interface

uses
    Winapi.Windows,
    System.SysUtils,
    System.Types;

type
    TGrispConsole = class
    private
        mInputHandle: THandle;
        mOutputHandle: THandle;
        mOriginalInputMode: DWORD;
        mOriginalOutputMode: DWORD;
        mWidth: Integer;
        mHeight: Integer;
        procedure ConfigureConsole;
        procedure RestoreConsole;
        procedure RefreshSize;
    public
        constructor Create;
        destructor Destroy; override;
        procedure BeginFrame;
        procedure EndFrame;
        procedure WriteAt(const ParaX, ParaY: Integer; const ParaText: string);
        procedure WriteAnsi(const ParaText: string);
        function ReadKey(out ParaKey: TInputRecord): Boolean;
        function Width: Integer;
        function Height: Integer;
        procedure HideCursor;
        procedure ShowCursor;
    end;

implementation

constructor TGrispConsole.Create;
begin
    inherited Create;
    mInputHandle := GetStdHandle(STD_INPUT_HANDLE);
    mOutputHandle := GetStdHandle(STD_OUTPUT_HANDLE);
    ConfigureConsole;
    RefreshSize;
end;

destructor TGrispConsole.Destroy;
begin
    RestoreConsole;
    inherited Destroy;
end;

procedure TGrispConsole.ConfigureConsole;
var
    vOutputMode: DWORD;
    vInputMode: DWORD;
begin
    GetConsoleMode(mOutputHandle, mOriginalOutputMode);
    GetConsoleMode(mInputHandle, mOriginalInputMode);

    vOutputMode := mOriginalOutputMode or ENABLE_VIRTUAL_TERMINAL_PROCESSING;
    SetConsoleMode(mOutputHandle, vOutputMode);

    vInputMode := mOriginalInputMode;
    vInputMode := vInputMode and not ENABLE_LINE_INPUT;
    vInputMode := vInputMode and not ENABLE_ECHO_INPUT;
    vInputMode := vInputMode or ENABLE_WINDOW_INPUT;
    vInputMode := vInputMode or ENABLE_PROCESSED_INPUT;
    SetConsoleMode(mInputHandle, vInputMode);

    SetConsoleOutputCP(CP_UTF8);
    SetConsoleCP(CP_UTF8);
end;

procedure TGrispConsole.RestoreConsole;
begin
    WriteAnsi(#27'[0m'#27'[?25h'#27'[2J'#27'[H');
    SetConsoleMode(mInputHandle, mOriginalInputMode);
    SetConsoleMode(mOutputHandle, mOriginalOutputMode);
end;

procedure TGrispConsole.RefreshSize;
var
    vInfo: TConsoleScreenBufferInfo;
begin
    if GetConsoleScreenBufferInfo(mOutputHandle, vInfo) then
    begin
        mWidth := vInfo.srWindow.Right - vInfo.srWindow.Left + 1;
        mHeight := vInfo.srWindow.Bottom - vInfo.srWindow.Top + 1;
    end
    else
    begin
        mWidth := 120;
        mHeight := 40;
    end;
end;

procedure TGrispConsole.BeginFrame;
begin
    RefreshSize;
    WriteAnsi(#27'[2J'#27'[H'#27'[?25l');
end;

procedure TGrispConsole.EndFrame;
begin
    WriteAnsi(#27'[0m');
end;

procedure TGrispConsole.WriteAt(const ParaX, ParaY: Integer; const ParaText: string);
begin
    WriteAnsi(Format(#27'[%d;%dH', [ParaY + 1, ParaX + 1]) + ParaText);
end;

procedure TGrispConsole.WriteAnsi(const ParaText: string);
var
    vWritten: DWORD;
    vText: UnicodeString;
begin
    vText := UnicodeString(ParaText);
    if Length(vText) = 0 then
        Exit;
    WriteConsoleW(mOutputHandle, PWideChar(vText), Length(vText), vWritten, nil);
end;

function TGrispConsole.ReadKey(out ParaKey: TInputRecord): Boolean;
var
    vRead: DWORD;
    vRecord: TInputRecord;
begin
    Result := False;
    while ReadConsoleInputW(mInputHandle, vRecord, 1, vRead) do
    begin
        if vRead <> 1 then
            Continue;
        if vRecord.EventType = KEY_EVENT then
        begin
            if vRecord.Event.KeyEvent.bKeyDown then
            begin
                ParaKey := vRecord;
                Result := True;
                Exit;
            end;
        end
        else if vRecord.EventType = WINDOW_BUFFER_SIZE_EVENT then
        begin
            RefreshSize;
        end;
    end;
end;

function TGrispConsole.Width: Integer;
begin
    Result := mWidth;
end;

function TGrispConsole.Height: Integer;
begin
    Result := mHeight;
end;

procedure TGrispConsole.HideCursor;
begin
    WriteAnsi(#27'[?25l');
end;

procedure TGrispConsole.ShowCursor;
begin
    WriteAnsi(#27'[?25h');
end;

end.
