unit GSDASpecContentIDV2;

interface

uses
  System.SysUtils,
  System.JSON,
  System.Hash,
  GSDAIdentityRegistry,
  GSDAIdentityTraceGraph,
  GSDATraceabilityV2,
  GSDACoverageV2,
  GSDAIdentityFactory;

type
  TSpecContentIDV2 = class
  private
    class function Canonical(const Obj: TJSONObject): string; static;
    class function Hash(const S: string): string; static;
  public
    class function Compute(
      Registry: TGSDAIdentityRegistry;
      Traceability: TGSDAIdentityTraceability;
      Coverage: TCoverageV2Result
    ): string; static;
  end;

implementation

{ Helpers }

class function TSpecContentIDV2.Canonical(const Obj: TJSONObject): string;
begin
  Result := Obj.ToJSON;
end;

class function TSpecContentIDV2.Hash(const S: string): string;
begin
  Result := THashSHA2.GetHashString(S);
end;

{ Compute SpecContentID V2 }

class function TSpecContentIDV2.Compute(
  Registry: TGSDAIdentityRegistry;
  Traceability: TGSDAIdentityTraceability;
  Coverage: TCoverageV2Result
): string;
var
  Root: TJSONObject;
  IdArr: TJSONArray;
  NodeArr: TJSONArray;
  CovObj: TJSONObject;
  Rec: TGSDAIdentityRecord;
  Node: TTraceNode;
begin
  Root := TJSONObject.Create;
  try
    // 1. Identity registry snapshot
    IdArr := TJSONArray.Create;
    for Rec in Registry.All do
      IdArr.Add(Rec.IdentityValue);
    Root.AddPair('identity_registry', IdArr);

    // 2. Traceability graph snapshot
    NodeArr := TJSONArray.Create;
    for Node in Traceability.Graph.AllNodes do
    begin
      NodeArr.Add(
        TJSONObject.Create
          .AddPair('id', Node.IdentityValue)
          .AddPair('kind', Ord(Node.Kind).ToString)
      );
    end;
    Root.AddPair('traceability_graph', NodeArr);

    // 3. Coverage snapshot
    CovObj := TJSONObject.Create;
    CovObj.AddPair('total_requirements', Coverage.TotalRequirements.ToString);
    CovObj.AddPair('covered_requirements', Coverage.CoveredRequirements.ToString);
    CovObj.AddPair('total_artifacts', Coverage.TotalArtifacts.ToString);
    CovObj.AddPair('artifacts_with_evidence', Coverage.ArtifactsWithEvidence.ToString);
    CovObj.AddPair('total_decisions', Coverage.TotalDecisions.ToString);
    CovObj.AddPair('decisions_linked_to_requirements', Coverage.DecisionsLinkedToRequirements.ToString);
    CovObj.AddPair('requirement_coverage_ratio', Coverage.RequirementCoverageRatio.ToString);
    CovObj.AddPair('artifact_evidence_ratio', Coverage.ArtifactEvidenceRatio.ToString);
    CovObj.AddPair('decision_requirement_ratio', Coverage.DecisionRequirementRatio.ToString);
    Root.AddPair('coverage', CovObj);

    // 4. Compute canonical + hash
    Result := 'spec_v2:' + Hash(Canonical(Root));
  finally
    Root.Free;
  end;
end;

end.
