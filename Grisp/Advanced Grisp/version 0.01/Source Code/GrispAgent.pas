unit GrispAgent;

interface

uses
  SysUtils, Classes,
  GrispSIR, GrispToolManifest, GrispWorldState,
  GrispPlanner, GrispEvaluator, GrispValidator, GrispExecutor,
  GrispMarkerParser;   // <-- added to resolve TDocument

type
  TGrispAgent = class
  private
    FSIR: TSIRDocument;
    FManifests: TToolManifestRegistry;
    FWorldState: TWorldState;
    FSelectedPlan: TPlanCandidate;
    FCanonicalEIR: string;
    FMode: string; // 'auto' or 'manual'
    procedure LoadSIR(const Filename: string);
    procedure LoadManifests(const Dir: string);
    procedure LoadWorldState(const Filename: string);
    procedure SaveWorldState(const Filename: string);
    function GeneratePrompt: string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Run(const SIRFile, ManifestDir, WorldFile: string);
  end;

implementation

{ TGrispAgent }

constructor TGrispAgent.Create;
begin
  FSIR := TSIRDocument.Create;
  FManifests := TToolManifestRegistry.Create;
  FWorldState := TWorldState.Create;
end;

destructor TGrispAgent.Destroy;
begin
  FSIR.Free;
  FManifests.Free;
  FWorldState.Free;
  inherited;
end;

procedure TGrispAgent.LoadSIR(const Filename: string);
var
  sl: TStringList;
  Doc: TDocument;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(Filename);
    Doc := TDocument.Create;
    try
      if Doc.Parse(sl.Text) then
        FSIR.LoadFromBlock(Doc.Root)
      else
        raise Exception.Create('Failed to parse SIR file');
    finally
      Doc.Free;
    end;
  finally
    sl.Free;
  end;
end;

procedure TGrispAgent.LoadManifests(const Dir: string);
begin
  FManifests.LoadFromDirectory(Dir);
end;

procedure TGrispAgent.LoadWorldState(const Filename: string);
begin
  FWorldState.LoadFromFile(Filename);
end;

procedure TGrispAgent.SaveWorldState(const Filename: string);
begin
  FWorldState.SaveToFile(Filename);
end;

function TGrispAgent.GeneratePrompt: string;
begin
  Result := 'You are an AI planner. Given the following SIR intent and world state, generate a CEIR plan (in Compact EIR format) that achieves the goal.' + sLineBreak +
            'SIR: ' + sLineBreak + FSIR.Goals.Text + sLineBreak +
            'Constraints: ' + FSIR.Constraints.Text + sLineBreak +
            'WorldState variables: ' + sLineBreak +
            '  current_temp = ' + FWorldState.GetVariable('current_temp') + sLineBreak +
            '  fan_speed = ' + FWorldState.GetVariable('fan_speed') + sLineBreak +
            'Available tools: CoolingSystem (set_speed), Hardware (read_sensor), Clock (sleep)' + sLineBreak +
            'Respond with only CEIR code, no explanations.';
end;

procedure TGrispAgent.Run(const SIRFile, ManifestDir, WorldFile: string);
var
  Planner: TPlanner;
  Candidates: TArray<TPlanCandidate>;
  Evaluator: TEvaluator;
  Validator: TValidator;
  Executor: TExecutor;
  UserInput: string;
  lines: TStringList;
  eir: string;
begin
  LoadSIR(SIRFile);
  LoadManifests(ManifestDir);
  LoadWorldState(WorldFile);

  Write('Run in auto mode? (y/n): ');
  ReadLn(UserInput);
  if SameText(UserInput, 'y') then
    FMode := 'auto'
  else
    FMode := 'manual';

  if FMode = 'auto' then
  begin
    Planner := TPlanner.Create(FSIR, FWorldState, FManifests);
    try
      Candidates := Planner.GenerateCandidates;
    finally
      Planner.Free;
    end;
    Evaluator := TEvaluator.Create(FWorldState, FManifests);
    try
      FSelectedPlan := Evaluator.SelectBest(Candidates);
    finally
      Evaluator.Free;
    end;
    WriteLn('Selected plan: ', FSelectedPlan.PlanID);
  end
  else
  begin
    WriteLn('Copy the following prompt and paste it into your LLM:');
    WriteLn('----------------------------------------');
    WriteLn(GeneratePrompt);
    WriteLn('----------------------------------------');
    WriteLn('Paste the LLM response (CEIR) below (end with a line containing "END"):');
    lines := TStringList.Create;
    try
      while True do
      begin
        ReadLn(UserInput);
        if SameText(UserInput, 'END') then
          Break;
        lines.Add(UserInput);
      end;
      FSelectedPlan.CEIRText := lines.Text;
      FSelectedPlan.PlanID := 'manual-plan';
      FSelectedPlan.Confidence := 0.9;
      FSelectedPlan.Risk := 'low';
    finally
      lines.Free;
    end;
  end;

  Validator := TValidator.Create(FWorldState, FManifests);
  try
    eir := FSelectedPlan.CEIRText;
    if not Validator.Validate(eir) then
    begin
      WriteLn('Validation failed: ', Validator.ErrorCode, ' - ', Validator.ErrorMessage);
      Exit;
    end;
    FCanonicalEIR := eir;
    WriteLn('Validation passed. Canonical EIR generated.');
  finally
    Validator.Free;
  end;

  Executor := TExecutor.Create(FWorldState, FManifests);
  try
    Executor.ExecuteCanonicalEIR(FCanonicalEIR);
    Executor.PrintEvents;
  finally
    Executor.Free;
  end;

  SaveWorldState(WorldFile);
  WriteLn('WorldState saved.');
end;

end.
