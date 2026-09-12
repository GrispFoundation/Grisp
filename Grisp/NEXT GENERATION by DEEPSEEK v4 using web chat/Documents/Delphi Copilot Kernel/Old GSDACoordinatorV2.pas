unit GSDACoordinatorV2;

interface

uses
  System.SysUtils,
  System.JSON,
  GSDAKernelV2,
  GSDAIdentityFactory,
  GSDAIdentityRegistry,
  GSDATraceabilityV2,
  GSDACoverageV2,
  GSDAPublicationBundleV2,
  GSDARevisionLineageV2;

type
  TCoordinatorRoundState = record
    RoundID: string;
    RoundIndex: Integer;
    Completed: Boolean;
  end;

  TCoordinatorRunState = class
  private
    FRunID: string;
    FRounds: TArray<TCoordinatorRoundState>;
  public
    constructor Create(const ARunID: string);

    procedure AddRound(const RoundID: string; Index: Integer);
    procedure MarkRoundComplete(Index: Integer);

    property RunID: string read FRunID;
    property Rounds: TArray<TCoordinatorRoundState> read FRounds;
  end;

  TGSDACoordinatorV2 = class
  private
    FKernel: TGSDAKernelV2;
    FLineage: TGSDARevisionLineageV2;

    function StartNewRun: TCoordinatorRunState;
    function StartNewRound(RunState: TCoordinatorRunState): TCoordinatorRoundState;

    procedure ProcessPeerMessage(const PeerID, RunID, TaskID, RoundID: string;
                                 MsgType: Integer; Confidence: Integer;
                                 const Payload: string);

    procedure FinalizeRound(RunState: TCoordinatorRunState; RoundIndex: Integer);
    procedure FinalizeRun(RunState: TCoordinatorRunState);

    procedure PerformPublication;
  public
    constructor Create(AKernel: TGSDAKernelV2; ALineage: TGSDARevisionLineageV2);

    procedure ExecuteTask(const UserPrompt: string);
  end;

implementation

{ TCoordinatorRunState }

constructor TCoordinatorRunState.Create(const ARunID: string);
begin
  FRunID := ARunID;
  SetLength(FRounds, 0);
end;

procedure TCoordinatorRunState.AddRound(const RoundID: string; Index: Integer);
var
  R: TCoordinatorRoundState;
begin
  R.RoundID := RoundID;
  R.RoundIndex := Index;
  R.Completed := False;

  SetLength(FRounds, Length(FRounds) + 1);
  FRounds[High(FRounds)] := R;
end;

procedure TCoordinatorRunState.MarkRoundComplete(Index: Integer);
begin
  if (Index >= 0) and (Index < Length(FRounds)) then
    FRounds[Index].Completed := True;
end;

{ TGSDACoordinatorV2 }

constructor TGSDACoordinatorV2.Create(AKernel: TGSDAKernelV2;
                                      ALineage: TGSDARevisionLineageV2);
begin
  FKernel := AKernel;
  FLineage := ALineage;
end;

function TGSDACoordinatorV2.StartNewRun: TCoordinatorRunState;
var
  Run: TRun;
begin
  Run := FKernel.StartRun(FKernel.State.FTasks.Last);
  Result := TCoordinatorRunState.Create(Run.RunID);
end;

function TGSDACoordinatorV2.StartNewRound(RunState: TCoordinatorRunState): TCoordinatorRoundState;
var
  Index: Integer;
  RoundID: string;
begin
  Index := Length(RunState.Rounds);
  RoundID := TGSDAIdentityFactory.MakeDerived('round', RunState.RunID, Index).Value;

  RunState.AddRound(RoundID, Index);

  Result := RunState.Rounds[Index];
end;

procedure TGSDACoordinatorV2.ProcessPeerMessage(const PeerID, RunID, TaskID, RoundID: string;
                                                MsgType: Integer; Confidence: Integer;
                                                const Payload: string);
begin
  FKernel.ProcessIncomingFromT1(
    Payload,
    PeerID,
    RunID,
    TaskID,
    RoundID,
    TMessageType(MsgType),
    Confidence
  );
end;

procedure TGSDACoordinatorV2.FinalizeRound(RunState: TCoordinatorRunState; RoundIndex: Integer);
begin
  RunState.MarkRoundComplete(RoundIndex);
end;

procedure TGSDACoordinatorV2.FinalizeRun(RunState: TCoordinatorRunState);
begin
  // Nothing special yet — run finalization hooks go here
end;

procedure TGSDACoordinatorV2.PerformPublication;
var
  BundleBuilder: TPublicationBundleV2;
  Bundle: TJSONObject;
begin
  BundleBuilder := TPublicationBundleV2.Create(FKernel, FLineage);
  Bundle := BundleBuilder.BuildBundle;

  Writeln('Publication Bundle V2:');
  Writeln(Bundle.ToJSON);
end;

procedure TGSDACoordinatorV2.ExecuteTask(const UserPrompt: string);
var
  Task: TTask;
  RunState: TCoordinatorRunState;
  Round: TCoordinatorRoundState;
begin
  // 1. Create task
  Task := FKernel.CreateTask(
    UserPrompt,
    'general_intent',
    'general_domain',
    'default_namespace',
    'en',
    ['general_user'],
    [],
    ['final_output'],
    'default_priority'
  );

  // 2. Start run
  RunState := StartNewRun;

  // 3. Start round
  Round := StartNewRound(RunState);

  // 4. Simulate peer messages
  ProcessPeerMessage('peer1', RunState.RunID, Task.TaskID, Round.RoundID,
                     Ord(mtCandidate), 900,
                     '{"schema":"candidate","content":"example"}');

  ProcessPeerMessage('peer2', RunState.RunID, Task.TaskID, Round.RoundID,
                     Ord(mtCritique), 850,
                     '{"schema":"critique","content":"example"}');

  // 5. Finalize round
  FinalizeRound(RunState, Round.RoundIndex);

  // 6. Finalize run
  FinalizeRun(RunState);

  // 7. Publication
  PerformPublication;
end;

end.
