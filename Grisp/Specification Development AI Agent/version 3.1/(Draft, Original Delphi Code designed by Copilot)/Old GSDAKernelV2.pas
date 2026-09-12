unit GSDAKernel;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  GSDAIdentity,        // semantic/execution/coordinator/derived identities
  GSDACanonicalJson;

type
  TGSDAId = string;

  TTrustZone = (tzT0, tzT1, tzT2, tzT3, tzT4, tzT5, tzT6, tzT7);

  EProtocolFailure   = class(Exception);
  ESchemaFailure     = class(Exception);
  EPublicationFailure = class(Exception);

  TTask = class
  public
    TaskSemanticId: TSemanticIdentity;
    TargetContextSemanticId: TSemanticIdentity;

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

    function TaskID: string;
    function TargetContextID: string;
  end;

  TRun = class
  public
    RunCoordinatorId: TCoordinatorIdentity;
    TargetContextSemanticId: TSemanticIdentity;

    StartedAt: TDateTime;
    CoordinatorVersion: string;
    KernelVersion: string;
    SchemaProfile: string;
    ReferenceSemanticsVersion: string;
    InitialConfigID: string;
    LogicalSequenceBase: Int64;

    function RunID: string;
  end;

  TMessageType = (mtCandidate, mtCritique, mtRepair, mtScore,
                  mtRequirement, mtTerm, mtQuestion, mtConsolidation);

  TMessageEnvelope = class
  public
    Schema: string;        // "gsp/3.1"
    MessageExecutionId: TExecutionIdentity;

    MsgType: TMessageType;
    PeerID: string;
    RunID: string;
    TaskID: string;
    RoundID: string;
    ParentIDs: TArray<string>;
    Confidence: Integer;
    Payload: TJSONObject;

    function MessageID: string;
  end;

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

    function FindRunById(const RunID: string): TRun;
    function FindTaskById(const TaskID: string): TTask;
  end;

  TGSDAKernel = class
  private
    FState: TAuthoritativeState;
    FKernelVersion: string;

    function SortStrings(const Arr: TArray<string>): TArray<string>;

    function BuildTaskSemanticIdentity(ATask: TTask): TSemanticIdentity;
    function BuildTargetContextSemanticIdentity(ATask: TTask): TSemanticIdentity;

    function NewRunCoordinatorId: TCoordinatorIdentity;
    function NewRoundDerivedId(const RunID: string; RoundIndex: Integer): TDerivedExecutionIdentity;

    function BuildMessageExecutionIdentity(AMsg: TMessageEnvelope): TExecutionIdentity;

    procedure ValidateMessageEnvelope(AMsg: TMessageEnvelope);
    procedure ValidateConfidence(Confidence: Integer);
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
                                   const PeerID, RunID, TaskID, RoundID: string;
                                   MsgType: TMessageType;
                                   Confidence: Integer): TMessageEnvelope;

    property State: TAuthoritativeState read FState;
  end;

implementation

uses
  System.Hash;

{ TTask }

function TTask.TaskID: string;
begin
  Result := TaskSemanticId.Value;
end;

function TTask.TargetContextID: string;
begin
  Result := TargetContextSemanticId.Value;
end;

{ TRun }

function TRun.RunID: string;
begin
  Result := RunCoordinatorId.Value;
end;

{ TMessageEnvelope }

function TMessageEnvelope.MessageID: string;
begin
  Result := MessageExecutionId.Value;
end;

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

function TAuthoritativeState.FindRunById(const RunID: string): TRun;
var
  R: TRun;
begin
  Result := nil;
  for R in FRuns do
    if R.RunID = RunID then
      Exit(R);
end;

function TAuthoritativeState.FindTaskById(const TaskID: string): TTask;
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

function TGSDAKernel.BuildTaskSemanticIdentity(ATask: TTask): TSemanticIdentity;
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

    Result := TSemanticIdentity.FromJson('task', Obj);
  finally
    Obj.Free;
  end;
end;

function TGSDAKernel.BuildTargetContextSemanticIdentity(ATask: TTask): TSemanticIdentity;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema', 'target_context_identity/3.1');
    Obj.AddPair('task_id', ATask.TaskID);
    Obj.AddPair('namespace', ATask.Namespace);
    Obj.AddPair('target_language', ATask.TargetLanguage);

    Result := TSemanticIdentity.FromJson('ctx', Obj);
  finally
    Obj.Free;
  end;
end;

function TGSDAKernel.NewRunCoordinatorId: TCoordinatorIdentity;
begin
  Result := TCoordinatorIdentity.New('run');
end;

function TGSDAKernel.NewRoundDerivedId(const RunID: string; RoundIndex: Integer): TDerivedExecutionIdentity;
begin
  Result := TDerivedExecutionIdentity.Build('round', RunID, RoundIndex);
end;

function TGSDAKernel.BuildMessageExecutionIdentity(AMsg: TMessageEnvelope): TExecutionIdentity;
var
  Extra: TJSONObject;
begin
  Extra := TJSONObject.Create;
  try
    Extra.AddPair('payload_schema', AMsg.Payload.GetValue<string>('schema', ''));
    Extra.AddPair('content_id', AMsg.Payload.GetValue<string>('content_id', ''));

    Result := TExecutionIdentity.Build(
      'message_identity/3.1',
      AMsg.RunID,
      AMsg.PeerID,
      AMsg.RoundID,
      Extra
    );
  finally
    Extra.Free;
  end;
end;

procedure TGSDAKernel.ValidateConfidence(Confidence: Integer);
begin
  if (Confidence < 1) or (Confidence > 1000) then
    raise EProtocolFailure.CreateFmt('Invalid confidence: %d', [Confidence]);
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

  Result.TaskSemanticId := BuildTaskSemanticIdentity(Result);
  Result.TargetContextSemanticId := BuildTargetContextSemanticIdentity(Result);

  FState.AddTask(Result);
end;

function TGSDAKernel.StartRun(ATask: TTask): TRun;
begin
  Result := TRun.Create;
  Result.RunCoordinatorId := NewRunCoordinatorId;
  Result.TargetContextSemanticId := ATask.TargetContextSemanticId;
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
                                           const PeerID, RunID, TaskID, RoundID: string;
                                           MsgType: TMessageType;
                                           Confidence: Integer): TMessageEnvelope;
var
  Sanitized: string;
  PayloadJSON: TJSONObject;
begin
  Sanitized := Trim(RawPayload);

  PayloadJSON := TJSONObject.ParseJSONValue(Sanitized) as TJSONObject;
  if PayloadJSON = nil then
    raise EProtocolFailure.Create('Malformed JSON payload');

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

  Result.MessageExecutionId := BuildMessageExecutionIdentity(Result);

  ValidateMessageEnvelope(Result);

  FState.AddMessage(Result);
end;

end.
