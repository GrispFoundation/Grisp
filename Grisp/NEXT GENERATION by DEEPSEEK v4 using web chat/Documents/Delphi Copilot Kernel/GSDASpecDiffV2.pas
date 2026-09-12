unit GSDASpecDiffV2;

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  GSDAIdentityRegistry,
  GSDAIdentityTraceGraph,
  GSDATraceabilityV2,
  GSDACoverageV2;

type
  TSpecDiffV2 = class
  private
    class function DiffIdentityRegistry(OldReg, NewReg: TGSDAIdentityRegistry): TJSONObject; static;
    class function DiffTraceGraph(OldGraph, NewGraph: TGSDAIdentityTraceGraph): TJSONObject; static;
    class function DiffCoverage(const OldCov, NewCov: TCoverageV2Result): TJSONObject; static;
  public
    class function Compute(
      OldReg, NewReg: TGSDAIdentityRegistry;
      OldTrace, NewTrace: TGSDAIdentityTraceability;
      OldCov, NewCov: TCoverageV2Result
    ): string; static;
  end;

implementation

{ Identity Registry Diff }

class function TSpecDiffV2.DiffIdentityRegistry(OldReg, NewReg: TGSDAIdentityRegistry): TJSONObject;
var
  Obj: TJSONObject;
  AddedArr, RemovedArr: TJSONArray;
  Rec: TGSDAIdentityRecord;
begin
  Obj := TJSONObject.Create;
  AddedArr := TJSONArray.Create;
  RemovedArr := TJSONArray.Create;

  // Added identities
  for Rec in NewReg.All do
    if not OldReg.Exists(Rec.IdentityValue) then
      AddedArr.Add(Rec.IdentityValue);

  // Removed identities
  for Rec in OldReg.All do
    if not NewReg.Exists(Rec.IdentityValue) then
      RemovedArr.Add(Rec.IdentityValue);

  Obj.AddPair('added_identities', AddedArr);
  Obj.AddPair('removed_identities', RemovedArr);
  Result := Obj;
end;

{ Trace Graph Diff }

class function TSpecDiffV2.DiffTraceGraph(OldGraph, NewGraph: TGSDAIdentityTraceGraph): TJSONObject;
var
  Obj: TJSONObject;
  AddedNodes, RemovedNodes: TJSONArray;
  Node: TTraceNode;
begin
  Obj := TJSONObject.Create;
  AddedNodes := TJSONArray.Create;
  RemovedNodes := TJSONArray.Create;

  // Added nodes
  for Node in NewGraph.AllNodes do
    if OldGraph.FindNode(Node.IdentityValue) = nil then
      AddedNodes.Add(Node.IdentityValue);

  // Removed nodes
  for Node in OldGraph.AllNodes do
    if NewGraph.FindNode(Node.IdentityValue) = nil then
      RemovedNodes.Add(Node.IdentityValue);

  Obj.AddPair('added_nodes', AddedNodes);
  Obj.AddPair('removed_nodes', RemovedNodes);
  Result := Obj;
end;

{ Coverage Diff }

class function TSpecDiffV2.DiffCoverage(const OldCov, NewCov: TCoverageV2Result): TJSONObject;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;

  Obj.AddPair('requirement_coverage_delta',
    (NewCov.RequirementCoverageRatio - OldCov.RequirementCoverageRatio).ToString);

  Obj.AddPair('artifact_evidence_delta',
    (NewCov.ArtifactEvidenceRatio - OldCov.ArtifactEvidenceRatio).ToString);

  Obj.AddPair('decision_requirement_delta',
    (NewCov.DecisionRequirementRatio - OldCov.DecisionRequirementRatio).ToString);

  Result := Obj;
end;

{ Compute Full Spec Diff }

class function TSpecDiffV2.Compute(
  OldReg, NewReg: TGSDAIdentityRegistry;
  OldTrace, NewTrace: TGSDAIdentityTraceability;
  OldCov, NewCov: TCoverageV2Result
): string;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('identity_registry_diff',
      DiffIdentityRegistry(OldReg, NewReg));

    Root.AddPair('trace_graph_diff',
      DiffTraceGraph(OldTrace.Graph, NewTrace.Graph));

    Root.AddPair('coverage_diff',
      DiffCoverage(OldCov, NewCov));

    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

end.
