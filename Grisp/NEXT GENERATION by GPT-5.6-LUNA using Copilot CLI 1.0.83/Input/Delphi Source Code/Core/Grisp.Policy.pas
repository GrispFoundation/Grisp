unit Grisp.Policy;

interface

uses
  System.SysUtils, Grisp.Types;

type
  TGrispPolicyCheck = record
    PolicyId: string;
    Passed: Boolean;
    Details: string;
  end;
  TGrispPolicyResult = record
    PolicyProfile: string;
    CapabilitiesRequested: TArray<string>;
    CapabilitiesGranted: TArray<string>;
    Checks: TArray<TGrispPolicyCheck>;
    ResultName: string;
    Reason: string;
  end;
  IGrispPolicyEngine = interface
    function Evaluate(const ATask: TGrispTask; const AArtifact: TGrispArtifactBundle): TGrispPolicyResult;
  end;
  TGrispFailClosedPolicy = class(TInterfacedObject, IGrispPolicyEngine)
    function Evaluate(const ATask: TGrispTask; const AArtifact: TGrispArtifactBundle): TGrispPolicyResult;
  end;

implementation

function TGrispFailClosedPolicy.Evaluate(const ATask: TGrispTask;
  const AArtifact: TGrispArtifactBundle): TGrispPolicyResult;
var
  I: Integer;
begin
  Result.PolicyProfile := ATask.PolicyProfile;
  Result.CapabilitiesRequested := Copy(ATask.RequiredCapabilities);
  SetLength(Result.CapabilitiesGranted, 0);
  SetLength(Result.Checks, Length(ATask.RequiredCapabilities));
  Result.ResultName := 'PASS';
  Result.Reason := '';
  for I := 0 to Length(ATask.RequiredCapabilities) - 1 do
  begin
    Result.Checks[I].PolicyId := ATask.RequiredCapabilities[I];
    Result.Checks[I].Passed := ATask.RequiredCapabilities[I] <> '';
    Result.Checks[I].Details := 'Capability must be explicitly named and authorized';
    if Result.Checks[I].Passed then
    begin
      SetLength(Result.CapabilitiesGranted, Length(Result.CapabilitiesGranted) + 1);
      Result.CapabilitiesGranted[High(Result.CapabilitiesGranted)] := ATask.RequiredCapabilities[I];
    end
    else
      Result.ResultName := 'FAIL';
  end;
  if AArtifact.TaskId <> ATask.TaskId then
  begin
    Result.ResultName := 'FAIL';
    Result.Reason := 'artifact task mismatch';
  end;
end;

end.
