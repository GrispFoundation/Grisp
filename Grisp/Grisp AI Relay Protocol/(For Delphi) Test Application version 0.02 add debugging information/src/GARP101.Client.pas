unit GARP101.Client;

interface

uses
    System.SysUtils,
    System.Classes,
    System.JSON,
    IdTCPClient,
    IdGlobal,
    IdException,
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
        FDebug: Boolean;

        procedure DebugLog(const AMessage: string);
        procedure DebugFrame(
            const APrefix: string;
            const AFrame: TBytes;
            const ADecodedFrame: TGARPFrame
        );
        procedure EnsureConnected;
        function NextRequestID: string;

        procedure SendFrame(
            const AMessageType: TGARPMessageType;
            const AMessage: TJSONObject;
            const ARequestID: string = '';
            const ASessionID: string = ''
        );

        function ReceiveFrame(
            out AFrame: TGARPFrame
        ): Boolean;

        function ReceiveUntil(
            const ARequestID: string;
            const AAcceptedTypes: array of TGARPMessageType;
            out AFrame: TGARPFrame
        ): Boolean;

        function BuildMessage(
            const ATypeName: string;
            const APayload: TJSONValue
        ): TJSONObject;

        procedure CloseConnection;
    public
        constructor Create(
            const AHost: string;
            const APort: Integer;
            const ASecret: string
        );

        destructor Destroy; override;

        procedure ConnectAndAuthenticate;

        function GetCapabilities: TJSONObject;
        function GetBrowserStatus: TJSONObject;
        function ListTabs: TJSONObject;

        function CreateSession(
            const AProvider: string;
            const ATabID: string = ''
        ): TJSONObject;

        function Prompt(
            const APrompt: string;
            const AStream: Boolean = True;
            const ATimeoutMS: Integer = 180000;
            const AAutoContinue: Boolean = True
        ): TJSONObject;

        function WaitForCompletion(
            const ARequestID: string;
            const ATimeoutMS: Cardinal = 180000
        ): TJSONObject;

        function CancelPrompt(
            const ARequestID: string;
            const AReason: string
        ): TJSONObject;

        procedure Ping;
        procedure CloseSession;

        property SessionID: string read FSessionID;
        property TabID: string read FTabID;
        property RequestID: string read FRequestID;
        property Authenticated: Boolean read FAuthenticated;
        property Debug: Boolean read FDebug write FDebug;
    end;

implementation

constructor TGARPClient101.Create(
    const AHost: string;
    const APort: Integer;
    const ASecret: string
);
begin
    inherited Create;

    FClient :=
        TIdTCPClient.Create(nil);

    FClient.Host := AHost;
    FClient.Port := APort;
    FClient.ConnectTimeout := 5000;
    FClient.ReadTimeout := GARP_READ_TIMEOUT;

    FClientID :=
        'GARP101-Delphi-Test-' +
        GARPNewUUID;

    FClientVersion := '1.0.0';
    FSecret := ASecret;

    FClientNonce := '';
    FAuthenticated := False;
    FSessionID := '';
    FTabID := '';
    FRequestID := '';
    FDebug := False;

    DebugLog(
        Format(
            'constructed host=%s port=%d client_id=%s client_version=%s',
            [
                AHost,
                APort,
                FClientID,
                FClientVersion
            ]
        )
    );
end;

destructor TGARPClient101.Destroy;
begin
    DebugLog('destroying client');

    CloseConnection;

    FClient.Free;

    inherited Destroy;
end;

procedure TGARPClient101.DebugLog(
    const AMessage: string
);
begin
    if not FDebug then
        Exit;

    Writeln(
        '[DEBUG ',
        FormatDateTime(
            'hh:nn:ss.zzz',
            Now
        ),
        '] ',
        AMessage
    );
end;

procedure TGARPClient101.DebugFrame(
    const APrefix: string;
    const AFrame: TBytes;
    const ADecodedFrame: TGARPFrame
);
begin
    if not FDebug then
        Exit;

    DebugLog(
        Format(
            '%s frame_bytes=%d type=%s message_type=0x%.4x request_id=%s session_id=%s',
            [
                APrefix,
                Length(AFrame),
                GARPMessageTypeToName(
                    ADecodedFrame.MessageType
                ),
                ADecodedFrame.MessageType,
                ADecodedFrame.RequestID,
                ADecodedFrame.SessionID
            ]
        )
    );

    if ADecodedFrame.MessageJSON <> nil then
    begin
        DebugLog(
            APrefix +
            ' JSON=' +
            ADecodedFrame.MessageJSON.ToJSON
        );
    end;
end;

procedure TGARPClient101.CloseConnection;
begin
    DebugLog('CloseConnection');

    FAuthenticated := False;

    if FClient <> nil then
    begin
        if FClient.Connected then
        begin
            try
                FClient.Disconnect;
            except
                { Ignore disconnect errors during destruction. }
            end;
        end;
    end;
end;

procedure TGARPClient101.EnsureConnected;
begin
    if not FClient.Connected then
    begin
        raise Exception.Create(
            'GARP client is not connected'
        );
    end;

    if not FAuthenticated then
    begin
        raise Exception.Create(
            'GARP client is not authenticated'
        );
    end;
end;

function TGARPClient101.NextRequestID: string;
begin
    Result := GARPNewUUID;
    FRequestID := Result;

    DebugLog(
        'allocated request_id=' +
        FRequestID
    );
end;

function TGARPClient101.BuildMessage(
    const ATypeName: string;
    const APayload: TJSONValue
): TJSONObject;
begin
    Result :=
        GARPBuildJSON(
            ATypeName,
            APayload
        );

    DebugLog(
        'BuildMessage type=' +
        ATypeName +
        ' JSON=' +
        Result.ToJSON
    );
end;

procedure TGARPClient101.SendFrame(
    const AMessageType: TGARPMessageType;
    const AMessage: TJSONObject;
    const ARequestID: string;
    const ASessionID: string
);
var
    LFrame: TBytes;
    LPayloadBytes: TBytes;
    LPayloadText: string;
begin
    if AMessage = nil then
    begin
        raise Exception.Create(
            'Cannot send a nil GARP message'
        );
    end;

    if FDebug then
    begin
        DebugLog(
            Format(
                'SEND preparing type=%s (0x%.4x) request_id=%s session_id=%s',
                [
                    GARPMessageTypeToName(
                        AMessageType
                    ),
                    AMessageType,
                    ARequestID,
                    ASessionID
                ]
            )
        );

        DebugLog(
            'SEND JSON=' +
            AMessage.ToJSON
        );

        LPayloadText :=
            AMessage.ToJSON;

        LPayloadBytes :=
            TEncoding.UTF8.GetBytes(
                LPayloadText
            );

        DebugLog(
            Format(
                'SEND UTF8 payload bytes=%d',
                [Length(LPayloadBytes)]
            )
        );
    end;

    LFrame :=
        GARPEncodeFrame(
            AMessageType,
            AMessage,
            ARequestID,
            ASessionID
        );

    DebugLog(
        Format(
            'SEND encoded frame bytes=%d',
            [Length(LFrame)]
        )
    );

    GARPWriteFrame(
        FClient,
        LFrame
    );

    DebugLog(
        'SEND completed type=' +
        GARPMessageTypeToName(
            AMessageType
        )
    );
end;

function TGARPClient101.ReceiveFrame(
    out AFrame: TGARPFrame
): Boolean;
var
    LBytes: TBytes;
begin
    FillChar(
        AFrame,
        SizeOf(AFrame),
        0
    );

    DebugLog('RECEIVE waiting for frame');

    LBytes :=
        GARPReadFrame(
            FClient
        );

    DebugLog(
        Format(
            'RECEIVE raw frame bytes=%d',
            [Length(LBytes)]
        )
    );

    AFrame :=
        GARPDecodeFrame(
            LBytes
        );

    DebugFrame(
        'RECEIVE',
        LBytes,
        AFrame
    );

    Result := True;
end;

function TGARPClient101.ReceiveUntil(
    const ARequestID: string;
    const AAcceptedTypes: array of TGARPMessageType;
    out AFrame: TGARPFrame
): Boolean;
var
    LTypeMatches: Boolean;
    LIndex: Integer;
    LAcceptedType: TGARPMessageType;
    LPong: TJSONObject;
begin
    FillChar(
        AFrame,
        SizeOf(AFrame),
        0
    );

    DebugLog(
        'ReceiveUntil request_id=' +
        ARequestID
    );

    repeat
        ReceiveFrame(AFrame);

        if AFrame.MessageType = GARP_PING then
        begin
            DebugLog(
                'ReceiveUntil received asynchronous PING; sending PONG'
            );

            LPong :=
                BuildMessage(
                    'pong',
                    nil
                );

            try
                SendFrame(
                    GARP_PONG,
                    LPong
                );
            finally
                LPong.Free;
            end;

            AFrame.MessageJSON.Free;
            AFrame.MessageJSON := nil;

            Continue;
        end;

        LTypeMatches :=
            Length(AAcceptedTypes) = 0;

        if not LTypeMatches then
        begin
            for LIndex :=
                Low(AAcceptedTypes)
                to High(AAcceptedTypes) do
            begin
                LAcceptedType :=
                    AAcceptedTypes[LIndex];

                if AFrame.MessageType = LAcceptedType then
                begin
                    LTypeMatches := True;
                    Break;
                end;
            end;
        end;

        DebugLog(
            Format(
                'ReceiveUntil candidate type=%s request_id=%s type_match=%s',
                [
                    GARPMessageTypeToName(
                        AFrame.MessageType
                    ),
                    AFrame.RequestID,
                    BoolToStr(
                        LTypeMatches,
                        True
                    )
                ]
            )
        );

        { A different request must never satisfy this request. }
        if (ARequestID <> '') and
           (AFrame.RequestID <> '') and
           (not SameText(
                ARequestID,
                AFrame.RequestID
           )) then
        begin
            Writeln(
                '[async ',
                GARPMessageTypeToName(
                    AFrame.MessageType
                ),
                '] ',
                AFrame.MessageJSON.ToJSON
            );

            DebugLog(
                'ReceiveUntil rejected frame due to request_id mismatch'
            );

            AFrame.MessageJSON.Free;
            AFrame.MessageJSON := nil;

            Continue;
        end;

        { The message belongs to this request but is not expected yet. }
        if not LTypeMatches then
        begin
            Writeln(
                '[ignored ',
                GARPMessageTypeToName(
                    AFrame.MessageType
                ),
                '] ',
                AFrame.MessageJSON.ToJSON
            );

            DebugLog(
                'ReceiveUntil ignored frame because type is not accepted'
            );

            AFrame.MessageJSON.Free;
            AFrame.MessageJSON := nil;

            Continue;
        end;

        DebugLog(
            'ReceiveUntil accepted ' +
            GARPMessageTypeToName(
                AFrame.MessageType
            )
        );

        Exit(True);
    until False;
end;

procedure TGARPClient101.ConnectAndAuthenticate;
var
    LPayload: TJSONObject;
    LHello: TJSONObject;
    LFrame: TGARPFrame;
    LServerNonce: string;
    LProof: string;
    LAuth: TJSONObject;
    LAuthMessage: TJSONObject;
    LReplyPayload: TJSONObject;
    LErrorPayload: TJSONObject;
    LErrorCode: string;
    LErrorMessage: string;
begin
    DebugLog(
        'ConnectAndAuthenticate begin'
    );

    if FClient.Connected then
    begin
        DebugLog(
            Format(
                'already connected authenticated=%s',
                [
                    BoolToStr(
                        FAuthenticated,
                        True
                    )
                ]
            )
        );

        if FAuthenticated then
            Exit;

        CloseConnection;
    end;

    if FSecret = '' then
    begin
        raise Exception.Create(
            'GARP secret is empty. Use --secret or GARP_SECRET.'
        );
    end;

    FSessionID := '';
    FTabID := '';
    FRequestID := '';
    FAuthenticated := False;

    DebugLog(
        Format(
            'connecting to %s:%d',
            [
                FClient.Host,
                FClient.Port
            ]
        )
    );

    FClient.Connect;

    DebugLog('TCP connection established');

    FClient.IOHandler.ReadTimeout :=
        GARP_READ_TIMEOUT;

    FClientNonce :=
        GARPCreateNonce;

    DebugLog(
        'generated client nonce=' +
        FClientNonce
    );

    { HELLO }

    LPayload :=
        TJSONObject.Create;

    try
        LPayload.AddPair(
            'client_id',
            FClientID
        );

        LPayload.AddPair(
            'client_version',
            FClientVersion
        );

        LPayload.AddPair(
            'nonce',
            FClientNonce
        );

        DebugLog(
            'HELLO payload=' +
            LPayload.ToJSON
        );

        LHello :=
            BuildMessage(
                'hello',
                LPayload
            );

        try
            LPayload := nil;

            SendFrame(
                GARP_HELLO,
                LHello
            );
        finally
            LHello.Free;
        end;
    finally
        LPayload.Free;
    end;

    { HELLO_CHALLENGE }

    DebugLog(
        'waiting for HELLO_CHALLENGE'
    );

    ReceiveFrame(LFrame);

    try
        if LFrame.MessageType = GARP_ERROR then
        begin
            LErrorPayload :=
                LFrame.MessageJSON.GetValue<TJSONObject>(
                    'payload'
                );

            LErrorCode := '';

            LErrorMessage :=
                LFrame.MessageJSON.ToJSON;

            if LErrorPayload <> nil then
            begin
                LErrorCode :=
                    LErrorPayload.GetValue<string>(
                        'code',
                        ''
                    );

                LErrorMessage :=
                    LErrorPayload.GetValue<string>(
                        'message',
                        LErrorMessage
                    );
            end;

            raise Exception.Create(
                'GARP HELLO rejected [' +
                LErrorCode +
                ']: ' +
                LErrorMessage
            );
        end;

        if LFrame.MessageType <>
           GARP_HELLO_CHALLENGE then
        begin
            raise Exception.CreateFmt(
                'Expected hello_challenge, received %s: %s',
                [
                    GARPMessageTypeToName(
                        LFrame.MessageType
                    ),
                    LFrame.MessageJSON.ToJSON
                ]
            );
        end;

        LServerNonce :=
            LFrame.MessageJSON.GetValue<string>(
                'payload.server_nonce',
                ''
            );

        DebugLog(
            'received server_nonce=' +
            LServerNonce
        );

        if LServerNonce = '' then
        begin
            raise Exception.Create(
                'hello_challenge does not contain server_nonce'
            );
        end;
    finally
        LFrame.MessageJSON.Free;
        LFrame.MessageJSON := nil;
    end;

    { HELLO_AUTH }

    LProof :=
        GARPMakeHMACProof(
            FSecret,
            FClientID,
            FClientNonce,
            LServerNonce
        );

    DebugLog(
        'generated HMAC proof=' +
        LProof
    );

    LAuth :=
        TJSONObject.Create;

    try
        LAuth.AddPair(
            'client_id',
            FClientID
        );

        LAuth.AddPair(
            'client_nonce',
            FClientNonce
        );

        LAuth.AddPair(
            'server_nonce',
            LServerNonce
        );

        LAuth.AddPair(
            'proof',
            LProof
        );

        DebugLog(
            'HELLO_AUTH payload=' +
            LAuth.ToJSON
        );

        LAuthMessage :=
            BuildMessage(
                'hello_auth',
                LAuth
            );

        try
            LAuth := nil;

            SendFrame(
                GARP_HELLO_AUTH,
                LAuthMessage
            );
        finally
            LAuthMessage.Free;
        end;
    finally
        LAuth.Free;
    end;

    { HELLO_ACK }

    DebugLog(
        'waiting for HELLO_ACK'
    );

    ReceiveFrame(LFrame);

    try
        if LFrame.MessageType = GARP_ERROR then
        begin
            LErrorPayload :=
                LFrame.MessageJSON.GetValue<TJSONObject>(
                    'payload'
                );

            LErrorCode := '';

            LErrorMessage :=
                LFrame.MessageJSON.ToJSON;

            if LErrorPayload <> nil then
            begin
                LErrorCode :=
                    LErrorPayload.GetValue<string>(
                        'code',
                        ''
                    );

                LErrorMessage :=
                    LErrorPayload.GetValue<string>(
                        'message',
                        LErrorMessage
                    );
            end;

            FAuthenticated := False;

            raise Exception.Create(
                'GARP authentication failed [' +
                LErrorCode +
                ']: ' +
                LErrorMessage
            );
        end;

        if LFrame.MessageType <>
           GARP_HELLO_ACK then
        begin
            FAuthenticated := False;

            raise Exception.CreateFmt(
                'Expected hello_ack, received %s: %s',
                [
                    GARPMessageTypeToName(
                        LFrame.MessageType
                    ),
                    LFrame.MessageJSON.ToJSON
                ]
            );
        end;

        LReplyPayload :=
            LFrame.MessageJSON.GetValue<TJSONObject>(
                'payload'
            );

        if LReplyPayload = nil then
        begin
            FAuthenticated := False;

            raise Exception.Create(
                'hello_ack has no payload'
            );
        end;

        FAuthenticated := True;

        DebugLog(
            'authentication successful'
        );
    finally
        LFrame.MessageJSON.Free;
        LFrame.MessageJSON := nil;
    end;

    DebugLog(
        'ConnectAndAuthenticate complete'
    );
end;

function TGARPClient101.GetCapabilities: TJSONObject;
var
    LMessage: TJSONObject;
    LFrame: TGARPFrame;
    LRequestID: string;
begin
    EnsureConnected;

    LRequestID :=
        NextRequestID;

    DebugLog(
        'GetCapabilities request_id=' +
        LRequestID
    );

    LMessage :=
        BuildMessage(
            'capabilities',
            nil
        );

    try
        SendFrame(
            GARP_CAPABILITIES,
            LMessage,
            LRequestID,
            ''
        );
    finally
        LMessage.Free;
    end;

    ReceiveUntil(
        LRequestID,
        [
            GARP_CAPABILITIES,
            GARP_RESPONSE,
            GARP_ERROR
        ],
        LFrame
    );

    Result :=
        LFrame.MessageJSON;

    LFrame.MessageJSON := nil;
end;

function TGARPClient101.GetBrowserStatus: TJSONObject;
var
    LMessage: TJSONObject;
    LFrame: TGARPFrame;
    LRequestID: string;
begin
    EnsureConnected;

    LRequestID :=
        NextRequestID;

    DebugLog(
        'GetBrowserStatus request_id=' +
        LRequestID
    );

    LMessage :=
        BuildMessage(
            'browser_status',
            nil
        );

    try
        SendFrame(
            GARP_BROWSER_STATUS,
            LMessage,
            LRequestID,
            ''
        );
    finally
        LMessage.Free;
    end;

    ReceiveUntil(
        LRequestID,
        [
            GARP_BROWSER_STATUS,
            GARP_RESPONSE,
            GARP_ERROR
        ],
        LFrame
    );

    Result :=
        LFrame.MessageJSON;

    LFrame.MessageJSON := nil;
end;

function TGARPClient101.ListTabs: TJSONObject;
var
    LMessage: TJSONObject;
    LFrame: TGARPFrame;
    LRequestID: string;
begin
    EnsureConnected;

    LRequestID :=
        NextRequestID;

    DebugLog(
        'ListTabs request_id=' +
        LRequestID
    );

    LMessage :=
        BuildMessage(
            'list_tabs',
            nil
        );

    try
        SendFrame(
            GARP_LIST_TABS,
            LMessage,
            LRequestID,
            ''
        );
    finally
        LMessage.Free;
    end;

    ReceiveUntil(
        LRequestID,
        [
            GARP_RESPONSE,
            GARP_LIST_TABS,
            GARP_ERROR
        ],
        LFrame
    );

    Result :=
        LFrame.MessageJSON;

    LFrame.MessageJSON := nil;
end;

function TGARPClient101.CreateSession(
    const AProvider: string;
    const ATabID: string
): TJSONObject;
var
    LPayload: TJSONObject;
    LMessage: TJSONObject;
    LFrame: TGARPFrame;
    LRequestID: string;
    LSessionID: string;
    LReturnedTabID: string;
begin
    EnsureConnected;

    if Trim(AProvider) = '' then
    begin
        raise Exception.Create(
            'Provider is empty'
        );
    end;

    LRequestID :=
        NextRequestID;

    DebugLog(
        Format(
            'CreateSession provider=%s tab_id=%s request_id=%s',
            [
                AProvider,
                ATabID,
                LRequestID
            ]
        )
    );

    LPayload :=
        TJSONObject.Create;

    try
        LPayload.AddPair(
            'provider',
            AProvider
        );

        if ATabID <> '' then
        begin
            LPayload.AddPair(
                'tab_id',
                ATabID
            );
        end;

        DebugLog(
            'CreateSession payload=' +
            LPayload.ToJSON
        );

        LMessage :=
            BuildMessage(
                'create_session',
                LPayload
            );

        try
            LPayload := nil;

            SendFrame(
                GARP_CREATE_SESSION,
                LMessage,
                LRequestID,
                ''
            );
        finally
            LMessage.Free;
        end;
    finally
        LPayload.Free;
    end;

    ReceiveUntil(
        LRequestID,
        [
            GARP_RESPONSE,
            GARP_SESSION_READY,
            GARP_ERROR
        ],
        LFrame
    );

    Result :=
        LFrame.MessageJSON;

    LFrame.MessageJSON := nil;

    LSessionID :=
        Result.GetValue<string>(
            'payload.session_id',
            ''
        );

    if LSessionID = '' then
    begin
        LSessionID :=
            Result.GetValue<string>(
                'session_id',
                ''
            );
    end;

    LReturnedTabID :=
        Result.GetValue<string>(
            'payload.tab_id',
            ''
        );

    if LReturnedTabID = '' then
    begin
        LReturnedTabID :=
            Result.GetValue<string>(
                'tab_id',
                ''
            );
    end;

    if LSessionID <> '' then
        FSessionID := LSessionID;

    if LReturnedTabID <> '' then
        FTabID := LReturnedTabID;

    DebugLog(
        Format(
            'CreateSession result session_id=%s tab_id=%s client_session_id=%s client_tab_id=%s',
            [
                LSessionID,
                LReturnedTabID,
                FSessionID,
                FTabID
            ]
        )
    );
end;

function TGARPClient101.Prompt(
    const APrompt: string;
    const AStream: Boolean;
    const ATimeoutMS: Integer;
    const AAutoContinue: Boolean
): TJSONObject;
var
    LOptions: TJSONObject;
    LPrompt: TJSONObject;
    LPayload: TJSONObject;
    LMessage: TJSONObject;
    LFrame: TGARPFrame;
begin
    EnsureConnected;

    DebugLog(
        Format(
            'Prompt begin session_id=%s tab_id=%s current_request_id=%s',
            [
                FSessionID,
                FTabID,
                FRequestID
            ]
        )
    );

    if FSessionID = '' then
    begin
        raise Exception.Create(
            'No GARP session is active'
        );
    end;

    if APrompt = '' then
    begin
        raise Exception.Create(
            'Prompt text is empty'
        );
    end;

    if ATimeoutMS <= 0 then
    begin
        raise Exception.Create(
            'Prompt timeout must be greater than zero'
        );
    end;

    DebugLog(
        'Prompt EXACT text=[' +
        APrompt +
        ']'
    );

    DebugLog(
        'Prompt text length=' +
        IntToStr(
            Length(APrompt)
        )
    );

    DebugLog(
        'Prompt UTF8 byte length=' +
        IntToStr(
            Length(
                TEncoding.UTF8.GetBytes(
                    APrompt
                )
            )
        )
    );

    NextRequestID;

    DebugLog(
        'Prompt assigned request_id=' +
        FRequestID
    );

    LPrompt :=
        TJSONObject.Create;

    try
        LPrompt.AddPair(
            'format',
            'text'
        );

        LPrompt.AddPair(
            'text',
            APrompt
        );

        DebugLog(
            'Prompt object=' +
            LPrompt.ToJSON
        );

        LOptions :=
            TJSONObject.Create;

        try
            LOptions.AddPair(
                'stream',
                TJSONBool.Create(
                    AStream
                )
            );

            LOptions.AddPair(
                'timeout_ms',
                TJSONNumber.Create(
                    ATimeoutMS
                )
            );

            LOptions.AddPair(
                'auto_continue',
                TJSONBool.Create(
                    AAutoContinue
                )
            );

            DebugLog(
                'Prompt options=' +
                LOptions.ToJSON
            );

            LPayload :=
                TJSONObject.Create;

            try
                LPayload.AddPair(
                    'prompt',
                    LPrompt
                );

                LPrompt := nil;

                LPayload.AddPair(
                    'options',
                    LOptions
                );

                LOptions := nil;

                DebugLog(
                    'Prompt payload=' +
                    LPayload.ToJSON
                );

                LMessage :=
                    BuildMessage(
                        'prompt',
                        LPayload
                    );

                try
                    LPayload := nil;

                    DebugLog(
                        'Prompt FINAL message=' +
                        LMessage.ToJSON
                    );

                    DebugLog(
                        Format(
                            'Prompt sending request_id=%s session_id=%s',
                            [
                                FRequestID,
                                FSessionID
                            ]
                        )
                    );

                    SendFrame(
                        GARP_PROMPT,
                        LMessage,
                        FRequestID,
                        FSessionID
                    );

                    DebugLog(
                        'Prompt GARP_PROMPT frame sent successfully'
                    );
                finally
                    LMessage.Free;
                end;
            finally
                LPayload.Free;
            end;
        finally
            LOptions.Free;
        end;
    finally
        LPrompt.Free;
    end;

    DebugLog(
        'Prompt waiting for PROMPT_ACK request_id=' +
        FRequestID
    );

    ReceiveUntil(
        FRequestID,
        [
            GARP_PROMPT_ACK,
            GARP_ERROR
        ],
        LFrame
    );

    DebugLog(
        'Prompt received ' +
        GARPMessageTypeToName(
            LFrame.MessageType
        )
    );

    Result :=
        LFrame.MessageJSON;

    LFrame.MessageJSON := nil;

    DebugLog(
        'Prompt complete'
    );
end;

function TGARPClient101.WaitForCompletion(
    const ARequestID: string;
    const ATimeoutMS: Cardinal
): TJSONObject;
var
    LStart: UInt64;
    LElapsed: UInt64;
    LFrame: TGARPFrame;
    LPayload: TJSONObject;
    LStatus: string;
    LPong: TJSONObject;
begin
    EnsureConnected;

    if ARequestID = '' then
    begin
        raise Exception.Create(
            'Request ID is empty'
        );
    end;

    DebugLog(
        Format(
            'WaitForCompletion begin request_id=%s timeout_ms=%d session_id=%s',
            [
                ARequestID,
                ATimeoutMS,
                FSessionID
            ]
        )
    );

    LStart :=
        TThread.GetTickCount64;

    repeat
        FillChar(
            LFrame,
            SizeOf(LFrame),
            0
        );

        if not FClient.IOHandler.Readable(1000) then
        begin
            LElapsed :=
                TThread.GetTickCount64 - LStart;

            if FDebug then
            begin
                DebugLog(
                    Format(
                        'WaitForCompletion no frame yet elapsed_ms=%d/%d',
                        [
                            LElapsed,
                            ATimeoutMS
                        ]
                    )
                );
            end;

            if LElapsed >= ATimeoutMS then
                Break;

            Continue;
        end;

        try
            ReceiveFrame(LFrame);

            Writeln(
                '[',
                GARPMessageTypeToName(
                    LFrame.MessageType
                ),
                '] ',
                LFrame.MessageJSON.ToJSON
            );

            DebugLog(
                Format(
                    'WaitForCompletion received type=%s request_id=%s session_id=%s expected_request_id=%s',
                    [
                        GARPMessageTypeToName(
                            LFrame.MessageType
                        ),
                        LFrame.RequestID,
                        LFrame.SessionID,
                        ARequestID
                    ]
                )
            );

            if (ARequestID <> '') and
               (LFrame.RequestID <> '') and
               (not SameText(
                    ARequestID,
                    LFrame.RequestID
               )) then
            begin
                DebugLog(
                    'WaitForCompletion ignoring frame because request_id differs'
                );

                Continue;
            end;

            case LFrame.MessageType of

                GARP_GENERATION_COMPLETED:
                    begin
                        DebugLog(
                            'WaitForCompletion -> GENERATION_COMPLETED'
                        );

                        Result :=
                            LFrame.MessageJSON;

                        LFrame.MessageJSON := nil;

                        Exit;
                    end;

                GARP_GENERATION_FAILED,
                GARP_ERROR:
                    begin
                        DebugLog(
                            'WaitForCompletion -> FAILURE/ERROR'
                        );

                        Result :=
                            LFrame.MessageJSON;

                        LFrame.MessageJSON := nil;

                        Exit;
                    end;

                GARP_GENERATION_DELTA:
                    begin
                        LPayload :=
                            LFrame.MessageJSON.GetValue<TJSONObject>(
                                'payload'
                            );

                        if LPayload <> nil then
                        begin
                            DebugLog(
                                'GENERATION_DELTA payload=' +
                                LPayload.ToJSON
                            );
                        end
                        else
                        begin
                            DebugLog(
                                'GENERATION_DELTA has no object payload'
                            );
                        end;
                    end;

                GARP_GENERATION_STARTED:
                    begin
                        DebugLog(
                            'GENERATION_STARTED payload=' +
                            LFrame.MessageJSON.GetValue<TJSONObject>(
                                'payload'
                            ).ToJSON
                        );
                    end;

                GARP_GENERATION_PROGRESS:
                    begin
                        LPayload :=
                            LFrame.MessageJSON.GetValue<TJSONObject>(
                                'payload'
                            );

                        if LPayload <> nil then
                        begin
                            LStatus :=
                                LPayload.GetValue<string>(
                                    'state',
                                    ''
                                );

                            DebugLog(
                                'GENERATION_PROGRESS state=' +
                                LStatus +
                                ' payload=' +
                                LPayload.ToJSON
                            );

                            if SameText(
                                LStatus,
                                'complete'
                            ) then
                            begin
                                DebugLog(
                                    'WaitForCompletion -> progress state complete'
                                );

                                Result :=
                                    LFrame.MessageJSON;

                                LFrame.MessageJSON := nil;

                                Exit;
                            end;
                        end;
                    end;

                GARP_INPUT_SUBMITTED:
                    begin
                        DebugLog(
                            'INPUT_SUBMITTED payload=' +
                            LFrame.MessageJSON.GetValue<TJSONObject>(
                                'payload'
                            ).ToJSON
                        );
                    end;

                GARP_SESSION_READY:
                    begin
                        DebugLog(
                            'SESSION_READY payload=' +
                            LFrame.MessageJSON.GetValue<TJSONObject>(
                                'payload'
                            ).ToJSON
                        );
                    end;

                GARP_NAVIGATION:
                    begin
                        DebugLog(
                            'NAVIGATION payload=' +
                            LFrame.MessageJSON.GetValue<TJSONObject>(
                                'payload'
                            ).ToJSON
                        );
                    end;

                GARP_PROVIDER_ERROR:
                    begin
                        DebugLog(
                            'PROVIDER_ERROR payload=' +
                            LFrame.MessageJSON.GetValue<TJSONObject>(
                                'payload'
                            ).ToJSON
                        );
                    end;

                GARP_AUTH_REQUIRED:
                    begin
                        DebugLog(
                            'AUTH_REQUIRED payload=' +
                            LFrame.MessageJSON.GetValue<TJSONObject>(
                                'payload'
                            ).ToJSON
                        );
                    end;

                GARP_RATE_LIMITED:
                    begin
                        DebugLog(
                            'RATE_LIMITED payload=' +
                            LFrame.MessageJSON.GetValue<TJSONObject>(
                                'payload'
                            ).ToJSON
                        );
                    end;

                GARP_PING:
                    begin
                        DebugLog(
                            'WaitForCompletion received PING; replying PONG'
                        );

                        LPong :=
                            BuildMessage(
                                'pong',
                                nil
                            );

                        try
                            SendFrame(
                                GARP_PONG,
                                LPong
                            );
                        finally
                            LPong.Free;
                        end;
                    end;
            end;

        finally
            LFrame.MessageJSON.Free;
            LFrame.MessageJSON := nil;
        end;

    until
        TThread.GetTickCount64 - LStart >= ATimeoutMS;

    DebugLog(
        Format(
            'WaitForCompletion timed out request_id=%s elapsed_ms=%d',
            [
                ARequestID,
                TThread.GetTickCount64 - LStart
            ]
        )
    );

    LPayload :=
        TJSONObject.Create;

    try
        LPayload.AddPair(
            'code',
            'GENERATION_TIMEOUT'
        );

        LPayload.AddPair(
            'message',
            'Timed out waiting for generation_completed'
        );

        LPayload.AddPair(
            'request_id',
            ARequestID
        );

        Result :=
            GARPBuildJSON(
                'error',
                LPayload,
                ARequestID,
                FSessionID
            );

        LPayload := nil;
    finally
        LPayload.Free;
    end;
end;

function TGARPClient101.CancelPrompt(
    const ARequestID: string;
    const AReason: string
): TJSONObject;
var
    LPayload: TJSONObject;
    LMessage: TJSONObject;
    LFrame: TGARPFrame;
begin
    EnsureConnected;

    if ARequestID = '' then
    begin
        raise Exception.Create(
            'Request ID is empty'
        );
    end;

    DebugLog(
        Format(
            'CancelPrompt request_id=%s reason=%s',
            [
                ARequestID,
                AReason
            ]
        )
    );

    LPayload :=
        TJSONObject.Create;

    try
        LPayload.AddPair(
            'reason',
            AReason
        );

        LMessage :=
            BuildMessage(
                'cancel_prompt',
                LPayload
            );

        try
            LPayload := nil;

            SendFrame(
                GARP_CANCEL_PROMPT,
                LMessage,
                ARequestID,
                FSessionID
            );
        finally
            LMessage.Free;
        end;
    finally
        LPayload.Free;
    end;

    ReceiveUntil(
        ARequestID,
        [
            GARP_CANCEL_ACK,
            GARP_ERROR
        ],
        LFrame
    );

    Result :=
        LFrame.MessageJSON;

    LFrame.MessageJSON := nil;
end;

procedure TGARPClient101.Ping;
var
    LMessage: TJSONObject;
    LFrame: TGARPFrame;
begin
    EnsureConnected;

    DebugLog('PING begin');

    LMessage :=
        BuildMessage(
            'ping',
            nil
        );

    try
        SendFrame(
            GARP_PING,
            LMessage
        );
    finally
        LMessage.Free;
    end;

    ReceiveUntil(
        '',
        [
            GARP_PONG,
            GARP_ERROR
        ],
        LFrame
    );

    DebugLog('PING received PONG');

    LFrame.MessageJSON.Free;
    LFrame.MessageJSON := nil;
end;

procedure TGARPClient101.CloseSession;
var
    LPayload: TJSONObject;
    LMessage: TJSONObject;
    LFrame: TGARPFrame;
    LRequestID: string;
begin
    if FSessionID = '' then
    begin
        DebugLog(
            'CloseSession skipped because session_id is empty'
        );

        Exit;
    end;

    EnsureConnected;

    LRequestID :=
        NextRequestID;

    DebugLog(
        Format(
            'CloseSession request_id=%s session_id=%s tab_id=%s',
            [
                LRequestID,
                FSessionID,
                FTabID
            ]
        )
    );

    LPayload :=
        TJSONObject.Create;

    try
        LPayload.AddPair(
            'session_id',
            FSessionID
        );

        LMessage :=
            BuildMessage(
                'close_session',
                LPayload
            );

        try
            LPayload := nil;

            SendFrame(
                GARP_CLOSE_SESSION,
                LMessage,
                LRequestID,
                FSessionID
            );
        finally
            LMessage.Free;
        end;
    finally
        LPayload.Free;
    end;

    ReceiveUntil(
        LRequestID,
        [
            GARP_RESPONSE,
            GARP_CLOSE_SESSION,
            GARP_ERROR
        ],
        LFrame
    );

    LFrame.MessageJSON.Free;
    LFrame.MessageJSON := nil;

    FSessionID := '';
    FTabID := '';

    DebugLog(
        'CloseSession complete; local session/tab IDs cleared'
    );
end;

end.
