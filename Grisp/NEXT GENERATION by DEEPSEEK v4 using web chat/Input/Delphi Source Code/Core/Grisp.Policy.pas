unit Grisp.Policy;

interface

uses
  System.SysUtils, System.Generics.Collections, Grisp.Types;

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
    ResultName: string; // PASS, FAIL, REQUIRES_HUMAN_APPROVAL
    Reason: string;
  end;

  IGrispPolicyEngine = interface
    function Evaluate(const ATask: TGrispTask; const AArtifact: TGrispArtifactBundle): TGrispPolicyResult;
  end;

  TGrispFailClosedPolicy = class(TInterfacedObject, IGrispPolicyEngine)
  private
    FAllowList: TDictionary<string, Boolean>;
    FHighRisk: TDictionary<string, Boolean>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Allow(const ACapability: string);
    procedure MarkHighRisk(const ACapability: string);
    function Evaluate(const ATask: TGrispTask; const AArtifact: TGrispArtifactBundle): TGrispPolicyResult;
  end;

implementation

constructor TGrispFailClosedPolicy.Create;
begin
  inherited;
  FAllowList := TDictionary<string, Boolean>.Create;
  FHighRisk := TDictionary<string, Boolean>.Create;
end;

destructor TGrispFailClosedPolicy.Destroy;
begin
  FAllowList.Free;
  FHighRisk.Free;
  inherited;
end;

procedure TGrispFailClosedPolicy.Allow(const ACapability: string);
begin
  FAllowList.AddOrSetValue(ACapability, True);
end;

procedure TGrispFailClosedPolicy.MarkHighRisk(const ACapability: string);
begin
  FHighRisk.AddOrSetValue(ACapability, True);
end;

function TGrispFailClosedPolicy.Evaluate(const ATask: TGrispTask;
  const AArtifact: TGrispArtifactBundle): TGrispPolicyResult;
var
  I: Integer;
  Cap: string;
  Allowed: Boolean;
  NeedsHuman: Boolean;
begin
  Result.PolicyProfile := ATask.PolicyProfile;
  Result.CapabilitiesRequested := Copy(ATask.RequiredCapabilities);
  SetLength(Result.CapabilitiesGranted, 0);
  SetLength(Result.Checks, Length(ATask.RequiredCapabilities));
  Result.ResultName := 'PASS';
  Result.Reason := '';
  NeedsHuman := False;

  for I := 0 to High(ATask.RequiredCapabilities) do
  begin
    Cap := ATask.RequiredCapabilities[I];
    Result.Checks[I].PolicyId := Cap;

    Allowed := FAllowList.ContainsKey(Cap);
    Result.Checks[I].Passed := Allowed;

    if Allowed then
    begin
      SetLength(Result.CapabilitiesGranted, Length(Result.CapabilitiesGranted) + 1);
      Result.CapabilitiesGranted[High(Result.CapabilitiesGranted)] := Cap;
      Result.Checks[I].Details := 'authorized by allowlist';
      if FHighRisk.ContainsKey(Cap) then
        NeedsHuman := True;
    end
    else
    begin
      Result.Checks[I].Details := 'not authorized';
      Result.ResultName := 'FAIL';
      Result.Reason := Result.Reason + Cap + ':not_authorized;';
    end;
  end;

  if (Result.ResultName = 'PASS') and NeedsHuman then
  begin
    Result.ResultName := 'REQUIRES_HUMAN_APPROVAL';
    Result.Reason := 'high-risk capability requires human approval';
  end;

  if AArtifact.TaskId <> ATask.TaskId then
  begin
    Result.ResultName := 'FAIL';
    Result.Reason := 'artifact task mismatch';
  end;
end;

end.