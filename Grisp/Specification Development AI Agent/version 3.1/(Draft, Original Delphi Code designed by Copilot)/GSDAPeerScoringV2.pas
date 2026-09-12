unit GSDAPeerScoringV2;

interface

uses
  System.SysUtils,
  System.JSON,
  GSDAIdentityRegistry,
  GSDAIdentityValidation,
  GSDAIdentityProvenance,
  GSDAKernelV2;

type
  // Final weighted score for a peer message
  TWeightedPeerScore = record
    ExecutionIdentity: string;
    PeerID: string;
    RawConfidence: Integer;
    Reliability: Double;
    TrustZoneWeight: Double;
    MessageTypeWeight: Double;
    ProvenanceWeight: Double;
    FinalScore: Double;
  end;

  TGSDAPeerScoringV2 = class
  private
    FRegistry: TGSDAIdentityRegistry;
    FKernel: TGSDAKernelV2;

    function ComputeReliability(const PeerID: string): Double;
    function ComputeTrustZoneWeight(const PeerID: string): Double;
    function ComputeMessageTypeWeight(MsgType: Integer): Double;
    function ComputeProvenanceWeight(const ExecID: string): Double;
  public
    constructor Create(AKernel: TGSDAKernelV2);

    function ScoreMessage(const PeerID, ExecID: string;
                          MsgType: Integer;
                          Confidence: Integer): TWeightedPeerScore;
  end;

implementation

{ TGSDAPeerScoringV2 }

constructor TGSDAPeerScoringV2.Create(AKernel: TGSDAKernelV2);
begin
  FKernel := AKernel;
  FRegistry := AKernel.IdentityRegistry;
end;

function TGSDAPeerScoringV2.ComputeReliability(const PeerID: string): Double;
var
  R: Double;
begin
  // Default reliability if peer has no history
  R := FKernel.GetPeerReliability(PeerID);

  if R < 0.0 then
    R := 0.5; // neutral baseline

  Result := R;
end;

function TGSDAPeerScoringV2.ComputeTrustZoneWeight(const PeerID: string): Double;
begin
  if PeerID.StartsWith('t1:') then
    Exit(1.0);

  if PeerID.StartsWith('t2:') then
    Exit(0.8);

  Result := 0.0; // untrusted peers contribute nothing
end;

function TGSDAPeerScoringV2.ComputeMessageTypeWeight(MsgType: Integer): Double;
begin
  case MsgType of
    Ord(mtCandidate):      Result := 1.0;
    Ord(mtCritique):       Result := 0.9;
    Ord(mtRepair):         Result := 1.1;
    Ord(mtScore):          Result := 1.0;
    Ord(mtConsolidation):  Result := 1.2;
  else
    Result := 0.0;
  end;
end;

function TGSDAPeerScoringV2.ComputeProvenanceWeight(const ExecID: string): Double;
var
  Prov: TGSDAIdentityProvenance;
begin
  Prov := FRegistry.FindByIdentity(ExecID).Provenance;

  case Prov.TrustZone of
    pzSemanticFactory:     Result := 1.0;
    pzExecutionFactory:    Result := 1.0;
    pzAdapterSanitization: Result := 0.9;
    pzKernelValidation:    Result := 1.1;
    pzKernelStateCommit:   Result := 1.2;
  else
    Result := 0.5;
  end;
end;

function TGSDAPeerScoringV2.ScoreMessage(const PeerID, ExecID: string;
                                         MsgType: Integer;
                                         Confidence: Integer): TWeightedPeerScore;
var
  R, TZ, MT, PV: Double;
  Final: Double;
begin
  R := ComputeReliability(PeerID);
  TZ := ComputeTrustZoneWeight(PeerID);
  MT := ComputeMessageTypeWeight(MsgType);
  PV := ComputeProvenanceWeight(ExecID);

  Final := Confidence * R * TZ * MT * PV;

  Result.ExecutionIdentity := ExecID;
  Result.PeerID := PeerID;
  Result.RawConfidence := Confidence;
  Result.Reliability := R;
  Result.TrustZoneWeight := TZ;
  Result.MessageTypeWeight := MT;
  Result.ProvenanceWeight := PV;
  Result.FinalScore := Final;
end;

end.
