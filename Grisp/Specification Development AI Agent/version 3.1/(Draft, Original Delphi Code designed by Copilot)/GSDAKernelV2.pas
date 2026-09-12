unit GSDAKernelV2;

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  GSDAIdentityRegistry,
  GSDAIdentityFactory,
  GSDAIdentityProvenance,
  GSDATraceabilityV2,
  GSDACoverageV2,
  GSDASpecContentIDV2,
  GSDASpecDiffV2,
  GSDARevisionLineageV2,
  GSDAPublicationBundleV2;

type
  TTask = class
    TaskID: string;
    Prompt: string;
  end;

  TRun = class
    RunID: string;
    Task: TTask;
    Rounds: TDictionary<string, TList<TJSONObject>>;
  end;

  TKernelState = class
    FTasks: TList<TTask>;
    FRuns: TDictionary<string, TRun>;
  end;

  TGSDAKernelV2 = class
  private
    FState: TKernelState;
    FRegistry: TGSDAIdentityRegistry;
    FPeerReliability: TDictionary<string, Double>;
    FLineage: TGSDARevisionLineageV2;

    function ComputeTraceability: TGSDAIdentityTraceability;
    function ComputeCoverage(const Trace: TGSDAIdentityTraceability): TCoverageV2Result;
    function ComputeSpecContentID(const Trace: TGSDAIdentityTraceability;
                                  const Cov: TCoverageV2Result): string;
    function GetPreviousSpecContentID: string;
    function ComputeDiffSummary(const OldID, NewID: string;
                                const Trace: TGSDAIdentityTraceability;
                                const Cov: TCoverageV2Result): string;
  public
    constructor Create;

    property State: TKernelState read FState;
    property IdentityRegistry: TGSDAIdentityRegistry read FRegistry;
    property Lineage: TGSDARevisionLineageV2 read FLineage;

    function CreateTask(const Prompt: string;
                        Intent, Domain, Namespace, Lang: string;
                        Users, Inputs, Outputs: TArray<string>;
                        Priority: string): TTask;

    function StartRun(Task: TTask): TRun;

    procedure ProcessIncomingFromT1(const Payload: string;
                                    const PeerID, RunID, TaskID, RoundID: string;
                                    MsgType: Integer; Confidence: Integer);

    function GetPeerReliability(const PeerID: string): Double;
    procedure UpdatePeerReliability(const PeerID: string; Delta: Double);

    procedure RegisterExecutionIdentity(const ExecID: string;
                                        const Provenance: TGSDAIdentityProvenance);

    function BuildPublicationBundle: TJSONObject;
    procedure CommitRevision(HumanAccepted: Boolean);
    function GetLatestSpecContentID: string;
  end;

implementation

constructor TGSDAKernelV2.Create;
begin
  FState := TKernelState.Create;
  FState.FTasks := TList<TTask>.Create;
  FState.FRuns := TDictionary<string, TRun>.Create;

  FRegistry := TGSDAIdentityRegistry.Create;
  FPeerReliability := TDictionary<string, Double>.Create;
  FLineage := TGSDARevisionLineageV2.Create;
end;

function TGSDAKernelV2.CreateTask(const Prompt: string;
                                  Intent, Domain, Namespace, Lang: string;
                                  Users, Inputs, Outputs: TArray<string>;
                                  Priority: string): TTask;
var
  T: TTask;
begin
  T := TTask.Create;
  T.TaskID := TGSDAIdentityFactory.MakeSemantic('task', Prompt).Value;
  T.Prompt := Prompt;
  FState.FTasks.Add(T);
  Result := T;
end;

function TGSDAKernelV2.StartRun(Task: TTask): TRun;
var
  R: TRun;
begin
  R := TRun.Create;
  R.RunID := TGSDAIdentityFactory.MakeExecution('run', Task.TaskID).Value;
  R.Task := Task;
  R.Rounds := TDictionary<string, TList<TJSONObject>>.Create;
  FState.FRuns.Add(R.RunID, R);
  Result := R;
end;

procedure TGSDAKernelV2.ProcessIncomingFromT1(const Payload: string;
                                              const PeerID, RunID, TaskID, RoundID: string;
                                              MsgType: Integer; Confidence: Integer);
var
  Run: TRun;
  RoundMsgs: TList<TJSONObject>;
  Obj: TJSONObject;
begin
  if not FState.FRuns.TryGetValue(RunID, Run) then
    raise Exception.Create('Run not found');

  if not Run.Rounds.TryGetValue(RoundID, RoundMsgs) then
  begin
    RoundMsgs := TList<TJSONObject>.Create;
    Run.Rounds.Add(RoundID, RoundMsgs);
  end;

  Obj := TJSONObject.ParseJSONValue(Payload) as TJSONObject;
  RoundMsgs.Add(Obj);
end;

function TGSDAKernelV2.GetPeerReliability(const PeerID: string): Double;
begin
  if not FPeerReliability.ContainsKey(PeerID) then
    Exit(0.5);
  Result := FPeerReliability[PeerID];
end;

procedure TGSDAKernelV2.UpdatePeerReliability(const PeerID: string; Delta: Double);
var
  R: Double;
begin
  R := GetPeerReliability(PeerID);
  R := R + Delta;
  if R < 0 then R := 0;
  if R > 1 then R := 1;
  FPeerReliability.AddOrSetValue(PeerID, R);
end;

procedure TGSDAKernelV2.RegisterExecutionIdentity(const ExecID: string;
                                                  const Provenance: TGSDAIdentityProvenance);
begin
  FRegistry.RegisterExecutionIdentity(ExecID, Provenance);
end;

function TGSDAKernelV2.ComputeTraceability: TGSDAIdentityTraceability;
var
  TraceEngine: TGSDATraceabilityEngineV2;
begin
  TraceEngine := TGSDATraceabilityEngineV2.Create(FRegistry);
  Result := TraceEngine.ComputeTraceability;
end;

function TGSDAKernelV2.ComputeCoverage(
  const Trace: TGSDAIdentityTraceability): TCoverageV2Result;
var
  CoverageEngine: TGSDACoverageEngineV2;
begin
  CoverageEngine := TGSDACoverageEngineV2.Create(FRegistry, Trace);
  Result := CoverageEngine.ComputeCoverage;
end;

function TGSDAKernelV2.ComputeSpecContentID(
  const Trace: TGSDAIdentityTraceability;
  const Cov: TCoverageV2Result): string;
begin
  Result := TSpecContentIDV2.Compute(FRegistry, Trace, Cov);
end;

function TGSDAKernelV2.GetPreviousSpecContentID: string;
var
  Latest: TGSDARevisionEntry;
begin
  Latest := FLineage.Latest;
  if Latest = nil then
    Result := ''
  else
    Result := Latest.SpecContentID;
end;

function TGSDAKernelV2.ComputeDiffSummary(
  const OldID, NewID: string;
  const Trace: TGSDAIdentityTraceability;
  const Cov: TCoverageV2Result): string;
var
  OldEntry: TGSDARevisionEntry;
  OldTrace: TGSDAIdentityTraceability;
  OldCov: TCoverageV2Result;
begin
  OldEntry := FLineage.FindBySpecContentID(OldID);
  if OldEntry = nil then
    Exit('{"diff":"initial"}');

  OldTrace := ComputeTraceability;
  OldCov := ComputeCoverage(OldTrace);

  Result := TSpecDiffV2.Compute(
    FRegistry,
    FRegistry,
    OldTrace,
    Trace,
    OldCov,
    Cov
  );
end;

function TGSDAKernelV2.BuildPublicationBundle: TJSONObject;
var
  Trace: TGSDAIdentityTraceability;
  Cov: TCoverageV2Result;
  SpecID, OldID, DiffSummary: string;
  Bundle: TJSONObject;
begin
  Trace := ComputeTraceability;
  Cov := ComputeCoverage(Trace);

  SpecID := ComputeSpecContentID(Trace, Cov);
  OldID := GetPreviousSpecContentID;
  DiffSummary := ComputeDiffSummary(OldID, SpecID, Trace, Cov);

  Bundle := TJSONObject.Create;
  Bundle.AddPair('spec_content_id', SpecID);
  Bundle.AddPair('identity_registry', FRegistry.ToJson);
  Bundle.AddPair('traceability_graph', Trace.ToJson);
  Bundle.AddPair('coverage', TJSONObject.Create
    .AddPair('total_requirements', Cov.TotalRequirements.ToString)
    .AddPair('covered_requirements', Cov.CoveredRequirements.ToString)
    .AddPair('total_artifacts', Cov.TotalArtifacts.ToString)
    .AddPair('artifacts_with_evidence', Cov.ArtifactsWithEvidence.ToString)
    .AddPair('total_decisions', Cov.TotalDecisions.ToString)
    .AddPair('decisions_linked_to_requirements', Cov.DecisionsLinkedToRequirements.ToString)
    .AddPair('requirement_coverage_ratio', Cov.RequirementCoverageRatio.ToString)
    .AddPair('artifact_evidence_ratio', Cov.ArtifactEvidenceRatio.ToString)
    .AddPair('decision_requirement_ratio', Cov.DecisionRequirementRatio.ToString)
  );
  Bundle.AddPair('revision_lineage', FLineage.ToJson);
  Bundle.AddPair('diff_summary', TJSONObject.ParseJSONValue(DiffSummary) as TJSONObject);
  Result := Bundle;
end;

procedure TGSDAKernelV2.CommitRevision(HumanAccepted: Boolean);
var
  Trace: TGSDAIdentityTraceability;
  Cov: TCoverageV2Result;
  SpecID, OldID, DiffSummary: string;
  Entry: TGSDARevisionEntry;
begin
  Trace := ComputeTraceability;
  Cov := ComputeCoverage(Trace);

  SpecID := ComputeSpecContentID(Trace, Cov);
  OldID := GetPreviousSpecContentID;
  DiffSummary := ComputeDiffSummary(OldID, SpecID, Trace, Cov);

  Entry := TGSDARevisionEntry.Create(
    SpecID,
    OldID,
    HumanAccepted,
    'signature-placeholder',
    DiffSummary
  );
  FLineage.AddRevision(Entry);
end;

function TGSDAKernelV2.GetLatestSpecContentID: string;
var
  Latest: TGSDARevisionEntry;
begin
  Latest := FLineage.Latest;
  if Latest = nil then
    Result := ''
  else
    Result := Latest.SpecContentID;
end;

end.
