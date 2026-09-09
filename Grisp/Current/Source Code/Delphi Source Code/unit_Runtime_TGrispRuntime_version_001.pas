unit unit_Runtime_TGrispRuntime_version_001;

interface

uses
  System.Classes,
  unit_Graph_TGrispGraph_version_001,
  unit_Runtime_TGrispRuntimeConfig_version_001,
  unit_Runtime_TGrispRuntimeEngine_version_001;

type
  // Public API facade
  TGrispRuntime = class
  private
    class var FDefaultConfig: TGrispRuntimeConfig;
    class var FDefaultEngine: TGrispRuntimeEngine;

    class function GetEngine(Graph: TGrispGraph): TGrispRuntimeEngine;
    class procedure ReleaseEngine(Engine: TGrispRuntimeEngine);
  public
    class procedure Initialize;
    class procedure Configure(const Config: TGrispRuntimeConfig);
    class function Run(Graph: TGrispGraph; MaxSteps: Integer = 0; Trace: TStrings = nil): Integer; overload;
    class function RunWithPhases(Graph: TGrispGraph; MaxPhases: Integer = 0;
                                 MaxStepsPerPhase: Integer = 0; Trace: TStrings = nil): Integer;
    class function RunUntilStable(Graph: TGrispGraph; MaxSteps: Integer = 0; Trace: TStrings = nil): Integer;

    class property DefaultConfig: TGrispRuntimeConfig read FDefaultConfig;
  end;

implementation

class procedure TGrispRuntime.Initialize;
begin
  FDefaultConfig.SetDefaults;
  FDefaultEngine := nil;
end;

class procedure TGrispRuntime.Configure(const Config: TGrispRuntimeConfig);
begin
  FDefaultConfig := Config;
end;

class function TGrispRuntime.GetEngine(Graph: TGrispGraph): TGrispRuntimeEngine;
begin
  if FDefaultEngine = nil then
    FDefaultEngine := TGrispRuntimeEngine.Create(Graph);
  Result := FDefaultEngine;
  Result.SetConfig(FDefaultConfig);
end;

class procedure TGrispRuntime.ReleaseEngine(Engine: TGrispRuntimeEngine);
begin
  if Engine = FDefaultEngine then
  begin
    FDefaultEngine.Free;
    FDefaultEngine := nil;
  end
  else
    Engine.Free;
end;

class function TGrispRuntime.Run(Graph: TGrispGraph; MaxSteps: Integer; Trace: TStrings): Integer;
var
  Engine: TGrispRuntimeEngine;
begin
  Engine := GetEngine(Graph);
  try
    Result := Engine.RunWithTrace(Trace, MaxSteps);
  finally
    ReleaseEngine(Engine);
  end;
end;

class function TGrispRuntime.RunWithPhases(Graph: TGrispGraph; MaxPhases, MaxStepsPerPhase: Integer;
                                           Trace: TStrings): Integer;
var
  Engine: TGrispRuntimeEngine;
begin
  Engine := GetEngine(Graph);
  try
    Result := Engine.RunWithPhasesAndTrace(Trace, MaxPhases, MaxStepsPerPhase);
  finally
    ReleaseEngine(Engine);
  end;
end;

class function TGrispRuntime.RunUntilStable(Graph: TGrispGraph; MaxSteps: Integer; Trace: TStrings): Integer;
begin
  Result := Run(Graph, MaxSteps, Trace);
end;

initialization
  TGrispRuntime.Initialize;
end.
