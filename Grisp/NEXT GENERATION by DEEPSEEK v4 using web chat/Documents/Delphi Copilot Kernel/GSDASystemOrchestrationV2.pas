unit GSDASystemOrchestrationV2;

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  GSDAKernelV2,
  GSDATaskOrchestrationV2,
  GSDARevisionLineageV2;

type
  TSystemExecutionResultV2 = record
    TaskResults: TArray<TTaskExecutionResultV2>;
  end;

  TGSDASystemOrchestratorV2 = class
  private
    FKernel: TGSDAKernelV2;
    FLineage: TGSDARevisionLineageV2;
    FTaskOrchestrator: TGSDATaskOrchestratorV2;

  public
    constructor Create;

    function ExecuteTasks(const Prompts: TArray<string>;
                          const RawMessagesPerTaskPerRound: array of array of TArray<string>;
                          const PeerIDsPerTaskPerRound: array of array of TArray<string>;
                          const MsgTypesPerTaskPerRound: array of array of TArray<Integer>;
                          const ConfidencesPerTaskPerRound: array of array of TArray<Integer>): TSystemExecutionResultV2;

    function ToJson(const Result: TSystemExecutionResultV2): TJSONObject;
  end;

implementation

{ TGSDASystemOrchestratorV2 }

constructor TGSDASystemOrchestratorV2.Create;
begin
  FKernel := TGSDAKernelV2.Create;
  FLineage := TGSDARevisionLineageV2.Create;
  FTaskOrchestrator := TGSDATaskOrchestratorV2.Create(FKernel, FLineage);
end;

function TGSDASystemOrchestratorV2.ExecuteTasks(
  const Prompts: TArray<string>;
  const RawMessagesPerTaskPerRound: array of array of TArray<string>;
  const PeerIDsPerTaskPerRound: array of array of TArray<string>;
  const MsgTypesPerTaskPerRound: array of array of TArray<Integer>;
  const ConfidencesPerTaskPerRound: array of array of TArray<Integer>): TSystemExecutionResultV2;
var
  I: Integer;
  Results: TList<TTaskExecutionResultV2>;
begin
  Results := TList<TTaskExecutionResultV2>.Create;
  try
    for I := 0 to High(Prompts) do
      Results.Add(
        FTaskOrchestrator.ExecuteTask(
          Prompts[I],
          RawMessagesPerTaskPerRound[I],
          PeerIDsPerTaskPerRound[I],
          MsgTypesPerTaskPerRound[I],
          ConfidencesPerTaskPerRound[I]
        )
      );

    Result.TaskResults := Results.ToArray;
  finally
    Results.Free;
  end;
end;

function TGSDASystemOrchestratorV2.ToJson(
  const Result: TSystemExecutionResultV2): TJSONObject;
var
  Root: TJSONObject;
  Arr: TJSONArray;
  R: TTaskExecutionResultV2;
  Obj: TJSONObject;
begin
  Root := TJSONObject.Create;
  Arr := TJSONArray.Create;

  for R in Result.TaskResults do
  begin
    Obj := TJSONObject.Create;
    Obj.AddPair('task_id', R.TaskID);
    Obj.AddPair('run_id', R.RunID);
    Obj.AddPair('final_round_index', R.FinalRoundIndex.ToString);
    Obj.AddPair('final_execution_identity', R.FinalExecutionIdentity);
    Obj.AddPair('converged', BoolToStr(R.Converged, True));
    Obj.AddPair('final_payload', R.FinalPayload);
    Obj.AddPair('publication_bundle', R.PublicationBundle);
    Arr.Add(Obj);
  end;

  Root.AddPair('system_execution_results', Arr);
  Result := Root;
end;

end.
