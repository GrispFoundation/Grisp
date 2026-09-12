unit GSDAPublication;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  GSDAKernel,          // your kernel unit
  GSDACanonicalJson;   // canonical JSON unit

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

  EPublicationBlocked = class(Exception);

  TGSDAPublication = class
  private
    FKernel: TGSDAKernel;

    function ComputeSpecContentID(const Requirements,
                                  Glossary,
                                  Assumptions,
                                  OpenQuestions,
                                  Traceability: TJSONObject): string;

    function CheckSchemaValidity: TPublicationPredicateResult;
    function CheckCoverageThresholds: TPublicationPredicateResult;
    function CheckTraceabilityCompleteness: TPublicationPredicateResult;
    function CheckGlossaryNormalization: TPublicationPredicateResult;
    function CheckRegistryUniqueness: TPublicationPredicateResult;
    function CheckNoNormativeKeywordLeaks: TPublicationPredicateResult;
    function CheckNoUnresolvedReferences: TPublicationPredicateResult;
    function CheckNoCriticalFindings: TPublicationPredicateResult;

    function HumanAccepts(const SpecContentID: string): Boolean;
  public
    constructor Create(AKernel: TGSDAKernel);

    function EvaluatePublication(const Requirements,
                                 Glossary,
                                 Assumptions,
                                 OpenQuestions,
                                 Traceability: TJSONObject): TPublicationSummary;

    procedure Publish(const Requirements,
                      Glossary,
                      Assumptions,
                      OpenQuestions,
                      Traceability: TJSONObject);
  end;

implementation

uses
  System.Hash;

{ TGSDAPublication }

constructor TGSDAPublication.Create(AKernel: TGSDAKernel);
begin
  FKernel := AKernel;
end;

function TGSDAPublication.ComputeSpecContentID(const Requirements,
                                               Glossary,
                                               Assumptions,
                                               OpenQuestions,
                                               Traceability: TJSONObject): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema', 'spec_content_identity/3.1');
    Obj.AddPair('requirements_content',
      TGSDACanonicalJson.Canonicalize(Requirements));
    Obj.AddPair('glossary_content',
      TGSDACanonicalJson.Canonicalize(Glossary));
    Obj.AddPair('assumptions_content',
      TGSDACanonicalJson.Canonicalize(Assumptions));
    Obj.AddPair('open_questions_content',
      TGSDACanonicalJson.Canonicalize(OpenQuestions));
    Obj.AddPair('traceability_content',
      TGSDACanonicalJson.Canonicalize(Traceability));

    Result := 'spec:' + THashSHA2.GetHashString(
      TGSDACanonicalJson.Canonicalize(Obj)
    );
  finally
    Obj.Free;
  end;
end;

function TGSDAPublication.CheckSchemaValidity: TPublicationPredicateResult;
begin
  Result.Name := 'SCHEMA_VALIDITY';
  // TODO: walk all records in FKernel.State and validate against JSON Schema.
  Result.Passed := True;
  Result.Reason := '';
end;

function TGSDAPublication.CheckCoverageThresholds: TPublicationPredicateResult;
begin
  Result.Name := 'COVERAGE_THRESHOLDS';
  // TODO: compute coverage from intent elements vs linked artifacts.
  Result.Passed := True;
  Result.Reason := '';
end;

function TGSDAPublication.CheckTraceabilityCompleteness: TPublicationPredicateResult;
begin
  Result.Name := 'TRACEABILITY_COMPLETENESS';
  // TODO: ensure every requirement, artifact, decision, evidence, assumption, question is linked.
  Result.Passed := True;
  Result.Reason := '';
end;

function TGSDAPublication.CheckGlossaryNormalization: TPublicationPredicateResult;
begin
  Result.Name := 'GLOSSARY_NORMALIZATION';
  // TODO: verify term_id normalization and collision detection.
  Result.Passed := True;
  Result.Reason := '';
end;

function TGSDAPublication.CheckRegistryUniqueness: TPublicationPredicateResult;
begin
  Result.Name := 'REGISTRY_UNIQUENESS';
  // TODO: ensure all registry identifiers are unique per namespace.
  Result.Passed := True;
  Result.Reason := '';
end;

function TGSDAPublication.CheckNoNormativeKeywordLeaks: TPublicationPredicateResult;
begin
  Result.Name := 'NORMATIVE_KEYWORD_LEAKS';
  // TODO: run a linter over rendered spec text to detect unmarked RFC 2119 keywords.
  Result.Passed := True;
  Result.Reason := '';
end;

function TGSDAPublication.CheckNoUnresolvedReferences: TPublicationPredicateResult;
begin
  Result.Name := 'UNRESOLVED_REFERENCES';
  // TODO: ensure all SourceRef.source_id resolve to valid identities.
  Result.Passed := True;
  Result.Reason := '';
end;

function TGSDAPublication.CheckNoCriticalFindings: TPublicationPredicateResult;
begin
  Result.Name := 'CRITICAL_FINDINGS';
  // TODO: ensure no blocking findings remain unresolved.
  Result.Passed := True;
  Result.Reason := '';
end;

function TGSDAPublication.HumanAccepts(const SpecContentID: string): Boolean;
begin
  // Stub: in a real system, this would verify a signature or explicit approval.
  // For now, we simulate acceptance.
  Result := True;
end;

function TGSDAPublication.EvaluatePublication(const Requirements,
                                              Glossary,
                                              Assumptions,
                                              OpenQuestions,
                                              Traceability: TJSONObject): TPublicationSummary;
var
  Preds: TList<TPublicationPredicateResult>;
begin
  Preds := TList<TPublicationPredicateResult>.Create;
  try
    Preds.Add(CheckSchemaValidity);
    Preds.Add(CheckCoverageThresholds);
    Preds.Add(CheckTraceabilityCompleteness);
    Preds.Add(CheckGlossaryNormalization);
    Preds.Add(CheckRegistryUniqueness);
    Preds.Add(CheckNoNormativeKeywordLeaks);
    Preds.Add(CheckNoUnresolvedReferences);
    Preds.Add(CheckNoCriticalFindings);

    Result.SpecContentID := ComputeSpecContentID(
      Requirements, Glossary, Assumptions, OpenQuestions, Traceability
    );
    Result.Predicates := Preds.ToArray;
    Result.HumanAccepted := HumanAccepts(Result.SpecContentID);
  finally
    Preds.Free;
  end;
end;

procedure TGSDAPublication.Publish(const Requirements,
                                   Glossary,
                                   Assumptions,
                                   OpenQuestions,
                                   Traceability: TJSONObject);
var
  Summary: TPublicationSummary;
  P: TPublicationPredicateResult;
begin
  Summary := EvaluatePublication(
    Requirements, Glossary, Assumptions, OpenQuestions, Traceability
  );

  for P in Summary.Predicates do
    if not P.Passed then
      raise EPublicationBlocked.CreateFmt(
        'Publication blocked by predicate %s: %s',
        [P.Name, P.Reason]
      );

  if not Summary.HumanAccepted then
    raise EPublicationBlocked.Create('Publication blocked: human did not accept');

  // At this point, you would:
  // - create a revision record
  // - update revision lineage
  // - export a package
  // - commit atomically

  // For now, we just log:
  Writeln(Format('Published spec with content_id %s', [Summary.SpecContentID]));
end;

end.
