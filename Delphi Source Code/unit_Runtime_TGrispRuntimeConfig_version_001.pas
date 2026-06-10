unit unit_Runtime_TGrispRuntimeConfig_version_001;

interface

type
  TGrispRuntimeConfig = record
    MaxSteps: Integer;
    MaxPhases: Integer;
    MaxStepsPerPhase: Integer;
    TraceEnabled: Boolean;
    PhaseMode: Boolean;
    AutoCleanup: Boolean;

    procedure SetDefaults;
  end;

implementation

procedure TGrispRuntimeConfig.SetDefaults;
begin
  MaxSteps := 1000;
  MaxPhases := 10;
  MaxStepsPerPhase := 100;
  TraceEnabled := False;
  PhaseMode := False;
  AutoCleanup := True;
end;

end.
