unit GSDAPublicationBundleV2;

interface

uses
  System.SysUtils,
  System.JSON,
  GSDAKernelV2,
  GSDAPublicationV2,
  GSDARevisionLineageV2,
  GSDASpecContentIDV2,
  GSDASpecDiffV2,
  GSDAIdentityRegistry,
  GSDATraceabilityV2,
  GSDACoverageV2;

type
  TPublicationBundleV2 = class
  private
    FKernel: TGSDAKernelV2;
    FLineage: TGSDARevisionLineageV2;

    function ComputeTraceability: TGSDAIdentityTraceability;
    function ComputeCoverage(const Trace: TGSDAIdentityTraceability): TCoverageV2Result;
    function ComputeSpecContentID(const Trace: TGSDAIdentityTraceability;
                                  const Cov: TCoverageV2Result): string;
    function ComputeDiffSummary(const OldID, NewID: string;
                                const Trace: TGSDAIdentityTraceability;
                                const Cov: TCoverageV2Result): string;
    function BuildMetadata(const SpecID: string): TJSONObject;
  public
    constructor Create(AKernel: TGSDAKernelV2; ALineage: TGSDARevisionLineageV2);

    function BuildBundle: TJSONObject;
  end;

implementation

{ TPublicationBundleV2 }

constructor TPublicationBundleV2.Create(AKernel: TGSDAKernelV2;
                                       ALineage: TGSDARevisionLineageV2);
begin
  FKernel := AKernel;
  FLineage := ALineage;
end;

function TPublicationBundleV2.ComputeTraceability: TGSDAIdentityTraceability;
var
  TraceEngine: TGSDATraceabilityEngineV2;
begin
  TraceEngine := TGSDATraceabilityEngineV2.Create(FKernel.IdentityRegistry);
  Result := TraceEngine.ComputeTraceability;
end;

function TPublicationBundleV2.ComputeCoverage(
  const Trace: TGSDAIdentityTraceability): TCoverageV2Result;
var
  CoverageEngine: TGSDACoverageEngineV2;
begin
  CoverageEngine := TGSDACoverageEngineV2.Create(FKernel.IdentityRegistry, Trace);
  Result := CoverageEngine.ComputeCoverage;
end;

function TPublicationBundleV2.ComputeSpecContentID(
  const Trace: TGSDAIdentityTraceability;
  const Cov: TCoverageV2Result): string;
begin
  Result := TSpecContentIDV2.Compute(
    FKernel.IdentityRegistry,
    Trace,
    Cov
  );
end;

function TPublicationBundleV2.ComputeDiffSummary(
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
    FKernel.IdentityRegistry,
    FKernel.IdentityRegistry,
    OldTrace,
    Trace,
    OldCov,
    Cov
  );
end;

function TPublicationBundleV2.BuildMetadata(const SpecID: string): TJSONObject;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  Obj.AddPair('spec_content_id', SpecID);
  Obj.AddPair('kernel_version', FKernel.KernelVersion);
  Obj.AddPair('timestamp', DateTimeToStr(Now));
  Obj.AddPair('publisher', 'GSDAKernelV2');
  Result := Obj;
end;

function TPublicationBundleV2.BuildBundle: TJSONObject;
var
  Trace: TGSDAIdentityTraceability;
  Cov: TCoverageV2Result;
  SpecID, OldID, DiffSummary: string;
  Bundle: TJSONObject;
begin
  Trace := ComputeTraceability;
  Cov := ComputeCoverage(Trace);

  SpecID := ComputeSpecContentID(Trace, Cov);
  OldID := FLineage.Latest.SpecContentID;

  DiffSummary := ComputeDiffSummary(OldID, SpecID, Trace, Cov);

  Bundle := TJSONObject.Create;

  Bundle.AddPair('spec_content_id', SpecID);
  Bundle.AddPair('identity_registry', FKernel.IdentityRegistry.ToJson);
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
  Bundle.AddPair('metadata', BuildMetadata(SpecID));

  Result := Bundle;
end;

end.
