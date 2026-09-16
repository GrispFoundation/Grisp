program GARP124.Test;

{$APPTYPE CONSOLE}

uses
    System.SysUtils,
    System.JSON,
    Winapi.Windows,
    GARP124.Protocol in 'GARP124.Protocol.pas',
    GARP124.Client in 'GARP124.Client.pas';

const
    CP_UTF8 = 65001;

type
    TOptions = record
        Host: string;
        Port: Integer;
        Secret: string;
        Provider: string;
        PromptText: string;
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
    Writeln('GARP/1.24 Delphi Test Client');
    Writeln;
    Writeln('Usage: GARP124.Test.exe [options]');
    Writeln;
    Writeln('Connection:');
    Writeln('  --host <host>             Default 127.0.0.1');
    Writeln('  --port <port>             Default 9999');
    Writeln('  --secret <secret>         GARP_SECRET used by Firefox');
    Writeln;
    Writeln('Tests:');
    Writeln('  --self-test               Local 1.24 framing/transcript tests');
    Writeln('  --conformance             Live GARP/1.24 smoke test');
    Writeln('  --ping                    PING and RESPONSE test');
    Writeln('  --capabilities            GET_CAPABILITIES test');
    Writeln('  --browser-status          Show latest BROWSER_STATUS event');
    Writeln('  --list-tabs               LIST_TABS test');
    Writeln('  --session <provider>      CREATE_SESSION test');
    Writeln('  --prompt <text>           Create/use session and run prompt; quotes optional');
    Writeln('  --debug                   Enable protocol tracing');
end;

function ReadCommandLineArguments: TArray<string>;
var
    LCommandLine: string;
    LLength: Integer;
    LIndex: Integer;
    LQuoted: Boolean;
    LToken: string;
    LBackslashes: Integer;
    LChar: Char;
begin
    // Delphi's ParamStr() has already parsed the Windows command line.
    // For GARP prompts we need the original command line so that a prompt
    // containing spaces is never accidentally interpreted as several options.
    LCommandLine := GetCommandLine;
    LLength := Length(LCommandLine);
    LIndex := 1;

    // Skip the executable name using Windows command-line quoting rules.
    LQuoted := False;
    while LIndex <= LLength do
    begin
        LChar := LCommandLine[LIndex];
        if LChar = '"' then
            LQuoted := not LQuoted
        else if not LQuoted and (LChar <= ' ') then
            Break;
        Inc(LIndex);
    end;

    while (LIndex <= LLength) and (LCommandLine[LIndex] <= ' ') do
        Inc(LIndex);

    Result := [];

    while LIndex <= LLength do
    begin
        while (LIndex <= LLength) and (LCommandLine[LIndex] <= ' ') do
            Inc(LIndex);
        if LIndex > LLength then
            Break;

        LToken := '';
        LQuoted := False;

        while LIndex <= LLength do
        begin
            LChar := LCommandLine[LIndex];

            if LChar = '\\' then
            begin
                LBackslashes := 0;
                while (LIndex <= LLength) and (LCommandLine[LIndex] = '\') do
                begin
                    Inc(LBackslashes);
                    Inc(LIndex);
                end;

                if (LIndex <= LLength) and (LCommandLine[LIndex] = '"') then
                begin
                    // Backslashes immediately before a quote follow the
                    // standard Windows command-line interpretation.
                    LToken := LToken + StringOfChar('\', LBackslashes div 2);
                    if Odd(LBackslashes) then
                    begin
                        LToken := LToken + '"';
                        Inc(LIndex);
                    end
                    else
                        LQuoted := not LQuoted;
                end
                else
                    LToken := LToken + StringOfChar('\', LBackslashes);

                Continue;
            end;

            if LChar = '"' then
            begin
                // A quote toggles grouping and is not included in the value.
                LQuoted := not LQuoted;
                Inc(LIndex);
                Continue;
            end;

            if not LQuoted and (LChar <= ' ') then
                Break;

            LToken := LToken + LChar;
            Inc(LIndex);
        end;

        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := LToken;

        while (LIndex <= LLength) and (LCommandLine[LIndex] <= ' ') do
            Inc(LIndex);
    end;
end;

function ParseOptions: TOptions;
var
    LArguments: TArray<string>;
    LIndex: Integer;
    LArg: string;
    LOption: string;
begin
    Result.Host := '127.0.0.1';
    Result.Port := GARP_DEFAULT_PORT;
    Result.Secret := GetEnvironmentVariable('GARP_SECRET');
    Result.Provider := '';
    Result.PromptText := '';
    Result.RunConformance := False;
    Result.RunSelfTest := False;
    Result.DoPing := False;
    Result.DoCapabilities := False;
    Result.DoBrowserStatus := False;
    Result.DoListTabs := False;
    Result.DoPrompt := False;
    Result.DoSession := False;
    Result.Debug := False;

    LArguments := ReadCommandLineArguments;
    LIndex := 0;

    while LIndex < Length(LArguments) do
    begin
        LArg := LArguments[LIndex];

        if LArg = '--host' then
        begin
            Inc(LIndex);
            if LIndex >= Length(LArguments) then
                raise Exception.Create('--host requires a value');
            Result.Host := LArguments[LIndex];
        end
        else if LArg = '--port' then
        begin
            Inc(LIndex);
            if LIndex >= Length(LArguments) then
                raise Exception.Create('--port requires a value');
            Result.Port := StrToInt(LArguments[LIndex]);
        end
        else if LArg = '--secret' then
        begin
            Inc(LIndex);
            if LIndex >= Length(LArguments) then
                raise Exception.Create('--secret requires a value');
            Result.Secret := LArguments[LIndex];
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
            if LIndex >= Length(LArguments) then
                raise Exception.Create('--session requires a provider');
            Result.Provider := LArguments[LIndex];
            Result.DoSession := True;
        end
        else if LArg = '--prompt' then
        begin
            Inc(LIndex);
            if LIndex >= Length(LArguments) then
                raise Exception.Create('--prompt requires text');

            // Because ReadCommandLineArguments parses the original Windows
            // command line itself, a quoted or unquoted prompt is already
            // represented without Delphi ParamStr() altering its boundaries.
            // Join all following non-option tokens so prompts with spaces are
            // accepted even when the caller omitted surrounding quotes.
            Result.PromptText := '';
            while LIndex < Length(LArguments) do
            begin
                LOption := LArguments[LIndex];
                if (LOption = '--host') or
                   (LOption = '--port') or
                   (LOption = '--secret') or
                   (LOption = '--self-test') or
                   (LOption = '--conformance') or
                   (LOption = '--ping') or
                   (LOption = '--capabilities') or
                   (LOption = '--browser-status') or
                   (LOption = '--list-tabs') or
                   (LOption = '--session') or
                   (LOption = '--prompt') or
                   (LOption = '--debug') then
                    Break;

                if Result.PromptText <> '' then
                    Result.PromptText := Result.PromptText + ' ';
                Result.PromptText := Result.PromptText + LOption;
                Inc(LIndex);
            end;

            if Result.PromptText = '' then
                raise Exception.Create('--prompt requires text');
            Result.DoPrompt := True;
            Continue;
        end
        else if LArg = '--debug' then
            Result.Debug := True
        else
            raise Exception.Create('Unknown option: ' + LArg);

        Inc(LIndex);
    end;

    if not (Result.RunConformance or Result.RunSelfTest or Result.DoPing or
        Result.DoCapabilities or Result.DoBrowserStatus or Result.DoListTabs or
        Result.DoSession or Result.DoPrompt) then
        PrintHelp;
end;

procedure AssertEqual(const AName, AExpected, AActual: string);
begin
    if AExpected <> AActual then
        raise Exception.CreateFmt('%s failed. Expected="%s" Actual="%s"', [AName, AExpected, AActual]);
    Writeln('[PASS] ', AName);
end;

procedure AssertTrue(const AName: string; ACondition: Boolean);
begin
    if not ACondition then
        raise Exception.Create(AName + ' failed');
    Writeln('[PASS] ', AName);
end;

procedure RunSelfTest;
const
    LSecret = '0123456789abcdef0123456789abcdef';
var
    LRequestID: string;
    LSessionID: string;
    LPayload: TJSONObject;
    LMessage: TJSONObject;
    LFrameBytes: TBytes;
    LFrame: TGARPFrame;
    LText: string;
    LClientNonce: TBytes;
    LServerNonce: TBytes;
    LOffered: TArray<string>;
    LFinal: TArray<string>;
    LProof: TBytes;
begin
    Writeln('=== GARP/1.24 local self-test ===');
    LRequestID := GARPNewUUID;
    LSessionID := GARPNewUUID;
    LText := 'Unicode: äöü 日本語 🚀 and embedded newline' + sLineBreak + 'second line';

    LPayload := TJSONObject.Create;
    try
        LPayload.AddPair('text', LText);
        LMessage := GARPBuildJSON('DIAGNOSTIC', LPayload, LRequestID, LSessionID);
        LPayload := nil;
        try
            LFrameBytes := GARPEncodeFrame(GARP_DIAGNOSTIC, LMessage, LRequestID, LSessionID);
        finally
            LMessage.Free;
        end;
    finally
        LPayload.Free;
    end;

    LFrame := GARPDecodeFrame(LFrameBytes);
    try
        AssertEqual('protocol', GARP_PROTOCOL, LFrame.MessageJSON.GetValue<string>('garp', ''));
        AssertEqual('message type', 'DIAGNOSTIC', LFrame.MessageJSON.GetValue<string>('type', ''));
        AssertEqual('request UUID', LRequestID, LFrame.RequestID);
        AssertEqual('session UUID', LSessionID, LFrame.SessionID);
        AssertEqual('UTF-8 payload', LText, LFrame.MessageJSON.GetValue<string>('payload.text', ''));
        AssertTrue('48-byte fixed header', Length(LFrameBytes) > GARP_FIXED_HEADER_LENGTH);
    finally
        LFrame.MessageJSON.Free;
    end;

    SetLength(LClientNonce, 16);
    SetLength(LServerNonce, 16);
    for var LIndex := 0 to 15 do
    begin
        LClientNonce[LIndex] := LIndex + 1;
        LServerNonce[LIndex] := 16 - LIndex;
    end;
    LOffered := ['!ext-pong'];
    LFinal := ['!ext-pong'];
    LProof := GARPMakeProof(
        LSecret,
        GARP_DOMAIN_CLIENT_PROOF,
        LClientNonce,
        LServerNonce,
        LOffered,
        LFinal,
        'GARPClient',
        '1.24.0',
        'GarpGateway',
        '1.24.0'
    );
    AssertEqual(
        'client proof Base64URL',
        '4RiTq2SUP15gOp1alqIRdMBUM7Qv4CMZqREMXX4efQs',
        GARPBase64UrlEncode(LProof)
    );
    LProof := GARPMakeProof(
        LSecret,
        GARP_DOMAIN_SERVER_PROOF,
        LClientNonce,
        LServerNonce,
        LOffered,
        LFinal,
        'GARPClient',
        '1.24.0',
        'GarpGateway',
        '1.24.0'
    );
    AssertEqual(
        'server proof Base64URL',
        'iFaTVoYbn_pb5yCCHOTpAUyfzFaCkXXKgLAbpMX6cfI',
        GARPBase64UrlEncode(LProof)
    );
end;

procedure PrintJSONObject(const ATitle: string; AObject: TJSONObject);
begin
    Writeln('--- ', ATitle, ' ---');
    if AObject = nil then Writeln('<nil>') else Writeln(AObject.Format(2));
end;

procedure RunLiveBasic(const AOptions: TOptions);
var
    LClient: TGARPClient124;
    LResponse: TJSONObject;
begin
    LClient := TGARPClient124.Create(AOptions.Host, AOptions.Port, AOptions.Secret);
    try
        LClient.Debug := AOptions.Debug;
        LClient.ConnectAndAuthenticate;
        Writeln('[PASS] HELLO/HELLO_CHALLENGE/HELLO_AUTH/HELLO_ACK');

        if AOptions.DoPing then begin LClient.Ping; Writeln('[PASS] PING/RESPONSE'); end;
        if AOptions.DoCapabilities then begin LResponse := LClient.GetCapabilities; try PrintJSONObject('GET_CAPABILITIES', LResponse); finally LResponse.Free; end; end;
        if AOptions.DoBrowserStatus then begin LResponse := LClient.GetBrowserStatus; try PrintJSONObject('BROWSER_STATUS', LResponse); finally LResponse.Free; end; end;
        if AOptions.DoListTabs then begin LResponse := LClient.ListTabs; try PrintJSONObject('LIST_TABS', LResponse); finally LResponse.Free; end; end;
        if AOptions.DoSession then begin
            LResponse := LClient.CreateSession(AOptions.Provider);
            try PrintJSONObject('CREATE_SESSION', LResponse); finally LResponse.Free; end;
            Writeln('SessionID: ', LClient.SessionID);
            Writeln('TabID    : ', LClient.TabID);
        end;
        if AOptions.DoPrompt then
        begin
            if LClient.SessionID = '' then
            begin
                if AOptions.Provider = '' then raise Exception.Create('--prompt requires --session <provider>');
                LResponse := LClient.CreateSession(AOptions.Provider);
                LResponse.Free;
            end;
            LResponse := LClient.Prompt(AOptions.PromptText);
            try PrintJSONObject('PROMPT RESPONSE', LResponse); finally LResponse.Free; end;
            LResponse := LClient.WaitForCompletion(LClient.RequestID, 180000);
            try PrintJSONObject('TERMINAL EVENT', LResponse); finally LResponse.Free; end;
        end;
        LClient.CloseSession;
    finally
        LClient.Free;
    end;
end;

procedure RunConformance(const AOptions: TOptions);
var
    LClient: TGARPClient124;
    LResponse: TJSONObject;
    LProvider: string;
    LPromptID: string;
begin
    Writeln('=== GARP/1.24 live conformance smoke test ===');
    if AOptions.Secret = '' then raise Exception.Create('GARP secret not supplied');

    LProvider := AOptions.Provider;
    if LProvider = '' then LProvider := 'deepseek';

    LClient := TGARPClient124.Create(AOptions.Host, AOptions.Port, AOptions.Secret);
    try
        LClient.Debug := AOptions.Debug;
        LClient.ConnectAndAuthenticate;
        Writeln('[PASS] HELLO/HELLO_CHALLENGE/HELLO_AUTH/HELLO_ACK');

        LClient.Ping;
        Writeln('[PASS] PING/RESPONSE');

        LResponse := LClient.GetCapabilities;
        try
            Writeln('[PASS] GET_CAPABILITIES');
            PrintJSONObject('CAPABILITIES', LResponse);
        finally LResponse.Free; end;

        LResponse := LClient.GetBrowserStatus;
        try
            Writeln('[PASS] BROWSER_STATUS');
            PrintJSONObject('BROWSER_STATUS', LResponse);
        finally LResponse.Free; end;

        LResponse := LClient.ListTabs;
        try
            Writeln('[PASS] LIST_TABS');
            PrintJSONObject('LIST_TABS', LResponse);
        finally LResponse.Free; end;

        Writeln('Creating session for provider: ', LProvider);
        LResponse := LClient.CreateSession(LProvider);
        try
            Writeln('[PASS] CREATE_SESSION');
            PrintJSONObject('CREATE_SESSION', LResponse);
        finally LResponse.Free; end;

        LResponse := LClient.Prompt('Reply with exactly: GARP/1.24 TEST OK', 120000, True);
        try
            Writeln('[PASS] PROMPT accepted by RESPONSE');
            PrintJSONObject('PROMPT RESPONSE', LResponse);
        finally LResponse.Free; end;
        LPromptID := LClient.RequestID;

        LResponse := LClient.WaitForCompletion(LPromptID, 120000);
        try
            PrintJSONObject('TERMINAL EVENT', LResponse);
            AssertTrue('terminal generation event',
                SameText(LResponse.GetValue<string>('type', ''), 'GENERATION_COMPLETED') or
                SameText(LResponse.GetValue<string>('type', ''), 'GENERATION_FAILED') or
                SameText(LResponse.GetValue<string>('type', ''), 'GENERATION_CANCELLED'));
        finally LResponse.Free; end;

        LClient.CloseSession;
        Writeln('[PASS] CLOSE_SESSION');
    finally
        LClient.Free;
    end;
end;

var
    LOptions: TOptions;
begin
    SetConsoleOutputCP(CP_UTF8);
    try
        LOptions := ParseOptions;
        if LOptions.RunSelfTest then RunSelfTest;
        if LOptions.RunConformance then
            RunConformance(LOptions)
        else if LOptions.DoPing or LOptions.DoCapabilities or LOptions.DoBrowserStatus or
            LOptions.DoListTabs or LOptions.DoSession or LOptions.DoPrompt then
            RunLiveBasic(LOptions);
    except
        on E: Exception do
        begin
            Writeln('ERROR: ', E.ClassName, ': ', E.Message);
            ExitCode := 1;
        end;
    end;
end.
