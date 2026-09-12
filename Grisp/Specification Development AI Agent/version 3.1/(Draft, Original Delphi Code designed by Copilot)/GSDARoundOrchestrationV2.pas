unit GSDARoundOrchestrationV2;

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  GSDAPeerAdapterV2,
  GSDAPeerScoringV2,
  GSDAPeerConsolidationV2,
  GSDAIdentityFactory,
  GSDAKernelV2;

type
  TRoundOutputV2 = record
    RoundIndex: Integer;
    ConsolidatedPayload: TJSONObject;
    ConsolidatedExecutionIdentity: string;
    WinningPeerID: string;
    WinningScore: Double;
    Converged: Boolean;
  end;

  TGSDARoundOrchestratorV2 = class
  private
    FKernel: TGSDAKernelV2;
    FAdapter: TGSDAPeerAdapterV2;
    FScoring: TGSDAPeerScoringV2;
    FConsolidation: TGSDAPeerConsolidationV2;

    function CollectPeerMessages(const RunID, RoundID: string;
                                 const RawMessages: TArray<string>;
                                 const PeerIDs: TArray<string>;
                                 const MsgTypes: TArray<Integer>;
                                 const Confidences: TArray<Integer>): TArray<TSanitizedPeerMessage>;

    function ConsolidateRound(const RunID, RoundID: string;
                              const Messages: TArray<TSanitizedPeerMessage>): TRoundOutputV2;

    function DetectConvergence(const Prev, Curr: TRoundOutputV2): Boolean;

    function BuildNextRoundID(const RunID: string; Index: Integer): string;
  public
    constructor Create(AKernel: TGSDAKernelV2);

    function ExecuteRounds(const RunID: string;
                           const RawMessagesPerRound: array of TArray<string>;
                           const PeerIDsPerRound: array of TArray<string>;
                           const MsgTypesPerRound: array of TArray<Integer>;
                           const ConfidencesPerRound: array of TArray<Integer>): TRoundOutputV2;
  end;

implementation

{ TGSDARoundOrchestratorV2 }

constructor TGSDARoundOrchestratorV2.Create(AKernel: TGSDAKernelV2);
begin
  FKernel := AKernel;
  FAdapter := TGSDAPeerAdapterV2.Create(AKernel);
  FScoring := TGSDAPeerScoringV2.Create(AKernel);
  FConsolidation := TGSDAPeerConsolidationV2.Create(AKernel);
end;

function TGSDARoundOrchestratorV2.CollectPeerMessages(
  const RunID, RoundID: string;
  const RawMessages: TArray<string>;
  const PeerIDs: TArray<string>;
  const MsgTypes: TArray<Integer>;
  const Confidences: TArray<Integer>): TArray<TSanitizedPeerMessage>;
var
  I: Integer;
begin
  SetLength(Result, Length(RawMessages));

  for I := 0 to High(RawMessages) do
    Result[I] := FAdapter.SanitizeAndValidate(
      PeerIDs[I],
      RunID,
      FKernel.State.FTasks.Last.TaskID,
      RoundID,
      MsgTypes[I],
      Confidences[I],
      RawMessages[I]
    );
end;

function TGSDARoundOrchestratorV2.ConsolidateRound(
  const RunID, RoundID: string;
  const Messages: TArray<TSanitizedPeerMessage>): TRoundOutputV2;
var
  Payloads: TArray<TJSONObject>;
  PeerIDs: TArray<string>;
  MsgTypes: TArray<Integer>;
  Confidences: TArray<Integer>;
  ExecIDs: TArray<string>;
  I: Integer;
  Cons: TConsolidationResultV2;
begin
  SetLength(Payloads, Length(Messages));
  SetLength(PeerIDs, Length(Messages));
  SetLength(MsgTypes, Length(Messages));
  SetLength(Confidences, Length(Messages));
  SetLength(ExecIDs, Length(Messages));

  for I := 0 to High(Messages) do
  begin
    Payloads[I] := Messages[I].Payload;
    PeerIDs[I] := Messages[I].PeerID;
    MsgTypes[I] := Messages[I].MsgType;
    Confidences[I] := Messages[I].Confidence;
    ExecIDs[I] := Messages[I].ExecutionIdentity;
  end;

  Cons := FConsolidation.Consolidate(
    RunID,
    RoundID,
    PeerIDs,
    MsgTypes,
    Confidences,
    ExecIDs,
    Payloads
  );

  Result.RoundIndex := StrToIntDef(RoundID.Split([':'])[1], 0);
  Result.ConsolidatedPayload := Cons.ConsolidatedPayload;
  Result.ConsolidatedExecutionIdentity := Cons.ConsolidatedExecutionIdentity;
  Result.WinningPeerID := Cons.WinningPeerID;
  Result.WinningScore := Cons.WinningScore;
  Result.Converged := False;
end;

function TGSDARoundOrchestratorV2.DetectConvergence(
  const Prev, Curr: TRoundOutputV2): Boolean;
begin
  if Prev.ConsolidatedPayload.ToJSON = Curr.ConsolidatedPayload.ToJSON then
    Exit(True);

  if Abs(Prev.WinningScore - Curr.WinningScore) < 0.0001 then
    Exit(True);

  Result := False;
end;

function TGSDARoundOrchestratorV2.BuildNextRoundID(
  const RunID: string; Index: Integer): string;
begin
  Result := TGSDAIdentityFactory.MakeDerived(
    'round',
    RunID,
    Index
  ).Value;
end;

function TGSDARoundOrchestratorV2.ExecuteRounds(
  const RunID: string;
  const RawMessagesPerRound: array of TArray<string>;
  const PeerIDsPerRound: array of TArray<string>;
  const MsgTypesPerRound: array of TArray<Integer>;
  const ConfidencesPerRound: array of TArray<Integer>): TRoundOutputV2;
var
  RoundIndex: Integer;
  RoundID: string;
  Messages: TArray<TSanitizedPeerMessage>;
  PrevOutput, CurrOutput: TRoundOutputV2;
begin
  RoundIndex := 0;
  RoundID := BuildNextRoundID(RunID, RoundIndex);

  Messages := CollectPeerMessages(
    RunID,
    RoundID,
    RawMessagesPerRound[RoundIndex],
    PeerIDsPerRound[RoundIndex],
    MsgTypesPerRound[RoundIndex],
    ConfidencesPerRound[RoundIndex]
  );

  CurrOutput := ConsolidateRound(RunID, RoundID, Messages);

  while RoundIndex < High(RawMessagesPerRound) do
  begin
    PrevOutput := CurrOutput;

    Inc(RoundIndex);
    RoundID := BuildNextRoundID(RunID, RoundIndex);

    Messages := CollectPeerMessages(
      RunID,
      RoundID,
      RawMessagesPerRound[RoundIndex],
      PeerIDsPerRound[RoundIndex],
      MsgTypesPerRound[RoundIndex],
      ConfidencesPerRound[RoundIndex]
    );

    CurrOutput := ConsolidateRound(RunID, RoundID, Messages);

    if DetectConvergence(PrevOutput, CurrOutput) then
    begin
      CurrOutput.Converged := True;
      Exit(CurrOutput);
    end;
  end;

  CurrOutput.Converged := False;
  Result := CurrOutput;
end;

end.
