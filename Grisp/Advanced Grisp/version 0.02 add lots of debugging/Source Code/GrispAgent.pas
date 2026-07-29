{$DEFINE DEBUG}
unit GrispAgent;

interface

uses
  SysUtils, Classes, System.IOUtils, System.Math,  // <-- added System.Math for Min
  GrispSIR, GrispToolManifest, GrispWorldState,
  GrispPlanner, GrispEvaluator, GrispValidator, GrispExecutor,
  GrispMarkerParser;

type
  TGrispAgent = class
  private
    FSIR: TSIRDocument;
    FManifests: TToolManifestRegistry;
    FWorldState: TWorldState;
    FSelectedPlan: TPlanCandidate;
    FCanonicalEIR: string;
    FMode: string;
    FCEIRFile: string;
    procedure LoadSIR(const Filename: string);
    procedure LoadManifests(const Dir: string);
    procedure LoadWorldState(const Filename: string);
    procedure SaveWorldState(const Filename: string);
    function GeneratePrompt: string;
    procedure Debug(const Msg: string);
    procedure DebugHexDump(const Data: string; const Count: Integer);
    function ReadCEIRFromConsole: string;
    function ReadCEIRFromFile(const Filename: string): string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Run(const SIRFile, ManifestDir, WorldFile: string; const CEIRFile: string = '');
  end;

implementation

constructor TGrispAgent.Create;
begin
  FSIR := TSIRDocument.Create;
  FManifests := TToolManifestRegistry.Create;
  FWorldState := TWorldState.Create;
  FCEIRFile := '';
end;

destructor TGrispAgent.Destroy;
begin
  FSIR.Free;
  FManifests.Free;
  FWorldState.Free;
  inherited;
end;

procedure TGrispAgent.Debug(const Msg: string);
begin
  {$IFDEF DEBUG}
  Writeln(ErrOutput, '[Agent] ', Msg);
  {$ENDIF}
end;

procedure TGrispAgent.DebugHexDump(const Data: string; const Count: Integer);
var
  Bytes: TBytes;
  i: Integer;
  s: string;
begin
  // Convert the string to its UTF‑8 byte representation to show actual file bytes
  Bytes := TEncoding.UTF8.GetBytes(Data);
  s := '';
  for i := 0 to Min(Count, Length(Bytes)) - 1 do
    s := s + Format('%.2x ', [Bytes[i]]);
  Debug('Hex dump (first ' + IntToStr(Min(Count, Length(Bytes))) + ' UTF-8 bytes): ' + s);
end;

procedure TGrispAgent.LoadSIR(const Filename: string);
var
  Bytes: TBytes;
  Content: string;
  FullPath: string;
  Doc: TDocument;
begin
  FullPath := ExpandFileName(Filename);
  Debug('Loading SIR from: ' + FullPath);
  if not FileExists(FullPath) then
  begin
    Debug('SIR file does NOT exist: ' + FullPath);
    raise Exception.Create('SIR file not found: ' + FullPath);
  end;
  Bytes := TFile.ReadAllBytes(FullPath);
  // Remove UTF-8 BOM if present (EF BB BF)
  if (Length(Bytes) >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
    Bytes := Copy(Bytes, 3, Length(Bytes)-3);
  // Remove UTF-16 BOM if present (FE FF)
  if (Length(Bytes) >= 2) and (Bytes[0] = $FE) and (Bytes[1] = $FF) then
    Bytes := Copy(Bytes, 2, Length(Bytes)-2);
  Content := TEncoding.UTF8.GetString(Bytes);
  Debug('Loaded SIR file, length = ' + IntToStr(Length(Content)));
  Debug('First 50 chars: ' + Copy(Content, 1, 50));
  DebugHexDump(Content, 10);
  Doc := TDocument.Create;
  try
    if not Doc.Parse(Content) then
      raise Exception.Create('Failed to parse SIR file: syntax error');
    if not FSIR.LoadFromBlock(Doc.Root) then
      raise Exception.Create('Failed to load SIR content');
    Debug('SIR loaded with ' + IntToStr(FSIR.Goals.Count) + ' goals, ' +
      IntToStr(FSIR.Constraints.Count) + ' constraints.');
  finally
    Doc.Free;
  end;
end;

procedure TGrispAgent.LoadManifests(const Dir: string);
var
  FullDir: string;
begin
  FullDir := ExpandFileName(Dir);
  Debug('Loading manifests from: ' + FullDir);
  if not DirectoryExists(FullDir) then
  begin
    Debug('Manifest directory does NOT exist: ' + FullDir);
    raise Exception.Create('Manifest directory not found: ' + FullDir);
  end;
  FManifests.LoadFromDirectory(FullDir);
  Debug('Manifests loaded, found ' + IntToStr(FManifests.GetToolCount) + ' tools');
end;

procedure TGrispAgent.LoadWorldState(const Filename: string);
var
  FullPath: string;
begin
  FullPath := ExpandFileName(Filename);
  Debug('Loading WorldState from: ' + FullPath);
  if not FileExists(FullPath) then
    Debug('WorldState file does not exist, will create new');
  FWorldState.LoadFromFile(FullPath);
  Debug('WorldState version: ' + IntToStr(FWorldState.Version));
end;

procedure TGrispAgent.SaveWorldState(const Filename: string);
var
  FullPath: string;
begin
  FullPath := ExpandFileName(Filename);
  Debug('Saving WorldState to: ' + FullPath);
  FWorldState.SaveToFile(FullPath);
end;

function TGrispAgent.GeneratePrompt: string;
var
  Vars: TArray<string>;
  v: string;
begin
  Result := 'You are an AI planner. Given the following SIR intent and world state, generate a CEIR plan (in Compact EIR format) that achieves the goal.' + sLineBreak +
            'SIR:' + sLineBreak +
            '  Goals: ' + FSIR.Goals.Text + sLineBreak +
            '  Constraints: ' + FSIR.Constraints.Text + sLineBreak +
            '  Assumptions: ' + FSIR.Assumptions.Text + sLineBreak +
            '  Policies: ' + FSIR.Policies.Text + sLineBreak +
            'WorldState variables:' + sLineBreak;
  Vars := FWorldState.GetVariableNames;
  if Length(Vars) > 0 then
    for v in Vars do
      Result := Result + '  ' + v + ' = ' + FWorldState.GetVariable(v) + sLineBreak
  else
    Result := Result + '  (none)' + sLineBreak;
  Result := Result + 'Available tools: ' + FManifests.GetToolNames + sLineBreak +
            'Respond with only CEIR code, no explanations.';
end;

function TGrispAgent.ReadCEIRFromConsole: string;
var
  lines: TStringList;
  UserInput: string;
begin
  lines := TStringList.Create;
  try
    Writeln('Paste the LLM response (CEIR) below.');
    Writeln('Type a line containing "END" to finish, or press Ctrl+Z then Enter to finish.');
    while True do
    begin
      if Eof then
      begin
        if lines.Count > 0 then
          Break
        else
          raise Exception.Create('No input received');
      end;
      ReadLn(UserInput);
      if SameText(Trim(UserInput), 'END') then
        Break;
      lines.Add(UserInput);
    end;
    Result := lines.Text;
  finally
    lines.Free;
  end;
end;

function TGrispAgent.ReadCEIRFromFile(const Filename: string): string;
var
  Bytes: TBytes;
begin
  if not FileExists(Filename) then
    raise Exception.Create('CEIR file not found: ' + Filename);
  Bytes := TFile.ReadAllBytes(Filename);
  // Remove BOM
  if (Length(Bytes) >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
    Bytes := Copy(Bytes, 3, Length(Bytes)-3);
  if (Length(Bytes) >= 2) and (Bytes[0] = $FE) and (Bytes[1] = $FF) then
    Bytes := Copy(Bytes, 2, Length(Bytes)-2);
  Result := TEncoding.UTF8.GetString(Bytes);
  Debug('Read CEIR from file: ' + Filename);
  Debug('CEIR length = ' + IntToStr(Length(Result)));
  Debug('First 50 chars: ' + Copy(Result, 1, 50));
  DebugHexDump(Result, 20);
end;

procedure TGrispAgent.Run(const SIRFile, ManifestDir, WorldFile: string; const CEIRFile: string = '');
var
  Planner: TPlanner;
  Candidates: TArray<TPlanCandidate>;
  Evaluator: TEvaluator;
  Validator: TValidator;
  Executor: TExecutor;
  UserInput: string;
  eir: string;
  ActualCEIRFile: string;
begin
  Debug('Current directory: ' + GetCurrentDir);
  Debug('SIR file: ' + SIRFile);
  Debug('Manifest dir: ' + ManifestDir);
  Debug('WorldState file: ' + WorldFile);
  if CEIRFile <> '' then
    Debug('CEIR file: ' + CEIRFile);

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

    if CEIRFile <> '' then
      ActualCEIRFile := CEIRFile
    else if FileExists('plan.ceir') then
    begin
      ActualCEIRFile := 'plan.ceir';
      WriteLn('Using existing file: plan.ceir');
    end
    else
      ActualCEIRFile := '';

    if ActualCEIRFile <> '' then
    begin
      FSelectedPlan.CEIRText := ReadCEIRFromFile(ActualCEIRFile);
      WriteLn('Read CEIR from file: ', ActualCEIRFile);
    end
    else
    begin
      FSelectedPlan.CEIRText := ReadCEIRFromConsole;
      WriteLn('Read CEIR from console.');
    end;

    FSelectedPlan.CEIRText := Trim(FSelectedPlan.CEIRText);
    if FSelectedPlan.CEIRText.EndsWith('END') then
      FSelectedPlan.CEIRText := Copy(FSelectedPlan.CEIRText, 1, Length(FSelectedPlan.CEIRText)-3);
    FSelectedPlan.PlanID := 'manual-plan';
    FSelectedPlan.Confidence := 0.9;
    FSelectedPlan.Risk := 'low';
  end;

  Validator := TValidator.Create(FWorldState, FManifests);
  try
    eir := FSelectedPlan.CEIRText;
    Debug('CEIR text length = ' + IntToStr(Length(eir)));
    Debug('First 200 chars of CEIR: ' + Copy(eir, 1, 200));
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
