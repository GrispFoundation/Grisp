unit Grisp.MockCompiler;

interface

uses
  System.SysUtils, System.Classes, System.DateUtils, Grisp.Types, Grisp.Canonical;

type
  /// <summary>
  /// Deterministic mock compiler harness for verifying candidate state transitions
  /// and evidence logging without requiring an active toolchain installation.
  /// </summary>
  TGrispMockCompiler = class
  private
    FForceFailure: Boolean;
    FMockOutputLog: string;
  public
    constructor Create(AForceFailure: Boolean = False);

    /// <summary>
    /// Evaluates candidate manifest bytes, logs proof, and advances state machine.
    /// Fails closed if candidate state is invalid or compilation fails.
    /// </summary>
    function Compile(var ACandidate: TGrispCandidate): Boolean;

    property ForceFailure: Boolean read FForceFailure write FForceFailure;
    property MockOutputLog: string read FMockOutputLog write FMockOutputLog;
  end;

implementation

constructor TGrispMockCompiler.Create(AForceFailure: Boolean);
begin
  inherited Create;
  FForceFailure := AForceFailure;
  FMockOutputLog := '';
end;

function TGrispMockCompiler.Compile(var ACandidate: TGrispCandidate): Boolean;
var
  Evidence: TGrispEvidence;
  SourceCode: string;
  IsSuccess: Boolean;
begin
  // Gate 1: Enforce state precondition
  if ACandidate.State <> csParsed then
  begin
    ACandidate.State := csRejected;
    ACandidate.LastError := errCompileFailed;
    Exit(False);
  end;

  ACandidate.State := csCompiling;
  SourceCode := TEncoding.UTF8.GetString(ACandidate.Manifest.RawBytes);

  // Gate 2: Evaluate mock failure triggers in source payload
  IsSuccess := not FForceFailure and 
               not SourceCode.Contains('[SYNTAX_ERROR]') and 
               not SourceCode.Contains('COMPILER_FAIL');

  // Build tamper-evident log entry
  Evidence.Timestamp := Now;
  Evidence.Stage := csCompiling;
  Evidence.Success := IsSuccess;

  if IsSuccess then
  begin
    Evidence.ExitCode := 0;
    Evidence.OutputLog := 'MockCompiler: Target unit compiled successfully. 0 Errors, 0 Warnings.';
    // Simulate deterministic artifact hash generated from raw source
    Evidence.ArtifactHash := TGrispCanonical.ComputeSHA256(SourceCode + '_MOCK_EXEC');
    
    ACandidate.State := csCompiled;
    ACandidate.LastError := errNone;
  end
  else
  begin
    Evidence.ExitCode := 1;
    if not FMockOutputLog.IsEmpty then
      Evidence.OutputLog := FMockOutputLog
    else
      Evidence.OutputLog := 'MockCompiler: Fatal syntax error encountered during syntax tree emission.';
    Evidence.ArtifactHash := '';

    ACandidate.State := csRejected;
    ACandidate.LastError := errCompileFailed;
  end;

  // Record objective proof into evidence log
  SetLength(ACandidate.EvidenceLog, Length(ACandidate.EvidenceLog) + 1);
  ACandidate.EvidenceLog[High(ACandidate.EvidenceLog)] := Evidence;

  Result := IsSuccess;
end;

end.