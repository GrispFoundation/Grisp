unit GSDATraceabilityV2;

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  GSDAIdentity,
  GSDAIdentityRegistry,
  GSDAIdentityTraceGraph;

type
  // Final traceability output
  TGSDAIdentityTraceability = class
  private
    FGraph: TGSDAIdentityTraceGraph;
  public
    constructor Create(AGraph: TGSDAIdentityTraceGraph);
    function ToJson: TJSONObject;
    property Graph: TGSDAIdentityTraceGraph read FGraph;
  end;

  // Traceability engine
  TGSDATraceabilityEngineV2 = class
  private
    FRegistry: TGSDAIdentityRegistry;
    FGraph: TGSDAIdentityTraceGraph;

    procedure LinkRequirementToArtifact(const ReqId, ArtId: string);
    procedure LinkArtifactToEvidence(const ArtId, EvId: string);
    procedure LinkDecisionToRequirement(const DecId, ReqId: string);
    procedure LinkDecisionToArtifact(const DecId, ArtId: string);
    procedure LinkDecisionToEvidence(const DecId, EvId: string);

  public
    constructor Create(ARegistry: TGSDAIdentityRegistry);

    // Build full traceability graph from registry contents
    function ComputeTraceability: TGSDAIdentityTraceability;
  end;

implementation

{ TGSDAIdentityTraceability }

constructor TGSDAIdentityTraceability.Create(AGraph: TGSDAIdentityTraceGraph);
begin
  FGraph := AGraph;
end;

function TGSDAIdentityTraceability.ToJson: TJSONObject;
var
  Obj: TJSONObject;
  NodesArr: TJSONArray;
  NodeObj: TJSONObject;
  Node: TTraceNode;
  OutArr, InArr: TJSONArray;
  S: string;
begin
  Obj := TJSONObject.Create;
  NodesArr := TJSONArray.Create;

  for Node in FGraph.AllNodes do
  begin
    NodeObj := TJSONObject.Create;
    NodeObj.AddPair('identity', Node.IdentityValue);
    NodeObj.AddPair('kind', Ord(Node.Kind).ToString);

    OutArr := TJSONArray.Create;
    for S in Node.Outgoing do
      OutArr.Add(S);
    NodeObj.AddPair('outgoing', OutArr);

    InArr := TJSONArray.Create;
    for S in Node.Incoming do
      InArr.Add(S);
    NodeObj.AddPair('incoming', InArr);

    NodesArr.Add(NodeObj);
  end;

  Obj.AddPair('traceability_graph', NodesArr);
  Result := Obj;
end;

{ TGSDATraceabilityEngineV2 }

constructor TGSDATraceabilityEngineV2.Create(ARegistry: TGSDAIdentityRegistry);
begin
  FRegistry := ARegistry;
  FGraph := TGSDAIdentityTraceGraph.Create;
end;

procedure TGSDATraceabilityEngineV2.LinkRequirementToArtifact(const ReqId, ArtId: string);
begin
  FGraph.Link(ReqId, tnRequirement, ArtId, tnArtifact);
end;

procedure TGSDATraceabilityEngineV2.LinkArtifactToEvidence(const ArtId, EvId: string);
begin
  FGraph.Link(ArtId, tnArtifact, EvId, tnEvidence);
end;

procedure TGSDATraceabilityEngineV2.LinkDecisionToRequirement(const DecId, ReqId: string);
begin
  FGraph.Link(DecId, tnDecision, ReqId, tnRequirement);
end;

procedure TGSDATraceabilityEngineV2.LinkDecisionToArtifact(const DecId, ArtId: string);
begin
  FGraph.Link(DecId, tnDecision, ArtId, tnArtifact);
end;

procedure TGSDATraceabilityEngineV2.LinkDecisionToEvidence(const DecId, EvId: string);
begin
  FGraph.Link(DecId, tnDecision, EvId, tnEvidence);
end;

function TGSDATraceabilityEngineV2.ComputeTraceability: TGSDAIdentityTraceability;
var
  Rec: TGSDAIdentityRecord;
begin
  // Walk all identities in the registry and link them based on kind
  for Rec in FRegistry.All do
  begin
    case Rec.IdentityKind of
      'requirement':
        FGraph.GetOrCreateNode(Rec.IdentityValue, tnRequirement);

      'artifact':
        FGraph.GetOrCreateNode(Rec.IdentityValue, tnArtifact);

      'evidence':
        FGraph.GetOrCreateNode(Rec.IdentityValue, tnEvidence);

      'decision':
        FGraph.GetOrCreateNode(Rec.IdentityValue, tnDecision);
    end;
  end;

  // TODO: Real linking logic based on provenance fields
  // For now, simulate simple linking:
  //
  // requirement -> artifact -> evidence
  // decision -> requirement
  // decision -> artifact
  // decision -> evidence

  for Rec in FRegistry.All do
  begin
    if Rec.IdentityKind = 'requirement' then
    begin
      // Simulated artifact link
      if FRegistry.Exists('artifact:dummy') then
        LinkRequirementToArtifact(Rec.IdentityValue, 'artifact:dummy');
    end;

    if Rec.IdentityKind = 'artifact' then
    begin
      if FRegistry.Exists('evidence:dummy') then
        LinkArtifactToEvidence(Rec.IdentityValue, 'evidence:dummy');
    end;

    if Rec.IdentityKind = 'decision' then
    begin
      if FRegistry.Exists('requirement:dummy') then
        LinkDecisionToRequirement(Rec.IdentityValue, 'requirement:dummy');

      if FRegistry.Exists('artifact:dummy') then
        LinkDecisionToArtifact(Rec.IdentityValue, 'artifact:dummy');

      if FRegistry.Exists('evidence:dummy') then
        LinkDecisionToEvidence(Rec.IdentityValue, 'evidence:dummy');
    end;
  end;

  Result := TGSDAIdentityTraceability.Create(FGraph);
end;

end.
