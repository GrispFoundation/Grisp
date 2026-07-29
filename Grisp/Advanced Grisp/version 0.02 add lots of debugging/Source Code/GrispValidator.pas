{$DEFINE DEBUG}
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
    FDebugLog: TStringList;
    procedure Debug(const Msg: string);
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
    destructor Destroy; override;
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
  FDebugLog := TStringList.Create;
  FDebugLog.Add('=== Validator started ===');
end;

destructor TValidator.Destroy;
begin
  FDebugLog.Free;
  inherited;
end;

procedure TValidator.Debug(const Msg: string);
begin
  {$IFDEF DEBUG}
  FDebugLog.Add(Msg);
  Writeln(ErrOutput, '[Validator] ', Msg);
  {$ENDIF}
end;

function TValidator.Validate(var EIRText: string): Boolean;
var
  Expanded: string;
begin
  Debug('Validate: input EIR length = ' + IntToStr(Length(EIRText)));
  Expanded := ExpandCEIR(EIRText);
  Debug('Validate: after expansion, length = ' + IntToStr(Length(Expanded)));
  // Save expanded text for inspection
  var sl := TStringList.Create;
  try
    sl.Text := Expanded;
    sl.SaveToFile('expanded_eir_debug.txt');
    Debug('Validate: saved expanded EIR to expanded_eir_debug.txt');
    if Length(Expanded) > 0 then
      Debug('Validate: first 200 chars: ' + Copy(Expanded, 1, 200));
  finally
    sl.Free;
  end;
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
      // Log the error
      Debug('Validation failed: ' + FErrorMessage);
      var LogFile := TStringList.Create;
      try
        LogFile.Add('=== Validation error ===');
        LogFile.Add('Error: ' + FErrorMessage);
        LogFile.Add('Stack trace: ' + E.StackTrace);
        LogFile.Add('Expanded EIR:');
        LogFile.Text := Expanded;
        LogFile.SaveToFile('validator_error.log');
      finally
        LogFile.Free;
      end;
    end;
  end;
end;

procedure TValidator.CheckSyntax(const EIRText: string);
var
  Doc: TDocument;
begin
  Debug('CheckSyntax: parsing document...');
  Doc := TDocument.Create;
  try
    if not Doc.Parse(EIRText) then
    begin
      Debug('CheckSyntax: parse returned False');
      raise Exception.Create('V001: Syntax error in EIR');
    end;
    Debug('CheckSyntax: parse succeeded');
    var Prog := Doc.Root.FindChild('PROGRAM');
    if not Assigned(Prog) then
    begin
      Debug('CheckSyntax: PROGRAM block not found');
      Debug('CheckSyntax: Root has ' + IntToStr(Doc.Root.Children.Count) + ' children');
      for var i := 0 to Doc.Root.Children.Count - 1 do
        Debug('  child[' + IntToStr(i) + '] name = ' + Doc.Root.Children[i].Name);
      raise Exception.Create('V001: Missing PROGRAM block');
    end;
    Debug('CheckSyntax: PROGRAM block found');
  finally
    Doc.Free;
  end;
end;

procedure TValidator.CheckUndefinedVariables(const EIRText: string);
begin
  // stub
  Debug('CheckUndefinedVariables: skipped (stub)');
end;

procedure TValidator.CheckTypeMismatches(const EIRText: string);
begin
  Debug('CheckTypeMismatches: skipped (stub)');
end;

procedure TValidator.CheckMissingToolArguments(const EIRText: string);
begin
  Debug('CheckMissingToolArguments: skipped (stub)');
end;

procedure TValidator.CheckInvalidTransitions(const EIRText: string);
begin
  Debug('CheckInvalidTransitions: skipped (stub)');
end;

procedure TValidator.CheckMissingCapabilities(const EIRText: string);
begin
  Debug('CheckMissingCapabilities: skipped (stub)');
end;

procedure TValidator.CheckDependencyCycles(const EIRText: string);
begin
  Debug('CheckDependencyCycles: skipped (stub)');
end;

procedure TValidator.CheckPolicyViolations(const EIRText: string);
begin
  Debug('CheckPolicyViolations: skipped (stub)');
end;

procedure TValidator.CheckResourceLimits(const EIRText: string);
begin
  Debug('CheckResourceLimits: skipped (stub)');
end;

procedure TValidator.CheckPreconditions(const EIRText: string);
begin
  Debug('CheckPreconditions: skipped (stub)');
end;

procedure TValidator.CheckSideEffectConsistency(const EIRText: string);
begin
  Debug('CheckSideEffectConsistency: skipped (stub)');
end;

procedure TValidator.CheckTransitionConditions(const EIRText: string);
begin
  Debug('CheckTransitionConditions: skipped (stub)');
end;

procedure TValidator.CheckCostExpressions(const EIRText: string);
begin
  Debug('CheckCostExpressions: skipped (stub)');
end;

procedure TValidator.CheckBundleStrategies(const EIRText: string);
begin
  Debug('CheckBundleStrategies: skipped (stub)');
end;

end.
