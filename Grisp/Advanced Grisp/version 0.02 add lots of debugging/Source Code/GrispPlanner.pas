unit GrispPlanner;

interface

uses
  SysUtils, Classes, Generics.Collections,
  GrispSIR, GrispToolManifest, GrispWorldState;

type
  TPlanCandidate = record
    PlanID: string;
    Confidence: Double;
    Risk: string;
    Dependencies: TStringList;
    SelectedTools: TStringList;
    CEIRText: string;
    EstimatedToolCalls: Integer;
  end;

  TPlanner = class
  private
    FSIR: TSIRDocument;
    FWorldState: TWorldState;
    FManifests: TToolManifestRegistry;
    function GenerateCandidate(const ID: string): TPlanCandidate;
  public
    constructor Create(SIR: TSIRDocument; WorldState: TWorldState; Manifests: TToolManifestRegistry);
    function GenerateCandidates: TArray<TPlanCandidate>;
  end;

implementation

{ TPlanner }

constructor TPlanner.Create(SIR: TSIRDocument; WorldState: TWorldState; Manifests: TToolManifestRegistry);
begin
  FSIR := SIR;
  FWorldState := WorldState;
  FManifests := Manifests;
end;

function TPlanner.GenerateCandidate(const ID: string): TPlanCandidate;
var
  C: TPlanCandidate;
  sb: TStringBuilder;
begin
  C.PlanID := ID;
  C.Confidence := 0.85;
  C.Risk := 'low';
  C.Dependencies := TStringList.Create;
  C.Dependencies.Add('power_available');
  C.SelectedTools := TStringList.Create;
  C.SelectedTools.Add('CoolingSystem');
  C.SelectedTools.Add('Hardware');
  C.SelectedTools.Add('Clock');
  C.EstimatedToolCalls := 10;
  sb := TStringBuilder.Create;
  try
    sb.AppendLine('⟦BEGIN PROGRAM⟧');
    sb.AppendLine('  ⟦BEGIN METADATA⟧plan_id = "' + ID + '"⟦END METADATA⟧');
    sb.AppendLine('  ⟦SET current_temp = 0⟧');
    sb.AppendLine('  ⟦SET fan_speed = 0⟧');
    sb.AppendLine('  ⟦WHILE current_temp > 38 DO⟧');
    sb.AppendLine('    ⟦CALL Hardware.read_sensor(sensor_id = "sensor_01") INTO current_temp⟧');
    sb.AppendLine('    ⟦IF current_temp > 42 THEN⟧');
    sb.AppendLine('      ⟦SET fan_speed = 100⟧');
    sb.AppendLine('    ⟦ELSE IF current_temp > 40 THEN⟧');
    sb.AppendLine('      ⟦SET fan_speed = 70⟧');
    sb.AppendLine('    ⟦ELSE⟧');
    sb.AppendLine('      ⟦SET fan_speed = 40⟧');
    sb.AppendLine('    ⟦END IF⟧');
    sb.AppendLine('    ⟦CALL CoolingSystem.set_speed(speed = fan_speed)⟧');
    sb.AppendLine('    ⟦CALL Clock.sleep(duration = 30)⟧');
    sb.AppendLine('  ⟦END WHILE⟧');
    sb.AppendLine('⟦END PROGRAM⟧');
    C.CEIRText := sb.ToString;
  finally
    sb.Free;
  end;
  Result := C;
end;

function TPlanner.GenerateCandidates: TArray<TPlanCandidate>;
var
  List: TList<TPlanCandidate>;
  B, C: TPlanCandidate;
begin
  List := TList<TPlanCandidate>.Create;
  try
    List.Add(GenerateCandidate('plan-A'));
    B := GenerateCandidate('plan-B');
    B.Confidence := 0.95;
    B.Risk := 'medium';
    B.CEIRText := StringReplace(B.CEIRText, 'fan_speed = 70', 'fan_speed = 80', [rfReplaceAll]);
    List.Add(B);
    C := GenerateCandidate('plan-C');
    C.Confidence := 0.60;
    C.Risk := 'high';
    C.CEIRText := StringReplace(C.CEIRText, 'fan_speed = 70', 'fan_speed = 30', [rfReplaceAll]);
    List.Add(C);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

end.