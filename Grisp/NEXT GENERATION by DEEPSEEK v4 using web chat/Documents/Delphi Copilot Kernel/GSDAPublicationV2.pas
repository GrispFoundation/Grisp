unit GSDAPublicationV2;

interface

uses
  System.SysUtils,
  System.JSON,
  GSDAKernelV2,
  GSDAIdentityRegistry,
  GSDATraceabilityV2,
  GSDACoverageV2;

type
  TPublicationPredicateResult = record
    Name: string;
    Passed: Boolean;
    Reason: string;
  end;

  TPublicationSummary = record
    SpecContentID: string;
    Predicates: TArray<TPublicationPredicateResult>;
    HumanAccepted: Boolean;
  end;

  TGSDAPublicationV2 = class
  private
    FKernel: TGSDAKernelV2;

    function CheckCoverageV2: TPublicationPredicateResult;
    function CheckTraceabilityV2: TPublicationPredicateResult;
    function HumanAccepts(const SpecContentID: string): Boolean;
  public
    constructor Create(AKernel: TGSDAKernelV2);

    function EvaluatePublication: TPublicationSummary;
    procedure Publish;
  end;

implementation

uses
  System.Hash;

{ TGSDAPublicationV2 }

constructor TGSDAPublicationV2.Create(AKernel: TGSDAKernelV2);
begin
  FKernel := AKernel;
end;

function TGSDAPublicationV2.CheckCoverageV2: TPublicationPredicateResult;
var
  TraceEngine: TGSDATraceabilityEngineV2;
  Trace: TGSDAIdentityTraceability;
  CoverageEngine: TGSDACoverageEngineV2;
  Cov: TCoverageV2Result;
begin
  Result.Name := 'IDENTITY_COVERAGE_V2';

  // Build traceability graph from identity registry
  TraceEngine := TGSDATraceabilityEngineV2.Create(FKernel.IdentityRegistry);
  Trace := TraceEngine.ComputeTraceability;

  // Compute coverage using identity graph
  CoverageEngine := TGSDACoverageEngineV2.Create(FKernel.IdentityRegistry, Trace);
  Cov := CoverageEngine.ComputeCoverage;

  // Coverage thresholds
  if Cov.RequirementCoverageRatio < 1.0 then
  begin
    Result.Passed := False;
    Result.Reason :=
      Format('Requirement coverage %.2f < 1.0 (covered=%d / total=%d)',
        [Cov.RequirementCoverageRatio, Cov.CoveredRequirements, Cov.TotalRequirements]);
    Exit;
  end;

  if Cov.ArtifactEvidenceRatio < 1.0 then
  begin
    Result.Passed := False;
    Result.Reason :=
      Format('Artifact evidence coverage %.2f < 1.0 (with evidence=%d / total=%d)',
        [Cov.ArtifactEvidenceRatio, Cov.ArtifactsWithEvidence, Cov.TotalArtifacts]);
    Exit;
  end;

  if Cov.DecisionRequirementRatio < 1.0 then
  begin
    Result.Passed := False;
    Result.Reason :=
      Format('Decision→Requirement coverage %.2f < 1.0 (linked=%d / total=%d)',
        [Cov.DecisionRequirementRatio, Cov.DecisionsLinkedToRequirements, Cov.TotalDecisions]);
    Exit;
  end;

  Result.Passed := True;
  Result.Reason := '';
end;

function TGSDAPublicationV2.CheckTraceabilityV2: TPublicationPredicateResult;
var
  TraceEngine: TGSDATraceabilityEngineV2;
  Trace: TGSDAIdentityTraceability;
begin
  Result.Name := 'TRACEABILITY_V2';

  TraceEngine := TGSDATraceabilityEngineV2.Create(FKernel.IdentityRegistry);
  Trace := TraceEngine.ComputeTraceability;

  // Basic check: at least one node exists
  if Length(Trace.Graph.AllNodes) = 0 then
  begin
    Result.Passed := False;
    Result.Reason := 'Traceability graph is empty';
    Exit;
  end;

  Result.Passed := True;
  Result.Reason := '';
end;

function TGSDAPublicationV2.HumanAccepts(const SpecContentID: string): Boolean;
begin
  // Stub: replace with signature or UI approval later
  Result := True;
end;

function TGSDAPublicationV2.EvaluatePublication: TPublicationSummary;
var
  Preds: TList<TPublicationPredicateResult>;
  P: TPublicationPredicateResult;
begin
  Preds := TList<TPublicationPredicateResult>.Create;
  try
    Preds.Add(CheckCoverageV2);
    Preds.Add(CheckTraceabilityV2);

    Result.SpecContentID := 'spec:' + THashSHA2.GetHashString('dummy'); // replace with your real content ID
    Result.Predicates := Preds.ToArray;
    Result.HumanAccepted := HumanAccepts(Result.SpecContentID);
  finally
    Preds.Free;
  end;
end;

procedure TGSDAPublicationV2.Publish;
var
  Summary: TPublicationSummary;
  P: TPublicationPredicateResult;
begin
  Summary := EvaluatePublication;

  for P in Summary.Predicates do
    if not P.Passed then
      raise Exception.CreateFmt('Publication blocked by %s: %s', [P.Name, P.Reason]);

  if not Summary.HumanAccepted then
    raise Exception.Create('Publication blocked: human did not accept');

  Writeln('Publication succeeded with content_id: ' + Summary.SpecContentID);
end;

end.
