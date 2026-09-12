unit Grisp.Agent;

interface

uses
  System.SysUtils, Grisp.Types, Grisp.Artifact, Grisp.Policy, Grisp.Commit;

type
  IGrispCompiler = interface
    function Compile(const AArtifact: TGrispArtifactBundle; out AEvidence: TGrispEvidence): Boolean;
  end;

  IGrispRuntime = interface
    function Run(const AArtifact: TGrispArtifactBundle; out AEvidence: TGrispEvidence): Boolean;
  end;

  IGrispTestRunner = interface
    function Test(const AArtifact: TGrispArtifactBundle; out AEvidence: TGrispEvidence): Boolean;
  end;

  TGrispAgent = class
  private
    FPolicy: IGrispPolicyEngine;
    FCompiler: IGrispCompiler;
    FRuntime: IGrispRuntime;
    FTestRunner: IGrispTestRunner;
  public
    constructor Create(
      APolicy: IGrispPolicyEngine;
      ACompiler: IGrispCompiler;
      ARuntime: IGrispRuntime;
      ATestRunner: IGrispTestRunner
    );

    function ExecuteTask(
      const ATask: TGrispTask;
      const AArtifact: TGrispArtifactBundle;
      const AFinalRoot: string;
      out ADecision: TGrispDecision;
      out AError: string
    ): Boolean;
  end;

implementation

constructor TGrispAgent.Create(
  APolicy: IGrispPolicyEngine;
  ACompiler: IGrispCompiler;
  ARuntime: IGrispRuntime;
  ATestRunner: IGrispTestRunner
);
begin
  inherited Create;
  FPolicy := APolicy;
  FCompiler := ACompiler;
  FRuntime := ARuntime;
  FTestRunner := ATestRunner;
end;

function TGrispAgent.ExecuteTask(
  const ATask: TGrispTask;
  const AArtifact: TGrispArtifactBundle;
  const AFinalRoot: string;
  out ADecision: TGrispDecision;
  out AError: string
): Boolean;
var
  Evidence: TGrispEvidence;
  PolicyResult: TGrispPolicyResult;
  CompileOK, RuntimeOK, TestOK: Boolean;
begin
  AError := '';
  ADecision := Default(TGrispDecision);
  ADecision.DecisionId := NewUuid;
  ADecision.TaskId := ATask.TaskId;
  ADecision.ArtifactId := AArtifact.ArtifactId;
  ADecision.CreatedAt := UtcNowText;
  ADecision.AcceptanceRuleVersion := '2.0';
  ADecision.OrchestratorVersion := '2.0';

  // 1. Artifact validation.
  if not ValidateArtifact(AArtifact, AError) then
  begin
    ADecision.Accepted := False;
    ADecision.Reason := 'ARTIFACT_INVALID: ' + AError;
    Exit(False);
  end;

  // 2. Policy.
  PolicyResult := FPolicy.Evaluate(ATask, AArtifact);
  if PolicyResult.ResultName <> 'PASS' then
  begin
    ADecision.Accepted := False;
    ADecision.Reason := 'POLICY_' + PolicyResult.ResultName + ': ' + PolicyResult.Reason;
    Exit(False);
  end;

  // 3. Compile.
  CompileOK := FCompiler.Compile(AArtifact, Evidence);
  if not CompileOK then
  begin
    ADecision.Accepted := False;
    ADecision.Reason := 'COMPILE_FAILED';
    Exit(False);
  end;

  // 4. Runtime.
  RuntimeOK := FRuntime.Run(AArtifact, Evidence);
  if not RuntimeOK then
  begin
    ADecision.Accepted := False;
    ADecision.Reason := 'RUNTIME_FAILED';
    Exit(False);
  end;

  // 5. Tests.
  TestOK := FTestRunner.Test(AArtifact, Evidence);
  if not TestOK then
  begin
    ADecision.Accepted := False;
    ADecision.Reason := 'TEST_FAILED';
    Exit(False);
  end;

  // 6. Commit.
  if not CommitArtifact(AArtifact, AFinalRoot, Evidence, AError) then
  begin
    ADecision.Accepted := False;
    ADecision.Reason := 'COMMIT_FAILED: ' + AError;
    Exit(False);
  end;

  ADecision.Accepted := True;
  ADecision.Reason := 'ACCEPTED';
  ADecision.FinalVerifiedArtifactId := AArtifact.ArtifactId;
  Result := True;
end;

end.