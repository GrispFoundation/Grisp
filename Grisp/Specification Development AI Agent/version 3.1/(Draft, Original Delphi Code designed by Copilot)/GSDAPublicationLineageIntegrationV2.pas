unit GSDAPublicationLineageIntegrationV2;

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
  TGSDAPublicationLineageIntegratorV2 = class
  private
    FKernel: TGSDAKernelV2;
    FLineage: TGSDARevisionLineageV2;

    function ComputeSpecContentID: string;
    function ComputeSpecDiff(const OldID, NewID: string): string;
    function GetPreviousSpecContentID: string;
    function ComputeTraceability: TGSDAIdentityTraceability;
    function ComputeCoverage(const Trace: TGSDAIdentityTraceability): TCoverageV2Result;
  public
    constructor Create(AKernel: TGSDAKernelV2; ALineage: TGSDARevisionLineageV2);

    procedure IntegratePublication;
  end;

implementation

{ TGSDAPublicationLineageIntegratorV2 }

constructor TGSDAPublicationLineageIntegratorV2.Create(AKernel: TGSDAKernelV2;
                                                       ALineage: TGSDARevisionLineageV2);
begin
  FKernel := AKernel;
  FLineage := ALineage;
end;

function TGSDAPublicationLineageIntegratorV2.GetPreviousSpecContentID: string;
var
  Latest: TGSDARevisionEntry;
begin
  Latest := FLineage.Latest;
  if Latest = nil then
    Result := ''  // first publication
  else
    Result := Latest.SpecContentID;
end;

function TGSDAPublicationLineageIntegratorV2.ComputeTraceability: TGSDAIdentityTraceability;
var
  TraceEngine: TGSDATraceabilityEngineV2;
begin
  TraceEngine := TGSDATraceabilityEngineV2.Create(FKernel.IdentityRegistry);
  Result := TraceEngine.ComputeTraceability;
end;

function TGSDAPublicationLineageIntegratorV2.ComputeCoverage(
  const Trace: TGSDAIdentityTraceability): TCoverageV2Result;
var
  CoverageEngine: TGSDACoverageEngineV2;
begin
  CoverageEngine := TGSDACoverageEngineV2.Create(FKernel.IdentityRegistry, Trace);
  Result := CoverageEngine.ComputeCoverage;
end;

function TGSDAPublicationLineageIntegratorV2.ComputeSpecContentID: string;
var
  Trace: TGSDAIdentityTraceability;
  Cov: TCoverageV2Result;
begin
  Trace := ComputeTraceability;
  Cov := ComputeCoverage(Trace);

  Result := TSpecContentIDV2.Compute(
    FKernel.IdentityRegistry,
    Trace,
    Cov
  );
end;

function TGSDAPublicationLineageIntegratorV2.ComputeSpecDiff(
  const OldID, NewID: string): string;
var
  OldEntry: TGSDARevisionEntry;
  OldTrace, NewTrace: TGSDAIdentityTraceability;
  OldCov, NewCov: TCoverageV2Result;
begin
  OldEntry := FLineage.FindBySpecContentID(OldID);

  // If no previous revision exists, diff is empty
  if OldEntry = nil then
  begin
    Result := '{"diff":"initial"}';
    Exit;
  end;

  // Compute old traceability + coverage
  OldTrace := ComputeTraceability;
  OldCov := ComputeCoverage(OldTrace);

  // Compute new traceability + coverage
  NewTrace := ComputeTraceability;
  NewCov := ComputeCoverage(NewTrace);

  Result := TSpecDiffV2.Compute(
    FKernel.IdentityRegistry,
    FKernel.IdentityRegistry, // registry is authoritative; diff is identity-based
    OldTrace,
    NewTrace,
    OldCov,
    NewCov
  );
end;

procedure TGSDAPublicationLineageIntegratorV2.IntegratePublication;
var
  Pub: TGSDAPublicationV2;
  Summary: TPublicationSummary;
  NewSpecID, OldSpecID, DiffSummary: string;
  Entry: TGSDARevisionEntry;
begin
  Pub := TGSDAPublicationV2.Create(FKernel);

  // 1. Evaluate publication predicates
  Summary := Pub.EvaluatePublication;

  // 2. Compute SpecContentID V2
  NewSpecID := ComputeSpecContentID;

  // 3. Get previous spec ID
  OldSpecID := GetPreviousSpecContentID;

  // 4. Compute diff summary
  DiffSummary := ComputeSpecDiff(OldSpecID, NewSpecID);

  // 5. Create revision entry
  Entry := TGSDARevisionEntry.Create(
    NewSpecID,
    OldSpecID,
    Summary.HumanAccepted,
    'signature-placeholder',
    DiffSummary
  );

  // 6. Add to lineage
  FLineage.AddRevision(Entry);

  // 7. Final publication
  Pub.Publish;
end;

end.
