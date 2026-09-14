unit GARP101.Protocol;

interface

uses
    System.SysUtils,
    System.JSON,
    System.Hash,
    IdTCPClient,
    IdGlobal;

const
    GARP_PROTOCOL = 'GARP/1.01';
    GARP_VERSION_BYTE = $11;
    GARP_MAGIC_0 = Ord('G');
    GARP_MAGIC_1 = Ord('A');
    GARP_MAGIC_2 = Ord('R');
    GARP_MAGIC_3 = Ord('P');
    GARP_FIXED_HEADER_LENGTH = 48;
    GARP_DEFAULT_PORT = 9999;
    GARP_MAX_FRAME_SIZE = 16 * 1024 * 1024;
    GARP_READ_TIMEOUT = 10000;

    GARP_ZERO_UUID = '00000000-0000-0000-0000-000000000000';

type
    TGARPMessageType = Word;

const
    GARP_HELLO = $0001;
    GARP_HELLO_ACK = $0002;
    GARP_CAPABILITIES = $0003;
    GARP_BROWSER_STATUS = $0004;
    GARP_HELLO_CHALLENGE = $0005;
    GARP_RESPONSE = $0006;
    GARP_HELLO_AUTH = $0007;

    GARP_LIST_TABS = $0010;
    GARP_OPEN_TAB = $0011;
    GARP_CLOSE_TAB = $0012;
    GARP_SELECT_TAB = $0013;

    GARP_CREATE_SESSION = $0020;
    GARP_ATTACH_SESSION = $0021;
    GARP_DETACH_SESSION = $0022;
    GARP_CLOSE_SESSION = $0023;
    GARP_RESET_SESSION = $0024;

    GARP_PROMPT = $0030;
    GARP_PROMPT_ACK = $0031;
    GARP_CANCEL_PROMPT = $0032;
    GARP_CANCEL_ACK = $0033;
    GARP_GET_PROMPT_STATUS = $0034;
    GARP_GET_RESPONSE = $0035;
    GARP_SUBSCRIBE_RESPONSE = $0036;

    GARP_SESSION_READY = $0040;
    GARP_SESSION_CHANGED = $0041;
    GARP_INPUT_SUBMITTED = $0042;
    GARP_GENERATION_STARTED = $0043;
    GARP_GENERATION_DELTA = $0044;
    GARP_GENERATION_PROGRESS = $0045;
    GARP_CONTINUATION_REQUIRED = $0046;
    GARP_CONTINUATION_SUBMITTED = $0047;
    GARP_GENERATION_COMPLETED = $0048;
    GARP_GENERATION_FAILED = $0049;

    GARP_NAVIGATION = $0050;
    GARP_PROVIDER_ERROR = $0051;
    GARP_AUTH_REQUIRED = $0052;
    GARP_RATE_LIMITED = $0053;
    GARP_DIAGNOSTIC = $0054;

    GARP_PING = $0060;
    GARP_PONG = $0061;

    GARP_ERROR = $00F0;

type
    EGARPProtocolError = class(Exception);

    TGARPFrame = record
        MessageType: TGARPMessageType;
        RequestID: string;
        SessionID: string;
        MessageJSON: TJSONObject;
    end;

function GARPMessageTypeToName(const AMessageType: TGARPMessageType): string;
function GARPMessageNameToType(const AName: string): TGARPMessageType;
function GARPNewUUID: string;
function GARPCreateNonce: string;
function GARPUUIDToBytes(const AValue: string): TBytes;
function GARPBytesToUUID(const ABytes: TBytes; const AOffset: Integer): string;
function GARPBuildJSON(const ATypeName: string; const APayload: TJSONValue;
    const ARequestID: string = ''; const ASessionID: string = ''): TJSONObject;
function GARPEncodeFrame(const AMessageType: TGARPMessageType; const AJSON: TJSONObject;
    const ARequestID: string = ''; const ASessionID: string = ''): TBytes;
function GARPDecodeFrame(const AFrame: TBytes): TGARPFrame;
function GARPHMACSHA256Hex(const ASecret, AText: string): string;
function GARPMakeHMACProof(const ASecret, AClientID, AClientNonce, AServerNonce: string): string;
function GARPReadFrame(AClient: TIdTCPClient): TBytes;
procedure GARPWriteFrame(AClient: TIdTCPClient; const AFrame: TBytes);
function GARPWriteRead(AClient: TIdTCPClient; const AFrame: TBytes): TBytes;

implementation

function GARPMessageTypeToName(const AMessageType: TGARPMessageType): string;
begin
    case AMessageType of
        GARP_HELLO: Result := 'hello';
        GARP_HELLO_ACK: Result := 'hello_ack';
        GARP_CAPABILITIES: Result := 'capabilities';
        GARP_BROWSER_STATUS: Result := 'browser_status';
        GARP_HELLO_CHALLENGE: Result := 'hello_challenge';
        GARP_RESPONSE: Result := 'response';
        GARP_HELLO_AUTH: Result := 'hello_auth';

        GARP_LIST_TABS: Result := 'list_tabs';
        GARP_OPEN_TAB: Result := 'open_tab';
        GARP_CLOSE_TAB: Result := 'close_tab';
        GARP_SELECT_TAB: Result := 'select_tab';

        GARP_CREATE_SESSION: Result := 'create_session';
        GARP_ATTACH_SESSION: Result := 'attach_session';
        GARP_DETACH_SESSION: Result := 'detach_session';
        GARP_CLOSE_SESSION: Result := 'close_session';
        GARP_RESET_SESSION: Result := 'reset_session';

        GARP_PROMPT: Result := 'prompt';
        GARP_PROMPT_ACK: Result := 'prompt_ack';
        GARP_CANCEL_PROMPT: Result := 'cancel_prompt';
        GARP_CANCEL_ACK: Result := 'cancel_ack';
        GARP_GET_PROMPT_STATUS: Result := 'get_prompt_status';
        GARP_GET_RESPONSE: Result := 'get_response';
        GARP_SUBSCRIBE_RESPONSE: Result := 'subscribe_response';

        GARP_SESSION_READY: Result := 'session_ready';
        GARP_SESSION_CHANGED: Result := 'session_changed';
        GARP_INPUT_SUBMITTED: Result := 'input_submitted';
        GARP_GENERATION_STARTED: Result := 'generation_started';
        GARP_GENERATION_DELTA: Result := 'generation_delta';
        GARP_GENERATION_PROGRESS: Result := 'generation_progress';
        GARP_CONTINUATION_REQUIRED: Result := 'continuation_required';
        GARP_CONTINUATION_SUBMITTED: Result := 'continuation_submitted';
        GARP_GENERATION_COMPLETED: Result := 'generation_completed';
        GARP_GENERATION_FAILED: Result := 'generation_failed';

        GARP_NAVIGATION: Result := 'navigation';
        GARP_PROVIDER_ERROR: Result := 'provider_error';
        GARP_AUTH_REQUIRED: Result := 'auth_required';
        GARP_RATE_LIMITED: Result := 'rate_limited';
        GARP_DIAGNOSTIC: Result := 'diagnostic';

        GARP_PING: Result := 'ping';
        GARP_PONG: Result := 'pong';

        GARP_ERROR: Result := 'error';
    else
        Result := '';
    end;
end;

function GARPMessageNameToType(const AName: string): TGARPMessageType;
const
    CMessageTypes: array[0..39] of TGARPMessageType = (
        GARP_HELLO,
        GARP_HELLO_ACK,
        GARP_CAPABILITIES,
        GARP_BROWSER_STATUS,
        GARP_HELLO_CHALLENGE,
        GARP_RESPONSE,
        GARP_HELLO_AUTH,
        GARP_LIST_TABS,
        GARP_OPEN_TAB,
        GARP_CLOSE_TAB,
        GARP_SELECT_TAB,
        GARP_CREATE_SESSION,
        GARP_ATTACH_SESSION,
        GARP_DETACH_SESSION,
        GARP_CLOSE_SESSION,
        GARP_RESET_SESSION,
        GARP_PROMPT,
        GARP_PROMPT_ACK,
        GARP_CANCEL_PROMPT,
        GARP_CANCEL_ACK,
        GARP_GET_PROMPT_STATUS,
        GARP_GET_RESPONSE,
        GARP_SUBSCRIBE_RESPONSE,
        GARP_SESSION_READY,
        GARP_SESSION_CHANGED,
        GARP_INPUT_SUBMITTED,
        GARP_GENERATION_STARTED,
        GARP_GENERATION_DELTA,
        GARP_GENERATION_PROGRESS,
        GARP_CONTINUATION_REQUIRED,
        GARP_CONTINUATION_SUBMITTED,
        GARP_GENERATION_COMPLETED,
        GARP_GENERATION_FAILED,
        GARP_NAVIGATION,
        GARP_PROVIDER_ERROR,
        GARP_AUTH_REQUIRED,
        GARP_RATE_LIMITED,
        GARP_DIAGNOSTIC,
        GARP_PING,
        GARP_PONG
    );
var
    LName: string;
    LIndex: Integer;
    LMessageType: TGARPMessageType;
begin
    LName := LowerCase(Trim(AName));

    for LIndex := Low(CMessageTypes) to High(CMessageTypes) do
    begin
        LMessageType := CMessageTypes[LIndex];
        if SameText(GARPMessageTypeToName(LMessageType), LName) then
            Exit(LMessageType);
    end;

    if SameText(GARPMessageTypeToName(GARP_ERROR), LName) then
        Exit(GARP_ERROR);

    Result := 0;
end;

function GARPNewUUID: string;
var
    LGuid: TGUID;
begin
    CreateGUID(LGuid);
    Result := GUIDToString(LGuid);
    Result := Copy(Result, 2, Length(Result) - 2);
    Result := LowerCase(Result);
end;

function GARPCreateNonce: string;
begin
    Result := GARPNewUUID;
end;

function GARPUUIDToBytes(const AValue: string): TBytes;
var
    LText: string;
    LIndex: Integer;
    LHex: string;
    LValue: Integer;
begin
    SetLength(Result, 16);

    if AValue = '' then
        Exit;

    if SameText(AValue, GARP_ZERO_UUID) then
        Exit;

    LText := LowerCase(StringReplace(AValue, '-', '', [rfReplaceAll]));

    if Length(LText) <> 32 then
        raise EGARPProtocolError.Create('Invalid UUID length: ' + AValue);

    for LIndex := 1 to Length(LText) do
    begin
        if not CharInSet(LText[LIndex], ['0'..'9', 'a'..'f']) then
            raise EGARPProtocolError.Create(
                'Invalid UUID hexadecimal data: ' + AValue);
    end;

    for LIndex := 0 to 15 do
    begin
        LHex := Copy(LText, LIndex * 2 + 1, 2);

        if not TryStrToInt('$' + LHex, LValue) then
            raise EGARPProtocolError.Create(
                'Invalid UUID byte: ' + AValue);

        Result[LIndex] := Byte(LValue);
    end;
end;

function GARPBytesToUUID(const ABytes: TBytes; const AOffset: Integer): string;
var
    LIndex: Integer;
    LText: string;
    LZero: Boolean;
begin
    if (AOffset < 0) or (Length(ABytes) < AOffset + 16) then
        raise EGARPProtocolError.Create('UUID field is truncated');

    LText := '';
    LZero := True;

    for LIndex := 0 to 15 do
    begin
        LText := LText + IntToHex(ABytes[AOffset + LIndex], 2);

        if ABytes[AOffset + LIndex] <> 0 then
            LZero := False;
    end;

    if LZero then
        Exit('');

    Result :=
        Copy(LText, 1, 8) + '-' +
        Copy(LText, 9, 4) + '-' +
        Copy(LText, 13, 4) + '-' +
        Copy(LText, 17, 4) + '-' +
        Copy(LText, 21, 12);

    Result := LowerCase(Result);
end;

function GARPBuildJSON(const ATypeName: string; const APayload: TJSONValue;
    const ARequestID: string; const ASessionID: string): TJSONObject;
begin
    Result := TJSONObject.Create;
    Result.AddPair('protocol', GARP_PROTOCOL);
    Result.AddPair('type', LowerCase(ATypeName));

    if ARequestID <> '' then
        Result.AddPair('request_id', ARequestID);

    if ASessionID <> '' then
        Result.AddPair('session_id', ASessionID);

    if APayload <> nil then
        Result.AddPair('payload', APayload)
    else
        Result.AddPair('payload', TJSONObject.Create);
end;

function GARPEncodeFrame(const AMessageType: TGARPMessageType;
    const AJSON: TJSONObject; const ARequestID: string;
    const ASessionID: string): TBytes;
var
    LPayload: UTF8String;
    LPayloadLength: Cardinal;
    LHeaderLength: Word;
    LPayloadBytes: TBytes;
    LRequestBytes: TBytes;
    LSessionBytes: TBytes;
    LIndex: Integer;
begin
    if GARPMessageTypeToName(AMessageType) = '' then
        raise EGARPProtocolError.CreateFmt(
            'Unknown message type: %d', [AMessageType]);

    if AJSON = nil then
        raise EGARPProtocolError.Create('JSON message is nil');

    LPayload := UTF8String(AJSON.ToJSON);
    LPayloadBytes := TBytes(LPayload);
    LPayloadLength := Length(LPayloadBytes);
    LHeaderLength := GARP_FIXED_HEADER_LENGTH;

    if LPayloadLength > GARP_MAX_FRAME_SIZE then
        raise EGARPProtocolError.Create(
            'GARP payload exceeds configured maximum');

    SetLength(Result, GARP_FIXED_HEADER_LENGTH + LPayloadLength);

    Result[0] := GARP_MAGIC_0;
    Result[1] := GARP_MAGIC_1;
    Result[2] := GARP_MAGIC_2;
    Result[3] := GARP_MAGIC_3;

    Result[4] := GARP_VERSION_BYTE;
    Result[5] := 0;

    Result[6] := Byte(LHeaderLength shr 8);
    Result[7] := Byte(LHeaderLength and $FF);

    Result[8] := Byte(LPayloadLength shr 24);
    Result[9] := Byte(LPayloadLength shr 16);
    Result[10] := Byte(LPayloadLength shr 8);
    Result[11] := Byte(LPayloadLength);

    Result[12] := Byte(AMessageType shr 8);
    Result[13] := Byte(AMessageType and $FF);

    Result[14] := 0;
    Result[15] := 0;

    LRequestBytes := GARPUUIDToBytes(ARequestID);
    LSessionBytes := GARPUUIDToBytes(ASessionID);

    for LIndex := 0 to 15 do
    begin
        Result[16 + LIndex] := LRequestBytes[LIndex];
        Result[32 + LIndex] := LSessionBytes[LIndex];
    end;

    if LPayloadLength > 0 then
    begin
        Move(
            LPayloadBytes[0],
            Result[GARP_FIXED_HEADER_LENGTH],
            LPayloadLength
        );
    end;
end;

function GARPDecodeFrame(const AFrame: TBytes): TGARPFrame;
var
    LHeaderLength: Cardinal;
    LPayloadLength: Cardinal;
    LMessageType: TGARPMessageType;
    LPayload: string;
    LValue: TJSONValue;
    LMessageName: string;
    LExpectedName: string;
    LPayloadBytes: TBytes;
begin
    FillChar(Result, SizeOf(Result), 0);
    Result.MessageJSON := nil;

    if Length(AFrame) < GARP_FIXED_HEADER_LENGTH then
        raise EGARPProtocolError.Create(
            'GARP frame is shorter than the fixed header');

    if (AFrame[0] <> GARP_MAGIC_0) or
       (AFrame[1] <> GARP_MAGIC_1) or
       (AFrame[2] <> GARP_MAGIC_2) or
       (AFrame[3] <> GARP_MAGIC_3) then
    begin
        raise EGARPProtocolError.Create('Invalid GARP magic');
    end;

    if AFrame[4] <> GARP_VERSION_BYTE then
        raise EGARPProtocolError.CreateFmt(
            'Unsupported GARP version byte: %.2x', [AFrame[4]]);

    if AFrame[14] <> 0 then
        raise EGARPProtocolError.Create(
            'GARP reserved field is nonzero');

    if AFrame[15] <> 0 then
        raise EGARPProtocolError.Create(
            'GARP reserved field is nonzero');

    LHeaderLength :=
        (Cardinal(AFrame[6]) shl 8) or
        Cardinal(AFrame[7]);

    LPayloadLength :=
        (Cardinal(AFrame[8]) shl 24) or
        (Cardinal(AFrame[9]) shl 16) or
        (Cardinal(AFrame[10]) shl 8) or
        Cardinal(AFrame[11]);

    if LHeaderLength < GARP_FIXED_HEADER_LENGTH then
        raise EGARPProtocolError.Create(
            'Invalid GARP header length');

    if LHeaderLength + LPayloadLength <> Cardinal(Length(AFrame)) then
        raise EGARPProtocolError.Create(
            'GARP payload length mismatch');

    if LPayloadLength > GARP_MAX_FRAME_SIZE then
        raise EGARPProtocolError.Create(
            'GARP payload exceeds configured maximum');

    LMessageType :=
        (Word(AFrame[12]) shl 8) or
        Word(AFrame[13]);

    LExpectedName := GARPMessageTypeToName(LMessageType);

    if LExpectedName = '' then
        raise EGARPProtocolError.CreateFmt(
            'Unknown GARP message type: %.4x',
            [LMessageType]);

    LPayload := '';

    if LPayloadLength > 0 then
    begin
        SetLength(LPayloadBytes, LPayloadLength);

        Move(
            AFrame[LHeaderLength],
            LPayloadBytes[0],
            LPayloadLength
        );

        LPayload := TEncoding.UTF8.GetString(LPayloadBytes);
    end;

    LValue := TJSONObject.ParseJSONValue(LPayload);

    if not (LValue is TJSONObject) then
    begin
        LValue.Free;
        raise EGARPProtocolError.Create(
            'GARP payload is not a JSON object');
    end;

    Result.MessageJSON := TJSONObject(LValue);

    LMessageName :=
        Result.MessageJSON.GetValue<string>('type', '');

    if (Result.MessageJSON.GetValue<string>('protocol', '') <>
            GARP_PROTOCOL) or
       (not SameText(LMessageName, LExpectedName)) then
    begin
        Result.MessageJSON.Free;
        Result.MessageJSON := nil;

        raise EGARPProtocolError.Create(
            'GARP JSON protocol/type does not match the binary header');
    end;

    Result.MessageType := LMessageType;
    Result.RequestID := GARPBytesToUUID(AFrame, 16);
    Result.SessionID := GARPBytesToUUID(AFrame, 32);
end;

function GARPHMACSHA256Hex(const ASecret, AText: string): string;
var
    LData: TBytes;
    LDigest: TBytes;
    LIndex: Integer;
begin
    LData := TEncoding.UTF8.GetBytes(AText);

    LDigest :=
        THashSHA2.GetHMACAsBytes(
            LData,
            ASecret,
            SHA256
        );

    Result := '';

    for LIndex := 0 to High(LDigest) do
        Result := Result + IntToHex(LDigest[LIndex], 2);

    Result := LowerCase(Result);
end;

function GARPMakeHMACProof(const ASecret, AClientID, AClientNonce,
    AServerNonce: string): string;
begin
    Result :=
        GARPHMACSHA256Hex(
            ASecret,
            GARP_PROTOCOL + '|' +
            AClientID + '|' +
            AClientNonce + '|' +
            AServerNonce
        );
end;

function GARPReadFrame(AClient: TIdTCPClient): TBytes;
var
    LHeader: TIdBytes;
    LPayload: TIdBytes;
    LPayloadLength: Cardinal;
    LHeaderLength: Cardinal;
begin
    SetLength(LHeader, GARP_FIXED_HEADER_LENGTH);

    AClient.IOHandler.ReadBytes(
        LHeader,
        GARP_FIXED_HEADER_LENGTH,
        False
    );

    if Length(LHeader) < GARP_FIXED_HEADER_LENGTH then
        raise EGARPProtocolError.Create(
            'GARP header read was incomplete');

    if (LHeader[0] <> GARP_MAGIC_0) or
       (LHeader[1] <> GARP_MAGIC_1) or
       (LHeader[2] <> GARP_MAGIC_2) or
       (LHeader[3] <> GARP_MAGIC_3) then
    begin
        raise EGARPProtocolError.Create(
            'Invalid GARP magic received');
    end;

    if LHeader[4] <> GARP_VERSION_BYTE then
        raise EGARPProtocolError.CreateFmt(
            'Unsupported GARP version byte received: %.2x',
            [LHeader[4]]);

    LHeaderLength :=
        (Cardinal(LHeader[6]) shl 8) or
        Cardinal(LHeader[7]);

    LPayloadLength :=
        (Cardinal(LHeader[8]) shl 24) or
        (Cardinal(LHeader[9]) shl 16) or
        (Cardinal(LHeader[10]) shl 8) or
        Cardinal(LHeader[11]);

    if LHeaderLength < GARP_FIXED_HEADER_LENGTH then
        raise EGARPProtocolError.Create(
            'Invalid GARP header length received');

    if LHeaderLength <> GARP_FIXED_HEADER_LENGTH then
        raise EGARPProtocolError.Create(
            'Extended GARP headers are not supported by this tester yet');

    if LPayloadLength > GARP_MAX_FRAME_SIZE then
        raise EGARPProtocolError.Create(
            'Received GARP payload exceeds configured maximum');

    SetLength(Result, GARP_FIXED_HEADER_LENGTH + LPayloadLength);

    Move(
        LHeader[0],
        Result[0],
        GARP_FIXED_HEADER_LENGTH
    );

    if LPayloadLength > 0 then
    begin
        SetLength(LPayload, LPayloadLength);

        AClient.IOHandler.ReadBytes(
            LPayload,
            LPayloadLength,
            False
        );

        if Length(LPayload) <> Integer(LPayloadLength) then
            raise EGARPProtocolError.Create(
                'GARP payload read was incomplete');

        Move(
            LPayload[0],
            Result[GARP_FIXED_HEADER_LENGTH],
            LPayloadLength
        );
    end;
end;

procedure GARPWriteFrame(AClient: TIdTCPClient; const AFrame: TBytes);
var
    LIdBytes: TIdBytes;
begin
    if Length(AFrame) < GARP_FIXED_HEADER_LENGTH then
        raise EGARPProtocolError.Create(
            'Cannot send an undersized GARP frame');

    if Length(AFrame) > GARP_FIXED_HEADER_LENGTH + GARP_MAX_FRAME_SIZE then
        raise EGARPProtocolError.Create(
            'Cannot send a GARP frame exceeding configured maximum');

    SetLength(LIdBytes, Length(AFrame));

    if Length(AFrame) > 0 then
        Move(
            AFrame[0],
            LIdBytes[0],
            Length(AFrame)
        );

    AClient.IOHandler.Write(LIdBytes);
end;

function GARPWriteRead(AClient: TIdTCPClient;
    const AFrame: TBytes): TBytes;
begin
    GARPWriteFrame(AClient, AFrame);
    Result := GARPReadFrame(AClient);
end;

end.
