unit GSDA31.GARP;

interface

uses
    System.SysUtils,
    System.JSON,
    System.Classes,
    System.Generics.Collections,
    System.SyncObjs,
    IdContext,
    IdCustomTCPServer,
    IdTCPServer,
    IdGlobal,
    GSDA31,
    GSDA31.Agent,
    GSDA31.Gateway;

type
    EGSDA31GARPFailure = class(Exception);

    TGSDA31GARPServer = class
    private
        FServer: TIdTCPServer;
        FGateway: TGSDACommandGateway31;
        FLock: TCriticalSection;
        FMaxFrameBytes: Integer;
        FPort: Word;
        procedure HandleExecute(AContext: TIdContext);
        function ReadFrame(AContext: TIdContext): string;
        procedure WriteFrame(AContext: TIdContext; const AValue: string);
        function ProcessFrame(const AFrame: string): string;
    public
        constructor Create(
            AAgent: TGSDASpecAgent31;
            APort: Word = 9911;
            AMaxFrameBytes: Integer = 16 * 1024 * 1024
        );
        destructor Destroy; override;
        procedure Start;
        procedure Stop;
        function IsActive: Boolean;
        property Port: Word read FPort;
        property Active: Boolean read IsActive;
    end;

implementation

function GARPGetRequiredString(
    const AObject: TJSONObject; const AName: string): string;
begin
    Result := AObject.GetValue<string>(AName, '');
    if Result = '' then
        raise EGSDA31GARPFailure.Create('Missing GARP field: ' + AName);
end;

function GARPBuildErrorResponse(
    const ARequest: TJSONObject; const ACode, AMessage: string): string;
var
    LResponse: TJSONObject;
    LRequestID: string;
    LSessionID: string;
    LTabID: string;
    LSequence: Int64;
begin
    LRequestID := ARequest.GetValue<string>('request_id', '');
    LSessionID := ARequest.GetValue<string>('session_id', '');
    LTabID := ARequest.GetValue<string>('tab_id', '');
    LSequence := ARequest.GetValue<Int64>('sequence', 0);

    LResponse := TJSONObject.Create;
    try
        LResponse.AddPair('schema', 'garp/1.0');
        LResponse.AddPair('message_type', 'error');
        LResponse.AddPair('request_id', LRequestID);
        LResponse.AddPair('session_id', LSessionID);
        LResponse.AddPair('tab_id', LTabID);
        LResponse.AddPair('sequence', TJSONNumber.Create(LSequence));
        LResponse.AddPair('accepted', TJSONBool.Create(False));
        LResponse.AddPair('error_code', ACode);
        LResponse.AddPair('error_message', AMessage);
        Result := LResponse.ToJSON;
    finally
        LResponse.Free;
    end;
end;

constructor TGSDA31GARPServer.Create(
    AAgent: TGSDASpecAgent31; APort: Word; AMaxFrameBytes: Integer);
begin
    if AAgent = nil then
        raise EArgumentNilException.Create('Agent');
    if AMaxFrameBytes <= 0 then
        raise EArgumentOutOfRangeException.Create('AMaxFrameBytes');

    FGateway := TGSDACommandGateway31.Create(AAgent);
    FLock := TCriticalSection.Create;
    FMaxFrameBytes := AMaxFrameBytes;
    FPort := APort;
    FServer := TIdTCPServer.Create(nil);
    FServer.DefaultPort := FPort;
    FServer.OnExecute := HandleExecute;
end;

destructor TGSDA31GARPServer.Destroy;
begin
    Stop;
    FServer.Free;
    FLock.Free;
    FGateway.Free;
    inherited Destroy;
end;

procedure TGSDA31GARPServer.Start;
begin
    if not FServer.Active then
        FServer.Active := True;
end;

procedure TGSDA31GARPServer.Stop;
begin
    if FServer.Active then
        FServer.Active := False;
end;

function TGSDA31GARPServer.IsActive: Boolean;
begin
    Result := FServer.Active;
end;

function TGSDA31GARPServer.ReadFrame(AContext: TIdContext): string;
var
    LLength: UInt32;
    LByte: Byte;
    LIndex: Integer;
    LBytes: TIdBytes;
begin
    LLength := 0;
    for LIndex := 0 to 3 do
    begin
        LByte := AContext.Connection.IOHandler.ReadByte;
        LLength := (LLength shl 8) or LByte;
    end;

    if LLength = 0 then
        raise EGSDA31GARPFailure.Create('Empty GARP frame');
    if LLength > UInt32(FMaxFrameBytes) then
        raise EGSDA31GARPFailure.Create('GARP frame exceeds configured limit');

    SetLength(LBytes, Integer(LLength));
    AContext.Connection.IOHandler.ReadBytes(LBytes, Integer(LLength), False);
    Result := TEncoding.UTF8.GetString(LBytes);
end;

procedure TGSDA31GARPServer.WriteFrame(
    AContext: TIdContext; const AValue: string);
var
    LBytes: TIdBytes;
    LLength: UInt32;
    LPrefix: TIdBytes;
begin
    LBytes := TEncoding.UTF8.GetBytes(AValue);
    if Length(LBytes) = 0 then
        raise EGSDA31GARPFailure.Create('Cannot send empty GARP frame');
    if Length(LBytes) > FMaxFrameBytes then
        raise EGSDA31GARPFailure.Create('GARP response exceeds configured limit');

    LLength := UInt32(Length(LBytes));
    SetLength(LPrefix, 4);
    LPrefix[0] := Byte((LLength shr 24) and $FF);
    LPrefix[1] := Byte((LLength shr 16) and $FF);
    LPrefix[2] := Byte((LLength shr 8) and $FF);
    LPrefix[3] := Byte(LLength and $FF);

    AContext.Connection.IOHandler.Write(LPrefix);
    AContext.Connection.IOHandler.Write(LBytes);
end;

function TGSDA31GARPServer.ProcessFrame(const AFrame: string): string;
var
    LValue: TJSONValue;
    LRequest: TJSONObject;
    LCommand: TJSONObject;
    LResponsePayload: TJSONObject;
    LResponse: TJSONObject;
    LSchema: string;
    LMessageType: string;
    LRequestID: string;
    LSessionID: string;
    LTabID: string;
    LSequence: Int64;
begin
    LValue := TJSONObject.ParseJSONValue(Trim(AFrame));
    if not (LValue is TJSONObject) then
    begin
        LValue.Free;
        raise EGSDA31GARPFailure.Create('GARP frame is not a JSON object');
    end;

    LRequest := TJSONObject(LValue);
    try
        LSchema := LRequest.GetValue<string>('schema', '');
        if LSchema <> 'garp/1.0' then
            raise EGSDA31GARPFailure.Create('Unsupported GARP schema');

        LMessageType := LRequest.GetValue<string>('message_type', '');
        if LMessageType <> 'command' then
            raise EGSDA31GARPFailure.Create('GARP request message_type must be command');

        LRequestID := GARPGetRequiredString(LRequest, 'request_id');
        LSessionID := GARPGetRequiredString(LRequest, 'session_id');
        LTabID := GARPGetRequiredString(LRequest, 'tab_id');
        LSequence := LRequest.GetValue<Int64>('sequence', 0);
        if LSequence <= 0 then
            raise EGSDA31GARPFailure.Create('GARP sequence must be positive');

        if not (LRequest.GetValue('payload') is TJSONObject) then
            raise EGSDA31GARPFailure.Create('GARP payload object is required');
        LCommand := LRequest.GetValue('payload') as TJSONObject;

        FLock.Acquire;
        try
            LResponsePayload := FGateway.Execute(LCommand);
        finally
            FLock.Release;
        end;

        LResponse := TJSONObject.Create;
        try
            LResponse.AddPair('schema', 'garp/1.0');
            LResponse.AddPair('message_type', 'command_response');
            LResponse.AddPair('request_id', LRequestID);
            LResponse.AddPair('session_id', LSessionID);
            LResponse.AddPair('tab_id', LTabID);
            LResponse.AddPair('sequence', TJSONNumber.Create(LSequence));
            LResponse.AddPair('payload', LResponsePayload);
            Result := LResponse.ToJSON;
        finally
            LResponse.Free;
        end;
    except
        on E: EGSDA31GARPFailure do
            Result := GARPBuildErrorResponse(LRequest, 'GARP_PROTOCOL_FAILURE', E.Message);
        on E: Exception do
            Result := GARPBuildErrorResponse(LRequest, 'GARP_INTERNAL_FAILURE', E.Message);
    end;
end;

procedure TGSDA31GARPServer.HandleExecute(AContext: TIdContext);
var
    LFrame: string;
    LResponse: string;
begin
    try
        LFrame := ReadFrame(AContext);
        LResponse := ProcessFrame(LFrame);
        WriteFrame(AContext, LResponse);
    except
        on E: Exception do
            AContext.Connection.Disconnect;
    end;
end;

end.
