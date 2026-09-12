unit Grisp.Types;

interface

uses
  System.SysUtils, System.DateUtils;

type
  TGrispTaskId = string;
  TGrispArtifactId = string;
  TGrispEvidenceId = string;
  TGrispDecisionId = string;

  TGrispArtifactKind = (
    akExecutable, akLibrary, akUnit, akProject, akScript, akPatch,
    akDocumentation, akAnalysis);

  TGrispArtifactFileKind = (
    afkSource, afkTest, afkManifest, afkBinary, afkDoc, afkOther);

  TGrispContentEncoding = (ceUtf8, ceBase64);

  TGrispEvidenceOperation = (
    eoParse, eoStaticValidate, eoCompile, eoRun, eoTest,
    eoPolicyCheck, eoHash, eoFormat, eoLint, eoCommit, eoBrowser, eoOther);

  TGrispEvidenceStatus = (
    esOk, esFailed, esTimedOut, esCrashed, esCancelled, esParseError, esRejected);

  TGrispCandidateState = (
    csCreated, csParsed, csNormalized, csStaticValid, csCompilePending,
    csCompiled, csRuntimePending, csRuntimeVerified, csTestPending,
    csTestVerified, csPolicyVerified, csAcceptable, csSelected,
    csFinalVerified, csCommitted, csParseFailed, csStaticFailed,
    csPolicyRejected, csCompileFailed, csRuntimeFailed, csTestFailed,
    csTimeout, csCancelled, csCrashed, csVerificationFailed, csCommitFailed);

  TGrispDiagnostic = record
    Severity: string;
    Code: string;
    Line: Int64;
    Column: Int64;
    MessageText: string;
  end;

  TGrispArtifactFile = record
    FileName: string;
    Language: string;
    Kind: TGrispArtifactFileKind;
    Content: TBytes;
    ContentEncoding: TGrispContentEncoding;
    ContentSHA256: string;
    SizeBytes: Int64;
  end;

  TGrispProvenance = record
    Provider: string;
    WorkerId: string;
    SessionId: string;
    TabId: string;
    MessageId: string;
    PromptHash: string;
    ResponseHash: string;
    CreatedAt: string;
  end;

  TGrispArtifactBundle = record
    ArtifactId: TGrispArtifactId;
    TaskId: TGrispTaskId;
    ParentArtifactId: TGrispArtifactId;
    Revision: Int64;
    Files: TArray<TGrispArtifactFile>;
    ArtifactKind: TGrispArtifactKind;
    Language: string;
    Provenance: TGrispProvenance;
    MetadataJson: string;
  end;

  TGrispTask = record
    TaskId: TGrispTaskId;
    UserPrompt: string;
    TargetLanguage: string;
    TargetPlatform: string;
    RequestedArtifactKind: TGrispArtifactKind;
    Constraints: string;
    AcceptanceTests: string;
    RiskLevel: string;
    RequiredCapabilities: TArray<string>;
    PolicyProfile: string;
    CreatedAt: string;
    MetadataJson: string;
  end;

  TGrispEvidence = record
    EvidenceId: TGrispEvidenceId;
    TaskId: TGrispTaskId;
    ArtifactId: TGrispArtifactId;
    Operation: TGrispEvidenceOperation;
    Tool: string;
    Status: TGrispEvidenceStatus;
    ExitCode: Int64;
    Diagnostics: TArray<TGrispDiagnostic>;
    StdOut: string;
    StdErr: string;
    ElapsedMs: Int64;
    InputHash: string;
    OutputHash: string;
    EnvironmentId: string;
    Environment: string;
    CreatedAt: string;
    MetadataJson: string;
  end;

  TGrispToolResult = record
    Operation: TGrispEvidenceOperation;
    Status: TGrispEvidenceStatus;
    Success: Boolean;
    ExitCode: Int64;
    TimedOut: Boolean;
    Crashed: Boolean;
    StdOut: string;
    StdErr: string;
    Diagnostics: TArray<TGrispDiagnostic>;
    DurationMs: Int64;
    InputHash: string;
    OutputHash: string;
    EnvironmentId: string;
  end;

  TGrispDecision = record
    DecisionId: TGrispDecisionId;
    TaskId: TGrispTaskId;
    ArtifactId: TGrispArtifactId;
    Accepted: Boolean;
    Reason: string;
    EvidenceIds: TArray<TGrispEvidenceId>;
    FinalVerifiedArtifactId: TGrispArtifactId;
    AcceptanceRuleVersion: string;
    OrchestratorVersion: string;
    CreatedAt: string;
    Actor: string;
  end;

function NewUuid: string;
function UtcNowText: string;
function ArtifactKindName(const AValue: TGrispArtifactKind): string;
function FileKindName(const AValue: TGrispArtifactFileKind): string;
function ContentEncodingName(const AValue: TGrispContentEncoding): string;
function EvidenceStatusName(const AValue: TGrispEvidenceStatus): string;
function CandidateStateName(const AState: TGrispCandidateState): string;

implementation

function NewUuid: string;
begin
  Result := TGUID.NewGuid.ToString;
  Result := Result.Trim(['{', '}']).ToLowerInvariant;
end;

function UtcNowText: string;
begin
  Result := DateToISO8601(TTimeZone.Local.ToUniversalTime(Now), True);
end;

function ArtifactKindName(const AValue: TGrispArtifactKind): string;
const
  Names: array[TGrispArtifactKind] of string = (
    'EXECUTABLE', 'LIBRARY', 'UNIT', 'PROJECT', 'SCRIPT', 'PATCH',
    'DOCUMENTATION', 'ANALYSIS');
begin
  Result := Names[AValue];
end;

function FileKindName(const AValue: TGrispArtifactFileKind): string;
const
  Names: array[TGrispArtifactFileKind] of string = (
    'source', 'test', 'manifest', 'binary', 'doc', 'other');
begin
  Result := Names[AValue];
end;

function ContentEncodingName(const AValue: TGrispContentEncoding): string;
begin
  if AValue = ceUtf8 then Result := 'utf-8' else Result := 'base64';
end;

function EvidenceStatusName(const AValue: TGrispEvidenceStatus): string;
const
  Names: array[TGrispEvidenceStatus] of string = (
    'ok', 'failed', 'timed_out', 'crashed', 'cancelled', 'parse_error', 'rejected');
begin
  Result := Names[AValue];
end;

function CandidateStateName(const AState: TGrispCandidateState): string;
const
  Names: array[TGrispCandidateState] of string = (
    'CREATED', 'PARSED', 'NORMALIZED', 'STATIC_VALID', 'COMPILE_PENDING',
    'COMPILED', 'RUNTIME_PENDING', 'RUNTIME_VERIFIED', 'TEST_PENDING',
    'TEST_VERIFIED', 'POLICY_VERIFIED', 'ACCEPTABLE', 'SELECTED',
    'FINAL_VERIFIED', 'COMMITTED', 'PARSE_FAILED', 'STATIC_FAILED',
    'POLICY_REJECTED', 'COMPILE_FAILED', 'RUNTIME_FAILED', 'TEST_FAILED',
    'TIMEOUT', 'CANCELLED', 'CRASHED', 'VERIFICATION_FAILED', 'COMMIT_FAILED');
begin
  Result := Names[AState];
end;

end.