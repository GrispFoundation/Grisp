unit Grisp.StateMachine;

interface

uses
  System.SysUtils, System.Classes, System.DateUtils,
  Grisp.Types, Grisp.Canonical, Grisp.Parser, Grisp.MockCompiler, Grisp.MockTestRunner;

type
  /// <summary>
  /// Fail-closed state machine orchestrator that controls candidate lifecycle,
  /// pipeline transitions, and evidence verification gates.
  /// </summary>
  TGrispStateMachine = class
  private
    FCompiler: TGrispMockCompiler;
    FTestRunner: TGrispMockTestRunner;
    FOwnsHarnesses: Boolean;

    procedure LogTransition(
      var ACandidate: TGrispCandidate; 
      AStage: TGrispCandidateState; 
      ASuccess: Boolean; 
      AExitCode: Integer; 
      const AMessage: string
    );
    function VerifyEvidenceChain(const ACandidate: TGrispCandidate): Boolean;
  public
    constructor Create; overload;
    constructor Create(ACompiler: TGrispMockCompiler; ATestRunner: TGrispMockTestRunner); overload;
    destructor Destroy; override;

    /// <summary>
    /// Executes full deterministic pipeline: Parse -> Compile -> Test.
    /// Returns False and marks csRejected if any gate condition fails.
    /// </summary>
    function ProcessResponse(
      const AResponse: string; 
      const ASessionID: TGrispSessionID; 
      const ATabID: TGrispTabID; 
      out ACandidate: TGrispCandidate
    ): Boolean;

    /// <summary>
    /// Promotes a verified candidate to csAccepted after verifying complete evidence history.
    /// Fails closed if proof of compilation and test execution is missing.
    /// </summary>
    function AcceptCandidate(var ACandidate: TGrispCandidate): Boolean;
  end;

implementation

constructor TGrispStateMachine.Create;
begin
  Create(TGrispMockCompiler.Create, TGrispMockTestRunner.Create);
  FOwnsHarnesses := True;
end;

constructor TGrispStateMachine.Create(ACompiler: TGrispMockCompiler; ATestRunner: TGrispMockTestRunner);
begin
  inherited Create;
  FCompiler := ACompiler;
  FTestRunner := ATestRunner;
  FOwnsHarnesses := False;
end;

destructor TGrispStateMachine.Destroy;
begin
  if FOwnsHarnesses then
  begin
    FCompiler.Free;
    FTestRunner.Free;
  end;
  inherited Destroy;
end;

procedure TGrispStateMachine.LogTransition(
  var ACandidate: TGrispCandidate; 
  AStage: TGrispCandidateState; 
  ASuccess: Boolean; 
  AExitCode: Integer; 
  const AMessage: string
);
var
  Evidence: TGrispEvidence;
begin
  Evidence.Timestamp := Now;
  Evidence.Stage := AStage;
  Evidence.Success := ASuccess;
  Evidence.ExitCode := AExitCode;
  Evidence.OutputLog := AMessage;
  
  if Length(ACandidate.Manifest.RawBytes) > 0 then
    Evidence.ArtifactHash := TGrispCanonical.ComputeSHA256(ACandidate.Manifest.RawBytes)
  else
    Evidence.ArtifactHash := '';

  SetLength(ACandidate.EvidenceLog, Length(ACandidate.EvidenceLog) + 1);
  ACandidate.EvidenceLog[High(ACandidate.EvidenceLog)] := Evidence;
end;

function TGrispStateMachine.VerifyEvidenceChain(const ACandidate: TGrispCandidate): Boolean;
var
  HasCompileEvidence, HasTestEvidence: Boolean;
  Evidence: TGrispEvidence;
begin
  HasCompileEvidence := False;
  HasTestEvidence := False;

  for Evidence in ACandidate.EvidenceLog do
  begin
    if (Evidence.Stage = csCompiling) and Evidence.Success then
      HasCompileEvidence := True;
    if (Evidence.Stage = csTesting) and Evidence.Success then
      HasTestEvidence := True;
  end;

  Result := HasCompileEvidence and HasTestEvidence;
end;

function TGrispStateMachine.ProcessResponse(
  const AResponse: string; 
  const ASessionID: TGrispSessionID; 
  const ATabID: TGrispTabID; 
  out ACandidate: TGrispCandidate
): Boolean;
begin
  // Gate 1: Fail-closed single block parsing
  if not TGrispParser.ParseResponse(AResponse, ASessionID, ATabID, ACandidate) then
  begin
    LogTransition(ACandidate, csCreated, False, -1, 'Parser Gate: Parsing failed or block structure ambiguous.');
    Exit(False);
  end;
  
  LogTransition(ACandidate, csParsed, True, 0, 'Parser Gate: Candidate payload extracted and hashed.');

  // Gate 2: Mock Compilation
  if not FCompiler.Compile(ACandidate) then
  begin
    LogTransition(ACandidate, csCompiling, False, 1, 'Compiler Gate: Code compilation failed.');
    Exit(False);
  end;

  // Gate 3: Test Runner Execution
  if not FTestRunner.RunTests(ACandidate) then
  begin
    LogTransition(ACandidate, csTesting, False, 1, 'Test Gate: Candidate failed verification test suite.');
    Exit(False);
  end;

  Result := True;
end;

function TGrispStateMachine.AcceptCandidate(var ACandidate: TGrispCandidate): Boolean;
begin
  // Fail-closed gate: Must be in csVerified state and pass objective evidence audit
  if (ACandidate.State <> csVerified) or not VerifyEvidenceChain(ACandidate) then
  begin
    ACandidate.State := csRejected;
    ACandidate.LastError := errTestFailed;
    LogTransition(ACandidate, csRejected, False, -1, 'Acceptance Gate: Rejected due to invalid state or incomplete evidence chain.');
    Exit(False);
  end;

  ACandidate.State := csAccepted;
  ACandidate.LastError := errNone;
  LogTransition(ACandidate, csAccepted, True, 0, 'Acceptance Gate: Candidate successfully accepted into target codebase.');

  Result := True;
end;

end.