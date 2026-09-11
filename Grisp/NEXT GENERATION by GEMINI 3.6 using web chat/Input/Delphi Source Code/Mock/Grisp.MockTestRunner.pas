unit Grisp.MockTestRunner;

interface

uses
  System.SysUtils, System.Classes, System.DateUtils, Grisp.Types, Grisp.Canonical;

type
  /// <summary>
  /// Mock test execution harness for running test vectors against compiled candidates
  /// and generating verifiable evidence logs prior to final acceptance.
  /// </summary>
  TGrispMockTestRunner = class
  private
    FForceFailure: Boolean;
    FMockOutputLog: string;
  public
    constructor Create(AForceFailure: Boolean = False);

    /// <summary>
    /// Evaluates compiled candidate against test suite, records evidence,
    /// and advances state machine to csVerified or csRejected.
    /// </summary>
    function RunTests(var ACandidate: TGrispCandidate): Boolean;

    property ForceFailure: Boolean read FForceFailure write FForceFailure;
    property MockOutputLog: string read FMockOutputLog write FMockOutputLog;
  end;

implementation

constructor TGrispMockTestRunner.Create(AForceFailure: Boolean);
begin
  inherited Create;
  FForceFailure := AForceFailure;
  FMockOutputLog := '';
end;

function TGrispMockTestRunner.RunTests(var ACandidate: TGrispCandidate): Boolean;
var
  Evidence: TGrispEvidence;
  SourceCode: string;
  IsSuccess: Boolean;
begin
  // Gate 1: Enforce prerequisite compiled state
  if ACandidate.State <> csCompiled then
  begin
    ACandidate.State := csRejected;
    ACandidate.LastError := errTestFailed;
    Exit(False);
  end;

  ACandidate.State := csTesting;
  SourceCode := TEncoding.UTF8.GetString(ACandidate.Manifest.RawBytes);

  // Gate 2: Evaluate mock failure triggers within test suite
  IsSuccess := not FForceFailure and 
               not SourceCode.Contains('[TEST_FAIL]') and 
               not SourceCode.Contains('ASSERTION_ERROR');

  // Build test execution proof
  Evidence.Timestamp := Now;
  Evidence.Stage := csTesting;
  Evidence.Success := IsSuccess;

  if IsSuccess then
  begin
    Evidence.ExitCode := 0;
    Evidence.OutputLog := 'MockTestRunner: 12 test assertions executed. 0 Failures, 0 Skipped.';
    Evidence.ArtifactHash := TGrispCanonical.ComputeSHA256(SourceCode + '_MOCK_TEST_PASS');

    ACandidate.State := csVerified;
    ACandidate.LastError := errNone;
  end
  else
  begin
    Evidence.ExitCode := 1;
    if not FMockOutputLog.IsEmpty then
      Evidence.OutputLog := FMockOutputLog
    else
      Evidence.OutputLog := 'MockTestRunner: Assertion failure at line 42 (Expected TRUE, got FALSE).';
    Evidence.ArtifactHash := '';

    ACandidate.State := csRejected;
    ACandidate.LastError := errTestFailed;
  end;

  // Append proof to immutable candidate evidence log
  SetLength(ACandidate.EvidenceLog, Length(ACandidate.EvidenceLog) + 1);
  ACandidate.EvidenceLog[High(ACandidate.EvidenceLog)] := Evidence;

  Result := IsSuccess;
end;

end.