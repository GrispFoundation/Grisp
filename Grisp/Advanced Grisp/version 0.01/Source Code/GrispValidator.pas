unit GrispValidator;

interface

uses
  SysUtils, Classes, Generics.Collections,
  GrispEIR, GrispToolManifest, GrispWorldState;

type
  TValidator = class
  private
    FWorldState: TWorldState;
    FManifests: TToolManifestRegistry;
    FErrorCode: string;
    FErrorMessage: string;
    procedure CheckSyntax(const EIRText: string);
    procedure CheckUndefinedVariables(const EIRText: string);
    procedure CheckTypeMismatches(const EIRText: string);
    procedure CheckMissingToolArguments(const EIRText: string);
    procedure CheckInvalidTransitions(const EIRText: string);
    procedure CheckMissingCapabilities(const EIRText: string);
    procedure CheckDependencyCycles(const EIRText: string);
    procedure CheckPolicyViolations(const EIRText: string);
    procedure CheckResourceLimits(const EIRText: string);
    procedure CheckPreconditions(const EIRText: string);
    procedure CheckSideEffectConsistency(const EIRText: string);
    procedure CheckTransitionConditions(const EIRText: string);
    procedure CheckCostExpressions(const EIRText: string);
    procedure CheckBundleStrategies(const EIRText: string);
  public
    constructor Create(WorldState: TWorldState; Manifests: TToolManifestRegistry);
    function Validate(var EIRText: string): Boolean;
    property ErrorCode: string read FErrorCode;
    property ErrorMessage: string read FErrorMessage;
  end;

implementation

uses GrispMarkerParser;

{ TValidator }

constructor TValidator.Create(WorldState: TWorldState; Manifests: TToolManifestRegistry);
begin
  FWorldState := WorldState;
  FManifests := Manifests;
end;

function TValidator.Validate(var EIRText: string): Boolean;
var
  Expanded: string;
begin
  Expanded := ExpandCEIR(EIRText);
  try
    CheckSyntax(Expanded);
    CheckUndefinedVariables(Expanded);
    CheckTypeMismatches(Expanded);
    CheckMissingToolArguments(Expanded);
    CheckInvalidTransitions(Expanded);
    CheckMissingCapabilities(Expanded);
    CheckDependencyCycles(Expanded);
    CheckPolicyViolations(Expanded);
    CheckResourceLimits(Expanded);
    CheckPreconditions(Expanded);
    CheckSideEffectConsistency(Expanded);
    CheckTransitionConditions(Expanded);
    CheckCostExpressions(Expanded);
    CheckBundleStrategies(Expanded);
    EIRText := Expanded;
    Result := True;
  except
    on E: Exception do
    begin
      FErrorMessage := E.Message;
      Result := False;
    end;
  end;
end;

procedure TValidator.CheckSyntax(const EIRText: string);
var
  Doc: TDocument;
begin
  Doc := TDocument.Create;
  try
    if not Doc.Parse(EIRText) then
      raise Exception.Create('V001: Syntax error in EIR');
    if not Assigned(Doc.Root.FindChild('PROGRAM')) then
      raise Exception.Create('V001: Missing PROGRAM block');
  finally
    Doc.Free;
  end;
end;

procedure TValidator.CheckUndefinedVariables(const EIRText: string);
var
  Doc: TDocument;
  Vars: TDictionary<string, Boolean>;
  Prog: TBlock;
  b: TBlock;
  assignText: string;
  eqPos: Integer;
  varName: string;
begin
  Doc := TDocument.Create;
  Vars := TDictionary<string, Boolean>.Create;
  try
    Doc.Parse(EIRText);
    Prog := Doc.Root.FindChild('PROGRAM');
    if not Assigned(Prog) then Exit;
    for b in Prog.Children do
      if SameText(b.Name, 'VARIABLE') then
        Vars.AddOrSetValue(Trim(b.Content), True);
    for b in Prog.Children do
      if SameText(b.Name, 'ASSIGNMENT') then
      begin
        assignText := Trim(b.Content);
        eqPos := Pos('=', assignText);
        if eqPos > 0 then
        begin
          varName := Trim(Copy(assignText, 1, eqPos-1));
          if not Vars.ContainsKey(varName) then   // <-- 'then' added here
            raise Exception.Create('V002: Undefined variable "' + varName + '"');
        end;
      end;
  finally
    Vars.Free;
    Doc.Free;
  end;
end;

procedure TValidator.CheckTypeMismatches(const EIRText: string);
begin
  // Stub
end;

procedure TValidator.CheckMissingToolArguments(const EIRText: string);
begin
  // Stub
end;

procedure TValidator.CheckInvalidTransitions(const EIRText: string);
begin
  // Stub
end;

procedure TValidator.CheckMissingCapabilities(const EIRText: string);
begin
  // Stub
end;

procedure TValidator.CheckDependencyCycles(const EIRText: string);
begin
  // Stub
end;

procedure TValidator.CheckPolicyViolations(const EIRText: string);
begin
  // Stub
end;

procedure TValidator.CheckResourceLimits(const EIRText: string);
begin
  // Stub
end;

procedure TValidator.CheckPreconditions(const EIRText: string);
begin
  // Stub
end;

procedure TValidator.CheckSideEffectConsistency(const EIRText: string);
begin
  // Stub
end;

procedure TValidator.CheckTransitionConditions(const EIRText: string);
begin
  // Stub
end;

procedure TValidator.CheckCostExpressions(const EIRText: string);
begin
  // Stub
end;

procedure TValidator.CheckBundleStrategies(const EIRText: string);
begin
  // Stub
end;

end.
