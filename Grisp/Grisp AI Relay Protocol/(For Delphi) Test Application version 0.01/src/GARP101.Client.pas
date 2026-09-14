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
    end;

implementation

constructor TGARPClient101.Create(
    const AHost: string;
    const APort: Integer;
    const ASecret: string
);
begin
    inherited Create;

    FClient := TIdTCPClient.Create(nil);
    FClient.Host := AHost;
    FClient.Port := APort;
    FClient.ConnectTimeout := 5000;
    FClient.ReadTimeout := GARP_READ_TIMEOUT;

    FClientID := 'GARP101-Delphi-Test-' + GARPNewUUID;
    FClientVersion := '1.0.0';
    FSecret := ASecret;

    FClientNonce := '';
    FAuthenticated := False;
    FSessionID := '';
    FTabID := '';
    FRequestID := '';
end;

destructor TGARPClient101.Destroy;
begin
    CloseConnection;
    FClient.Free;
    inherited Destroy;
end;

procedure TGARPClient101.CloseConnection;
begin
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
        raise Exception.Create(
            'GARP client is not connected'
        );

    if not FAuthenticated then
        raise Exception.Create(
            'GARP client is not authenticated'
        );
end;

function TGARPClient101.NextRequestID: string;
begin
    Result := GARPNewUUID;
    FRequestID := Result;
end;

function TGARPClient101.BuildMessage(
    const ATypeName: string;
    const APayload: TJSONValue
): TJSONObject;
begin
    Result := GARPBuildJSON(
        ATypeName,
        APayload
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
begin
    if AMessage = nil then
        raise Exception.Create(
            'Cannot send a nil GARP message'
        );

    LFrame := GARPEncodeFrame(
        AMessageType,
        AMessage,
        ARequestID,
        ASessionID
    );

    GARPWriteFrame(
        FClient,
        LFrame
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

    LBytes := GARPReadFrame(
        FClient
    );

    AFrame := GARPDecodeFrame(
        LBytes
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

    repeat
        ReceiveFrame(AFrame);

        if AFrame.MessageType = GARP_PING then
        begin
            LPong := BuildMessage(
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
            for LIndex := Low(AAcceptedTypes) to High(AAcceptedTypes) do
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

            AFrame.MessageJSON.Free;
            AFrame.MessageJSON := nil;

            Continue;
        end;

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
    if FClient.Connected then
    begin
        if FAuthenticated then
            Exit;

        CloseConnection;
    end;

    if FSecret = '' then
        raise Exception.Create(
            'GARP secret is empty. Use --secret or GARP_SECRET.'
        );

    FSessionID := '';
    FTabID := '';
    FRequestID := '';
    FAuthenticated := False;

    FClient.Connect;

    FClient.IOHandler.ReadTimeout :=
        GARP_READ_TIMEOUT;

    FClientNonce :=
        GARPCreateNonce;

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

    ReceiveFrame(
        LFrame
    );

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

            if LErrorCode <> '' then
                raise Exception.Create(
                    'GARP HELLO rejected [' +
                    LErrorCode +
                    ']: ' +
                    LErrorMessage
                )
            else
                raise Exception.Create(
                    'GARP HELLO rejected: ' +
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

        if LServerNonce = '' then
            raise Exception.Create(
                'hello_challenge does not contain server_nonce'
            );
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

    ReceiveFrame(
        LFrame
    );

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

            if LErrorCode <> '' then
                raise Exception.Create(
                    'GARP authentication failed [' +
                    LErrorCode +
                    ']: ' +
                    LErrorMessage
                )
            else
                raise Exception.Create(
                    'GARP authentication failed: ' +
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
    finally
        LFrame.MessageJSON.Free;
        LFrame.MessageJSON := nil;
    end;
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
        raise Exception.Create(
            'Provider is empty'
        );

    LRequestID :=
        NextRequestID;

    LPayload :=
        TJSONObject.Create;

    try
        LPayload.AddPair(
            'provider',
            AProvider
        );

        if ATabID <> '' then
            LPayload.AddPair(
                'tab_id',
                ATabID
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
        LSessionID :=
            Result.GetValue<string>(
                'session_id',
                ''
            );

    LReturnedTabID :=
        Result.GetValue<string>(
            'payload.tab_id',
            ''
        );

    if LReturnedTabID = '' then
        LReturnedTabID :=
            Result.GetValue<string>(
                'tab_id',
                ''
            );

    if LSessionID <> '' then
        FSessionID := LSessionID;

    if LReturnedTabID <> '' then
        FTabID := LReturnedTabID;
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

    if FSessionID = '' then
        raise Exception.Create(
            'No GARP session is active'
        );

    if APrompt = '' then
        raise Exception.Create(
            'Prompt text is empty'
        );

    if ATimeoutMS <= 0 then
        raise Exception.Create(
            'Prompt timeout must be greater than zero'
        );

    NextRequestID;

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

        LOptions :=
            TJSONObject.Create;

        try
            LOptions.AddPair(
                'stream',
                TJSONBool.Create(AStream)
            );

            LOptions.AddPair(
                'timeout_ms',
                TJSONNumber.Create(ATimeoutMS)
            );

            LOptions.AddPair(
                'auto_continue',
                TJSONBool.Create(AAutoContinue)
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

                LMessage :=
                    BuildMessage(
                        'prompt',
                        LPayload
                    );

                try
                    LPayload := nil;

                    SendFrame(
                        GARP_PROMPT,
                        LMessage,
                        FRequestID,
                        FSessionID
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

    ReceiveUntil(
        FRequestID,
        [
            GARP_PROMPT_ACK,
            GARP_ERROR
        ],
        LFrame
    );

    Result :=
        LFrame.MessageJSON;

    LFrame.MessageJSON := nil;
end;

function TGARPClient101.WaitForCompletion(
    const ARequestID: string;
    const ATimeoutMS: Cardinal
): TJSONObject;
var
    LStart: UInt64;
    LFrame: TGARPFrame;
    LPayload: TJSONObject;
    LStatus: string;
    LPong: TJSONObject;
begin
    EnsureConnected;

    if ARequestID = '' then
        raise Exception.Create(
            'Request ID is empty'
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
            if TThread.GetTickCount64 - LStart >= ATimeoutMS then
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

            if (ARequestID <> '') and
               (LFrame.RequestID <> '') and
               (not SameText(
                    ARequestID,
                    LFrame.RequestID
               )) then
            begin
                Continue;
            end;

            case LFrame.MessageType of

                GARP_GENERATION_COMPLETED:
                    begin
                        Result :=
                            LFrame.MessageJSON;

                        LFrame.MessageJSON := nil;

                        Exit;
                    end;

                GARP_GENERATION_FAILED,
                GARP_ERROR:
                    begin
                        Result :=
                            LFrame.MessageJSON;

                        LFrame.MessageJSON := nil;

                        Exit;
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

                            if SameText(
                                LStatus,
                                'complete'
                            ) then
                            begin
                                Result :=
                                    LFrame.MessageJSON;

                                LFrame.MessageJSON := nil;

                                Exit;
                            end;
                        end;
                    end;

                GARP_PING:
                    begin
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
        raise Exception.Create(
            'Request ID is empty'
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
        Exit;

    EnsureConnected;

    LRequestID :=
        NextRequestID;

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
end;

end.

