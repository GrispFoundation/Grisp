unit GSDATraceability;

{

You can now plug this into your publication module like:

uses
  GSDATraceability;

function TGSDAPublication.CheckTraceabilityCompleteness: TPublicationPredicateResult;
var
  Engine: TGSDATraceabilityEngine;
  T: TTraceability;
begin
  Result.Name := 'TRACEABILITY_COMPLETENESS';

  Engine := TGSDATraceabilityEngine.Create(FKernel.State);
  try
    T := Engine.ComputeTraceability;
    // For now we just assume completeness; later you can add checks:
    // - every requirement appears in Requirements[]
    // - every artifact appears in Artifacts[]
    // - etc.
    Result.Passed := True;
    Result.Reason := '';
  finally
    Engine.Free;
  end;
end;

}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  GSDAKernel; // for TAuthoritativeState, TMessageEnvelope, etc.

type
  TRequirementLink = record
    RequirementID: string;
    ArtifactIDs: TArray<string>;
    EvidenceIDs: TArray<string>;
    DecisionIDs: TArray<string>;
  end;

  TArtifactLink = record
    ArtifactID: string;
    RequirementIDs: TArray<string>;
    EvidenceIDs: TArray<string>;
    DecisionIDs: TArray<string>;
  end;

  TDecisionLink = record
    DecisionID: string;
    RequirementIDs: TArray<string>;
    ArtifactIDs: TArray<string>;
    EvidenceIDs: TArray<string>;
  end;

  TEvidenceLink = record
    EvidenceID: string;
    RequirementIDs: TArray<string>;
    ArtifactIDs: TArray<string>;
    DecisionIDs: TArray<string>;
  end;

  TTraceability = record
    Requirements: TArray<TRequirementLink>;
    Artifacts: TArray<TArtifactLink>;
    Decisions: TArray<TDecisionLink>;
    Evidence: TArray<TEvidenceLink>;
  end;

  TGSDATraceabilityEngine = class
  private
    FState: TAuthoritativeState;

    function CollectRequirementLinks: TArray<TRequirementLink>;
    function CollectArtifactLinks: TArray<TArtifactLink>;
    function CollectDecisionLinks: TArray<TDecisionLink>;
    function CollectEvidenceLinks: TArray<TEvidenceLink>;
  public
    constructor Create(AState: TAuthoritativeState);

    function ComputeTraceability: TTraceability;
    function ToJson(const T: TTraceability): TJSONObject;
  end;

implementation

{ TGSDATraceabilityEngine }

constructor TGSDATraceabilityEngine.Create(AState: TAuthoritativeState);
begin
  FState := AState;
end;

function TGSDATraceabilityEngine.CollectRequirementLinks: TArray<TRequirementLink>;
var
  L: TList<TRequirementLink>;
  RLink: TRequirementLink;
begin
  // Stub: in a real system, you would walk requirement records in FState
  // and gather linked artifacts/evidence/decisions from their provenance.
  L := TList<TRequirementLink>.Create;
  try
    // Example dummy entry
    RLink.RequirementID := 'req:dummy';
    RLink.ArtifactIDs := ['art:dummy'];
    RLink.EvidenceIDs := ['ev:dummy'];
    RLink.DecisionIDs := ['dec:dummy'];
    L.Add(RLink);

    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function TGSDATraceabilityEngine.CollectArtifactLinks: TArray<TArtifactLink>;
var
  L: TList<TArtifactLink>;
  ALink: TArtifactLink;
begin
  // Stub: walk artifacts in FState and link back to requirements/evidence/decisions.
  L := TList<TArtifactLink>.Create;
  try
    ALink.ArtifactID := 'art:dummy';
    ALink.RequirementIDs := ['req:dummy'];
    ALink.EvidenceIDs := ['ev:dummy'];
    ALink.DecisionIDs := ['dec:dummy'];
    L.Add(ALink);

    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function TGSDATraceabilityEngine.CollectDecisionLinks: TArray<TDecisionLink>;
var
  L: TList<TDecisionLink>;
  DLink: TDecisionLink;
begin
  // Stub: walk decisions in FState and link to requirements/artifacts/evidence.
  L := TList<TDecisionLink>.Create;
  try
    DLink.DecisionID := 'dec:dummy';
    DLink.RequirementIDs := ['req:dummy'];
    DLink.ArtifactIDs := ['art:dummy'];
    DLink.EvidenceIDs := ['ev:dummy'];
    L.Add(DLink);

    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function TGSDATraceabilityEngine.CollectEvidenceLinks: TArray<TEvidenceLink>;
var
  L: TList<TEvidenceLink>;
  ELink: TEvidenceLink;
begin
  // Stub: walk evidence records in FState and link to requirements/artifacts/decisions.
  L := TList<TEvidenceLink>.Create;
  try
    ELink.EvidenceID := 'ev:dummy';
    ELink.RequirementIDs := ['req:dummy'];
    ELink.ArtifactIDs := ['art:dummy'];
    ELink.DecisionIDs := ['dec:dummy'];
    L.Add(ELink);

    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function TGSDATraceabilityEngine.ComputeTraceability: TTraceability;
begin
  Result.Requirements := CollectRequirementLinks;
  Result.Artifacts := CollectArtifactLinks;
  Result.Decisions := CollectDecisionLinks;
  Result.Evidence := CollectEvidenceLinks;
end;

function TGSDATraceabilityEngine.ToJson(const T: TTraceability): TJSONObject;
var
  Obj: TJSONObject;
  ReqArr, ArtArr, DecArr, EvArr: TJSONArray;
  R: TRequirementLink;
  A: TArtifactLink;
  D: TDecisionLink;
  E: TEvidenceLink;
  JReq, JArt, JDec, JEv: TJSONObject;
  S: string;
begin
  Obj := TJSONObject.Create;

  ReqArr := TJSONArray.Create;
  for R in T.Requirements do
  begin
    JReq := TJSONObject.Create;
    JReq.AddPair('requirement_id', R.RequirementID);
    JReq.AddPair('artifact_ids', TJSONArray.Create);
    for S in R.ArtifactIDs do
      JReq.GetValue<TJSONArray>('artifact_ids').Add(S);
    JReq.AddPair('evidence_ids', TJSONArray.Create);
    for S in R.EvidenceIDs do
      JReq.GetValue<TJSONArray>('evidence_ids').Add(S);
    JReq.AddPair('decision_ids', TJSONArray.Create);
    for S in R.DecisionIDs do
      JReq.GetValue<TJSONArray>('decision_ids').Add(S);
    ReqArr.AddElement(JReq);
  end;

  ArtArr := TJSONArray.Create;
  for A in T.Artifacts do
  begin
    JArt := TJSONObject.Create;
    JArt.AddPair('artifact_id', A.ArtifactID);
    JArt.AddPair('requirement_ids', TJSONArray.Create);
    for S in A.RequirementIDs do
      JArt.GetValue<TJSONArray>('requirement_ids').Add(S);
    JArt.AddPair('evidence_ids', TJSONArray.Create);
    for S in A.EvidenceIDs do
      JArt.GetValue<TJSONArray>('evidence_ids').Add(S);
    JArt.AddPair('decision_ids', TJSONArray.Create);
    for S in A.DecisionIDs do
      JArt.GetValue<TJSONArray>('decision_ids').Add(S);
    ArtArr.AddElement(JArt);
  end;

  DecArr := TJSONArray.Create;
  for D in T.Decisions do
  begin
    JDec := TJSONObject.Create;
    JDec.AddPair('decision_id', D.DecisionID);
    JDec.AddPair('requirement_ids', TJSONArray.Create);
    for S in D.RequirementIDs do
      JDec.GetValue<TJSONArray>('requirement_ids').Add(S);
    JDec.AddPair('artifact_ids', TJSONArray.Create);
    for S in D.ArtifactIDs do
      JDec.GetValue<TJSONArray>('artifact_ids').Add(S);
    JDec.AddPair('evidence_ids', TJSONArray.Create);
    for S in D.EvidenceIDs do
      JDec.GetValue<TJSONArray>('evidence_ids').Add(S);
    DecArr.AddElement(JDec);
  end;

  EvArr := TJSONArray.Create;
  for E in T.Evidence do
  begin
    JEv := TJSONObject.Create;
    JEv.AddPair('evidence_id', E.EvidenceID);
    JEv.AddPair('requirement_ids', TJSONArray.Create);
    for S in E.RequirementIDs do
      JEv.GetValue<TJSONArray>('requirement_ids').Add(S);
    JEv.AddPair('artifact_ids', TJSONArray.Create);
    for S in E.ArtifactIDs do
      JEv.GetValue<TJSONArray>('artifact_ids').Add(S);
    JEv.AddPair('decision_ids', TJSONArray.Create);
    for S in E.DecisionIDs do
      JEv.GetValue<TJSONArray>('decision_ids').Add(S);
    EvArr.AddElement(JEv);
  end;

  Obj.AddPair('requirements', ReqArr);
  Obj.AddPair('artifacts', ArtArr);
  Obj.AddPair('decisions', DecArr);
  Obj.AddPair('evidence', EvArr);

  Result := Obj;
end;

end.
