unit MLCRD_Peers;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  MLCRD_Types, MLCRD_Interfaces, MLCRD_Utils;

type
  // Deterministic stub peer
  TStubPeer = class(TInterfacedObject, IWebLLMPeer)
  private
    FName: string;
    FFixedScore: Double;
  public
    constructor Create(const AName: string; AFixedScore: Double = 0.85);
    function GetName: string;
    function GenerateCandidate(const UserPrompt: string; const Config: TAgentConfiguration): TCandidate;
    function CritiqueCandidate(const UserPrompt: string; const Candidate: TCandidate; const Config: TAgentConfiguration): TCritique;
    function RepairCandidate(const UserPrompt: string; const Candidate: TCandidate;
      const Critiques: TArray<TCritique>; const Config: TAgentConfiguration): TRepair;
    function RequestCapabilities(const UserPrompt: string; const Repairs: TArray<TRepair>;
      const Config: TAgentConfiguration): TArray<TCapabilityRequest>;
    function ProposeTestProgram(const UserPrompt: string; const Repair: TRepair;
      const Config: TAgentConfiguration): TTestProgram;
    function ScoreRepairs(const UserPrompt: string; const Candidates: TArray<TCandidate>;
      const Repairs: TArray<TRepair>; const Debugs: TArray<TDebugFeedback>;
      const Config: TAgentConfiguration): TArray<TScore>;
  end;

  TPeerSpecialty = (psSafety, psPerformance, psVerification, psGeneral);

  // Intelligent heuristic peer
  THeuristicPeer = class(TInterfacedObject, IWebLLMPeer)
  private
    FName: string;
    FSpecialty: TPeerSpecialty;
    function AnalyzeFlaws(const Code: string): TArray<string>;
    function SynthesizeFix(const Code: string; const Flaws: TArray<string>): string;
    function GetLanguageTemplate(const Lang: TAgentLanguage): string;
  public
    constructor Create(const AName: string; ASpecialty: TPeerSpecialty = psSafety);
    function GetName: string;
    function GenerateCandidate(const UserPrompt: string; const Config: TAgentConfiguration): TCandidate;
    function CritiqueCandidate(const UserPrompt: string; const Candidate: TCandidate; const Config: TAgentConfiguration): TCritique;
    function RepairCandidate(const UserPrompt: string; const Candidate: TCandidate;
      const Critiques: TArray<TCritique>; const Config: TAgentConfiguration): TRepair;
    function RequestCapabilities(const UserPrompt: string; const Repairs: TArray<TRepair>;
      const Config: TAgentConfiguration): TArray<TCapabilityRequest>;
    function ProposeTestProgram(const UserPrompt: string; const Repair: TRepair;
      const Config: TAgentConfiguration): TTestProgram;
    function ScoreRepairs(const UserPrompt: string; const Candidates: TArray<TCandidate>;
      const Repairs: TArray<TRepair>; const Debugs: TArray<TDebugFeedback>;
      const Config: TAgentConfiguration): TArray<TScore>;
  end;

  // External web-based LLM peer over HTTP REST (fallback to heuristic)
  TWebLLMClientPeer = class(TInterfacedObject, IWebLLMPeer)
  private
    FName: string;
    FEndpointUrl: string;
    FApiKey: string;
    FModelName: string;
    FLocalFallback: IWebLLMPeer;
  public
    constructor Create(const AName, AEndpointUrl, AApiKey, AModelName: string;
      AFallbackSpecialty: TPeerSpecialty = psGeneral);
    function GetName: string;
    function GenerateCandidate(const UserPrompt: string; const Config: TAgentConfiguration): TCandidate;
    function CritiqueCandidate(const UserPrompt: string; const Candidate: TCandidate; const Config: TAgentConfiguration): TCritique;
    function RepairCandidate(const UserPrompt: string; const Candidate: TCandidate;
      const Critiques: TArray<TCritique>; const Config: TAgentConfiguration): TRepair;
    function RequestCapabilities(const UserPrompt: string; const Repairs: TArray<TRepair>;
      const Config: TAgentConfiguration): TArray<TCapabilityRequest>;
    function ProposeTestProgram(const UserPrompt: string; const Repair: TRepair;
      const Config: TAgentConfiguration): TTestProgram;
    function ScoreRepairs(const UserPrompt: string; const Candidates: TArray<TCandidate>;
      const Repairs: TArray<TRepair>; const Debugs: TArray<TDebugFeedback>;
      const Config: TAgentConfiguration): TArray<TScore>;
  end;

function CreateFirefoxPeers(const Sites: TArray<string>; Port: Integer = 9999;
  const Host: string = 'localhost'): TArray<IWebLLMPeer>;

implementation

uses
  MLCRD_FirefoxPeer;

{ TStubPeer }

constructor TStubPeer.Create(const AName: string; AFixedScore: Double);
begin
  inherited Create;
  FName := AName;
  FFixedScore := AFixedScore;
end;

function TStubPeer.GetName: string;
begin
  Result := FName;
end;

function TStubPeer.GenerateCandidate(const UserPrompt: string; const Config: TAgentConfiguration): TCandidate;
begin
  // Generic stub – uses Config only for language hint (ignored)
  Result := TCandidate.Create(FName, Format('// Stub solution by %s for: %s'#13#10 +
    'int calculate(int a, int b) {'#13#10 +
    '    if (b == 0) return -1;'#13#10 +
    '    return a / b;'#13#10 +
    '}', [FName, UserPrompt]));
end;

function TStubPeer.CritiqueCandidate(const UserPrompt: string; const Candidate: TCandidate; const Config: TAgentConfiguration): TCritique;
var
  Issues: TArray<string>;
begin
  if not Candidate.Content.Contains('b == 0') then
    Issues := TArray<string>.Create('Missing zero divisor check', 'Unbounded division')
  else
    Issues := TArray<string>.Create('Code structure verified');

  Result := TCritique.Create(FName, Candidate.PeerName, Issues, 'Ensure divisor is guarded and return error code', 0.90);
end;

function TStubPeer.RepairCandidate(const UserPrompt: string; const Candidate: TCandidate;
  const Critiques: TArray<TCritique>; const Config: TAgentConfiguration): TRepair;
var
  FixedCode: string;
begin
  FixedCode := Candidate.Content;
  if not FixedCode.Contains('if (b == 0)') then
    FixedCode := StringReplace(FixedCode, 'return a / b;', 'if (b == 0) return -1;'#13#10'    return a / b;', []);
  Result := TRepair.Create(FName, Candidate.PeerName, Candidate.Content, Critiques,
    FixedCode + #13#10'// Repaired and audited by ' + FName, 'c');
end;

function TStubPeer.RequestCapabilities(const UserPrompt: string; const Repairs: TArray<TRepair>;
  const Config: TAgentConfiguration): TArray<TCapabilityRequest>;
begin
  Result := TArray<TCapabilityRequest>.Create(
    TCapabilityRequest.Create(FName, 'all', ['compile', 'runtime', 'test_execute'], 'Verify logic', 0.95)
  );
end;

function TStubPeer.ProposeTestProgram(const UserPrompt: string; const Repair: TRepair;
  const Config: TAgentConfiguration): TTestProgram;
var
  Lang: string;
begin
  // Use Config to select language
  case Config.PreferredLanguage of
    alPascal, alDelphi: Lang := 'Pascal';
    alC: Lang := 'C';
    alPython: Lang := 'Python';
  else
    Lang := 'C';
  end;
  // Simple stub test – does not analyse code, just a placeholder
  Result := TTestProgram.Create(FName, Repair.TargetPeer, Lang,
    'Stub test for ' + Repair.TargetPeer,
    '// TODO: Implement actual tests for: ' + Repair.Content + #13#10 +
    '// This is a stub; real test generation should be done by LLM peers.',
    ['Stub placeholder']
  );
end;

function TStubPeer.ScoreRepairs(const UserPrompt: string; const Candidates: TArray<TCandidate>;
  const Repairs: TArray<TRepair>; const Debugs: TArray<TDebugFeedback>;
  const Config: TAgentConfiguration): TArray<TScore>;
var
  I: Integer;
  R: TRepair;
  SVal: Double;
  Ext: TDebugFeedback;
begin
  SetLength(Result, Length(Repairs));
  for I := 0 to High(Repairs) do
  begin
    R := Repairs[I];
    SVal := FFixedScore;
    if R.Content.Contains('if (b == 0)') then
      SVal := SVal + 0.10
    else
      SVal := SVal - 0.30;

    if (I < Length(Debugs)) then
      Ext := Debugs[I]
    else
      Ext := TDebugFeedback.MakeSuccess('Stub debug OK');

    Result[I] := TScore.Create(FName, R.TargetPeer, R.FromPeer, EnsureRange(SVal, 0.0, 1.0),
      0.90, Ext, 'Scored by ' + FName);
  end;
end;

{ THeuristicPeer }

constructor THeuristicPeer.Create(const AName: string; ASpecialty: TPeerSpecialty);
begin
  inherited Create;
  FName := AName;
  FSpecialty := ASpecialty;
end;

function THeuristicPeer.GetName: string;
begin
  Result := FName;
end;

function THeuristicPeer.GetLanguageTemplate(const Lang: TAgentLanguage): string;
begin
  case Lang of
    alPascal, alDelphi:
      Result := 'program TestHarness;'#13#10 +
                '{$APPTYPE CONSOLE}'#13#10 +
                'uses SysUtils;'#13#10 +
                'begin'#13#10 +
                '  Writeln(''Running tests...'');'#13#10 +
                '  // Add your test code here'#13#10 +
                'end.';
    alC:
      Result := '#include <stdio.h>'#13#10 +
                '#include <assert.h>'#13#10 +
                'int main() {'#13#10 +
                '  printf("Running tests...\n");'#13#10 +
                '  // Add your test code here'#13#10 +
                '  return 0;'#13#10 +
                '}';
    alPython:
      Result := 'import unittest'#13#10 +
                'class TestHarness(unittest.TestCase):'#13#10 +
                '    def test_example(self):'#13#10 +
                '        self.assertTrue(True)'#13#10 +
                'if __name__ == "__main__":'#13#10 +
                '    unittest.main()';
  else
    Result := '// Fallback test harness';
  end;
end;

function THeuristicPeer.AnalyzeFlaws(const Code: string): TArray<string>;
var
  List: TList<string>;
  Low: string;
begin
  List := TList<string>.Create;
  try
    Low := LowerCase(Code);
    if (Low.Contains('/ b') or Low.Contains('/ y') or Low.Contains('/ divisor')) and
       not (Low.Contains('b == 0') or Low.Contains('b != 0') or Low.Contains('divisor == 0')) then
      List.Add('Missing check for division by zero');
    if (Low.Contains('int') and Low.Contains('/')) and
       not (Low.Contains('int_min') or Low.Contains('0x80000000')) then
      List.Add('Missing overflow guard for minimum integer negation');
    if Low.Contains('malloc') and not Low.Contains('free') then
      List.Add('Potential memory leak');
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function THeuristicPeer.SynthesizeFix(const Code: string; const Flaws: TArray<string>): string;
var
  Fixed: string;
  Flaw: string;
begin
  Fixed := Code;
  for Flaw in Flaws do
  begin
    if Flaw.Contains('division by zero') then
      Fixed := StringReplace(Fixed, 'return a / b;', 'if (b == 0) return -1;'#13#10'    return a / b;', [rfReplaceAll])
    else if Flaw.Contains('minimum integer') then
      Fixed := StringReplace(Fixed, 'return a / b;', 'if (a == -2147483647 - 1 && b == -1) return 2147483647;'#13#10'    return a / b;', [rfReplaceAll]);
  end;
  Result := Fixed;
end;

function THeuristicPeer.GenerateCandidate(const UserPrompt: string; const Config: TAgentConfiguration): TCandidate;
var
  SB: TStringBuilder;
  Low: string;
  LangName: string;
begin
  SB := TStringBuilder.Create;
  try
    Low := LowerCase(UserPrompt);
    if Low.Contains('grisp') or Low.Contains('rule') then
    begin
      SB.AppendLine('rules begin');
      SB.AppendLine('  rule "safe-exec" priority 100 begin');
      SB.AppendLine('    match begin');
      SB.AppendLine('      Task: TaskType;');
      SB.AppendLine('    end');
      SB.AppendLine('    actions begin');
      SB.AppendLine('      CreateNode(t, TaskType) with { name: "AuditTask"; status: "Ready"; };');
      SB.AppendLine('      EmitEvent("task_started", ["AuditTask"]);');
      SB.AppendLine('    end');
      SB.AppendLine('  end');
      SB.AppendLine('end');
    end
    else
    begin
      case Config.PreferredLanguage of
        alPascal, alDelphi: LangName := 'Pascal/Delphi';
        alC: LangName := 'C';
        alPython: LangName := 'Python';
      else
        LangName := 'C';
      end;
      SB.AppendLine('// Candidate generated by ' + FName + ' for language: ' + LangName);
      if Config.PreferredLanguage in [alPascal, alDelphi] then
      begin
        SB.AppendLine('function SafeDivide(a, b: Integer): Integer;');
        SB.AppendLine('begin');
        SB.AppendLine('  if b = 0 then');
        SB.AppendLine('    Result := -1');
        SB.AppendLine('  else');
        SB.AppendLine('    Result := a div b;');
        SB.AppendLine('end;');
      end
      else
      begin
        SB.AppendLine('int safe_divide(int a, int b, bool *success) {');
        SB.AppendLine('    if (b == 0) {');
        SB.AppendLine('        if (success) *success = false;');
        SB.AppendLine('        return 0;');
        SB.AppendLine('    }');
        SB.AppendLine('    if (success) *success = true;');
        SB.AppendLine('    return a / b;');
        SB.AppendLine('}');
      end;
    end;
    Result := TCandidate.Create(FName, SB.ToString);
  finally
    SB.Free;
  end;
end;

function THeuristicPeer.CritiqueCandidate(const UserPrompt: string; const Candidate: TCandidate; const Config: TAgentConfiguration): TCritique;
var
  Flaws: TArray<string>;
  FixSuggestion: string;
begin
  Flaws := AnalyzeFlaws(Candidate.Content);
  if Length(Flaws) > 0 then
    FixSuggestion := 'Add guards: ' + string.Join('; ', Flaws)
  else
    FixSuggestion := 'No issues found';
  Result := TCritique.Create(FName, Candidate.PeerName, Flaws, FixSuggestion, 0.92);
end;

function THeuristicPeer.RepairCandidate(const UserPrompt: string; const Candidate: TCandidate;
  const Critiques: TArray<TCritique>; const Config: TAgentConfiguration): TRepair;
var
  AllFlaws: TList<string>;
  Cr: TCritique;
  Issue: string;
  RepairedCode: string;
begin
  AllFlaws := TList<string>.Create;
  try
    for Cr in Critiques do
      for Issue in Cr.Issues do
        if not AllFlaws.Contains(Issue) then
          AllFlaws.Add(Issue);
    RepairedCode := SynthesizeFix(Candidate.Content, AllFlaws.ToArray);
    Result := TRepair.Create(FName, Candidate.PeerName, Candidate.Content, Critiques,
      RepairedCode + #13#10'// Repaired by ' + FName, 'text');
  finally
    AllFlaws.Free;
  end;
end;

function THeuristicPeer.RequestCapabilities(const UserPrompt: string; const Repairs: TArray<TRepair>;
  const Config: TAgentConfiguration): TArray<TCapabilityRequest>;
var
  Low: string;
  Caps: TList<string>;
begin
  Low := LowerCase(UserPrompt);
  Caps := TList<string>.Create;
  try
    Caps.Add('syntax_check');
    Caps.Add('compile');
    if Low.Contains('pointer') or Low.Contains('overflow') or Low.Contains('divide') then
    begin
      Caps.Add('runtime');
      Caps.Add('test_execute');
    end;
    Result := TArray<TCapabilityRequest>.Create(
      TCapabilityRequest.Create(FName, 'all', Caps.ToArray, 'Security and correctness', 0.95)
    );
  finally
    Caps.Free;
  end;
end;

function THeuristicPeer.ProposeTestProgram(const UserPrompt: string; const Repair: TRepair;
  const Config: TAgentConfiguration): TTestProgram;
var
  Template: string;
  LangName: string;
  Hints: TArray<string>;
begin
  // Use the code‑aware prompt: we will generate a generic harness, but the LLM peers will do better.
  // Here we just provide a skeleton using the language template.
  case Config.PreferredLanguage of
    alPascal, alDelphi: LangName := 'Pascal';
    alC: LangName := 'C';
    alPython: LangName := 'Python';
  else
    LangName := 'C';
  end;
  Template := GetLanguageTemplate(Config.PreferredLanguage);
  Hints := ['Implement tests for the functions in the repair code', 'Focus on edge cases'];
  Result := TTestProgram.Create(FName, Repair.TargetPeer, LangName,
    'Heuristic test for ' + Repair.TargetPeer,
    Template + #13#10 + '// TODO: Replace with actual tests derived from: ' + Repair.Content,
    Hints);
end;

function THeuristicPeer.ScoreRepairs(const UserPrompt: string; const Candidates: TArray<TCandidate>;
  const Repairs: TArray<TRepair>; const Debugs: TArray<TDebugFeedback>;
  const Config: TAgentConfiguration): TArray<TScore>;
var
  I: Integer;
  R: TRepair;
  Score: Double;
  Reason: string;
  Ext: TDebugFeedback;
begin
  SetLength(Result, Length(Repairs));
  for I := 0 to High(Repairs) do
  begin
    R := Repairs[I];
    Score := 0.70;
    Reason := '';
    if R.Content.Contains('b == 0') or R.Content.Contains('b = 0') then
    begin
      Score := Score + 0.15;
      Reason := Reason + 'Zero guard; ';
    end;
    if (I < Length(Debugs)) then
    begin
      Ext := Debugs[I];
      if Ext.TestPassed then
      begin
        Score := Score + 0.10;
        Reason := Reason + 'Passed; ';
      end;
      if Ext.CrashCount > 0 then
      begin
        Score := Score - 0.40;
        Reason := Reason + 'Crashed; ';
      end;
    end
    else
      Ext := TDebugFeedback.MakeSuccess('OK');
    Result[I] := TScore.Create(FName, R.TargetPeer, R.FromPeer, EnsureRange(Score, 0.0, 1.0),
      0.95, Ext, Reason.Trim);
  end;
end;

{ TWebLLMClientPeer }

constructor TWebLLMClientPeer.Create(const AName, AEndpointUrl, AApiKey, AModelName: string;
  AFallbackSpecialty: TPeerSpecialty);
begin
  inherited Create;
  FName := AName;
  FEndpointUrl := AEndpointUrl;
  FApiKey := AApiKey;
  FModelName := AModelName;
  FLocalFallback := THeuristicPeer.Create(AName, AFallbackSpecialty);
end;

function TWebLLMClientPeer.GetName: string;
begin
  Result := FName;
end;

function TWebLLMClientPeer.GenerateCandidate(const UserPrompt: string; const Config: TAgentConfiguration): TCandidate;
begin
  // For now, use fallback; could implement HTTP call later.
  Result := FLocalFallback.GenerateCandidate(UserPrompt, Config);
end;

function TWebLLMClientPeer.CritiqueCandidate(const UserPrompt: string; const Candidate: TCandidate; const Config: TAgentConfiguration): TCritique;
begin
  Result := FLocalFallback.CritiqueCandidate(UserPrompt, Candidate, Config);
end;

function TWebLLMClientPeer.RepairCandidate(const UserPrompt: string; const Candidate: TCandidate;
  const Critiques: TArray<TCritique>; const Config: TAgentConfiguration): TRepair;
begin
  Result := FLocalFallback.RepairCandidate(UserPrompt, Candidate, Critiques, Config);
end;

function TWebLLMClientPeer.RequestCapabilities(const UserPrompt: string; const Repairs: TArray<TRepair>;
  const Config: TAgentConfiguration): TArray<TCapabilityRequest>;
begin
  Result := FLocalFallback.RequestCapabilities(UserPrompt, Repairs, Config);
end;

function TWebLLMClientPeer.ProposeTestProgram(const UserPrompt: string; const Repair: TRepair;
  const Config: TAgentConfiguration): TTestProgram;
begin
  Result := FLocalFallback.ProposeTestProgram(UserPrompt, Repair, Config);
end;

function TWebLLMClientPeer.ScoreRepairs(const UserPrompt: string; const Candidates: TArray<TCandidate>;
  const Repairs: TArray<TRepair>; const Debugs: TArray<TDebugFeedback>;
  const Config: TAgentConfiguration): TArray<TScore>;
begin
  Result := FLocalFallback.ScoreRepairs(UserPrompt, Candidates, Repairs, Debugs, Config);
end;

function CreateFirefoxPeers(const Sites: TArray<string>; Port: Integer;
  const Host: string): TArray<IWebLLMPeer>;
var
  EffectiveSites: TArray<string>;
  I: Integer;
  Site: string;
  Fallback: IWebLLMPeer;
begin
  if Length(Sites) = 0 then
    EffectiveSites := ['deepseek']
  else
    EffectiveSites := Sites;
  SetLength(Result, Length(EffectiveSites));
  for I := 0 to High(EffectiveSites) do
  begin
    Site := EffectiveSites[I].Trim;
    if Site = '' then Site := 'deepseek';
    Fallback := THeuristicPeer.Create('HeuristicFallback_' + Site, TPeerSpecialty(I mod 4));
    Result[I] := TFirefoxChatAIPeer.Create(Site, Port, Fallback, Host);
  end;
end;

end.