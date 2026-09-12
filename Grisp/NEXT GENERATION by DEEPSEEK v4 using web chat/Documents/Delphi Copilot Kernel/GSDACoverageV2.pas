unit GSDACoverageV2;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  GSDAIdentityRegistry,
  GSDAIdentityTraceGraph,
  GSDATraceabilityV2;

type
  TCoverageV2Result = record
    TotalRequirements: Integer;
    CoveredRequirements: Integer;
    TotalArtifacts: Integer;
    ArtifactsWithEvidence: Integer;
    TotalDecisions: Integer;
    DecisionsLinkedToRequirements: Integer;
    RequirementCoverageRatio: Double;
    ArtifactEvidenceRatio: Double;
    DecisionRequirementRatio: Double;
  end;

  TGSDACoverageEngineV2 = class
  private
    FRegistry: TGSDAIdentityRegistry;
    FTraceability: TGSDAIdentityTraceability;

    function CountRequirementsCoveredByArtifacts(Graph: TGSDAIdentityTraceGraph): Integer;
    function CountArtifactsWithEvidence(Graph: TGSDAIdentityTraceGraph): Integer;
    function CountDecisionsLinkedToRequirements(Graph: TGSDAIdentityTraceGraph): Integer;
  public
    constructor Create(ARegistry: TGSDAIdentityRegistry; ATraceability: TGSDAIdentityTraceability);

    function ComputeCoverage: TCoverageV2Result;
  end;

implementation

{ TGSDACoverageEngineV2 }

constructor TGSDACoverageEngineV2.Create(ARegistry: TGSDAIdentityRegistry;
                                         ATraceability: TGSDAIdentityTraceability);
begin
  FRegistry := ARegistry;
  FTraceability := ATraceability;
end;

function TGSDACoverageEngineV2.CountRequirementsCoveredByArtifacts(Graph: TGSDAIdentityTraceGraph): Integer;
var
  Node: TTraceNode;
  Covered: Integer;
begin
  Covered := 0;
  for Node in Graph.AllNodes do
  begin
    if Node.Kind = tnRequirement then
    begin
      // Requirement is considered covered if it has at least one outgoing link to an artifact
      if Node.Outgoing.Count > 0 then
        Inc(Covered);
    end;
  end;
  Result := Covered;
end;

function TGSDACoverageEngineV2.CountArtifactsWithEvidence(Graph: TGSDAIdentityTraceGraph): Integer;
var
  Node: TTraceNode;
  Count: Integer;
  TargetId: string;
begin
  Count := 0;
  for Node in Graph.AllNodes do
  begin
    if Node.Kind = tnArtifact then
    begin
      for TargetId in Node.Outgoing do
      begin
        if Graph.FindNode(TargetId).Kind = tnEvidence then
        begin
          Inc(Count);
          Break;
        end;
      end;
    end;
  end;
  Result := Count;
end;

function TGSDACoverageEngineV2.CountDecisionsLinkedToRequirements(Graph: TGSDAIdentityTraceGraph): Integer;
var
  Node: TTraceNode;
  Count: Integer;
  TargetId: string;
begin
  Count := 0;
  for Node in Graph.AllNodes do
  begin
    if Node.Kind = tnDecision then
    begin
      for TargetId in Node.Outgoing do
      begin
        if Graph.FindNode(TargetId).Kind = tnRequirement then
        begin
          Inc(Count);
          Break;
        end;
      end;
    end;
  end;
  Result := Count;
end;

function TGSDACoverageEngineV2.ComputeCoverage: TCoverageV2Result;
var
  Graph: TGSDAIdentityTraceGraph;
  Node: TTraceNode;
begin
  Graph := FTraceability.Graph;

  Result.TotalRequirements := 0;
  Result.TotalArtifacts := 0;
  Result.TotalDecisions := 0;

  for Node in Graph.AllNodes do
  begin
    case Node.Kind of
      tnRequirement: Inc(Result.TotalRequirements);
      tnArtifact:    Inc(Result.TotalArtifacts);
      tnDecision:    Inc(Result.TotalDecisions);
    end;
  end;

  Result.CoveredRequirements := CountRequirementsCoveredByArtifacts(Graph);
  Result.ArtifactsWithEvidence := CountArtifactsWithEvidence(Graph);
  Result.DecisionsLinkedToRequirements := CountDecisionsLinkedToRequirements(Graph);

  if Result.TotalRequirements > 0 then
    Result.RequirementCoverageRatio :=
      Result.CoveredRequirements / Result.TotalRequirements
  else
    Result.RequirementCoverageRatio := 1.0;

  if Result.TotalArtifacts > 0 then
    Result.ArtifactEvidenceRatio :=
      Result.ArtifactsWithEvidence / Result.TotalArtifacts
  else
    Result.ArtifactEvidenceRatio := 1.0;

  if Result.TotalDecisions > 0 then
    Result.DecisionRequirementRatio :=
      Result.DecisionsLinkedToRequirements / Result.TotalDecisions
  else
    Result.DecisionRequirementRatio := 1.0;
end;

end.
