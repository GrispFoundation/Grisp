unit GARP124.Protocol;

interface

uses
    System.SysUtils,
    System.DateUtils,
    System.JSON,
    System.Hash,
    System.NetEncoding,
    System.Generics.Collections,
    System.Generics.Defaults,
    System.RegularExpressions,
    Winapi.Windows,
    IdTCPClient,
    IdGlobal;

const
    GARP_PROTOCOL = 'GARP/1.24';
    GARP_SEMANTIC_VERSION = '1.24';
    GARP_WIRE_VERSION = '0x00';
    GARP_VERSION_BYTE = $00;
    GARP_FIXED_HEADER_LENGTH = 48;
    GARP_DEFAULT_PORT = 9999;
    GARP_HANDSHAKE_MAX_PAYLOAD = 1024 * 1024;
    GARP_APPLICATION_MAX_PAYLOAD = 16 * 1024 * 1024;
    GARP_MAX_FRAME_SIZE = GARP_APPLICATION_MAX_PAYLOAD;
    GARP_READ_TIMEOUT = 10000;
    GARP_HANDSHAKE_TIMEOUT = 10000;
    GARP_ZERO_UUID = '00000000-0000-0000-0000-000000000000';
    GARP_DOMAIN_CLIENT_PROOF = 'GARP/1.24/client-proof';
    GARP_DOMAIN_SERVER_PROOF = 'GARP/1.24/server-proof';
    GARP_FEATURE_EXT_PONG = 'ext-pong';
    GARP_FEATURE_EXT_REPLAY_STORE = 'ext-replay-store';

    GARP_HELLO = $0001;
    GARP_HELLO_CHALLENGE = $0002;
    GARP_HELLO_AUTH = $0003;
    GARP_HELLO_ACK = $0004;
    GARP_RESPONSE = $0005;
    GARP_ERROR = $0006;

    GARP_CAPABILITIES = $0010;
    GARP_BROWSER_STATUS = $0011;
    GARP_LIST_TABS = $0012;
    GARP_OPEN_TAB = $0013;
    GARP_CLOSE_TAB = $0014;
    GARP_SELECT_TAB = $0015;
    GARP_GET_CAPABILITIES = $0016;

    GARP_CREATE_SESSION = $0020;
    GARP_ATTACH_SESSION = $0021;
    GARP_DETACH_SESSION = $0022;
    GARP_CLOSE_SESSION = $0023;
    GARP_RESET_SESSION = $0024;
    GARP_GET_SESSION = $0025;

    GARP_PROMPT = $0030;
    GARP_CANCEL_PROMPT = $0031;
    GARP_GET_PROMPT_STATUS = $0032;
    GARP_GET_RESPONSE = $0033;
    GARP_SUBSCRIBE_RESPONSE = $0034;
    GARP_CONTINUE_PROMPT = $0035;

    GARP_SESSION_READY = $0040;
    GARP_SESSION_CHANGED = $0041;
    GARP_NAVIGATION = $0042;
    GARP_NAVIGATION_DRIFT = $0043;
    GARP_RECOVERY_STATE = $0044;
    GARP_PROVIDER_CHANGED = $0045;

    GARP_INPUT_SUBMITTED = $0050;
    GARP_GENERATION_STARTED = $0051;
    GARP_GENERATION_DELTA = $0052;
    GARP_GENERATION_PROGRESS = $0053;
    GARP_CONTINUATION_REQUIRED = $0054;
    GARP_CONTINUATION_SUBMITTED = $0055;
    GARP_GENERATION_COMPLETED = $0056;
    GARP_GENERATION_FAILED = $0057;
    GARP_GENERATION_CANCELLED = $0058;

    GARP_PROVIDER_ERROR = $0060;
    GARP_PROVIDER_AUTH_REQUIRED = $0061;
    GARP_PROVIDER_RATE_LIMITED = $0062;
    GARP_DIAGNOSTIC = $0063;

    GARP_PING = $0070;
    GARP_PONG = $0071;

    GARP_GET_EVENTS = $0100;

    BCRYPT_USE_SYSTEM_PREFERRED_RNG = $00000002;

type
    TGARPMessageType = Word;

    EGARPProtocolError = class(Exception);

    TGARPFrame = record
        MessageType: TGARPMessageType;
        RequestID: string;
        SessionID: string;
        Timestamp: string;
        MessageJSON: TJSONObject;
        PayloadLength: Cardinal;
    end;

function GARPMessageTypeToName(const AMessageType: TGARPMessageType): string;
function GARPMessageNameToType(const AName: string): TGARPMessageType;
function GARPNewUUID: string;
function GARPCreateNonce: TBytes;
function GARPBase64UrlEncode(const ABytes: TBytes): string;
function GARPBase64UrlDecode(const AValue: string): TBytes;
function GARPRequireNonce16(const AValue: string): TBytes;
function GARPUUIDToBytes(const AValue: string): TBytes;
function GARPBytesToUUID(const ABytes: TBytes; const AOffset: Integer): string;
function GARPBuildJSON(
    const ATypeName: string;
    const APayload: TJSONValue;
    const ARequestID: string = '';
    const ASessionID: string = ''
): TJSONObject;
function GARPEncodeFrame(
    const AMessageType: TGARPMessageType;
    const AJSON: TJSONObject;
    const ARequestID: string = '';
    const ASessionID: string = ''
): TBytes;
function GARPDecodeFrame(const AFrame: TBytes): TGARPFrame;
function GARPReadFrame(
    AClient: TIdTCPClient;
    const AMaxPayloadBytes: Cardinal = GARP_HANDSHAKE_MAX_PAYLOAD
): TBytes;
procedure GARPWriteFrame(AClient: TIdTCPClient; const AFrame: TBytes);
function GARPWriteRead(AClient: TIdTCPClient; const AFrame: TBytes): TBytes;
function GARPCanonicalFeatureList(const AFeatures: array of string): TArray<string>;
function GARPEncodeTranscript(
    const ADomain: string;
    const AClientNonce: TBytes;
    const AServerNonce: TBytes;
    const ASelectedVersion: string;
    const ASelectedWireVersion: string;
    const AOfferedFeatures: TArray<string>;
    const AFinalFeatures: TArray<string>;
    const AClientName: string;
    const AClientVersion: string;
    const AServerName: string;
    const AServerVersion: string
): TBytes;
function GARPHMACSHA256(const ASecret: string; const AData: TBytes): TBytes;
function GARPMakeProof(
    const ASecret: string;
    const ADomain: string;
    const AClientNonce: TBytes;
    const AServerNonce: TBytes;
    const AOfferedFeatures: TArray<string>;
    const AFinalFeatures: TArray<string>;
    const AClientName: string;
    const AClientVersion: string;
    const AServerName: string;
    const AServerVersion: string
): TBytes;
function GARPJSONObjectPayload(const AFrame: TGARPFrame): TJSONObject;
function GARPFrameRequestIDMatches(const AFrame: TGARPFrame; const ARequestID: string): Boolean;
function GARPFramePromptRequestID(const AFrame: TGARPFrame): string;

implementation

function BCryptGenRandom(
    hAlgorithm: Pointer;
    pbBuffer: PByte;
    cbBuffer: Cardinal;
    dwFlags: Cardinal
): Cardinal; stdcall; external 'bcrypt.dll' name 'BCryptGenRandom';

function GARPMessageTypeToName(const AMessageType: TGARPMessageType): string;
begin
    case AMessageType of
        GARP_HELLO: Result := 'HELLO';
        GARP_HELLO_CHALLENGE: Result := 'HELLO_CHALLENGE';
        GARP_HELLO_AUTH: Result := 'HELLO_AUTH';
        GARP_HELLO_ACK: Result := 'HELLO_ACK';
        GARP_RESPONSE: Result := 'RESPONSE';
        GARP_ERROR: Result := 'ERROR';
        GARP_CAPABILITIES: Result := 'CAPABILITIES';
        GARP_BROWSER_STATUS: Result := 'BROWSER_STATUS';
        GARP_LIST_TABS: Result := 'LIST_TABS';
        GARP_OPEN_TAB: Result := 'OPEN_TAB';
        GARP_CLOSE_TAB: Result := 'CLOSE_TAB';
        GARP_SELECT_TAB: Result := 'SELECT_TAB';
        GARP_GET_CAPABILITIES: Result := 'GET_CAPABILITIES';
        GARP_CREATE_SESSION: Result := 'CREATE_SESSION';
        GARP_ATTACH_SESSION: Result := 'ATTACH_SESSION';
        GARP_DETACH_SESSION: Result := 'DETACH_SESSION';
        GARP_CLOSE_SESSION: Result := 'CLOSE_SESSION';
        GARP_RESET_SESSION: Result := 'RESET_SESSION';
        GARP_GET_SESSION: Result := 'GET_SESSION';
        GARP_PROMPT: Result := 'PROMPT';
        GARP_CANCEL_PROMPT: Result := 'CANCEL_PROMPT';
        GARP_GET_PROMPT_STATUS: Result := 'GET_PROMPT_STATUS';
        GARP_GET_RESPONSE: Result := 'GET_RESPONSE';
        GARP_SUBSCRIBE_RESPONSE: Result := 'SUBSCRIBE_RESPONSE';
        GARP_CONTINUE_PROMPT: Result := 'CONTINUE_PROMPT';
        GARP_SESSION_READY: Result := 'SESSION_READY';
        GARP_SESSION_CHANGED: Result := 'SESSION_CHANGED';
        GARP_NAVIGATION: Result := 'NAVIGATION';
        GARP_NAVIGATION_DRIFT: Result := 'NAVIGATION_DRIFT';
        GARP_RECOVERY_STATE: Result := 'RECOVERY_STATE';
        GARP_PROVIDER_CHANGED: Result := 'PROVIDER_CHANGED';
        GARP_INPUT_SUBMITTED: Result := 'INPUT_SUBMITTED';
        GARP_GENERATION_STARTED: Result := 'GENERATION_STARTED';
        GARP_GENERATION_DELTA: Result := 'GENERATION_DELTA';
        GARP_GENERATION_PROGRESS: Result := 'GENERATION_PROGRESS';
        GARP_CONTINUATION_REQUIRED: Result := 'CONTINUATION_REQUIRED';
        GARP_CONTINUATION_SUBMITTED: Result := 'CONTINUATION_SUBMITTED';
        GARP_GENERATION_COMPLETED: Result := 'GENERATION_COMPLETED';
        GARP_GENERATION_FAILED: Result := 'GENERATION_FAILED';
        GARP_GENERATION_CANCELLED: Result := 'GENERATION_CANCELLED';
        GARP_PROVIDER_ERROR: Result := 'PROVIDER_ERROR';
        GARP_PROVIDER_AUTH_REQUIRED: Result := 'PROVIDER_AUTH_REQUIRED';
        GARP_PROVIDER_RATE_LIMITED: Result := 'PROVIDER_RATE_LIMITED';
        GARP_DIAGNOSTIC: Result := 'DIAGNOSTIC';
        GARP_PING: Result := 'PING';
        GARP_PONG: Result := 'PONG';
        GARP_GET_EVENTS: Result := 'GET_EVENTS';
    else
        Result := '';
    end;
end;

function GARPMessageNameToType(const AName: string): TGARPMessageType;
var
    LIndex: TGARPMessageType;
    LName: string;
begin
    LName := UpperCase(Trim(AName));
    for LIndex := 0 to $0100 do
    begin
        if GARPMessageTypeToName(LIndex) = LName then
            Exit(LIndex);
    end;
    Result := 0;
end;

function GARPNewUUID: string;
var
    LGuid: TGUID;
begin
    if CreateGUID(LGuid) <> 0 then
        raise EGARPProtocolError.Create('Unable to generate UUID');
    Result := LowerCase(Copy(GUIDToString(LGuid), 2, 36));
end;

function GARPCreateNonce: TBytes;
begin
    SetLength(Result, 16);
    if BCryptGenRandom(nil, @Result[0], Length(Result), BCRYPT_USE_SYSTEM_PREFERRED_RNG) <> 0 then
        raise EGARPProtocolError.Create('Unable to generate cryptographically random GARP nonce');
end;

function GARPBase64UrlEncode(const ABytes: TBytes): string;
begin
    Result := TNetEncoding.Base64.EncodeBytesToString(ABytes);
    Result := StringReplace(Result, '+', '-', [rfReplaceAll]);
    Result := StringReplace(Result, '/', '_', [rfReplaceAll]);
    Result := StringReplace(Result, '=', '', [rfReplaceAll]);
end;

function GARPBase64UrlDecode(const AValue: string): TBytes;
var
    LText: string;
    LPadding: Integer;
begin
    if not TRegEx.IsMatch(AValue, '^[A-Za-z0-9_-]*$') then
        raise EGARPProtocolError.Create('Invalid Base64URL encoding');
    if (Length(AValue) mod 4) = 1 then
        raise EGARPProtocolError.Create('Invalid Base64URL length');

    LText := StringReplace(AValue, '-', '+', [rfReplaceAll]);
    LText := StringReplace(LText, '_', '/', [rfReplaceAll]);
    LPadding := (4 - (Length(LText) mod 4)) mod 4;

    while LPadding > 0 do
    begin
        LText := LText + '=';
        Dec(LPadding);
    end;

    try
        Result := TNetEncoding.Base64.DecodeStringToBytes(LText);
    except
        on E: Exception do
            raise EGARPProtocolError.Create('Invalid Base64URL encoding: ' + E.Message);
    end;
end;

function GARPRequireNonce16(const AValue: string): TBytes;
begin
    Result := GARPBase64UrlDecode(AValue);
    if Length(Result) <> 16 then
        raise EGARPProtocolError.Create('GARP nonce must decode to exactly 16 bytes');
end;

function GARPUUIDToBytes(const AValue: string): TBytes;
var
    LText: string;
    LIndex: Integer;
begin
    SetLength(Result, 16);

    if AValue = '' then
        Exit;

    if SameText(AValue, GARP_ZERO_UUID) then
        Exit;

    if not TRegEx.IsMatch(
        AValue,
        '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    ) then
        raise EGARPProtocolError.Create('Invalid UUID: ' + AValue);

    LText := StringReplace(LowerCase(AValue), '-', '', [rfReplaceAll]);

    for LIndex := 0 to 15 do
        Result[LIndex] := StrToInt('$' + Copy(LText, LIndex * 2 + 1, 2));
end;

function GARPBytesToUUID(const ABytes: TBytes; const AOffset: Integer): string;
var
    LIndex: Integer;
    LZero: Boolean;
    LText: string;
begin
    if (AOffset < 0) or (Length(ABytes) < AOffset + 16) then
        raise EGARPProtocolError.Create('UUID field is truncated');

    LZero := True;
    LText := '';

    for LIndex := 0 to 15 do
    begin
        LZero := LZero and (ABytes[AOffset + LIndex] = 0);
        LText := LText + IntToHex(ABytes[AOffset + LIndex], 2);
    end;

    if LZero then
        Exit('');

    Result := LowerCase(
        Copy(LText, 1, 8) + '-' +
        Copy(LText, 9, 4) + '-' +
        Copy(LText, 13, 4) + '-' +
        Copy(LText, 17, 4) + '-' +
        Copy(LText, 21, 12)
    );
end;

function GARPBuildJSON(
    const ATypeName: string;
    const APayload: TJSONValue;
    const ARequestID: string;
    const ASessionID: string
): TJSONObject;
begin
    Result := TJSONObject.Create;

    try
        Result.AddPair('garp', GARP_SEMANTIC_VERSION);
        Result.AddPair('type', UpperCase(ATypeName));

        if ARequestID = '' then
            Result.AddPair('request_id', TJSONNull.Create)
        else
            Result.AddPair('request_id', ARequestID);

        if ASessionID = '' then
            Result.AddPair('session_id', TJSONNull.Create)
        else
            Result.AddPair('session_id', ASessionID);

        Result.AddPair(
            'timestamp',
            DateToISO8601(TDateTime.NowUTC, True)
        );

        Result.AddPair('sequence', TJSONNull.Create);

        if APayload = nil then
            Result.AddPair('payload', TJSONObject.Create)
        else
            Result.AddPair('payload', APayload);
    except
        Result.Free;
        raise;
    end;
end;

function GARPEncodeFrame(
    const AMessageType: TGARPMessageType;
    const AJSON: TJSONObject;
    const ARequestID: string;
    const ASessionID: string
): TBytes;
var
    LPayloadBytes: TBytes;
    LRequestBytes: TBytes;
    LSessionBytes: TBytes;
    LPayloadText: string;
    LLength: Cardinal;
    LIndex: Integer;
begin
    if AJSON = nil then
        raise EGARPProtocolError.Create('JSON message is nil');

    if GARPMessageTypeToName(AMessageType) = '' then
        raise EGARPProtocolError.CreateFmt(
            'Unknown GARP message type: 0x%.4x',
            [AMessageType]
        );

    LPayloadText := AJSON.ToJSON;
    LPayloadBytes := TEncoding.UTF8.GetBytes(LPayloadText);
    LLength := Length(LPayloadBytes);

    if LLength > GARP_MAX_FRAME_SIZE then
        raise EGARPProtocolError.Create(
            'GARP payload exceeds maximum frame size'
        );

    SetLength(Result, GARP_FIXED_HEADER_LENGTH + LLength);

    Result[0] := Ord('G');
    Result[1] := Ord('A');
    Result[2] := Ord('R');
    Result[3] := Ord('P');
    Result[4] := GARP_VERSION_BYTE;
    Result[5] := 0;
    Result[6] := 0;
    Result[7] := GARP_FIXED_HEADER_LENGTH;
    Result[8] := Byte(LLength shr 24);
    Result[9] := Byte(LLength shr 16);
    Result[10] := Byte(LLength shr 8);
    Result[11] := Byte(LLength);
    Result[12] := Byte(AMessageType shr 8);
    Result[13] := Byte(AMessageType);
    Result[14] := 0;
    Result[15] := 0;

    LRequestBytes := GARPUUIDToBytes(ARequestID);
    LSessionBytes := GARPUUIDToBytes(ASessionID);

    for LIndex := 0 to 15 do
    begin
        Result[16 + LIndex] := LRequestBytes[LIndex];
        Result[32 + LIndex] := LSessionBytes[LIndex];
    end;

    if LLength > 0 then
        Move(
            LPayloadBytes[0],
            Result[GARP_FIXED_HEADER_LENGTH],
            LLength
        );
end;

function GARPDecodeFrame(const AFrame: TBytes): TGARPFrame;
var
    LHeaderLength: Cardinal;
    LPayloadLength: Cardinal;
    LMessageType: TGARPMessageType;
    LPayloadBytes: TBytes;
    LPayloadText: string;
    LValue: TJSONValue;
    LExpectedName: string;
    LRequestID: string;
    LSessionID: string;
    LEnvelopeRequestID: TJSONValue;
    LEnvelopeSessionID: TJSONValue;
begin
    FillChar(Result, SizeOf(Result), 0);
    Result.MessageJSON := nil;

    if Length(AFrame) < GARP_FIXED_HEADER_LENGTH then
        raise EGARPProtocolError.Create(
            'GARP frame is shorter than the fixed header'
        );

    if (AFrame[0] <> Ord('G')) or
       (AFrame[1] <> Ord('A')) or
       (AFrame[2] <> Ord('R')) or
       (AFrame[3] <> Ord('P')) then
        raise EGARPProtocolError.Create('Invalid GARP magic');

    if AFrame[4] <> GARP_VERSION_BYTE then
        raise EGARPProtocolError.CreateFmt(
            'Unsupported GARP wire version: 0x%.2x',
            [AFrame[4]]
        );

    if AFrame[5] <> 0 then
        raise EGARPProtocolError.Create('Unsupported GARP flags');

    LHeaderLength :=
        (Cardinal(AFrame[6]) shl 8) or
        Cardinal(AFrame[7]);

    if LHeaderLength <> GARP_FIXED_HEADER_LENGTH then
        raise EGARPProtocolError.Create(
            'GARP header length must be exactly 48 bytes'
        );

    LPayloadLength :=
        (Cardinal(AFrame[8]) shl 24) or
        (Cardinal(AFrame[9]) shl 16) or
        (Cardinal(AFrame[10]) shl 8) or
        Cardinal(AFrame[11]);

    if Cardinal(Length(AFrame)) <
       GARP_FIXED_HEADER_LENGTH + LPayloadLength then
        raise EGARPProtocolError.Create('GARP frame is truncated');

    if Cardinal(Length(AFrame)) >
       GARP_FIXED_HEADER_LENGTH + LPayloadLength then
        raise EGARPProtocolError.Create('GARP frame contains trailing bytes');

    if LPayloadLength > GARP_MAX_FRAME_SIZE then
        raise EGARPProtocolError.Create(
            'GARP payload exceeds maximum frame size'
        );

    if (AFrame[14] <> 0) or (AFrame[15] <> 0) then
        raise EGARPProtocolError.Create(
            'GARP reserved header field is nonzero'
        );

    LMessageType :=
        (Word(AFrame[12]) shl 8) or
        Word(AFrame[13]);

    LExpectedName := GARPMessageTypeToName(LMessageType);

    if LExpectedName = '' then
        raise EGARPProtocolError.CreateFmt(
            'Unknown GARP message type: 0x%.4x',
            [LMessageType]
        );

    SetLength(LPayloadBytes, LPayloadLength);

    if LPayloadLength > 0 then
        Move(
            AFrame[GARP_FIXED_HEADER_LENGTH],
            LPayloadBytes[0],
            LPayloadLength
        );

    try
        LPayloadText := TEncoding.UTF8.GetString(LPayloadBytes);
    except
        on E: Exception do
            raise EGARPProtocolError.Create(
                'Invalid UTF-8 payload: ' + E.Message
            );
    end;

    try
        LValue := TJSONObject.ParseJSONValue(LPayloadText);
    except
        on E: Exception do
            raise EGARPProtocolError.Create(
                'Invalid JSON payload: ' + E.Message
            );
    end;

    if not (LValue is TJSONObject) then
    begin
        LValue.Free;
        raise EGARPProtocolError.Create(
            'GARP payload is not a JSON object'
        );
    end;

    Result.MessageJSON := TJSONObject(LValue);

    try
        if Result.MessageJSON.GetValue<string>('garp', '') <>
           GARP_SEMANTIC_VERSION then
            raise EGARPProtocolError.Create(
                'GARP semantic version mismatch'
            );

        if not SameText(
            Result.MessageJSON.GetValue<string>('type', ''),
            LExpectedName
        ) then
            raise EGARPProtocolError.Create(
                'GARP binary/header message type mismatch'
            );

        LRequestID := GARPBytesToUUID(AFrame, 16);
        LSessionID := GARPBytesToUUID(AFrame, 32);
        LEnvelopeRequestID := Result.MessageJSON.GetValue('request_id');
        LEnvelopeSessionID := Result.MessageJSON.GetValue('session_id');

        if LEnvelopeRequestID = nil then
            raise EGARPProtocolError.Create(
                'Envelope request_id is missing'
            );

        if LEnvelopeSessionID = nil then
            raise EGARPProtocolError.Create(
                'Envelope session_id is missing'
            );

        if ((LRequestID = '') and
            not (LEnvelopeRequestID is TJSONNull)) or
           ((LRequestID <> '') and
            (not (LEnvelopeRequestID is TJSONString) or
             not SameText(
                 TJSONString(LEnvelopeRequestID).Value,
                 LRequestID
             ))) then
            raise EGARPProtocolError.Create(
                'Header/envelope request_id mismatch'
            );

        if ((LSessionID = '') and
            not (LEnvelopeSessionID is TJSONNull)) or
           ((LSessionID <> '') and
            (not (LEnvelopeSessionID is TJSONString) or
             not SameText(
                 TJSONString(LEnvelopeSessionID).Value,
                 LSessionID
             ))) then
            raise EGARPProtocolError.Create(
                'Header/envelope session_id mismatch'
            );

        Result.MessageType := LMessageType;
        Result.RequestID := LRequestID;
        Result.SessionID := LSessionID;
        Result.Timestamp :=
            Result.MessageJSON.GetValue<string>('timestamp', '');
        Result.PayloadLength := LPayloadLength;
    except
        Result.MessageJSON.Free;
        Result.MessageJSON := nil;
        raise;
    end;
end;

function GARPReadFrame(
    AClient: TIdTCPClient;
    const AMaxPayloadBytes: Cardinal
): TBytes;
var
    LHeader: TIdBytes;
    LPayload: TIdBytes;
    LPayloadLength: Cardinal;
    LHeaderLength: Cardinal;
    LIndex: Integer;
begin
    SetLength(LHeader, GARP_FIXED_HEADER_LENGTH);
    AClient.IOHandler.ReadBytes(LHeader, GARP_FIXED_HEADER_LENGTH, False);

    if Length(LHeader) <> GARP_FIXED_HEADER_LENGTH then
        raise EGARPProtocolError.Create('Incomplete GARP header');

    if (LHeader[0] <> Ord('G')) or
       (LHeader[1] <> Ord('A')) or
       (LHeader[2] <> Ord('R')) or
       (LHeader[3] <> Ord('P')) then
        raise EGARPProtocolError.Create(
            'Invalid GARP magic received'
        );

    if LHeader[4] <> GARP_VERSION_BYTE then
        raise EGARPProtocolError.CreateFmt(
            'Unsupported GARP wire version: 0x%.2x',
            [LHeader[4]]
        );

    if LHeader[5] <> 0 then
        raise EGARPProtocolError.Create('Unsupported GARP flags');

    LHeaderLength :=
        (Cardinal(LHeader[6]) shl 8) or
        Cardinal(LHeader[7]);

    if LHeaderLength <> GARP_FIXED_HEADER_LENGTH then
        raise EGARPProtocolError.Create(
            'GARP header length must be exactly 48 bytes'
        );

    LPayloadLength :=
        (Cardinal(LHeader[8]) shl 24) or
        (Cardinal(LHeader[9]) shl 16) or
        (Cardinal(LHeader[10]) shl 8) or
        Cardinal(LHeader[11]);

    if LPayloadLength > AMaxPayloadBytes then
        raise EGARPProtocolError.CreateFmt(
            'GARP payload exceeds receive limit: %d > %d',
            [LPayloadLength, AMaxPayloadBytes]
        );

    SetLength(Result, GARP_FIXED_HEADER_LENGTH + LPayloadLength);

    for LIndex := 0 to GARP_FIXED_HEADER_LENGTH - 1 do
        Result[LIndex] := LHeader[LIndex];

    if LPayloadLength > 0 then
    begin
        SetLength(LPayload, LPayloadLength);
        AClient.IOHandler.ReadBytes(
            LPayload,
            LPayloadLength,
            False
        );

        if Cardinal(Length(LPayload)) <> LPayloadLength then
            raise EGARPProtocolError.Create(
                'Incomplete GARP payload'
            );

        Move(
            LPayload[0],
            Result[GARP_FIXED_HEADER_LENGTH],
            LPayloadLength
        );
    end;
end;

procedure GARPWriteFrame(
    AClient: TIdTCPClient;
    const AFrame: TBytes
);
var
    LBytes: TIdBytes;
begin
    if Length(AFrame) < GARP_FIXED_HEADER_LENGTH then
        raise EGARPProtocolError.Create(
            'Cannot send undersized GARP frame'
        );

    if Length(AFrame) >
       GARP_FIXED_HEADER_LENGTH + GARP_MAX_FRAME_SIZE then
        raise EGARPProtocolError.Create(
            'Cannot send a GARP frame exceeding configured maximum'
        );

    SetLength(LBytes, Length(AFrame));
    Move(AFrame[0], LBytes[0], Length(AFrame));
    AClient.IOHandler.Write(LBytes);
end;

function GARPWriteRead(
    AClient: TIdTCPClient;
    const AFrame: TBytes
): TBytes;
begin
    GARPWriteFrame(AClient, AFrame);
    Result := GARPReadFrame(AClient);
end;

function GARPCompareUTF8(
    const ALeft,
    ARight: string
): Integer;
var
    LLeft: TBytes;
    LRight: TBytes;
    LIndex: Integer;
    LLimit: Integer;
begin
    LLeft := TEncoding.UTF8.GetBytes(ALeft);
    LRight := TEncoding.UTF8.GetBytes(ARight);
    LLimit := Length(LLeft);

    if Length(LRight) < LLimit then
        LLimit := Length(LRight);

    for LIndex := 0 to LLimit - 1 do
    begin
        if LLeft[LIndex] < LRight[LIndex] then
            Exit(-1);
        if LLeft[LIndex] > LRight[LIndex] then
            Exit(1);
    end;

    if Length(LLeft) < Length(LRight) then
        Result := -1
    else if Length(LLeft) > Length(LRight) then
        Result := 1
    else
        Result := 0;
end;

function GARPStringCompare(
    const ALeft,
    ARight: string
): Integer;
begin
    Result := GARPCompareUTF8(ALeft, ARight);
end;

function GARPCanonicalFeatureList(
    const AFeatures: array of string
): TArray<string>;
var
    LIndex: Integer;
    LList: TList<string>;
    LValue: string;
begin
    LList :=
        TList<string>.Create(
            TComparer<string>.Construct(
                function(
                    const ALeft,
                    ARight: string
                ): Integer
                begin
                    Result := GARPStringCompare(
                        ALeft,
                        ARight
                    );
                end
            )
        );

    try
        for LIndex := Low(AFeatures) to High(AFeatures) do
        begin
            LValue := AFeatures[LIndex];

            if LValue = '' then
                raise EGARPProtocolError.Create(
                    'Empty GARP feature token'
                );

            if LList.Contains(LValue) then
                raise EGARPProtocolError.Create(
                    'Duplicate feature: ' + LValue
                );

            LList.Add(LValue);
        end;

        LList.Sort;
        Result := LList.ToArray;
    finally
        LList.Free;
    end;
end;

procedure GARPPutU32(
    var ABuffer: TBytes;
    var AOffset: Integer;
    const AValue: Cardinal
);
begin
    if AOffset + 4 > Length(ABuffer) then
        SetLength(ABuffer, AOffset + 4);

    ABuffer[AOffset] := Byte(AValue shr 24);
    ABuffer[AOffset + 1] := Byte(AValue shr 16);
    ABuffer[AOffset + 2] := Byte(AValue shr 8);
    ABuffer[AOffset + 3] := Byte(AValue);

    Inc(AOffset, 4);
end;

procedure GARPPutBytes(
    var ABuffer: TBytes;
    var AOffset: Integer;
    const AValue: TBytes
);
begin
    GARPPutU32(
        ABuffer,
        AOffset,
        Length(AValue)
    );

    if Length(AValue) > 0 then
    begin
        if AOffset + Length(AValue) > Length(ABuffer) then
            SetLength(
                ABuffer,
                AOffset + Length(AValue)
            );

        Move(
            AValue[0],
            ABuffer[AOffset],
            Length(AValue)
        );

        Inc(AOffset, Length(AValue));
    end;
end;

function GARPEncodeTranscript(
    const ADomain: string;
    const AClientNonce: TBytes;
    const AServerNonce: TBytes;
    const ASelectedVersion: string;
    const ASelectedWireVersion: string;
    const AOfferedFeatures: TArray<string>;
    const AFinalFeatures: TArray<string>;
    const AClientName: string;
    const AClientVersion: string;
    const AServerName: string;
    const AServerVersion: string
): TBytes;
var
    LOffset: Integer;
    LValue: TBytes;
    LFeature: string;
begin
    LOffset := 0;
    SetLength(Result, 0);

    LValue := TEncoding.UTF8.GetBytes(ADomain);
    GARPPutBytes(Result, LOffset, LValue);
    GARPPutBytes(Result, LOffset, AClientNonce);
    GARPPutBytes(Result, LOffset, AServerNonce);

    LValue := TEncoding.UTF8.GetBytes(ASelectedVersion);
    GARPPutBytes(Result, LOffset, LValue);

    LValue := TEncoding.UTF8.GetBytes(ASelectedWireVersion);
    GARPPutBytes(Result, LOffset, LValue);

    GARPPutU32(
        Result,
        LOffset,
        Length(AOfferedFeatures)
    );

    for LFeature in AOfferedFeatures do
    begin
        LValue := TEncoding.UTF8.GetBytes(LFeature);
        GARPPutBytes(Result, LOffset, LValue);
    end;

    GARPPutU32(
        Result,
        LOffset,
        Length(AFinalFeatures)
    );

    for LFeature in AFinalFeatures do
    begin
        LValue := TEncoding.UTF8.GetBytes(LFeature);
        GARPPutBytes(Result, LOffset, LValue);
    end;

    LValue := TEncoding.UTF8.GetBytes(AClientName);
    GARPPutBytes(Result, LOffset, LValue);

    LValue := TEncoding.UTF8.GetBytes(AClientVersion);
    GARPPutBytes(Result, LOffset, LValue);

    LValue := TEncoding.UTF8.GetBytes(AServerName);
    GARPPutBytes(Result, LOffset, LValue);

    LValue := TEncoding.UTF8.GetBytes(AServerVersion);
    GARPPutBytes(Result, LOffset, LValue);
end;

function GARPHMACSHA256(
    const ASecret: string;
    const AData: TBytes
): TBytes;
begin
    Result :=
        THashSHA2.GetHMACAsBytes(
            AData,
            TEncoding.UTF8.GetBytes(ASecret),
            SHA256
        );
end;

function GARPMakeProof(
    const ASecret: string;
    const ADomain: string;
    const AClientNonce: TBytes;
    const AServerNonce: TBytes;
    const AOfferedFeatures: TArray<string>;
    const AFinalFeatures: TArray<string>;
    const AClientName: string;
    const AClientVersion: string;
    const AServerName: string;
    const AServerVersion: string
): TBytes;
var
    LTranscript: TBytes;
begin
    LTranscript :=
        GARPEncodeTranscript(
            ADomain,
            AClientNonce,
            AServerNonce,
            GARP_SEMANTIC_VERSION,
            GARP_WIRE_VERSION,
            AOfferedFeatures,
            AFinalFeatures,
            AClientName,
            AClientVersion,
            AServerName,
            AServerVersion
        );

    Result :=
        GARPHMACSHA256(
            ASecret,
            LTranscript
        );
end;

function GARPJSONObjectPayload(
    const AFrame: TGARPFrame
): TJSONObject;
begin
    if AFrame.MessageJSON = nil then
        raise EGARPProtocolError.Create(
            'GARP frame JSON is nil'
        );

    Result :=
        AFrame.MessageJSON.GetValue<TJSONObject>('payload');

    if Result = nil then
        raise EGARPProtocolError.Create(
            'GARP frame payload is not an object'
        );
end;

function GARPFrameRequestIDMatches(
    const AFrame: TGARPFrame;
    const ARequestID: string
): Boolean;
begin
    Result := SameText(
        AFrame.RequestID,
        ARequestID
    );
end;

function GARPFramePromptRequestID(
    const AFrame: TGARPFrame
): string;
var
    LPayload: TJSONObject;
begin
    LPayload := GARPJSONObjectPayload(AFrame);
    Result :=
        LPayload.GetValue<string>(
            'prompt_request_id',
            ''
        );
end;

end.
