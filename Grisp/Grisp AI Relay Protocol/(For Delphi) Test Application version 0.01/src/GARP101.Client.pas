unit GARP101.Client;

interface

uses
    System.SysUtils,
    System.JSON,
    IdTCPClient,
    GARP101.Protocol;

type
    TGARPClient101 = class
    private
        FClient: TIdTCPClient;
        FClientID: string;
        FClientVersion: string;
        FSecret: string;
        FClientNonce: string;
        FAuthenticated: Boolean;
        FSessionID: string;
        FTabID: string;
        FRequestID: string;
        procedure EnsureConnected;
        function NextRequestID: string;
        procedure SendFrame(const AMessageType: TGARPMessageType; const AMessage: TJSONObject;
            const ARequestID: string = ''; const ASessionID: string = '');
        function ReceiveFrame(out AFrame: TGARPFrame): Boolean;
        function ReceiveUntil(const ARequestID: string; const AAcceptedTypes: array of TGARPMessageType;
            out AFrame: TGARPFrame): Boolean;
        function BuildMessage(const ATypeName: string; const APayload: TJSONValue): TJSONObject;
    public
        constructor Create(const AHost: string; const APort: Integer; const ASecret: string);
        destructor Destroy; override;
        procedure ConnectAndAuthenticate;
        function GetCapabilities: TJSONObject;
        function GetBrowserStatus: TJSONObject;
        function ListTabs: TJSONObject;
        function CreateSession(const AProvider: string; const ATabID: string = ''): TJSONObject;
        function Prompt(const APrompt: string; const AStream: Boolean = True;
            const ATimeoutMS: Integer = 180000; const AAutoContinue: Boolean = True): TJSONObject;
        function WaitForCompletion(const ARequestID: string; const ATimeoutMS: Cardinal = 180000): TJSONObject;
        function CancelPrompt(const ARequestID, AReason: string): TJSONObject;
        procedure Ping;
        procedure CloseSession;
        property SessionID: string read FSessionID;
        property TabID: string read FTabID;
        property RequestID: string read FRequestID;
    end;

implementation

constructor TGARPClient101.Create(const AHost: string; const APort: Integer; const ASecret: string);
begin
    inherited Create;
    FClient := TIdTCPClient.Create(nil);
    FClient.Host := AHost;
    FClient.Port := APort;
    FClient.ConnectTimeout := 5000;
    FClient.ReadTimeout := 5000;
    FSecret := ASecret;
    FClientID := 'GARP101-Delphi-Test-' + GARPNewUUID;
    FClientVersion := '1.0.0';
end;

destructor TGARPClient101.Destroy;
begin
    FClient.Free;
    inherited Destroy;
end;

procedure TGARPClient101.EnsureConnected;
begin
    if not FClient.Connected then
        raise Exception.Create('GARP client is not connected');
end;

function TGARPClient101.NextRequestID: string;
begin
    Result := GARPNewUUID;
    FRequestID := Result;
end;

function TGARPClient101.BuildMessage(const ATypeName: string; const APayload: TJSONValue): TJSONObject;
begin
    Result := GARPBuildJSON(ATypeName, APayload);
end;

procedure TGARPClient101.SendFrame(const AMessageType: TGARPMessageType; const AMessage: TJSONObject;
    const ARequestID: string; const ASessionID: string);
var
    LFrame: TBytes;
begin
    LFrame := GARPEncodeFrame(AMessageType, AMessage, ARequestID, ASessionID);
    GARPWriteFrame(FClient, LFrame);
end;

function TGARPClient101.ReceiveFrame(out AFrame: TGARPFrame): Boolean;
var
    LBytes: TBytes;
begin
    LBytes := GARPReadFrame(FClient);
    AFrame := GARPDecodeFrame(LBytes);
    Result := True;
end;

function TGARPClient101.ReceiveUntil(const ARequestID: string; const AAcceptedTypes: array of TGARPMessageType;
    out AFrame: TGARPFrame): Boolean;
var
    LTypeMatches: Boolean;
    LIndex: Integer;
    LAcceptedType: TGARPMessageType;
begin
    repeat
        ReceiveFrame(AFrame);
        if (AFrame.MessageType = GARP_PING) then
        begin
            var LPong := BuildMessage('pong', TJSONObject.Create);
            try
                SendFrame(GARP_PONG, LPong);
            finally
                LPong.Free;
            end;
            AFrame.MessageJSON.Free;
            AFrame.MessageJSON := nil;
            Continue;
        end;

        LTypeMatches := Length(AAcceptedTypes) = 0;
        for LIndex := Low(AAcceptedTypes) to High(AAcceptedTypes) do
        begin
            LAcceptedType := AAcceptedTypes[LIndex];
            if AFrame.MessageType = LAcceptedType then
                LTypeMatches := True;
        end;

        if (ARequestID <> '') and (AFrame.RequestID <> '') and
           (not SameText(ARequestID, AFrame.RequestID)) then
        begin
            if LTypeMatches then
            begin
                // Asynchronous event for another request/session: surface it to the console caller.
                Writeln('[event ', GARPMessageTypeToName(AFrame.MessageType), '] ', AFrame.MessageJSON.ToJSON);
            end;
            AFrame.MessageJSON.Free;
            AFrame.MessageJSON := nil;
            Continue;
        end;

        if not LTypeMatches then
        begin
            AFrame.MessageJSON.Free;
            AFrame.MessageJSON := nil;
            Continue;
        end;

        Exit(True);
    until False;
end;

procedure TGARPClient101.ConnectAndAuthenticate;
var
    LHello: TJSONObject;
    LPayload: TJSONObject;
    LFrame: TGARPFrame;
    LServerNonce: string;
    LProof: string;
    LAuth: TJSONObject;
begin
    if FClient.Connected then
        Exit;
    if FSecret = '' then
        raise Exception.Create('GARP secret is empty. Use --secret or GARP_SECRET.');

    FClient.Connect;
    FClient.IOHandler.ReadTimeout := 10000;

    FClientNonce := GARPCreateNonce;
    LPayload := TJSONObject.Create;
    try
        LPayload.AddPair('client_id', FClientID);
        LPayload.AddPair('client_version', FClientVersion);
        LPayload.AddPair('nonce', FClientNonce);
        LHello := BuildMessage('hello', LPayload);
        try
            SendFrame(GARP_HELLO, LHello, '', '');
        finally
            LHello.Free;
        end;
    except
        raise;
    end;

    ReceiveFrame(LFrame);
    try
        if LFrame.MessageType <> GARP_HELLO_CHALLENGE then
            raise Exception.CreateFmt('Expected hello_challenge, received %s', [GARPMessageTypeToName(LFrame.MessageType)]);
        LServerNonce := LFrame.MessageJSON.GetValue<string>('payload.server_nonce', '');
        if LServerNonce = '' then
            raise Exception.Create('hello_challenge does not contain server_nonce');
    finally
        LFrame.MessageJSON.Free;
    end;

    LAuth := TJSONObject.Create;
    try
        LAuth.AddPair('client_id', FClientID);
        LAuth.AddPair('client_nonce', FClientNonce);
        LAuth.AddPair('server_nonce', LServerNonce);
        LProof := GARPMakeHMACProof(FSecret, FClientID, FClientNonce, LServerNonce);
        LAuth.AddPair('proof', LProof);

        var LAuthMessage := BuildMessage('hello_auth', LAuth);
        try
            SendFrame(GARP_HELLO_AUTH, LAuthMessage);
        finally
            LAuthMessage.Free;
        end;
    finally
        LAuth.Free;
    end;

    ReceiveFrame(LFrame);
    try
        if LFrame.MessageType <> GARP_HELLO_ACK then
            raise Exception.CreateFmt('Expected hello_ack, received %s', [GARPMessageTypeToName(LFrame.MessageType)]);
        LPayload := LFrame.MessageJSON.GetValue<TJSONObject>('payload');
        if LPayload = nil then
            raise Exception.Create('hello_ack has no payload');
        FAuthenticated := True;
    finally
        LFrame.MessageJSON.Free;
    end;
end;

function TGARPClient101.GetCapabilities: TJSONObject;
var
    LMessage: TJSONObject;
    LFrame: TGARPFrame;
    LRequestID: string;
begin
    EnsureConnected;
    LRequestID := NextRequestID;
    LMessage := BuildMessage('capabilities', TJSONObject.Create);
    try
        SendFrame(GARP_CAPABILITIES, LMessage, LRequestID, '');
    finally
        LMessage.Free;
    end;
    ReceiveUntil(LRequestID, [GARP_CAPABILITIES, GARP_RESPONSE], LFrame);
    Result := LFrame.MessageJSON;
end;

function TGARPClient101.GetBrowserStatus: TJSONObject;
var
    LMessage: TJSONObject;
    LFrame: TGARPFrame;
    LRequestID: string;
begin
    EnsureConnected;
    LRequestID := NextRequestID;
    LMessage := BuildMessage('browser_status', TJSONObject.Create);
    try
        SendFrame(GARP_BROWSER_STATUS, LMessage, LRequestID, '');
    finally
        LMessage.Free;
    end;
    ReceiveUntil(LRequestID, [GARP_BROWSER_STATUS, GARP_RESPONSE], LFrame);
    Result := LFrame.MessageJSON;
end;

function TGARPClient101.ListTabs: TJSONObject;
var
    LMessage: TJSONObject;
    LFrame: TGARPFrame;
    LRequestID: string;
begin
    EnsureConnected;
    LRequestID := NextRequestID;
    LMessage := BuildMessage('list_tabs', TJSONObject.Create);
    try
        SendFrame(GARP_LIST_TABS, LMessage, LRequestID, '');
    finally
        LMessage.Free;
    end;
    ReceiveUntil(LRequestID, [GARP_RESPONSE, GARP_LIST_TABS], LFrame);
    Result := LFrame.MessageJSON;
end;

function TGARPClient101.CreateSession(const AProvider: string; const ATabID: string): TJSONObject;
var
    LPayload: TJSONObject;
    LMessage: TJSONObject;
    LFrame: TGARPFrame;
    LRequestID: string;
    LSessionID: string;
    LTabID: string;
begin
    EnsureConnected;
    LRequestID := NextRequestID;
    LPayload := TJSONObject.Create;
    LPayload.AddPair('provider', AProvider);
    if ATabID <> '' then
        LPayload.AddPair('tab_id', ATabID);
    LMessage := BuildMessage('create_session', LPayload);
    try
        SendFrame(GARP_CREATE_SESSION, LMessage, LRequestID, '');
    finally
        LMessage.Free;
    end;
    ReceiveUntil(LRequestID, [GARP_RESPONSE, GARP_SESSION_READY], LFrame);
    Result := LFrame.MessageJSON;
    LSessionID := Result.GetValue<string>('payload.session_id', '');
    if LSessionID = '' then
        LSessionID := Result.GetValue<string>('session_id', '');
    LTabID := Result.GetValue<string>('payload.tab_id', '');
    if LTabID = '' then
        LTabID := Result.GetValue<string>('tab_id', '');
    if LSessionID <> '' then FSessionID := LSessionID;
    if LTabID <> '' then FTabID := LTabID;
end;

function TGARPClient101.Prompt(const APrompt: string; const AStream: Boolean;
    const ATimeoutMS: Integer; const AAutoContinue: Boolean): TJSONObject;
var
    LOptions: TJSONObject;
    LPrompt: TJSONObject;
    LPayload: TJSONObject;
    LMessage: TJSONObject;
    LFrame: TGARPFrame;
begin
    EnsureConnected;
    if FSessionID = '' then
        raise Exception.Create('No GARP session is active');

    NextRequestID;
    LPrompt := TJSONObject.Create;
    LPrompt.AddPair('format', 'text');
    LPrompt.AddPair('text', APrompt);
    LOptions := TJSONObject.Create;
    LOptions.AddPair('stream', TJSONBool.Create(AStream));
    LOptions.AddPair('timeout_ms', TJSONNumber.Create(ATimeoutMS));
    LOptions.AddPair('auto_continue', TJSONBool.Create(AAutoContinue));
    LPayload := TJSONObject.Create;
    LPayload.AddPair('prompt', LPrompt);
    LPayload.AddPair('options', LOptions);
    LMessage := BuildMessage('prompt', LPayload);
    try
        SendFrame(GARP_PROMPT, LMessage, FRequestID, FSessionID);
    finally
        LMessage.Free;
    end;

    ReceiveUntil(FRequestID, [GARP_PROMPT_ACK], LFrame);
    Result := LFrame.MessageJSON;
end;

function TGARPClient101.WaitForCompletion(const ARequestID: string; const ATimeoutMS: Cardinal): TJSONObject;
var
    LOriginalTimeout: Integer;
    LStart: UInt64;
    LFrame: TGARPFrame;
    LContent: string;
    LPayload: TJSONObject;
    LStatus: string;
begin
    EnsureConnected;
    LOriginalTimeout := FClient.IOHandler.ReadTimeout;
    FClient.IOHandler.ReadTimeout := 1000;
    try
        LStart := TThread.GetTickCount64;
        repeat
            LFrame.MessageJSON := nil;
            try
                if not ReceiveFrame(LFrame) then
                    raise Exception.Create('No GARP event received');

                Writeln('[', GARPMessageTypeToName(LFrame.MessageType), '] ', LFrame.MessageJSON.ToJSON);
                if (ARequestID <> '') and (LFrame.RequestID <> '') and not SameText(ARequestID, LFrame.RequestID) then
                begin
                    Continue;
                end;

                case LFrame.MessageType of
                    GARP_GENERATION_COMPLETED:
                        begin
                            Result := LFrame.MessageJSON;
                            LFrame.MessageJSON := nil;
                            Exit;
                        end;
                    GARP_GENERATION_FAILED, GARP_ERROR:
                        begin
                            Result := LFrame.MessageJSON;
                            LFrame.MessageJSON := nil;
                            Exit;
                        end;
                    GARP_GENERATION_PROGRESS:
                        begin
                            LPayload := LFrame.MessageJSON.GetValue<TJSONObject>('payload');
                            if LPayload <> nil then
                            begin
                                LStatus := LPayload.GetValue<string>('state', '');
                                if SameText(LStatus, 'complete') then
                                begin
                                    Result := LFrame.MessageJSON;
                                    LFrame.MessageJSON := nil;
                                    Exit;
                                end;
                            end;
                        end;
                end;
            except
                on E: EIdConnClosedGracefully do
                    raise Exception.Create('GARP connection closed while waiting for completion: ' + E.Message);
                on E: EIdReadTimeout do
                begin
                    // Continue until the overall deadline.
                end;
            finally
                LFrame.MessageJSON.Free;
            end;
        until TThread.GetTickCount64 - LStart >= ATimeoutMS;
    finally
        FClient.IOHandler.ReadTimeout := LOriginalTimeout;
    end;

    LPayload := TJSONObject.Create;
    LPayload.AddPair('code', 'GENERATION_TIMEOUT');
    LPayload.AddPair('message', 'Timed out waiting for generation_completed');
    LPayload.AddPair('request_id', ARequestID);
    Result := GARPBuildJSON('error', LPayload, ARequestID, FSessionID);
end;

function TGARPClient101.CancelPrompt(const ARequestID, AReason: string): TJSONObject;
var
    LPayload: TJSONObject;
    LMessage: TJSONObject;
    LFrame: TGARPFrame;
begin
    EnsureConnected;
    LPayload := TJSONObject.Create;
    LPayload.AddPair('reason', AReason);
    LMessage := BuildMessage('cancel_prompt', LPayload);
    try
        SendFrame(GARP_CANCEL_PROMPT, LMessage, ARequestID, FSessionID);
    finally
        LMessage.Free;
    end;
    ReceiveUntil(ARequestID, [GARP_CANCEL_ACK, GARP_ERROR], LFrame);
    Result := LFrame.MessageJSON;
end;

procedure TGARPClient101.Ping;
var
    LMessage: TJSONObject;
    LFrame: TGARPFrame;
begin
    EnsureConnected;
    LMessage := BuildMessage('ping', TJSONObject.Create);
    try
        SendFrame(GARP_PING, LMessage);
    finally
        LMessage.Free;
    end;
    ReceiveUntil('', [GARP_PONG], LFrame);
    LFrame.MessageJSON.Free;
end;

procedure TGARPClient101.CloseSession;
var
    LPayload: TJSONObject;
    LMessage: TJSONObject;
    LFrame: TGARPFrame;
    LRequestID: string;
begin
    if FSessionID = '' then
        Exit;
    EnsureConnected;
    LRequestID := NextRequestID;
    LPayload := TJSONObject.Create;
    LPayload.AddPair('session_id', FSessionID);
    LMessage := BuildMessage('close_session', LPayload);
    try
        SendFrame(GARP_CLOSE_SESSION, LMessage, LRequestID, FSessionID);
    finally
        LMessage.Free;
    end;
    ReceiveUntil(LRequestID, [GARP_RESPONSE, GARP_CLOSE_SESSION], LFrame);
    LFrame.MessageJSON.Free;
    FSessionID := '';
    FTabID := '';
end;

end.
