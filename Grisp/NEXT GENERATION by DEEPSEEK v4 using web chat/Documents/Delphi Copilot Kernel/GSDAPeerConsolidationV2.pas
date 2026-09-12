unit GSDAPeerConsolidationV2;

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  GSDAPeerScoringV2,
  GSDAIdentityFactory,
  GSDAIdentityRegistry,
  GSDAKernelV2;

type
  // Consolidation result
  TConsolidationResultV2 = record
    ConsolidatedPayload: TJSONObject;
    ConsolidatedExecutionIdentity: string;
    WinningPeerID: string;
    WinningScore: Double;
  end;

  // Consolidation engine
  TGSDAPeerConsolidationV2 = class
  private
    FKernel: TGSDAKernelV2;
    FScoring: TGSDAPeerScoringV2;

    function SelectTopCandidate(const Messages: TArray<TJSONObject>;
                                const Scores: TArray<TWeightedPeerScore>): Integer;

    function MergeRepairs(const Base: TJSONObject;
                          const Messages: TArray<TJSONObject>): TJSONObject;

    function ApplyCritiques(const Base: TJSONObject;
                            const Messages: TArray<TJSONObject>): TJSONObject;

    function BuildConsolidatedIdentity(const RunID, RoundID: string;
                                       const Payload: TJSONObject): string;
  public
    constructor Create(AKernel: TGSDAKernelV2);

    function Consolidate(const RunID, RoundID: string;
                         const PeerIDs: TArray<string>;
                         const MsgTypes: TArray<Integer>;
                         const Confidences: TArray<Integer>;
                         const ExecIDs: TArray<string>;
                         const Payloads: TArray<TJSONObject>): TConsolidationResultV2;
  end;

implementation

{ TGSDAPeerConsolidationV2 }

constructor TGSDAPeerConsolidationV2.Create(AKernel: TGSDAKernelV2);
begin
  FKernel := AKernel;
  FScoring := TGSDAPeerScoringV2.Create(AKernel);
end;

function TGSDAPeerConsolidationV2.SelectTopCandidate(
  const Messages: TArray<TJSONObject>;
  const Scores: TArray<TWeightedPeerScore>): Integer;
var
  I: Integer;
  BestIdx: Integer;
  BestScore: Double;
begin
  BestIdx := -1;
  BestScore := -1.0;

  for I := 0 to High(Scores) do
  begin
    if Scores[I].FinalScore > BestScore then
    begin
      BestScore := Scores[I].FinalScore;
      BestIdx := I;
    end;
  end;

  Result := BestIdx;
end;

function TGSDAPeerConsolidationV2.MergeRepairs(const Base: TJSONObject;
                                               const Messages: TArray<TJSONObject>): TJSONObject;
var
  Msg: TJSONObject;
  Repair: TJSONValue;
begin
  Result := Base.Clone as TJSONObject;

  for Msg in Messages do
  begin
    Repair := Msg.GetValue('repair');
    if Repair <> nil then
      Result.AddPair('repair_applied', Repair.Clone as TJSONValue);
  end;
end;

function TGSDAPeerConsolidationV2.ApplyCritiques(const Base: TJSONObject;
                                                 const Messages: TArray<TJSONObject>): TJSONObject;
var
  Msg: TJSONObject;
  Crit: TJSONValue;
begin
  Result := Base.Clone as TJSONObject;

  for Msg in Messages do
  begin
    Crit := Msg.GetValue('critique');
    if Crit <> nil then
      Result.AddPair('critique_applied', Crit.Clone as TJSONValue);
  end;
end;

function TGSDAPeerConsolidationV2.BuildConsolidatedIdentity(
  const RunID, RoundID: string;
  const Payload: TJSONObject): string;
var
  Extra: TJSONObject;
begin
  Extra := TJSONObject.Create;
  try
    Extra.AddPair('schema', Payload.GetValue('schema').Value);
    Extra.AddPair('consolidated', 'true');

    Result := TGSDAIdentityFactory.MakeExecution(
      'consolidated/3.1',
      RunID,
      'coordinator',
      RoundID,
      Extra
    ).Value;
  finally
    Extra.Free;
  end;
end;

function TGSDAPeerConsolidationV2.Consolidate(
  const RunID, RoundID: string;
  const PeerIDs: TArray<string>;
  const MsgTypes: TArray<Integer>;
  const Confidences: TArray<Integer>;
  const ExecIDs: TArray<string>;
  const Payloads: TArray<TJSONObject>): TConsolidationResultV2;
var
  Scores: TArray<TWeightedPeerScore>;
  I, BestIdx: Integer;
  Base: TJSONObject;
  Consolidated: TJSONObject;
begin
  SetLength(Scores, Length(PeerIDs));

  // 1. Score all messages
  for I := 0 to High(PeerIDs) do
    Scores[I] := FScoring.ScoreMessage(
      PeerIDs[I],
      ExecIDs[I],
      MsgTypes[I],
      Confidences[I]
    );

  // 2. Select top candidate
  BestIdx := SelectTopCandidate(Payloads, Scores);

  if BestIdx < 0 then
    raise Exception.Create('No valid peer messages to consolidate');

  Base := Payloads[BestIdx];

  // 3. Merge repairs
  Consolidated := MergeRepairs(Base, Payloads);

  // 4. Apply critiques
  Consolidated := ApplyCritiques(Consolidated, Payloads);

  // 5. Build consolidated execution identity
  Result.ConsolidatedExecutionIdentity :=
    BuildConsolidatedIdentity(RunID, RoundID, Consolidated);

  Result.ConsolidatedPayload := Consolidated;
  Result.WinningPeerID := PeerIDs[BestIdx];
  Result.WinningScore := Scores[BestIdx].FinalScore;
end;

end.
