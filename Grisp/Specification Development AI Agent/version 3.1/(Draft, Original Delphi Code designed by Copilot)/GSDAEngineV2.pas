unit GSDAEngineV2;

{

You now have a single engine:
delphi

var
  Engine: TGSDAEngineV2;
  Res: TGSDAEngineResultV2;
begin
  Engine := TGSDAEngineV2.Create;
  Res := Engine.ExecuteSystem(Prompts, RawMsgs, PeerIDs, MsgTypes, Confidences);
  Writeln(Res.SystemJson.ToJSON);
end;

}

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  GSDAKernelV2,
  GSDACoordinatorV2,
  GSDATaskOrchestrationV2,
  GSDARevisionLineageV2;

type
  TGSDAEngineResultV2 = record
    SystemJson: TJSONObject;
  end;

  TGSDAEngineV2 = class
  private
    FKernel: TGSDAKernelV2;
    FLineage: TGSDARevisionLineageV2;
    FCoordinator: TGSDACoordinatorV2;
    FTaskOrchestrator: TGSDATaskOrchestratorV2;

  public
    constructor Create;

    function ExecuteSystem(const Prompts: TArray<string>;
                           const RawMessagesPerTaskPerRound: array of array of TArray<string>;
                           const PeerIDsPerTaskPerRound: array of array of TArray<string>;
                           const MsgTypesPerTaskPerRound: array of array of TArray<Integer>;
                           const ConfidencesPerTaskPerRound: array of array of TArray<Integer>): TGSDAEngineResultV2;
  end;

implementation

constructor TGSDAEngineV2.Create;
begin
  FKernel := TGSDAKernelV2.Create;
  FLineage := FKernel.Lineage; // kernel owns lineage
  FCoordinator := TGSDACoordinatorV2.Create(FKernel);
  FTaskOrchestrator := TGSDATaskOrchestratorV2.Create(FKernel, FLineage);
end;

function TGSDAEngineV2.ExecuteSystem(
  const Prompts: TArray<string>;
  const RawMessagesPerTaskPerRound: array of array of TArray<string>;
  const PeerIDsPerTaskPerRound: array of array of TArray<string>;
  const MsgTypesPerTaskPerRound: array of array of TArray<Integer>;
  const ConfidencesPerTaskPerRound: array of array of TArray<Integer>): TGSDAEngineResultV2;
var
  I: Integer;
  TaskResult: TTaskExecutionResultV2;
  SystemObj, TaskArr, TaskObj: TJSONObject;
  TaskJsonArr: TJSONArray;
begin
  SystemObj := TJSONObject.Create;
  TaskJsonArr := TJSONArray.Create;

  for I := 0 to High(Prompts) do
  begin
    TaskResult := FTaskOrchestrator.ExecuteTask(
      Prompts[I],
      RawMessagesPerTaskPerRound[I],
      PeerIDsPerTaskPerRound[I],
      MsgTypesPerTaskPerRound[I],
      ConfidencesPerTaskPerRound[I]
    );

    TaskObj := TJSONObject.Create;
    TaskObj.AddPair('task_id', TaskResult.TaskID);
    TaskObj.AddPair('run_id', TaskResult.RunID);
    TaskObj.AddPair('final_round_index', TaskResult.FinalRoundIndex.ToString);
    TaskObj.AddPair('final_execution_identity', TaskResult.FinalExecutionIdentity);
    TaskObj.AddPair('converged', BoolToStr(TaskResult.Converged, True));
    TaskObj.AddPair('final_payload', TaskResult.FinalPayload);
    TaskObj.AddPair('publication_bundle', TaskResult.PublicationBundle);

    TaskJsonArr.Add(TaskObj);
  end;

  SystemObj.AddPair('tasks', TaskJsonArr);
  SystemObj.AddPair('revision_lineage', FLineage.ToJson);

  Result.SystemJson := SystemObj;
end;

end.
