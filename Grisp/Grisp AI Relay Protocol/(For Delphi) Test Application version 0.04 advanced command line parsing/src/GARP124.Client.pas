unit GARP124.Client;

interface

uses
    System.SysUtils,
    System.Classes,
    System.JSON,
    System.Generics.Collections,
    IdTCPClient,
    GARP124.Protocol;

type
    TGARPClient124 = class
    private
        FClient: TIdTCPClient;
        FClientID: string;
        FClientName: string;
        FClientVersion: string;
        FSecret: string;
        FClientNonce: TBytes;
        FServerNonce: TBytes;
        FOfferedFeatures: TArray<string>;
        FNegotiatedFeatures: TArray<string>;
        FServerName: string;
        FServerVersion: string;
        FAuthenticated: Boolean;
        FSessionID: string;
        FTabID: string;
        FRequestID: string;
        FDebug: Boolean;
        FBrowserStatus: TJSONObject;
        FCapabilities: TJSONObject;
        FServerProof: TBytes;

        procedure DebugLog(const AMessage: string);
        procedure DebugFrame(const APrefix: string; const AFrameBytes: TBytes; const AFrame: TGARPFrame);
        procedure EnsureConnected;
        function NextRequestID: string;
        procedure SendFrame(const AMessageType: TGARPMessageType; const AMessage: TJSONObject; const ARequestID: string = ''; const ASessionID: string = '');
        function ReceiveFrame(out AFrame: TGARPFrame; const ATimeoutMS: Cardinal = 0; const AMaxPayloadBytes: Cardinal = GARP_APPLICATION_MAX_PAYLOAD): Boolean;
        function ReceiveUntilRequest(const ARequestID: string; const AAcceptedTypes: array of TGARPMessageType; out AFrame: TGARPFrame; const ATimeoutMS: Cardinal = 30000; const AMaxPayloadBytes: Cardinal = GARP_APPLICATION_MAX_PAYLOAD): Boolean;
        function ReceiveUntilPromptEvent(const APromptRequestID: string; out AFrame: TGARPFrame; const ATimeoutMS: Cardinal): Boolean;
        function BuildMessage(const ATypeName: string; const APayload: TJSONValue; const ARequestID: string = ''; const ASessionID: string = ''): TJSONObject;
        function GetErrorText(const AFrame: TGARPFrame): string;
        function IsAcceptedType(const AMessageType: TGARPMessageType; const AAcceptedTypes: array of TGARPMessageType): Boolean;
        function ConstantTimeEqual(const ALeft, ARight: TBytes): Boolean;
        function HasNegotiatedFeature(const AFeature: string): Boolean;
        procedure HandleUnsolicitedFrame(var AFrame: TGARPFrame);
        procedure StoreCapabilities(const AFrame: TGARPFrame);
        procedure StoreBrowserStatus(const AFrame: TGARPFrame);
        function WaitForSessionReady(const ASessionID: string; const ATimeoutMS: Cardinal): TJSONObject;
        procedure CloseConnection;
    public
        constructor Create(const AHost: string; const APort: Integer; const ASecret: string);
        destructor Destroy; override;

        procedure ConnectAndAuthenticate;

        function GetCapabilities: TJSONObject;
        function GetBrowserStatus: TJSONObject;
        function ListTabs: TJSONObject;
        function OpenTab(const AURL: string): TJSONObject;
        function CloseTab(const ATabID: string): TJSONObject;
        function SelectTab(const ATabID: string): TJSONObject;

        function CreateSession(const AProvider: string; const ATabID: string = ''): TJSONObject;
        function GetSession: TJSONObject;
        function Prompt(const APrompt: string; const ATimeoutMS: Integer = 180000; const AAutoContinue: Boolean = True; const AForceFocus: Boolean = False; const ASimulateEnter: Boolean = False): TJSONObject;
        function WaitForCompletion(const ARequestID: string; const ATimeoutMS: Cardinal = 180000): TJSONObject;
        function GetPromptStatus(const ARequestID: string): TJSONObject;
        function GetResponse(const ARequestID: string): TJSONObject;
        function CancelPrompt(const ARequestID: string): TJSONObject;
        function ContinuePrompt(const ARequestID: string): TJSONObject;
        function GetEvents(const AFromSequence: UInt64; const AMaxEvents: Cardinal = 4096): TJSONObject;
        function SubscribeResponse(const ARequestID: string): TJSONObject;
        procedure Ping;
        procedure CloseSession;

        property SessionID: string read FSessionID;
        property TabID: string read FTabID;
        property RequestID: string read FRequestID;
        property Authenticated: Boolean read FAuthenticated;
        property Debug: Boolean read FDebug write FDebug;
        property BrowserStatus: TJSONObject read FBrowserStatus;
        property Capabilities: TJSONObject read FCapabilities;
        property NegotiatedFeatures: TArray<string> read FNegotiatedFeatures;
    end;

implementation

constructor TGARPClient124.Create(const AHost: string; const APort: Integer; const ASecret: string);
begin
    inherited Create;
    FClient := TIdTCPClient.Create(nil);
    FClient.Host := AHost;
    FClient.Port := APort;
    FClient.ConnectTimeout := 5000;
    FClient.ReadTimeout := GARP_READ_TIMEOUT;

    FClientID := 'GARP124-Delphi-Test-' + GARPNewUUID;
    FClientName := 'GARP124-Delphi-Test';
    FClientVersion := '1.24.0';
    FSecret := ASecret;
    FAuthenticated := False;
    FSessionID := '';
    FTabID := '';
    FRequestID := '';
    FDebug := False;
    FBrowserStatus := nil;
    FCapabilities := nil;
    FOfferedFeatures := GARPCanonicalFeatureList([GARP_FEATURE_EXT_PONG, GARP_FEATURE_EXT_REPLAY_STORE]);
end;

destructor TGARPClient124.Destroy;
begin
    CloseConnection;
    FBrowserStatus.Free;
    FCapabilities.Free;
    FClient.Free;
    inherited Destroy;
end;

procedure TGARPClient124.DebugLog(const AMessage: string);
begin
    if not FDebug then
        Exit;
    Writeln('[DEBUG ', FormatDateTime('hh:nn:ss.zzz', Now), '] ', AMessage);
end;

procedure TGARPClient124.DebugFrame(const APrefix: string; const AFrameBytes: TBytes; const AFrame: TGARPFrame);
begin
    if not FDebug then
        Exit;
    DebugLog(Format('%s bytes=%d type=%s request_id=%s session_id=%s', [
        APrefix, Length(AFrameBytes), GARPMessageTypeToName(AFrame.MessageType), AFrame.RequestID, AFrame.SessionID
    ]));
    if AFrame.MessageJSON <> nil then
        DebugLog(APrefix + ' JSON=' + AFrame.MessageJSON.ToJSON);
end;

procedure TGARPClient124.CloseConnection;
begin
    FAuthenticated := False;
    if (FClient <> nil) and FClient.Connected then
    begin
        try
            FClient.Disconnect;
        except
            on E: Exception do
                DebugLog('disconnect: ' + E.Message);
        end;
    end;
end;

procedure TGARPClient124.EnsureConnected;
begin
    if not FClient.Connected then
        raise EGARPProtocolError.Create('GARP client is not connected');
    if not FAuthenticated then
        raise EGARPProtocolError.Create('GARP client is not authenticated');
end;

function TGARPClient124.NextRequestID: string;
begin
    Result := GARPNewUUID;
    FRequestID := Result;
end;

function TGARPClient124.BuildMessage(const ATypeName: string; const APayload: TJSONValue; const ARequestID: string; const ASessionID: string): TJSONObject;
begin
    Result := GARPBuildJSON(ATypeName, APayload, ARequestID, ASessionID);
end;

procedure TGARPClient124.SendFrame(const AMessageType: TGARPMessageType; const AMessage: TJSONObject; const ARequestID: string; const ASessionID: string);
var
    LFrame: TBytes;
    LDecodedFrame: TGARPFrame;
begin
    LFrame := GARPEncodeFrame(AMessageType, AMessage, ARequestID, ASessionID);
    if FDebug then
    begin
        LDecodedFrame := GARPDecodeFrame(LFrame);
        try
            DebugFrame('SEND', LFrame, LDecodedFrame);
        finally
            LDecodedFrame.MessageJSON.Free;
            LDecodedFrame.MessageJSON := nil;
        end;
    end;
    GARPWriteFrame(FClient, LFrame);
end;

function TGARPClient124.ReceiveFrame(out AFrame: TGARPFrame; const ATimeoutMS: Cardinal; const AMaxPayloadBytes: Cardinal): Boolean;
var
    LFrameBytes: TBytes;
    LOldTimeout: Integer;
begin
    FillChar(AFrame, SizeOf(AFrame), 0);
    AFrame.MessageJSON := nil;
    LOldTimeout := FClient.IOHandler.ReadTimeout;
    try
        if ATimeoutMS > 0 then
            FClient.IOHandler.ReadTimeout := ATimeoutMS;
        LFrameBytes := GARPReadFrame(FClient, AMaxPayloadBytes);
        AFrame := GARPDecodeFrame(LFrameBytes);
        DebugFrame('RECEIVE', LFrameBytes, AFrame);
        Result := True;
    finally
        FClient.IOHandler.ReadTimeout := LOldTimeout;
    end;
end;

function TGARPClient124.IsAcceptedType(const AMessageType: TGARPMessageType; const AAcceptedTypes: array of TGARPMessageType): Boolean;
var
    LType: TGARPMessageType;
begin
    Result := False;
    for LType in AAcceptedTypes do
        if LType = AMessageType then
            Exit(True);
end;

function TGARPClient124.GetErrorText(const AFrame: TGARPFrame): string;
var
    LPayload: TJSONObject;
    LDetails: TJSONValue;
    LCode: string;
    LMessage: string;
begin
    Result := AFrame.MessageJSON.ToJSON;
    if AFrame.MessageType <> GARP_ERROR then
        Exit;
    try
        LPayload := GARPJSONObjectPayload(AFrame);
        LCode := LPayload.GetValue<string>('code', 'ERROR');
        LMessage := LPayload.GetValue<string>('message', Result);
        Result := Format('%s: %s', [LCode, LMessage]);
        LDetails := LPayload.GetValue('details');
        if LDetails <> nil then
            Result := Result + ' details=' + LDetails.ToJSON;
    except
        { Keep complete frame JSON as fallback. }
    end;
end;

procedure TGARPClient124.StoreCapabilities(const AFrame: TGARPFrame);
begin
    FCapabilities.Free;
    FCapabilities := AFrame.MessageJSON.Clone as TJSONObject;
end;

procedure TGARPClient124.StoreBrowserStatus(const AFrame: TGARPFrame);
begin
    FBrowserStatus.Free;
    FBrowserStatus := AFrame.MessageJSON.Clone as TJSONObject;
end;

procedure TGARPClient124.HandleUnsolicitedFrame(var AFrame: TGARPFrame);
begin
    if AFrame.MessageType = GARP_CAPABILITIES then
        StoreCapabilities(AFrame)
    else if AFrame.MessageType = GARP_BROWSER_STATUS then
        StoreBrowserStatus(AFrame)
    else if AFrame.MessageType = GARP_PING then
    begin
        var LPong := BuildMessage('PONG', nil);
        try
            SendFrame(GARP_PONG, LPong);
        finally
            LPong.Free;
        end;
    end;
end;

function TGARPClient124.ReceiveUntilRequest(const ARequestID: string; const AAcceptedTypes: array of TGARPMessageType; out AFrame: TGARPFrame; const ATimeoutMS: Cardinal; const AMaxPayloadBytes: Cardinal): Boolean;
var
    LStart: UInt64;
    LNow: UInt64;
    LRemaining: Cardinal;
    LFrame: TGARPFrame;
begin
    LStart := TThread.GetTickCount64;
    FillChar(AFrame, SizeOf(AFrame), 0);
    AFrame.MessageJSON := nil;

    while True do
    begin
        LNow := TThread.GetTickCount64;
        if LNow - LStart >= ATimeoutMS then
            Exit(False);
        LRemaining := ATimeoutMS - Cardinal(LNow - LStart);

        ReceiveFrame(LFrame, LRemaining, AMaxPayloadBytes);
        try
            {
              When the caller explicitly waits for an unsolicited envelope,
              return CAPABILITIES/BROWSER_STATUS instead of consuming it.
              This is required during post-authentication state acquisition.
            }
            if (ARequestID = '') and (LFrame.RequestID = '') then
            begin
                if IsAcceptedType(LFrame.MessageType, AAcceptedTypes) then
                begin
                    AFrame := LFrame;
                    LFrame.MessageJSON := nil;
                    Exit(True);
                end;

                if LFrame.MessageType in [GARP_CAPABILITIES, GARP_BROWSER_STATUS] then
                begin
                    HandleUnsolicitedFrame(LFrame);
                    Continue;
                end;
            end;

            if LFrame.MessageType = GARP_PING then
            begin
                HandleUnsolicitedFrame(LFrame);
                Continue;
            end;

            if (ARequestID <> '') and not GARPFrameRequestIDMatches(LFrame, ARequestID) then
                Continue;

            if IsAcceptedType(LFrame.MessageType, AAcceptedTypes) then
            begin
                AFrame := LFrame;
                LFrame.MessageJSON := nil;
                Exit(True);
            end;
        finally
            LFrame.MessageJSON.Free;
            LFrame.MessageJSON := nil;
        end;
    end;
end;

function TGARPClient124.ReceiveUntilPromptEvent(const APromptRequestID: string; out AFrame: TGARPFrame; const ATimeoutMS: Cardinal): Boolean;
var
    LStart: UInt64;
    LFrame: TGARPFrame;
    LPayload: TJSONObject;
    LPromptID: string;
    LNow: UInt64;
    LRemaining: Cardinal;
begin
    LStart := TThread.GetTickCount64;
    FillChar(AFrame, SizeOf(AFrame), 0);

    while True do
    begin
        LNow := TThread.GetTickCount64;
        if LNow - LStart >= ATimeoutMS then
            Exit(False);

        LRemaining := ATimeoutMS - Cardinal(LNow - LStart);

        FillChar(LFrame, SizeOf(LFrame), 0);
        LFrame.MessageJSON := nil;

        try
            ReceiveFrame(LFrame, LRemaining);

            if LFrame.MessageType in [GARP_CAPABILITIES, GARP_BROWSER_STATUS, GARP_PING] then
            begin
                HandleUnsolicitedFrame(LFrame);
                Continue;
            end;

            if LFrame.MessageType in [GARP_GENERATION_STARTED, GARP_GENERATION_DELTA, GARP_GENERATION_PROGRESS,
                GARP_CONTINUATION_REQUIRED, GARP_CONTINUATION_SUBMITTED, GARP_GENERATION_COMPLETED,
                GARP_GENERATION_FAILED, GARP_GENERATION_CANCELLED, GARP_INPUT_SUBMITTED,
                GARP_PROVIDER_ERROR, GARP_PROVIDER_AUTH_REQUIRED, GARP_PROVIDER_RATE_LIMITED, GARP_DIAGNOSTIC] then
            begin
                LPayload := GARPJSONObjectPayload(LFrame);
                LPromptID := LPayload.GetValue<string>('prompt_request_id', '');

                if SameText(LPromptID, APromptRequestID) then
                begin
                    {
                      Prompt lifecycle events are not all terminal. In particular,
                      INPUT_SUBMITTED merely confirms that the provider accepted the
                      prompt and that generation observation should continue. The
                      same applies to STARTED, DELTA, PROGRESS and continuation events.

                      WaitForCompletion must therefore consume those events and keep
                      waiting until one of the three terminal generation events is
                      received for this prompt.
                    }
                    if LFrame.MessageType in [GARP_GENERATION_COMPLETED, GARP_GENERATION_FAILED,
                        GARP_GENERATION_CANCELLED] then
                    begin
                        AFrame := LFrame;
                        LFrame.MessageJSON := nil;
                        Exit(True);
                    end;

                    DebugLog('Ignoring non-terminal prompt event: ' + GARPMessageTypeToName(LFrame.MessageType));
                end;
            end;
        finally
            LFrame.MessageJSON.Free;
            LFrame.MessageJSON := nil;
        end;
    end;
end;

function TGARPClient124.ConstantTimeEqual(const ALeft, ARight: TBytes): Boolean;
var
    LIndex: Integer;
    LDiff: Byte;
begin
    if Length(ALeft) <> Length(ARight) then
        Exit(False);
    LDiff := 0;
    for LIndex := 0 to High(ALeft) do
        LDiff := LDiff or (ALeft[LIndex] xor ARight[LIndex]);
    Result := LDiff = 0;
end;

function TGARPClient124.HasNegotiatedFeature(const AFeature: string): Boolean;
var
    LIndex: Integer;
begin
    Result := False;
    for LIndex := 0 to High(FNegotiatedFeatures) do
        if SameText(FNegotiatedFeatures[LIndex], AFeature) then
            Exit(True);
end;

procedure TGARPClient124.ConnectAndAuthenticate;
var
    LHelloPayload: TJSONObject;
    LAuthPayload: TJSONObject;
    LMessage: TJSONObject;
    LFrame: TGARPFrame;
    LChallenge: TJSONObject;
    LAck: TJSONObject;
    LServerNonceText: string;
    LSelectedVersion: string;
    LSelectedWire: string;
    LFinalFeaturesJSON: TJSONArray;
    LOfferedFeaturesJSON: TJSONArray;
    LFinalFeatures: TArray<string>;
    LIndex: Integer;
    LExpectedProof: TBytes;
    LServerProofText: string;
    LServerProof: TBytes;
    LOldTimeout: Integer;
begin
    if FSecret = '' then
        raise EGARPProtocolError.Create('GARP secret is empty');

    CloseConnection;
    FSessionID := '';
    FTabID := '';
    FRequestID := '';
    FAuthenticated := False;
    FCapabilities.Free;
    FCapabilities := nil;
    FBrowserStatus.Free;
    FBrowserStatus := nil;

    FClient.Connect;
    LOldTimeout := FClient.IOHandler.ReadTimeout;
    try
        FClient.IOHandler.ReadTimeout := GARP_HANDSHAKE_TIMEOUT;
        FClientNonce := GARPCreateNonce;

        LHelloPayload := TJSONObject.Create;
        try
            LHelloPayload.AddPair('client_name', FClientName);
            LHelloPayload.AddPair('client_version', FClientVersion);
            LOfferedFeaturesJSON := TJSONArray.Create;
            for LIndex := 0 to High(FOfferedFeatures) do
                LOfferedFeaturesJSON.Add(FOfferedFeatures[LIndex]);
            LHelloPayload.AddPair('versions', TJSONArray.Create.Add(GARP_SEMANTIC_VERSION));
            LHelloPayload.AddPair('wire_versions', TJSONArray.Create.Add(GARP_WIRE_VERSION));
            LHelloPayload.AddPair('features', LOfferedFeaturesJSON);
            LHelloPayload.AddPair('client_nonce', GARPBase64UrlEncode(FClientNonce));
            LMessage := BuildMessage('HELLO', LHelloPayload, GARPNewUUID);
            LHelloPayload := nil;
            try
                FRequestID := LMessage.GetValue<string>('request_id');
                SendFrame(GARP_HELLO, LMessage, FRequestID);
            finally
                LMessage.Free;
            end;
        finally
            LHelloPayload.Free;
        end;

        if not ReceiveUntilRequest(FRequestID, [GARP_HELLO_CHALLENGE, GARP_ERROR], LFrame, GARP_HANDSHAKE_TIMEOUT, GARP_HANDSHAKE_MAX_PAYLOAD) then
            raise EGARPProtocolError.Create('Timed out waiting for HELLO_CHALLENGE');
        try
            if LFrame.MessageType = GARP_ERROR then
                raise EGARPProtocolError.Create('HELLO rejected: ' + GetErrorText(LFrame));
            LChallenge := GARPJSONObjectPayload(LFrame);
            FServerName := LChallenge.GetValue<string>('server_name', '');
            FServerVersion := LChallenge.GetValue<string>('server_version', '');
            LSelectedVersion := LChallenge.GetValue<string>('selected_version', '');
            LSelectedWire := LChallenge.GetValue<string>('selected_wire_version', '');
            if LSelectedVersion <> GARP_SEMANTIC_VERSION then
                raise EGARPProtocolError.Create('Server selected an unsupported semantic version');
            if LSelectedWire <> GARP_WIRE_VERSION then
                raise EGARPProtocolError.Create('Server selected an unsupported wire version');
            LServerNonceText := LChallenge.GetValue<string>('server_nonce', '');
            FServerNonce := GARPRequireNonce16(LServerNonceText);

            LFinalFeaturesJSON := LChallenge.GetValue<TJSONArray>('features');
            if LFinalFeaturesJSON = nil then
                raise EGARPProtocolError.Create('HELLO_CHALLENGE has no features');
            SetLength(LFinalFeatures, LFinalFeaturesJSON.Count);
            for LIndex := 0 to LFinalFeaturesJSON.Count - 1 do
                LFinalFeatures[LIndex] := LFinalFeaturesJSON.Items[LIndex].Value;
            FNegotiatedFeatures := GARPCanonicalFeatureList(LFinalFeatures);
        finally
            LFrame.MessageJSON.Free;
            LFrame.MessageJSON := nil;
        end;

        LExpectedProof := GARPMakeProof(
            FSecret,
            GARP_DOMAIN_CLIENT_PROOF,
            FClientNonce,
            FServerNonce,
            FOfferedFeatures,
            FNegotiatedFeatures,
            FClientName,
            FClientVersion,
            FServerName,
            FServerVersion
        );

        LAuthPayload := TJSONObject.Create;
        try
            LAuthPayload.AddPair('client_proof', GARPBase64UrlEncode(LExpectedProof));
            LMessage := BuildMessage('HELLO_AUTH', LAuthPayload, FRequestID);
            LAuthPayload := nil;
            try
                SendFrame(GARP_HELLO_AUTH, LMessage, FRequestID);
            finally
                LMessage.Free;
            end;
        finally
            LAuthPayload.Free;
        end;

        if not ReceiveUntilRequest(FRequestID, [GARP_HELLO_ACK, GARP_ERROR], LFrame, GARP_HANDSHAKE_TIMEOUT, GARP_HANDSHAKE_MAX_PAYLOAD) then
            raise EGARPProtocolError.Create('Timed out waiting for HELLO_ACK');
        try
            if LFrame.MessageType = GARP_ERROR then
                raise EGARPProtocolError.Create('Authentication failed: ' + GetErrorText(LFrame));
            LAck := GARPJSONObjectPayload(LFrame);
            LServerProofText := LAck.GetValue<string>('server_proof', '');
            LServerProof := GARPBase64UrlDecode(LServerProofText);
            if Length(LServerProof) <> 32 then
                raise EGARPProtocolError.Create('HELLO_ACK server_proof must decode to 32 bytes');
            LExpectedProof := GARPMakeProof(
                FSecret,
                GARP_DOMAIN_SERVER_PROOF,
                FClientNonce,
                FServerNonce,
                FOfferedFeatures,
                FNegotiatedFeatures,
                FClientName,
                FClientVersion,
                FServerName,
                FServerVersion
            );
            if not ConstantTimeEqual(LExpectedProof, LServerProof) then
                raise EGARPProtocolError.Create('HELLO_ACK server proof verification failed');
            FServerProof := LServerProof;
            FAuthenticated := True;
        finally
            LFrame.MessageJSON.Free;
            LFrame.MessageJSON := nil;
        end;

        { The server emits CAPABILITIES and BROWSER_STATUS immediately after HELLO_ACK. }
        for LIndex := 1 to 2 do
        begin
            if not ReceiveUntilRequest('', [GARP_CAPABILITIES, GARP_BROWSER_STATUS, GARP_ERROR], LFrame, GARP_HANDSHAKE_TIMEOUT, GARP_HANDSHAKE_MAX_PAYLOAD) then
                raise EGARPProtocolError.Create('Timed out waiting for post-authentication state');
            try
                if LFrame.MessageType = GARP_ERROR then
                    raise EGARPProtocolError.Create('Post-authentication ERROR: ' + GetErrorText(LFrame));
                if LFrame.MessageType = GARP_CAPABILITIES then
                    StoreCapabilities(LFrame)
                else if LFrame.MessageType = GARP_BROWSER_STATUS then
                    StoreBrowserStatus(LFrame)
                else
                    Continue;
            finally
                LFrame.MessageJSON.Free;
                LFrame.MessageJSON := nil;
            end;
        end;
    finally
        FClient.IOHandler.ReadTimeout := LOldTimeout;
    end;
end;

function TGARPClient124.GetCapabilities: TJSONObject;
var
    LRequestID: string;
    LMessage: TJSONObject;
    LFrame: TGARPFrame;
begin
    EnsureConnected;
    LRequestID := NextRequestID;
    LMessage := BuildMessage('GET_CAPABILITIES', nil, LRequestID);
    try
        SendFrame(GARP_GET_CAPABILITIES, LMessage, LRequestID);
    finally
        LMessage.Free;
    end;
    if not ReceiveUntilRequest(LRequestID, [GARP_RESPONSE, GARP_ERROR], LFrame, 30000) then
        raise EGARPProtocolError.Create('Timed out waiting for GET_CAPABILITIES response');
    try
        if LFrame.MessageType = GARP_ERROR then
            raise EGARPProtocolError.Create(GetErrorText(LFrame));
        Result := LFrame.MessageJSON.Clone as TJSONObject;
    finally
        LFrame.MessageJSON.Free;
        LFrame.MessageJSON := nil;
    end;
end;

function TGARPClient124.GetBrowserStatus: TJSONObject;
begin
    EnsureConnected;
    if FBrowserStatus = nil then
        raise EGARPProtocolError.Create('No BROWSER_STATUS has been received yet');
    Result := FBrowserStatus.Clone as TJSONObject;
end;

function TGARPClient124.ListTabs: TJSONObject;
var
    LRequestID: string;
    LMessage: TJSONObject;
    LFrame: TGARPFrame;
begin
    EnsureConnected;
    LRequestID := NextRequestID;
    LMessage := BuildMessage('LIST_TABS', nil, LRequestID);
    try
        SendFrame(GARP_LIST_TABS, LMessage, LRequestID);
    finally
        LMessage.Free;
    end;
    if not ReceiveUntilRequest(LRequestID, [GARP_RESPONSE, GARP_ERROR], LFrame, 30000) then
        raise EGARPProtocolError.Create('Timed out waiting for LIST_TABS response');
    try
        if LFrame.MessageType = GARP_ERROR then
            raise EGARPProtocolError.Create(GetErrorText(LFrame));
        Result := LFrame.MessageJSON.Clone as TJSONObject;
    finally
        LFrame.MessageJSON.Free;
        LFrame.MessageJSON := nil;
    end;
end;

function TGARPClient124.OpenTab(const AURL: string): TJSONObject;
var
    LPayload: TJSONObject;
    LMessage: TJSONObject;
    LFrame: TGARPFrame;
    LRequestID: string;
begin
    EnsureConnected;
    LRequestID := NextRequestID;
    LPayload := TJSONObject.Create;
    try
        LPayload.AddPair('url', AURL);
        LMessage := BuildMessage('OPEN_TAB', LPayload, LRequestID);
        LPayload := nil;
        try
            SendFrame(GARP_OPEN_TAB, LMessage, LRequestID);
        finally
            LMessage.Free;
        end;
    finally
        LPayload.Free;
    end;
    if not ReceiveUntilRequest(LRequestID, [GARP_RESPONSE, GARP_ERROR], LFrame, 30000) then
        raise EGARPProtocolError.Create('Timed out waiting for OPEN_TAB response');
    try
        if LFrame.MessageType = GARP_ERROR then
            raise EGARPProtocolError.Create(GetErrorText(LFrame));
        Result := LFrame.MessageJSON.Clone as TJSONObject;
    finally
        LFrame.MessageJSON.Free;
    end;
end;

function TGARPClient124.CloseTab(const ATabID: string): TJSONObject;
var
    LPayload, LMessage: TJSONObject;
    LFrame: TGARPFrame;
    LRequestID: string;
begin
    EnsureConnected;
    LRequestID := NextRequestID;
    LPayload := TJSONObject.Create;
    try
        LPayload.AddPair('tab_id', ATabID);
        LMessage := BuildMessage('CLOSE_TAB', LPayload, LRequestID);
        LPayload := nil;
        try
            SendFrame(GARP_CLOSE_TAB, LMessage, LRequestID);
        finally
            LMessage.Free;
        end;
    finally
        LPayload.Free;
    end;
    if not ReceiveUntilRequest(LRequestID, [GARP_RESPONSE, GARP_ERROR], LFrame, 30000) then
        raise EGARPProtocolError.Create('Timed out waiting for CLOSE_TAB response');
    try
        if LFrame.MessageType = GARP_ERROR then raise EGARPProtocolError.Create(GetErrorText(LFrame));
        Result := LFrame.MessageJSON.Clone as TJSONObject;
    finally
        LFrame.MessageJSON.Free;
    end;
end;

function TGARPClient124.SelectTab(const ATabID: string): TJSONObject;
var
    LPayload, LMessage: TJSONObject;
    LFrame: TGARPFrame;
    LRequestID: string;
begin
    EnsureConnected;
    LRequestID := NextRequestID;
    LPayload := TJSONObject.Create;
    try
        LPayload.AddPair('tab_id', ATabID);
        LMessage := BuildMessage('SELECT_TAB', LPayload, LRequestID);
        LPayload := nil;
        try
            SendFrame(GARP_SELECT_TAB, LMessage, LRequestID);
        finally
            LMessage.Free;
        end;
    finally
        LPayload.Free;
    end;
    if not ReceiveUntilRequest(LRequestID, [GARP_RESPONSE, GARP_ERROR], LFrame, 30000) then
        raise EGARPProtocolError.Create('Timed out waiting for SELECT_TAB response');
    try
        if LFrame.MessageType = GARP_ERROR then raise EGARPProtocolError.Create(GetErrorText(LFrame));
        Result := LFrame.MessageJSON.Clone as TJSONObject;
    finally
        LFrame.MessageJSON.Free;
    end;
end;

function TGARPClient124.CreateSession(const AProvider: string; const ATabID: string): TJSONObject;
var
    LPayload, LOptions, LMessage: TJSONObject;
    LFrame: TGARPFrame;
    LRequestID: string;
    LReturnedSessionID: string;
    LReturnedTabID: string;
    LState: string;
    LReady: TJSONObject;
begin
    EnsureConnected;
    if Trim(AProvider) = '' then
        raise EGARPProtocolError.Create('Provider is empty');

    LRequestID := NextRequestID;
    LPayload := TJSONObject.Create;
    try
        LPayload.AddPair('provider', AProvider);
        LOptions := TJSONObject.Create;
        LPayload.AddPair('options', LOptions);
        if ATabID <> '' then
            LPayload.AddPair('tab_id', ATabID);

        LMessage := BuildMessage('CREATE_SESSION', LPayload, LRequestID);
        LPayload := nil;
        try
            SendFrame(GARP_CREATE_SESSION, LMessage, LRequestID);
        finally
            LMessage.Free;
        end;
    finally
        LPayload.Free;
    end;

    if not ReceiveUntilRequest(LRequestID, [GARP_RESPONSE, GARP_ERROR], LFrame, 30000) then
        raise EGARPProtocolError.Create('Timed out waiting for CREATE_SESSION response');
    try
        if LFrame.MessageType = GARP_ERROR then
            raise EGARPProtocolError.Create(GetErrorText(LFrame));
        Result := LFrame.MessageJSON.Clone as TJSONObject;
        LReturnedSessionID := GARPJSONObjectPayload(LFrame).GetValue<string>('session_id', '');
        if LReturnedSessionID = '' then
            raise EGARPProtocolError.Create('CREATE_SESSION response did not contain session_id');
        FSessionID := LReturnedSessionID;
        LReturnedTabID := GARPJSONObjectPayload(LFrame).GetValue<string>('tab_id', '');
        if LReturnedTabID <> '' then
            FTabID := LReturnedTabID;
        LState := GARPJSONObjectPayload(LFrame).GetValue<string>('state', '');
    finally
        LFrame.MessageJSON.Free;
    end;

    if SameText(LState, 'PREPARING') or
       SameText(LState, 'AUTH_REQUIRED') or
       SameText(LState, 'RATE_LIMITED') then
    begin
        LReady := WaitForSessionReady(FSessionID, 30000);
        LReady.Free;
    end;
end;

function TGARPClient124.WaitForSessionReady(const ASessionID: string; const ATimeoutMS: Cardinal): TJSONObject;
var
    LStart: UInt64;
    LNow: UInt64;
    LRemaining: Cardinal;
    LFrame: TGARPFrame;
    LState: string;
begin
    LStart := TThread.GetTickCount64;
    while True do
    begin
        LNow := TThread.GetTickCount64;
        if LNow - LStart >= ATimeoutMS then
            raise EGARPProtocolError.Create('Timed out waiting for SESSION_READY');
        LRemaining := ATimeoutMS - Cardinal(LNow - LStart);

        ReceiveFrame(LFrame, LRemaining);
        try
            if LFrame.MessageType in [GARP_CAPABILITIES, GARP_BROWSER_STATUS, GARP_PING] then
            begin
                HandleUnsolicitedFrame(LFrame);
                Continue;
            end;

            if LFrame.MessageType = GARP_ERROR then
                raise EGARPProtocolError.Create('CREATE_SESSION failed: ' + GetErrorText(LFrame));

            if LFrame.MessageType = GARP_SESSION_READY then
            begin
                if SameText(LFrame.SessionID, ASessionID) then
                begin
                    Result := LFrame.MessageJSON.Clone as TJSONObject;
                    Exit;
                end;
                Continue;
            end;

            if LFrame.MessageType = GARP_PROVIDER_AUTH_REQUIRED then
            begin
                LState := 'AUTH_REQUIRED';
                if SameText(LFrame.SessionID, ASessionID) then
                    raise EGARPProtocolError.Create('Provider authentication required');
            end;

            if LFrame.MessageType = GARP_PROVIDER_RATE_LIMITED then
            begin
                LState := 'RATE_LIMITED';
                if SameText(LFrame.SessionID, ASessionID) then
                    raise EGARPProtocolError.Create('Provider rate limited');
            end;
        finally
            LFrame.MessageJSON.Free;
            LFrame.MessageJSON := nil;
        end;
    end;
end;

function TGARPClient124.GetSession: TJSONObject;
var
    LRequestID: string;
    LMessage: TJSONObject;
    LFrame: TGARPFrame;
begin
    EnsureConnected;
    if FSessionID = '' then raise EGARPProtocolError.Create('No active session');
    LRequestID := NextRequestID;
    LMessage := BuildMessage('GET_SESSION', TJSONObject.Create, LRequestID, FSessionID);
    try
        SendFrame(GARP_GET_SESSION, LMessage, LRequestID, FSessionID);
    finally
        LMessage.Free;
    end;
    if not ReceiveUntilRequest(LRequestID, [GARP_RESPONSE, GARP_ERROR], LFrame, 30000) then
        raise EGARPProtocolError.Create('Timed out waiting for GET_SESSION response');
    try
        if LFrame.MessageType = GARP_ERROR then raise EGARPProtocolError.Create(GetErrorText(LFrame));
        Result := LFrame.MessageJSON.Clone as TJSONObject;
    finally
        LFrame.MessageJSON.Free;
    end;
end;

function TGARPClient124.Prompt(const APrompt: string; const ATimeoutMS: Integer; const AAutoContinue, AForceFocus, ASimulateEnter: Boolean): TJSONObject;
var
    LPayload, LOptions, LMessage: TJSONObject;
    LFrame: TGARPFrame;
    LRequestID: string;
begin
    EnsureConnected;
    if FSessionID = '' then raise EGARPProtocolError.Create('No active session');
    if APrompt = '' then raise EGARPProtocolError.Create('Prompt text is empty');
    if ATimeoutMS <= 0 then raise EGARPProtocolError.Create('Prompt timeout must be positive');

    LRequestID := NextRequestID;
    LPayload := TJSONObject.Create;
    try
        LPayload.AddPair('prompt', APrompt);
        LOptions := TJSONObject.Create;
        LOptions.AddPair('timeout_ms', UIntToStr(ATimeoutMS));
        LOptions.AddPair('auto_continue', TJSONBool.Create(AAutoContinue));
        LOptions.AddPair('max_continuations', TJSONNumber.Create(8));
        LOptions.AddPair('force_focus', TJSONBool.Create(AForceFocus));
        LOptions.AddPair('simulate_enter', TJSONBool.Create(ASimulateEnter));
        LPayload.AddPair('options', LOptions);

        LMessage := BuildMessage('PROMPT', LPayload, LRequestID, FSessionID);
        LPayload := nil;
        try
            SendFrame(GARP_PROMPT, LMessage, LRequestID, FSessionID);
        finally
            LMessage.Free;
        end;
    finally
        LPayload.Free;
    end;

    if not ReceiveUntilRequest(LRequestID, [GARP_RESPONSE, GARP_ERROR], LFrame, 30000) then
        raise EGARPProtocolError.Create('Timed out waiting for PROMPT acceptance');
    try
        if LFrame.MessageType = GARP_ERROR then
            raise EGARPProtocolError.Create(GetErrorText(LFrame));
        Result := LFrame.MessageJSON.Clone as TJSONObject;
        FRequestID := LRequestID;
    finally
        LFrame.MessageJSON.Free;
    end;
end;

function TGARPClient124.WaitForCompletion(const ARequestID: string; const ATimeoutMS: Cardinal): TJSONObject;
var
    LFrame: TGARPFrame;
    LStatus: TJSONObject;
    LErrorPayload: TJSONObject;
begin
    EnsureConnected;
    if ARequestID = '' then
        raise EGARPProtocolError.Create('Request ID is empty');

    if ReceiveUntilPromptEvent(ARequestID, LFrame, ATimeoutMS) then
    begin
        try
            Result := LFrame.MessageJSON.Clone as TJSONObject;
        finally
            LFrame.MessageJSON.Free;
        end;
        Exit;
    end;

    LStatus := nil;
    try
        try
            LStatus := GetPromptStatus(ARequestID);
        except
            on E: Exception do
                DebugLog('GET_PROMPT_STATUS after timeout failed: ' + E.Message);
        end;

        LErrorPayload := TJSONObject.Create;
        try
            LErrorPayload.AddPair('code', 'GENERATION_TIMEOUT');
            LErrorPayload.AddPair('message', 'Timed out waiting for a terminal prompt event');
            LErrorPayload.AddPair('prompt_request_id', ARequestID);
            if LStatus <> nil then
                LErrorPayload.AddPair('status', LStatus.Clone as TJSONObject);
            Result := GARPBuildJSON('ERROR', LErrorPayload);
            LErrorPayload := nil;
        finally
            LErrorPayload.Free;
        end;
    finally
        LStatus.Free;
    end;
end;

function TGARPClient124.GetPromptStatus(const ARequestID: string): TJSONObject;
var
    LPayload, LMessage: TJSONObject;
    LFrame: TGARPFrame;
    LCommandID: string;
begin
    EnsureConnected;
    if FSessionID = '' then raise EGARPProtocolError.Create('No active session');
    LCommandID := NextRequestID;
    LPayload := TJSONObject.Create;
    try
        LPayload.AddPair('prompt_request_id', ARequestID);
        LMessage := BuildMessage('GET_PROMPT_STATUS', LPayload, LCommandID, FSessionID);
        LPayload := nil;
        try
            SendFrame(GARP_GET_PROMPT_STATUS, LMessage, LCommandID, FSessionID);
        finally
            LMessage.Free;
        end;
    finally
        LPayload.Free;
    end;
    if not ReceiveUntilRequest(LCommandID, [GARP_RESPONSE, GARP_ERROR], LFrame, 30000) then raise EGARPProtocolError.Create('Timed out waiting for GET_PROMPT_STATUS');
    try
        if LFrame.MessageType = GARP_ERROR then raise EGARPProtocolError.Create(GetErrorText(LFrame));
        Result := LFrame.MessageJSON.Clone as TJSONObject;
    finally
        LFrame.MessageJSON.Free;
    end;
end;

function TGARPClient124.GetResponse(const ARequestID: string): TJSONObject;
var
    LPayload, LMessage: TJSONObject;
    LFrame: TGARPFrame;
    LCommandID: string;
begin
    EnsureConnected;
    LCommandID := NextRequestID;
    LPayload := TJSONObject.Create;
    try
        LPayload.AddPair('prompt_request_id', ARequestID);
        LMessage := BuildMessage('GET_RESPONSE', LPayload, LCommandID, FSessionID);
        LPayload := nil;
        try
            SendFrame(GARP_GET_RESPONSE, LMessage, LCommandID, FSessionID);
        finally
            LMessage.Free;
        end;
    finally
        LPayload.Free;
    end;
    if not ReceiveUntilRequest(LCommandID, [GARP_RESPONSE, GARP_ERROR], LFrame, 30000) then raise EGARPProtocolError.Create('Timed out waiting for GET_RESPONSE');
    try
        if LFrame.MessageType = GARP_ERROR then raise EGARPProtocolError.Create(GetErrorText(LFrame));
        Result := LFrame.MessageJSON.Clone as TJSONObject;
    finally
        LFrame.MessageJSON.Free;
    end;
end;

function TGARPClient124.CancelPrompt(const ARequestID: string): TJSONObject;
var
    LPayload, LMessage: TJSONObject;
    LFrame: TGARPFrame;
    LCommandID: string;
begin
    EnsureConnected;
    LCommandID := NextRequestID;
    LPayload := TJSONObject.Create;
    try
        LPayload.AddPair('prompt_request_id', ARequestID);
        LMessage := BuildMessage('CANCEL_PROMPT', LPayload, LCommandID, FSessionID);
        LPayload := nil;
        try
            SendFrame(GARP_CANCEL_PROMPT, LMessage, LCommandID, FSessionID);
        finally
            LMessage.Free;
        end;
    finally
        LPayload.Free;
    end;
    if not ReceiveUntilRequest(LCommandID, [GARP_RESPONSE, GARP_ERROR], LFrame, 30000) then raise EGARPProtocolError.Create('Timed out waiting for CANCEL_PROMPT');
    try
        if LFrame.MessageType = GARP_ERROR then raise EGARPProtocolError.Create(GetErrorText(LFrame));
        Result := LFrame.MessageJSON.Clone as TJSONObject;
    finally
        LFrame.MessageJSON.Free;
    end;
end;

function TGARPClient124.ContinuePrompt(const ARequestID: string): TJSONObject;
var
    LPayload, LMessage: TJSONObject;
    LFrame: TGARPFrame;
    LCommandID: string;
begin
    EnsureConnected;
    LCommandID := NextRequestID;
    LPayload := TJSONObject.Create;
    try
        LPayload.AddPair('prompt_request_id', ARequestID);
        LMessage := BuildMessage('CONTINUE_PROMPT', LPayload, LCommandID, FSessionID);
        LPayload := nil;
        try
            SendFrame(GARP_CONTINUE_PROMPT, LMessage, LCommandID, FSessionID);
        finally
            LMessage.Free;
        end;
    finally
        LPayload.Free;
    end;
    if not ReceiveUntilRequest(LCommandID, [GARP_RESPONSE, GARP_ERROR], LFrame, 30000) then raise EGARPProtocolError.Create('Timed out waiting for CONTINUE_PROMPT');
    try
        if LFrame.MessageType = GARP_ERROR then raise EGARPProtocolError.Create(GetErrorText(LFrame));
        Result := LFrame.MessageJSON.Clone as TJSONObject;
    finally
        LFrame.MessageJSON.Free;
    end;
end;

function TGARPClient124.GetEvents(const AFromSequence: UInt64; const AMaxEvents: Cardinal): TJSONObject;
var
    LPayload, LMessage: TJSONObject;
    LFrame: TGARPFrame;
    LCommandID: string;
begin
    EnsureConnected;
    if not HasNegotiatedFeature(GARP_FEATURE_EXT_REPLAY_STORE) then
        raise EGARPProtocolError.Create('ext-replay-store was not negotiated');
    LCommandID := NextRequestID;
    LPayload := TJSONObject.Create;
    try
        LPayload.AddPair('from_sequence', AFromSequence.ToString);
        LPayload.AddPair('max_events', TJSONNumber.Create(AMaxEvents));
        LMessage := BuildMessage('GET_EVENTS', LPayload, LCommandID, FSessionID);
        LPayload := nil;
        try
            SendFrame(GARP_GET_EVENTS, LMessage, LCommandID, FSessionID);
        finally
            LMessage.Free;
        end;
    finally
        LPayload.Free;
    end;
    if not ReceiveUntilRequest(LCommandID, [GARP_RESPONSE, GARP_ERROR], LFrame, 30000) then raise EGARPProtocolError.Create('Timed out waiting for GET_EVENTS');
    try
        if LFrame.MessageType = GARP_ERROR then raise EGARPProtocolError.Create(GetErrorText(LFrame));
        Result := LFrame.MessageJSON.Clone as TJSONObject;
    finally
        LFrame.MessageJSON.Free;
    end;
end;

function TGARPClient124.SubscribeResponse(const ARequestID: string): TJSONObject;
var
    LPayload, LMessage: TJSONObject;
    LFrame: TGARPFrame;
    LCommandID: string;
begin
    EnsureConnected;
    LCommandID := NextRequestID;
    LPayload := TJSONObject.Create;
    try
        LPayload.AddPair('prompt_request_id', ARequestID);
        LMessage := BuildMessage('SUBSCRIBE_RESPONSE', LPayload, LCommandID, FSessionID);
        LPayload := nil;
        try
            SendFrame(GARP_SUBSCRIBE_RESPONSE, LMessage, LCommandID, FSessionID);
        finally
            LMessage.Free;
        end;
    finally
        LPayload.Free;
    end;
    if not ReceiveUntilRequest(LCommandID, [GARP_RESPONSE, GARP_ERROR], LFrame, 30000) then raise EGARPProtocolError.Create('Timed out waiting for SUBSCRIBE_RESPONSE');
    try
        if LFrame.MessageType = GARP_ERROR then raise EGARPProtocolError.Create(GetErrorText(LFrame));
        Result := LFrame.MessageJSON.Clone as TJSONObject;
    finally
        LFrame.MessageJSON.Free;
    end;
end;

procedure TGARPClient124.Ping;
var
    LMessage: TJSONObject;
    LFrame: TGARPFrame;
    LRequestID: string;
begin
    EnsureConnected;
    LRequestID := NextRequestID;
    LMessage := BuildMessage('PING', nil, LRequestID);
    try
        SendFrame(GARP_PING, LMessage, LRequestID);
    finally
        LMessage.Free;
    end;
    if not ReceiveUntilRequest(LRequestID, [GARP_RESPONSE, GARP_PONG, GARP_ERROR], LFrame, 30000) then
        raise EGARPProtocolError.Create('Timed out waiting for PING response');
    try
        if LFrame.MessageType = GARP_ERROR then raise EGARPProtocolError.Create(GetErrorText(LFrame));
    finally
        LFrame.MessageJSON.Free;
    end;
end;

procedure TGARPClient124.CloseSession;
var
    LMessage: TJSONObject;
    LFrame: TGARPFrame;
    LRequestID: string;
begin
    if FSessionID = '' then Exit;
    EnsureConnected;
    LRequestID := NextRequestID;
    LMessage := BuildMessage('CLOSE_SESSION', nil, LRequestID, FSessionID);
    try
        SendFrame(GARP_CLOSE_SESSION, LMessage, LRequestID, FSessionID);
    finally
        LMessage.Free;
    end;
    if not ReceiveUntilRequest(LRequestID, [GARP_RESPONSE, GARP_ERROR], LFrame, 30000) then
        raise EGARPProtocolError.Create('Timed out waiting for CLOSE_SESSION');
    try
        if LFrame.MessageType = GARP_ERROR then raise EGARPProtocolError.Create(GetErrorText(LFrame));
    finally
        LFrame.MessageJSON.Free;
    end;
    FSessionID := '';
    FTabID := '';
end;

end.
