unit GSDAPeerAdapterV2;

interface

uses
  System.SysUtils,
  System.JSON,
  GSDAKernelV2,
  GSDAIdentityValidation,
  GSDAIdentityFactory;

type
  // Trust zones for incoming messages
  TPeerTrustZone = (
    tzUnknown,
    tzT1Peer,        // allowed
    tzT2Peer,        // allowed
    tzUntrusted      // blocked
  );

  // Sanitized + validated peer message
  TSanitizedPeerMessage = record
    PeerID: string;
    RunID: string;
    TaskID: string;
    RoundID: string;
    MsgType: Integer;
    Confidence: Integer;
    Payload: TJSONObject;
    ExecutionIdentity: string;
  end;

  // Peer adapter V2
  TGSDAPeerAdapterV2 = class
  private
    FKernel: TGSDAKernelV2;

    function DetermineTrustZone(const PeerID: string): TPeerTrustZone;
    procedure ValidateTrustZone(const Zone: TPeerTrustZone; const PeerID: string);

    function ParsePayload(const Raw: string): TJSONObject;
    procedure ValidateSchema(const Payload: TJSONObject);
    procedure ValidateConfidence(Value: Integer);
    procedure ValidateMessageType(Value: Integer);

    function BuildExecutionIdentity(const PeerID, RunID, RoundID: string;
                                    Payload: TJSONObject): string;

  public
    constructor Create(AKernel: TGSDAKernelV2);

    function SanitizeAndValidate(const PeerID, RunID, TaskID, RoundID: string;
                                 MsgType: Integer; Confidence: Integer;
                                 const RawPayload: string): TSanitizedPeerMessage;
  end;

implementation

{ TGSDAPeerAdapterV2 }

constructor TGSDAPeerAdapterV2.Create(AKernel: TGSDAKernelV2);
begin
  FKernel := AKernel;
end;

function TGSDAPeerAdapterV2.DetermineTrustZone(const PeerID: string): TPeerTrustZone;
begin
  if PeerID.StartsWith('t1:') then
    Exit(tzT1Peer);

  if PeerID.StartsWith('t2:') then
    Exit(tzT2Peer);

  Result := tzUntrusted;
end;

procedure TGSDAPeerAdapterV2.ValidateTrustZone(const Zone: TPeerTrustZone; const PeerID: string);
begin
  if Zone = tzUntrusted then
    raise Exception.CreateFmt('Peer "%s" is not allowed to send messages', [PeerID]);
end;

function TGSDAPeerAdapterV2.ParsePayload(const Raw: string): TJSONObject;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.ParseJSONValue(Raw) as TJSONObject;
  if Obj = nil then
    raise Exception.Create('Malformed JSON payload');
  Result := Obj;
end;

procedure TGSDAPeerAdapterV2.ValidateSchema(const Payload: TJSONObject);
begin
  if Payload.GetValue('schema') = nil then
    raise Exception.Create('Payload missing schema field');

  if not Payload.GetValue('schema').Value.StartsWith('gsp/') then
    raise Exception.Create('Invalid payload schema');
end;

procedure TGSDAPeerAdapterV2.ValidateConfidence(Value: Integer);
begin
  if (Value < 1) or (Value > 1000) then
    raise Exception.CreateFmt('Invalid confidence value: %d', [Value]);
end;

procedure TGSDAPeerAdapterV2.ValidateMessageType(Value: Integer);
begin
  if (Value < Ord(mtCandidate)) or (Value > Ord(mtConsolidation)) then
    raise Exception.CreateFmt('Invalid message type: %d', [Value]);
end;

function TGSDAPeerAdapterV2.BuildExecutionIdentity(const PeerID, RunID, RoundID: string;
                                                   Payload: TJSONObject): string;
var
  Extra: TJSONObject;
begin
  Extra := TJSONObject.Create;
  try
    Extra.AddPair('payload_schema', Payload.GetValue('schema').Value);
    Extra.AddPair('content_id', Payload.GetValue('content_id', ''));

    Result := TGSDAIdentityFactory.MakeExecution(
      'message_identity/3.1',
      RunID,
      PeerID,
      RoundID,
      Extra
    ).Value;
  finally
    Extra.Free;
  end;
end;

function TGSDAPeerAdapterV2.SanitizeAndValidate(const PeerID, RunID, TaskID, RoundID: string;
                                                MsgType: Integer; Confidence: Integer;
                                                const RawPayload: string): TSanitizedPeerMessage;
var
  Zone: TPeerTrustZone;
  Payload: TJSONObject;
  ExecID: string;
begin
  // 1. Trust zone check
  Zone := DetermineTrustZone(PeerID);
  ValidateTrustZone(Zone, PeerID);

  // 2. Parse payload
  Payload := ParsePayload(RawPayload);

  // 3. Schema validation
  ValidateSchema(Payload);

  // 4. Confidence validation
  ValidateConfidence(Confidence);

  // 5. Message type validation
  ValidateMessageType(MsgType);

  // 6. Build execution identity
  ExecID := BuildExecutionIdentity(PeerID, RunID, RoundID, Payload);

  // 7. Return sanitized message
  Result.PeerID := PeerID;
  Result.RunID := RunID;
  Result.TaskID := TaskID;
  Result.RoundID := RoundID;
  Result.MsgType := MsgType;
  Result.Confidence := Confidence;
  Result.Payload := Payload;
  Result.ExecutionIdentity := ExecID;
end;

end.
