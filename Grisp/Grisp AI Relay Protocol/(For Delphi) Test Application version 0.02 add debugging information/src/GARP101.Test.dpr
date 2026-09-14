program GARP101.Test;

{$APPTYPE CONSOLE}

uses
    System.SysUtils,
    System.Classes,
    System.JSON,
    IdException,
    Windows,
    GARP101.Protocol in 'GARP101.Protocol.pas',
    GARP101.Client in 'GARP101.Client.pas';

const
    CP_UTF8 = 65001;

type
    TOptions = record
        Host: string;
        Port: Integer;
        Secret: string;
        Provider: string;
        PromptText: string;
        SessionID: string;
        RunConformance: Boolean;
        RunSelfTest: Boolean;
        DoPing: Boolean;
        DoCapabilities: Boolean;
        DoBrowserStatus: Boolean;
        DoListTabs: Boolean;
        DoPrompt: Boolean;
        DoSession: Boolean;
        Debug: Boolean;
    end;

procedure PrintHelp;
begin
    Writeln('GARP/1.01 Delphi Test Client');
    Writeln;
    Writeln('Usage:');
    Writeln('  GARP101.Test.exe [options]');
    Writeln;
    Writeln('Connection:');
    Writeln('  --host <host>             Default 127.0.0.1');
    Writeln('  --port <port>             Default 9999');
    Writeln('  --secret <secret>         GARP_SECRET used by Firefox');
    Writeln;
    Writeln('Tests:');
    Writeln('  --self-test               Test local GARP frame encoding/decoding');
    Writeln('  --conformance             Run live protocol/session smoke tests');
    Writeln('  --ping                    Send PING and require PONG');
    Writeln('  --capabilities            Query CAPABILITIES');
    Writeln('  --browser-status          Query BROWSER_STATUS');
    Writeln('  --list-tabs               Query LIST_TABS');
    Writeln('  --session <provider>      CREATE_SESSION for a provider');
    Writeln('  --prompt <text>           Prompt the active/new session');
    Writeln('  --debug                   Enable detailed protocol/client tracing');
    Writeln;
    Writeln('Examples:');
    Writeln('  GARP101.Test.exe --secret development-secret --conformance --debug');
    Writeln('  GARP101.Test.exe --secret development-secret --session deepseek --prompt "Hello" --debug');
end;

function ParseOptions: TOptions;
var
    LIndex: Integer;
    LArg: string;
begin
    Result.Host := '127.0.0.1';
    Result.Port := GARP_DEFAULT_PORT;
    Result.Secret := GetEnvironmentVariable('GARP_SECRET');
    Result.Provider := '';
    Result.PromptText := '';
    Result.SessionID := '';
    Result.RunConformance := False;
    Result.RunSelfTest := False;
    Result.DoPing := False;
    Result.DoCapabilities := False;
    Result.DoBrowserStatus := False;
    Result.DoListTabs := False;
    Result.DoPrompt := False;
    Result.DoSession := False;
    Result.Debug := False;

    LIndex := 1;

    while LIndex <= ParamCount do
    begin
        LArg := ParamStr(LIndex);

        if LArg = '--host' then
        begin
            Inc(LIndex);

            if LIndex > ParamCount then
                raise Exception.Create('--host requires a value');

            Result.Host := ParamStr(LIndex);
        end
        else if LArg = '--port' then
        begin
            Inc(LIndex);

            if LIndex > ParamCount then
                raise Exception.Create('--port requires a value');

            Result.Port := StrToInt(ParamStr(LIndex));
        end
        else if LArg = '--secret' then
        begin
            Inc(LIndex);

            if LIndex > ParamCount then
                raise Exception.Create('--secret requires a value');

            Result.Secret := ParamStr(LIndex);
        end
        else if LArg = '--self-test' then
            Result.RunSelfTest := True
        else if LArg = '--conformance' then
            Result.RunConformance := True
        else if LArg = '--ping' then
            Result.DoPing := True
        else if LArg = '--capabilities' then
            Result.DoCapabilities := True
        else if LArg = '--browser-status' then
            Result.DoBrowserStatus := True
        else if LArg = '--list-tabs' then
            Result.DoListTabs := True
        else if LArg = '--session' then
        begin
            Inc(LIndex);

            if LIndex > ParamCount then
                raise Exception.Create('--session requires a provider');

            Result.Provider := ParamStr(LIndex);
            Result.DoSession := True;
        end
        else if LArg = '--prompt' then
        begin
            Inc(LIndex);

            if LIndex > ParamCount then
                raise Exception.Create('--prompt requires text');

            Result.PromptText := ParamStr(LIndex);
            Result.DoPrompt := True;
        end
        else if LArg = '--debug' then
            Result.Debug := True
        else
            raise Exception.Create('Unknown option: ' + LArg);

        Inc(LIndex);
    end;

    if not Result.RunConformance and
       not Result.RunSelfTest and
       not Result.DoPing and
       not Result.DoCapabilities and
       not Result.DoBrowserStatus and
       not Result.DoListTabs and
       not Result.DoSession and
       not Result.DoPrompt then
    begin
        PrintHelp;
    end;
end;

procedure AssertEqual(
    const AName: string;
    const AExpected: string;
    const AActual: string
);
begin
    if AExpected <> AActual then
    begin
        raise Exception.CreateFmt(
            '%s failed. Expected="%s" Actual="%s"',
            [AName, AExpected, AActual]
        );
    end;

    Writeln('[PASS] ', AName);
end;

procedure RunSelfTest;
var
    LRequestID: string;
    LSessionID: string;
    LPayload: TJSONObject;
    LMessage: TJSONObject;
    LFrameBytes: TBytes;
    LFrame: TGARPFrame;
    LText: string;
begin
    Writeln('=== GARP/1.01 local self-test ===');

    LRequestID := GARPNewUUID;
    LSessionID := GARPNewUUID;

    LText :=
        'Unicode: äöü 日本語 🚀 and embedded newline' +
        sLineBreak +
        'second line';

    LPayload := TJSONObject.Create;

    try
        LPayload.AddPair('text', LText);
        LPayload.AddPair('value', TJSONNumber.Create(123));

        LMessage :=
            GARPBuildJSON(
                'diagnostic',
                LPayload,
                LRequestID,
                LSessionID
            );

        try
            LFrameBytes :=
                GARPEncodeFrame(
                    GARP_DIAGNOSTIC,
                    LMessage,
                    LRequestID,
                    LSessionID
                );
        finally
            LMessage.Free;
        end;
    except
        LPayload.Free;
        raise;
    end;

    LFrame :=
        GARPDecodeFrame(LFrameBytes);

    try
        AssertEqual(
            'magic/version decode',
            GARP_PROTOCOL,
            LFrame.MessageJSON.GetValue<string>(
                'protocol',
                ''
            )
        );

        AssertEqual(
            'message type',
            'diagnostic',
            LFrame.MessageJSON.GetValue<string>(
                'type',
                ''
            )
        );

        AssertEqual(
            'request UUID',
            LRequestID,
            LFrame.RequestID
        );

        AssertEqual(
            'session UUID',
            LSessionID,
            LFrame.SessionID
        );

        AssertEqual(
            'UTF-8 payload',
            LText,
            LFrame.MessageJSON.GetValue<string>(
                'payload.text',
                ''
            )
        );

        if Length(LFrameBytes) <>
           GARP_FIXED_HEADER_LENGTH +
           Length(
               TEncoding.UTF8.GetBytes(
                   LFrame.MessageJSON.ToJSON
               )
           ) then
        begin
            raise Exception.Create(
                'Encoded frame length invariant failed'
            );
        end;

        Writeln('[PASS] length framing');
    finally
        LFrame.MessageJSON.Free;
    end;
end;

procedure PrintJSONObject(
    const ATitle: string;
    AObject: TJSONObject
);
begin
    Writeln('--- ', ATitle, ' ---');

    if AObject <> nil then
        Writeln(AObject.Format(2))
    else
        Writeln('<nil>');
end;

procedure RunLiveBasic(const AOptions: TOptions);
var
    LClient: TGARPClient101;
    LResponse: TJSONObject;
begin
    LClient :=
        TGARPClient101.Create(
            AOptions.Host,
            AOptions.Port,
            AOptions.Secret
        );

    try
        LClient.Debug := AOptions.Debug;

        LClient.ConnectAndAuthenticate;

        Writeln('[PASS] HELLO + HMAC authentication');

        if AOptions.DoPing then
        begin
            LClient.Ping;
            Writeln('[PASS] PING/PONG');
        end;

        if AOptions.DoCapabilities then
        begin
            LResponse :=
                LClient.GetCapabilities;

            try
                PrintJSONObject(
                    'CAPABILITIES',
                    LResponse
                );
            finally
                LResponse.Free;
            end;
        end;

        if AOptions.DoBrowserStatus then
        begin
            LResponse :=
                LClient.GetBrowserStatus;

            try
                PrintJSONObject(
                    'BROWSER_STATUS',
                    LResponse
                );
            finally
                LResponse.Free;
            end;
        end;

        if AOptions.DoListTabs then
        begin
            LResponse :=
                LClient.ListTabs;

            try
                PrintJSONObject(
                    'LIST_TABS',
                    LResponse
                );
            finally
                LResponse.Free;
            end;
        end;

        if AOptions.DoSession then
        begin
            LResponse :=
                LClient.CreateSession(
                    AOptions.Provider
                );

            try
                PrintJSONObject(
                    'CREATE_SESSION',
                    LResponse
                );

                Writeln(
                    'SessionID: ',
                    LClient.SessionID
                );

                Writeln(
                    'TabID    : ',
                    LClient.TabID
                );
            finally
                LResponse.Free;
            end;
        end;

        if AOptions.DoPrompt then
        begin
            if LClient.SessionID = '' then
            begin
                if AOptions.Provider = '' then
                begin
                    raise Exception.Create(
                        '--prompt requires --session <provider> when no session is active'
                    );
                end;

                LResponse :=
                    LClient.CreateSession(
                        AOptions.Provider
                    );

                LResponse.Free;
            end;

            LResponse :=
                LClient.Prompt(
                    AOptions.PromptText
                );

            try
                PrintJSONObject(
                    'PROMPT_ACK',
                    LResponse
                );
            finally
                LResponse.Free;
            end;

            LResponse :=
                LClient.WaitForCompletion(
                    LClient.RequestID,
                    180000
                );

            try
                PrintJSONObject(
                    'FINAL',
                    LResponse
                );
            finally
                LResponse.Free;
            end;
        end;

        if LClient.SessionID <> '' then
            LClient.CloseSession;
    finally
        LClient.Free;
    end;
end;

procedure RunConformance(const AOptions: TOptions);
var
    LClient: TGARPClient101;
    LResponse: TJSONObject;
    LSessionProvider: string;
begin
    Writeln('=== GARP/1.01 live conformance smoke test ===');

    if AOptions.Secret = '' then
    begin
        raise Exception.Create(
            'GARP secret not supplied. Use --secret or GARP_SECRET.'
        );
    end;

    LClient :=
        TGARPClient101.Create(
            AOptions.Host,
            AOptions.Port,
            AOptions.Secret
        );

    try
        LClient.Debug := AOptions.Debug;

        LClient.ConnectAndAuthenticate;

        Writeln(
            '[PASS] HELLO/HELLO_CHALLENGE/HELLO_AUTH/HELLO_ACK'
        );

        LClient.Ping;
        Writeln('[PASS] PING/PONG');

        LResponse :=
            LClient.GetCapabilities;

        try
            Writeln('[PASS] CAPABILITIES');
            PrintJSONObject(
                'CAPABILITIES',
                LResponse
            );
        finally
            LResponse.Free;
        end;

        LResponse :=
            LClient.GetBrowserStatus;

        try
            Writeln('[PASS] BROWSER_STATUS');
            PrintJSONObject(
                'BROWSER_STATUS',
                LResponse
            );
        finally
            LResponse.Free;
        end;

        LResponse :=
            LClient.ListTabs;

        try
            Writeln('[PASS] LIST_TABS');
            PrintJSONObject(
                'LIST_TABS',
                LResponse
            );
        finally
            LResponse.Free;
        end;

        LSessionProvider :=
            AOptions.Provider;

        if LSessionProvider = '' then
            LSessionProvider := 'deepseek';

        Writeln(
            'Creating session for provider: ',
            LSessionProvider
        );

        LResponse :=
            LClient.CreateSession(
                LSessionProvider
            );

        try
            Writeln('[PASS] CREATE_SESSION');

            PrintJSONObject(
                'CREATE_SESSION',
                LResponse
            );
        finally
            LResponse.Free;
        end;

        Writeln(
            'Waiting for provider session to become ready...'
        );

        Sleep(1500);

        LResponse :=
            LClient.Prompt(
                'Reply with exactly: GARP/1.01 TEST OK',
                True,
                120000,
                True
            );

        try
            Writeln('[PASS] PROMPT_ACK');

            PrintJSONObject(
                'PROMPT_ACK',
                LResponse
            );
        finally
            LResponse.Free;
        end;

        LResponse :=
            LClient.WaitForCompletion(
                LClient.RequestID,
                120000
            );

        try
            PrintJSONObject(
                'GENERATION_RESULT',
                LResponse
            );

            if SameText(
                LResponse.GetValue<string>(
                    'type',
                    ''
                ),
                'generation_completed'
            ) then
            begin
                Writeln(
                    '[PASS] GENERATION_COMPLETED'
                );
            end
            else
            begin
                Writeln(
                    '[INFO] Generation ended with: ',
                    LResponse.GetValue<string>(
                        'type',
                        'unknown'
                    )
                );
            end;
        finally
            LResponse.Free;
        end;

        LClient.CloseSession;

        Writeln('[PASS] CLOSE_SESSION');
    finally
        LClient.Free;
    end;
end;

begin
    SetConsoleOutputCP(CP_UTF8);

    try
        Randomize;

        var LOptions := ParseOptions;

        if LOptions.RunSelfTest then
            RunSelfTest;

        if LOptions.RunConformance then
        begin
            RunConformance(LOptions);
        end
        else if
            LOptions.DoPing or
            LOptions.DoCapabilities or
            LOptions.DoBrowserStatus or
            LOptions.DoListTabs or
            LOptions.DoSession or
            LOptions.DoPrompt then
        begin
            RunLiveBasic(LOptions);
        end;
    except
        on E: EIdConnClosedGracefully do
        begin
            Writeln(
                'GARP connection closed by Firefox: ',
                E.Message
            );

            ExitCode := 2;
        end;

        on E: Exception do
        begin
            Writeln(
                'ERROR: ',
                E.ClassName,
                ': ',
                E.Message
            );

            ExitCode := 1;
        end;
    end;
end.
