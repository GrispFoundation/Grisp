unit GSDATaskOrchestrationV2;

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  GSDAKernelV2,
  GSDARoundOrchestrationV2,
  GSDAPublicationBundleV2,
  GSDARevisionLineageV2,
  GSDAIdentityFactory;

type
  TTaskExecutionResultV2 = record
    TaskID: string;
    RunID: string;
    FinalRoundIndex: Integer;
    FinalPayload: TJSONObject;
    FinalExecutionIdentity: string;
    Converged: Boolean;
    PublicationBundle: TJSONObject;
  end;

  TGSDATaskOrchestratorV2 = class
  private
    FKernel: TGSDAKernelV2;
    FRoundOrchestrator: TGSDARoundOrchestratorV2;
    FLineage: TGSDARevisionLineageV2;

    function CreateTask(const UserPrompt: string): TTask;
    function StartRun(Task: TTask): string;
    function BuildPublicationBundle(const RunID: string): TJSONObject;
  public
    constructor Create(AKernel: TGSDAKernelV2; ALineage: TGSDARevisionLineageV2);

    function ExecuteTask(const UserPrompt: string;
                         const RawMessagesPerRound: array of TArray<string>;
                         const PeerIDsPerRound: array of TArray<string>;
                         const MsgTypesPerRound: array of TArray<Integer>;
                         const ConfidencesPerRound: array of TArray<Integer>): TTaskExecutionResultV2;
  end;

implementation

{ TGSDATaskOrchestratorV2 }

constructor TGSDATaskOrchestratorV2.Create(AKernel: TGSDAKernelV2;
                                           ALineage: TGSDARevisionLineageV2);
begin
  FKernel := AKernel;
  FLineage := ALineage;
  FRoundOrchestrator := TGSDARoundOrchestratorV2.Create(AKernel);
end;

function TGSDATaskOrchestratorV2.CreateTask(const UserPrompt: string): TTask;
begin
  Result := FKernel.CreateTask(
    UserPrompt,
    'general_intent',
    'general_domain',
    'default_namespace',
    'en',
    ['general_user'],
    [],
    ['final_output'],
    'default_priority'
  );
end;

function TGSDATaskOrchestratorV2.StartRun(Task: TTask): string;
var
  Run: TRun;
begin
  Run := FKernel.StartRun(Task);
  Result := Run.RunID;
end;

function TGSDATaskOrchestratorV2.BuildPublicationBundle(const RunID: string): TJSONObject;
var
  BundleBuilder: TPublicationBundleV2;
begin
  BundleBuilder := TPublicationBundleV2.Create(FKernel, FLineage);
  Result := BundleBuilder.BuildBundle;
end;

function TGSDATaskOrchestratorV2.ExecuteTask(
  const UserPrompt: string;
  const RawMessagesPerRound: array of TArray<string>;
  const PeerIDsPerRound: array of TArray<string>;
  const MsgTypesPerRound: array of TArray<Integer>;
  const ConfidencesPerRound: array of TArray<Integer>): TTaskExecutionResultV2;
var
  Task: TTask;
  RunID: string;
  RoundOutput: TRoundOutputV2;
  Bundle: TJSONObject;
begin
  // 1. Create task
  Task := CreateTask(UserPrompt);

  // 2. Start run
  RunID := StartRun(Task);

  // 3. Execute rounds
  RoundOutput := FRoundOrchestrator.ExecuteRounds(
    RunID,
    RawMessagesPerRound,
    PeerIDsPerRound,
    MsgTypesPerRound,
    ConfidencesPerRound
  );

  // 4. Build publication bundle
  Bundle := BuildPublicationBundle(RunID);

  // 5. Return final result
  Result.TaskID := Task.TaskID;
  Result.RunID := RunID;
  Result.FinalRoundIndex := RoundOutput.RoundIndex;
  Result.FinalPayload := RoundOutput.ConsolidatedPayload;
  Result.FinalExecutionIdentity := RoundOutput.ConsolidatedExecutionIdentity;
  Result.Converged := RoundOutput.Converged;
  Result.PublicationBundle := Bundle;
end;

end.
