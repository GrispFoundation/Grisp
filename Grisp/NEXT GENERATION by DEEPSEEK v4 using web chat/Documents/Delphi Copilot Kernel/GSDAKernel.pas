unit GSDAKernel;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON;

type
  // Basic identity types
  TGSDAId = string;

  // Trust zones
  TTrustZone = (tzT0, tzT1, tzT2, tzT3, tzT4, tzT5, tzT6, tzT7);

  // Exception types
  EProtocolFailure = class(Exception);
  ESchemaFailure   = class(Exception);
  EPublicationFailure = class(Exception);

  // Task record
  TTask = class
  public
    TaskID: TGSDAId;
    TargetContextID: TGSDAId;
    UserPrompt: string;
    UserIntent: string;
    Domain: string;
    Namespace: string;
    TargetLanguage: string;
    TargetAudience: TArray<string>;
    Constraints: TArray<string>;
    RequestedOutputs: TArray<string>;
    PriorityProfile: string;
    CreatedAt: TDateTime;
    Metadata: TJSONObject;
  end;

  // Run record
  TRun = class
  public
    RunID: TGSDAId;
    TaskID: TGSDAId;
    TargetContextID: TGSDAId;
    StartedAt: TDateTime;
    CoordinatorVersion: string;
    KernelVersion: string;
    SchemaProfile: string;
    ReferenceSemanticsVersion: string;
    InitialConfigID: TGSDAId;
    LogicalSequenceBase: Int64;
  end;

  // Message envelope
  TMessageType = (mtCandidate, mtCritique, mtRepair, mtScore,
                  mtRequirement, mtTerm, mtQuestion, mtConsolidation);

  TMessageEnvelope = class
  public
    Schema: string;        // "gsp/3.1"
    MessageID: TGSDAId;
    MsgType: TMessageType;
    PeerID: TGSDAId;
    RunID: TGSDAId;
    TaskID: TGSDAId;
    RoundID: TGSDAId;
    ParentIDs: TArray<TGSDAId>;
    Confidence: Integer;   // 1..1000
    Payload: TJSONObject;
  end;

  // Authoritative state (simplified)
  TAuthoritativeState = class
  private
    FRuns: TObjectList<TRun>;
    FTasks: TObjectList<TTask>;
    FMessages: TObjectList<TMessageEnvelope>;
  public
    constructor Create;
    destructor Destroy; override;

    procedure AddRun(ARun: TRun);
    procedure AddTask(ATask: TTask);
    procedure AddMessage(AMsg: TMessageEnvelope);

    function FindRun(const RunID: TGSDAId): TRun;
    function FindTask(const TaskID: TGSDAId): TTask;
  end;

  // Kernel interface
  TGSDAKernel = class
  private
    FState: TAuthoritativeState;
    FKernelVersion: string;

    function CanonicalIdentityObject(const Obj: TJSONObject): string;
    function SHA256Hex(const S: string): string;

    function SortStrings(const Arr: TArray<string>): TArray<string>;

    function ComputeTaskID(ATask: TTask): TGSDAId;
    function ComputeTargetContextID(ATask: TTask): TGSDAId;
    function NewRunID: TGSDAId;
    function NewRoundID(const RunID: TGSDAId; RoundIndex: Integer): TGSDAId;
    function ComputeMessageID(AMsg: TMessageEnvelope): TGSDAId;

    procedure ValidateMessageEnvelope(AMsg: TMessageEnvelope);
    procedure ValidateConfidence(Confidence: Integer);
    procedure ValidateSchema(const Schema: string);
  public
    constructor Create;
    destructor Destroy; override;

    function CreateTask(const UserPrompt, UserIntent, Domain,
                        Namespace, TargetLanguage: string;
                        const TargetAudience, Constraints,
                        RequestedOutputs: TArray<string>;
                        const PriorityProfile: string): TTask;

    function StartRun(ATask: TTask): TRun;

    function ProcessIncomingFromT1(const RawPayload: string;
                                   const PeerID, RunID, TaskID, RoundID: TGSDAId;
                                   MsgType: TMessageType;
                                   Confidence: Integer): TMessageEnvelope;

    property State: TAuthoritativeState read FState;
  end;

implementation

uses
  System.Hash,
  System.DateUtils;

{ TAuthoritativeState }

constructor TAuthoritativeState.Create;
begin
  FRuns := TObjectList<TRun>.Create(True);
  FTasks := TObjectList<TTask>.Create(True);
  FMessages := TObjectList<TMessageEnvelope>.Create(True);
end;

destructor TAuthoritativeState.Destroy;
begin
  FRuns.Free;
  FTasks.Free;
  FMessages.Free;
  inherited;
end;

procedure TAuthoritativeState.AddRun(ARun: TRun);
begin
  FRuns.Add(ARun);
end;

procedure TAuthoritativeState.AddTask(ATask: TTask);
begin
  FTasks.Add(ATask);
end;

procedure TAuthoritativeState.AddMessage(AMsg: TMessageEnvelope);
begin
  FMessages.Add(AMsg);
end;

function TAuthoritativeState.FindRun(const RunID: TGSDAId): TRun;
var
  R: TRun;
begin
  Result := nil;
  for R in FRuns do
    if R.RunID = RunID then
      Exit(R);
end;

function TAuthoritativeState.FindTask(const TaskID: TGSDAId): TTask;
var
  T: TTask;
begin
  Result := nil;
  for T in FTasks do
    if T.TaskID = TaskID then
      Exit(T);
end;

{ TGSDAKernel }

constructor TGSDAKernel.Create;
begin
  FState := TAuthoritativeState.Create;
  FKernelVersion := '3.1';
end;

destructor TGSDAKernel.Destroy;
begin
  FState.Free;
  inherited;
end;

function TGSDAKernel.SHA256Hex(const S: string): string;
begin
  Result := THashSHA2.GetHashString(S);
end;

function TGSDAKernel.SortStrings(const Arr: TArray<string>): TArray<string>;
var
  L: TList<string>;
  S: string;
begin
  L := TList<string>.Create;
  try
    for S in Arr do
      L.Add(S);
    L.Sort;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function TGSDAKernel.CanonicalIdentityObject(const Obj: TJSONObject): string;
begin
  // Placeholder: here you implement RFC 8785-style canonical JSON:
  // - sort keys by UTF-8 bytewise order
  // - reject duplicate keys
  // - normalize numbers, timestamps, etc.
  // For now, we use Obj.ToJSON as a stand-in.
  Result := Obj.ToJSON;
end;

function TGSDAKernel.ComputeTaskID(ATask: TTask): TGSDAId;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema', 'task_identity/3.1');
    Obj.AddPair('user_prompt', ATask.UserPrompt);
    Obj.AddPair('user_intent', ATask.UserIntent);
    Obj.AddPair('domain', ATask.Domain);
    Obj.AddPair('target_audience',
      TJSONArray.Create(SortStrings(ATask.TargetAudience)));
    Obj.AddPair('constraints',
      TJSONArray.Create(SortStrings(ATask.Constraints)));
    Obj.AddPair('requested_outputs',
      TJSONArray.Create(SortStrings(ATask.RequestedOutputs)));
    Obj.AddPair('priority_profile', ATask.PriorityProfile);

    Result := 'task:' + SHA256Hex(CanonicalIdentityObject(Obj));
  finally
    Obj.Free;
  end;
end;

function TGSDAKernel.ComputeTargetContextID(ATask: TTask): TGSDAId;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema', 'target_context_identity/3.1');
    Obj.AddPair('task_id', ATask.TaskID);
    Obj.AddPair('namespace', ATask.Namespace);
    Obj.AddPair('target_language', ATask.TargetLanguage);

    Result := 'ctx:' + SHA256Hex(CanonicalIdentityObject(Obj));
  finally
    Obj.Free;
  end;
end;

function TGSDAKernel.NewRunID: TGSDAId;
begin
  // UUID v4 stand-in using GUID
  Result := 'run:' + GUIDToString(TGUID.NewGuid);
end;

function TGSDAKernel.NewRoundID(const RunID: TGSDAId; RoundIndex: Integer): TGSDAId;
begin
  Result := 'round:' + RunID + ':' + IntToStr(RoundIndex);
end;

function TGSDAKernel.ComputeMessageID(AMsg: TMessageEnvelope): TGSDAId;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema', 'message_identity/3.1');
    Obj.AddPair('run_id', AMsg.RunID);
    Obj.AddPair('peer_id', AMsg.PeerID);
    Obj.AddPair('payload_schema', AMsg.Payload.GetValue<string>('schema', ''));
    Obj.AddPair('content_id', AMsg.Payload.GetValue<string>('content_id', ''));

    Result := 'msg:' + SHA256Hex(CanonicalIdentityObject(Obj));
  finally
    Obj.Free;
  end;
end;

procedure TGSDAKernel.ValidateConfidence(Confidence: Integer);
begin
  if (Confidence < 1) or (Confidence > 1000) then
    raise EProtocolFailure.CreateFmt('Invalid confidence: %d', [Confidence]);
end;

procedure TGSDAKernel.ValidateSchema(const Schema: string);
begin
  if Schema = '' then
    raise ESchemaFailure.Create('Missing schema identifier');
  // Here you would check against a registry of known schemas.
end;

procedure TGSDAKernel.ValidateMessageEnvelope(AMsg: TMessageEnvelope);
begin
  if AMsg.Schema <> 'gsp/3.1' then
    raise ESchemaFailure.Create('Invalid message schema');

  if AMsg.MessageID = '' then
    raise EProtocolFailure.Create('Missing message_id');

  if AMsg.PeerID = '' then
    raise EProtocolFailure.Create('Missing peer_id');

  if AMsg.RunID = '' then
    raise EProtocolFailure.Create('Missing run_id');

  if AMsg.TaskID = '' then
    raise EProtocolFailure.Create('Missing task_id');

  if AMsg.RoundID = '' then
    raise EProtocolFailure.Create('Missing round_id');

  ValidateConfidence(AMsg.Confidence);
end;

function TGSDAKernel.CreateTask(const UserPrompt, UserIntent, Domain,
                                Namespace, TargetLanguage: string;
                                const TargetAudience, Constraints,
                                RequestedOutputs: TArray<string>;
                                const PriorityProfile: string): TTask;
begin
  Result := TTask.Create;
  Result.UserPrompt := UserPrompt;
  Result.UserIntent := UserIntent;
  Result.Domain := Domain;
  Result.Namespace := Namespace;
  Result.TargetLanguage := TargetLanguage;
  Result.TargetAudience := TargetAudience;
  Result.Constraints := Constraints;
  Result.RequestedOutputs := RequestedOutputs;
  Result.PriorityProfile := PriorityProfile;
  Result.CreatedAt := Now;
  Result.Metadata := TJSONObject.Create;

  Result.TaskID := ComputeTaskID(Result);
  Result.TargetContextID := ComputeTargetContextID(Result);

  FState.AddTask(Result);
end;

function TGSDAKernel.StartRun(ATask: TTask): TRun;
begin
  Result := TRun.Create;
  Result.RunID := NewRunID;
  Result.TaskID := ATask.TaskID;
  Result.TargetContextID := ATask.TargetContextID;
  Result.StartedAt := Now;
  Result.CoordinatorVersion := '1.0';
  Result.KernelVersion := FKernelVersion;
  Result.SchemaProfile := '2020-12';
  Result.ReferenceSemanticsVersion := '3.1';
  Result.InitialConfigID := '';
  Result.LogicalSequenceBase := 0;

  FState.AddRun(Result);
end;

function TGSDAKernel.ProcessIncomingFromT1(const RawPayload: string;
                                           const PeerID, RunID, TaskID, RoundID: TGSDAId;
                                           MsgType: TMessageType;
                                           Confidence: Integer): TMessageEnvelope;
var
  Sanitized: string;
  PayloadJSON: TJSONObject;
begin
  // Trust boundary: T1 → T2 → T3 → T4
  // Here we simulate adapter sanitization and kernel validation.

  // Adapter sanitization (simplified)
  Sanitized := Trim(RawPayload);
  // BOM removal, structural checks, etc. would go here.

  // Parse JSON
  PayloadJSON := TJSONObject.ParseJSONValue(Sanitized) as TJSONObject;
  if PayloadJSON = nil then
    raise EProtocolFailure.Create('Malformed JSON payload');

  // Build envelope
  Result := TMessageEnvelope.Create;
  Result.Schema := 'gsp/3.1';
  Result.MsgType := MsgType;
  Result.PeerID := PeerID;
  Result.RunID := RunID;
  Result.TaskID := TaskID;
  Result.RoundID := RoundID;
  Result.ParentIDs := [];
  Result.Confidence := Confidence;
  Result.Payload := PayloadJSON;

  // Compute message_id after sanitization and canonicalization
  Result.MessageID := ComputeMessageID(Result);

  // Validate envelope
  ValidateMessageEnvelope(Result);

  // Store to authoritative state (T5) via kernel
  FState.AddMessage(Result);
end;

end.
