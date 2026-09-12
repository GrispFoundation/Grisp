unit GSDACoordinatorV2;

interface

uses
  System.SysUtils,
  System.JSON,
  GSDAKernelV2,
  GSDARoundOrchestrationV2;

type
  TGSDACoordinatorV2 = class
  private
    FKernel: TGSDAKernelV2;
    FRoundOrchestrator: TGSDARoundOrchestratorV2;

    procedure FinalizeRun(const RunID: string; const Converged: Boolean);
  public
    constructor Create(AKernel: TGSDAKernelV2);

    function ExecuteTask(const UserPrompt: string;
                         const RawMessagesPerRound: array of TArray<string>;
                         const PeerIDsPerRound: array of TArray<string>;
                         const MsgTypesPerRound: array of TArray<Integer>;
                         const ConfidencesPerRound: array of TArray<Integer>): TJSONObject;
  end;

implementation

constructor TGSDACoordinatorV2.Create(AKernel: TGSDAKernelV2);
begin
  FKernel := AKernel;
  FRoundOrchestrator := TGSDARoundOrchestratorV2.Create(AKernel);
end;

procedure TGSDACoordinatorV2.FinalizeRun(const RunID: string; const Converged: Boolean);
var
  Bundle: TJSONObject;
begin
  // 1. Commit revision to lineage
  FKernel.CommitRevision(Converged);

  // 2. Build publication bundle
  Bundle := FKernel.BuildPublicationBundle;

  // 3. Output bundle (Coordinator-level)
  Writeln('=== Publication Bundle V2 ===');
  Writeln(Bundle.ToJSON);
end;

function TGSDACoordinatorV2.ExecuteTask(
  const UserPrompt: string;
  const RawMessagesPerRound: array of TArray<string>;
  const PeerIDsPerRound: array of TArray<string>;
  const MsgTypesPerRound: array of TArray<Integer>;
  const ConfidencesPerRound: array of TArray<Integer>): TJSONObject;
var
  Task: TTask;
  Run: TRun;
  RoundOutput: TRoundOutputV2;
begin
  // 1. Create task
  Task := FKernel.CreateTask(
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

  // 2. Start run
  Run := FKernel.StartRun(Task);

  // 3. Execute multi-round orchestration
  RoundOutput := FRoundOrchestrator.ExecuteRounds(
    Run.RunID,
    RawMessagesPerRound,
    PeerIDsPerRound,
    MsgTypesPerRound,
    ConfidencesPerRound
  );

  // 4. Finalize run (commit revision + build publication bundle)
  FinalizeRun(Run.RunID, RoundOutput.Converged);

  // 5. Return publication bundle to caller
  Result := FKernel.BuildPublicationBundle;
end;

end.
