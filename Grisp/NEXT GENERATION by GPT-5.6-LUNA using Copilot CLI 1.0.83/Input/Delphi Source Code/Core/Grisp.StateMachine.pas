unit Grisp.StateMachine;

interface

uses
  System.SysUtils, Grisp.Types;

function CandidateStateName(const AState: TGrispCandidateState): string;
function CanTransition(const ACurrent: TGrispCandidateState;
  const AEvent: string; out ANext: TGrispCandidateState; out AReason: string): Boolean;

implementation

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

function CanTransition(const ACurrent: TGrispCandidateState;
  const AEvent: string; out ANext: TGrispCandidateState; out AReason: string): Boolean;
begin
  Result := True;
  AReason := '';
  ANext := ACurrent;
  if (ACurrent = csCreated) and (AEvent = 'parsed') then ANext := csParsed
  else if (ACurrent = csParsed) and (AEvent = 'normalized') then ANext := csNormalized
  else if (ACurrent = csNormalized) and (AEvent = 'static_ok') then ANext := csStaticValid
  else if (ACurrent = csStaticValid) and (AEvent = 'compile_pending') then ANext := csCompilePending
  else if (ACurrent = csCompilePending) and (AEvent = 'compile_ok') then ANext := csCompiled
  else if (ACurrent = csCompiled) and (AEvent = 'runtime_pending') then ANext := csRuntimePending
  else if (ACurrent = csRuntimePending) and (AEvent = 'runtime_ok') then ANext := csRuntimeVerified
  else if (ACurrent in [csCompiled, csRuntimeVerified]) and (AEvent = 'test_pending') then ANext := csTestPending
  else if (ACurrent = csTestPending) and (AEvent = 'test_ok') then ANext := csTestVerified
  else if (ACurrent in [csTestVerified, csRuntimeVerified, csCompiled]) and
    (AEvent = 'policy_ok') then ANext := csPolicyVerified
  else if (ACurrent = csPolicyVerified) and (AEvent = 'acceptable') then ANext := csAcceptable
  else if (ACurrent = csAcceptable) and (AEvent = 'selected') then ANext := csSelected
  else if (ACurrent = csSelected) and (AEvent = 'final_ok') then ANext := csFinalVerified
  else if (ACurrent = csFinalVerified) and (AEvent = 'committed') then ANext := csCommitted
  else if AEvent = 'parse_failed' then ANext := csParseFailed
  else if AEvent = 'static_failed' then ANext := csStaticFailed
  else if AEvent = 'policy_failed' then ANext := csPolicyRejected
  else if AEvent = 'compile_failed' then ANext := csCompileFailed
  else if AEvent = 'runtime_failed' then ANext := csRuntimeFailed
  else if AEvent = 'test_failed' then ANext := csTestFailed
  else if AEvent = 'timeout' then ANext := csTimeout
  else if AEvent = 'cancelled' then ANext := csCancelled
  else if AEvent = 'crashed' then ANext := csCrashed
  else begin Result := False; AReason := 'invalid state transition'; end;
end;

end.
