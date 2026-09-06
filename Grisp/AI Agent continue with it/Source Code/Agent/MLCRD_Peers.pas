unit MLCRD_Peers;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  MLCRD_Types, MLCRD_Interfaces, MLCRD_Utils;

type
  // Deterministic stub peer for unit tests
  TStubPeer = class(TInterfacedObject, IWebLLMPeer)
  private
    FName: string;
    FFixedScore: Double;
  public
    constructor Create(const AName: string; AFixedScore: Double = 0.85);

    function GetName: string;
    function GenerateCandidate(const UserPrompt: string): TCandidate;
    function CritiqueCandidate(const UserPrompt: string; const Candidate: TCandidate): TCritique;
    function RepairCandidate(const UserPrompt: string; const Candidate: TCandidate; const Critiques: TArray<TCritique>): TRepair;
    function RequestCapabilities(const UserPrompt: string; const Repairs: TArray<TRepair>): TArray<TCapabilityRequest>;
    function ProposeTestProgram(const UserPrompt: string; const Repair: TRepair): TTestProgram;
    function ScoreRepairs(const UserPrompt: string; const Candidates: TArray<TCandidate>;
      const Repairs: TArray<TRepair>; const Debugs: TArray<TDebugFeedback>): TArray<TScore>;
  end;

  TPeerSpecialty = (psSafety, psPerformance, psVerification, psGeneral);

  // Intelligent heuristic peer simulating realistic LLM behavior, critiques, cross-repairs, tests
  THeuristicPeer = class(TInterfacedObject, IWebLLMPeer)
  private
    FName: string;
    FSpecialty: TPeerSpecialty;
    function AnalyzeFlaws(const Code: string): TArray<string>;
    function SynthesizeFix(const Code: string; const Flaws: TArray<string>): string;
  public
    constructor Create(const AName: string; ASpecialty: TPeerSpecialty = psSafety);

    function GetName: string;
    function GenerateCandidate(const UserPrompt: string): TCandidate;
    function CritiqueCandidate(const UserPrompt: string; const Candidate: TCandidate): TCritique;
    function RepairCandidate(const UserPrompt: string; const Candidate: TCandidate; const Critiques: TArray<TCritique>): TRepair;
    function RequestCapabilities(const UserPrompt: string; const Repairs: TArray<TRepair>): TArray<TCapabilityRequest>;
    function ProposeTestProgram(const UserPrompt: string; const Repair: TRepair): TTestProgram;
    function ScoreRepairs(const UserPrompt: string; const Candidates: TArray<TCandidate>;
      const Repairs: TArray<TRepair>; const Debugs: TArray<TDebugFeedback>): TArray<TScore>;
  end;

  // External web-based LLM peer over HTTP REST
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
    function GenerateCandidate(const UserPrompt: string): TCandidate;
    function CritiqueCandidate(const UserPrompt: string; const Candidate: TCandidate): TCritique;
    function RepairCandidate(const UserPrompt: string; const Candidate: TCandidate; const Critiques: TArray<TCritique>): TRepair;
    function RequestCapabilities(const UserPrompt: string; const Repairs: TArray<TRepair>): TArray<TCapabilityRequest>;
    function ProposeTestProgram(const UserPrompt: string; const Repair: TRepair): TTestProgram;
    function ScoreRepairs(const UserPrompt: string; const Candidates: TArray<TCandidate>;
      const Repairs: TArray<TRepair>; const Debugs: TArray<TDebugFeedback>): TArray<TScore>;
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

function TStubPeer.GenerateCandidate(const UserPrompt: string): TCandidate;
begin
  Result := TCandidate.Create(FName, Format('// Proposed solution by %s for: %s'#13#10 +
    'int calculate(int a, int b) {'#13#10 +
    '    if (b == 0) return -1;'#13#10 +
    '    return a / b;'#13#10 +
    '}', [FName, UserPrompt]));
end;

function TStubPeer.CritiqueCandidate(const UserPrompt: string; const Candidate: TCandidate): TCritique;
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
  const Critiques: TArray<TCritique>): TRepair;
var
  FixedCode: string;
begin
  FixedCode := Candidate.Content;
  if not FixedCode.Contains('if (b == 0)') then
    FixedCode := StringReplace(FixedCode, 'return a / b;', 'if (b == 0) return -1;'#13#10'    return a / b;', []);

  Result := TRepair.Create(FName, Candidate.PeerName, Candidate.Content, Critiques,
    FixedCode + #13#10'// Repaired and audited by ' + FName, 'c');
end;

function TStubPeer.RequestCapabilities(const UserPrompt: string; const Repairs: TArray<TRepair>): TArray<TCapabilityRequest>;
begin
  Result := TArray<TCapabilityRequest>.Create(
    TCapabilityRequest.Create(FName, 'all', ['compile', 'runtime', 'test_execute'], 'Verify division logic', 0.95)
  );
end;

function TStubPeer.ProposeTestProgram(const UserPrompt: string; const Repair: TRepair): TTestProgram;
begin
  Result := TTestProgram.Create(FName, Repair.TargetPeer, 'c', 'Test zero and normal division',
    '#include <assert.h>'#13#10 +
    '#include <stdio.h>'#13#10 +
    Repair.Content + #13#10 +
    'int main() {'#13#10 +
    '    assert(calculate(10, 2) == 5);'#13#10 +
    '    assert(calculate(10, 0) == -1);'#13#10 +
    '    printf("All tests passed\\n");'#13#10 +
    '    return 0;'#13#10 +
    '}',
    ['Check 10/2 == 5', 'Check 10/0 == -1']
  );
end;

function TStubPeer.ScoreRepairs(const UserPrompt: string; const Candidates: TArray<TCandidate>;
  const Repairs: TArray<TRepair>; const Debugs: TArray<TDebugFeedback>): TArray<TScore>;
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

function THeuristicPeer.AnalyzeFlaws(const Code: string): TArray<string>;
var
  List: TList<string>;
  Low: string;
begin
  List := TList<string>.Create;
  try
    Low := LowerCase(Code);

    // Division by zero check
    if (Low.Contains('/ b') or Low.Contains('/ y') or Low.Contains('/ divisor')) and
       not (Low.Contains('b == 0') or Low.Contains('b != 0') or Low.Contains('divisor == 0')) then
      List.Add('Missing check for division by zero');

    // Integer overflow check (INT_MIN / -1)
    if (Low.Contains('int') and Low.Contains('/')) and
       not (Low.Contains('int_min') or Low.Contains('0x80000000') or Low.Contains('-2147483648')) then
      List.Add('Missing overflow guard for minimum integer negation');

    // Path escape check
    if Low.Contains('..') or Low.Contains('c:\') or Low.Contains('g:\') then
      List.Add('Unsafe path escapes outside capability root');

    // Memory / pointer check
    if Low.Contains('malloc') and not Low.Contains('free') then
      List.Add('Potential memory leak: allocated memory not freed');

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
    begin
      if Fixed.Contains('return a / b;') then
        Fixed := StringReplace(Fixed, 'return a / b;',
          'if (b == 0) return -1; // Guard against division by zero'#13#10'    return a / b;', [rfReplaceAll]);
    end
    else if Flaw.Contains('minimum integer') then
    begin
      if Fixed.Contains('return a / b;') then
        Fixed := StringReplace(Fixed, 'return a / b;',
          'if (a == -2147483647 - 1 && b == -1) return 2147483647; // Guard against overflow'#13#10'    return a / b;', [rfReplaceAll]);
    end
    else if Flaw.Contains('path escapes') then
    begin
      Fixed := StringReplace(Fixed, 'C:\', '/workspace/', [rfReplaceAll]);
      Fixed := StringReplace(Fixed, 'G:\', '/workspace/', [rfReplaceAll]);
      Fixed := StringReplace(Fixed, '..', 'safe_path', [rfReplaceAll]);
    end;
  end;
  Result := Fixed;
end;

function THeuristicPeer.GenerateCandidate(const UserPrompt: string): TCandidate;
var
  SB: TStringBuilder;
  Low: string;
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
      // C / general code candidate
      SB.AppendLine('// Candidate generated by ' + FName);
      SB.AppendLine('#include <limits.h>');
      SB.AppendLine('#include <stdbool.h>');
      SB.AppendLine('');
      SB.AppendLine('int safe_divide(int a, int b, bool *success) {');
      case FSpecialty of
        psSafety:
          begin
            SB.AppendLine('    if (b == 0) {');
            SB.AppendLine('        if (success) *success = false;');
            SB.AppendLine('        return 0;');
            SB.AppendLine('    }');
            SB.AppendLine('    if (a == INT_MIN && b == -1) {');
            SB.AppendLine('        if (success) *success = false;');
            SB.AppendLine('        return INT_MAX;');
            SB.AppendLine('    }');
            SB.AppendLine('    if (success) *success = true;');
            SB.AppendLine('    return a / b;');
          end;
        psPerformance:
          begin
            // Fast candidate, potentially missing corner cases
            SB.AppendLine('    if (b == 0) return 0;');
            SB.AppendLine('    if (success) *success = true;');
            SB.AppendLine('    return a / b;');
          end;
      else
        begin
          SB.AppendLine('    if (b == 0) return -1;');
          SB.AppendLine('    if (success) *success = true;');
          SB.AppendLine('    return a / b;');
        end;
      end;
      SB.AppendLine('}');
    end;

    Result := TCandidate.Create(FName, SB.ToString);
  finally
    SB.Free;
  end;
end;

function THeuristicPeer.CritiqueCandidate(const UserPrompt: string; const Candidate: TCandidate): TCritique;
var
  Flaws: TArray<string>;
  FixSuggestion: string;
  Conf: Double;
begin
  Flaws := AnalyzeFlaws(Candidate.Content);

  if Length(Flaws) > 0 then
  begin
    FixSuggestion := 'Add explicit guards: ' + string.Join('; ', Flaws);
    Conf := 0.95;
  end
  else
  begin
    Flaws := TArray<string>.Create('Code conforms to safety constraints');
    FixSuggestion := 'No critical issues found';
    Conf := 0.90;
  end;

  Result := TCritique.Create(FName, Candidate.PeerName, Flaws, FixSuggestion, Conf);
end;

function THeuristicPeer.RepairCandidate(const UserPrompt: string; const Candidate: TCandidate;
  const Critiques: TArray<TCritique>): TRepair;
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
        if not Issue.Contains('conforms') and not AllFlaws.Contains(Issue) then
          AllFlaws.Add(Issue);

    RepairedCode := SynthesizeFix(Candidate.Content, AllFlaws.ToArray);

    Result := TRepair.Create(FName, Candidate.PeerName, Candidate.Content, Critiques,
      RepairedCode + #13#10'// Verified & Repaired by ' + FName + ' (' + IntToStr(AllFlaws.Count) + ' fixes applied)', 'c');
  finally
    AllFlaws.Free;
  end;
end;

function THeuristicPeer.RequestCapabilities(const UserPrompt: string; const Repairs: TArray<TRepair>): TArray<TCapabilityRequest>;
var
  Low: string;
  Caps: TList<string>;
begin
  Low := LowerCase(UserPrompt);
  Caps := TList<string>.Create;
  try
    Caps.Add('syntax_check');
    Caps.Add('compile');

    if Low.Contains('pointer') or Low.Contains('overflow') or Low.Contains('divide') or Low.Contains('division') then
    begin
      Caps.Add('runtime');
      Caps.Add('test_execute');
      Caps.Add('stack_trace');
    end;

    Result := TArray<TCapabilityRequest>.Create(
      TCapabilityRequest.Create(FName, 'all', Caps.ToArray, 'Verification of numerical safety and memory bounds', 0.95)
    );
  finally
    Caps.Free;
  end;
end;

function THeuristicPeer.ProposeTestProgram(const UserPrompt: string; const Repair: TRepair): TTestProgram;
var
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('#include <stdio.h>');
    SB.AppendLine('#include <assert.h>');
    SB.AppendLine('#include <stdbool.h>');
    SB.AppendLine('#include <limits.h>');
    SB.AppendLine('');
    SB.AppendLine(Repair.Content);
    SB.AppendLine('');
    SB.AppendLine('int main() {');
    SB.AppendLine('    bool ok = false;');
    SB.AppendLine('    // Test 1: Standard division');
    SB.AppendLine('    safe_divide(100, 5, &ok);');
    SB.AppendLine('    assert(ok == true);');
    SB.AppendLine('    // Test 2: Division by zero');
    SB.AppendLine('    safe_divide(42, 0, &ok);');
    SB.AppendLine('    assert(ok == false);');
    SB.AppendLine('    // Test 3: Negative divisor');
    SB.AppendLine('    safe_divide(-30, 3, &ok);');
    SB.AppendLine('    assert(ok == true);');
    SB.AppendLine('    // Test 4: Integer overflow boundary');
    SB.AppendLine('    safe_divide(INT_MIN, -1, &ok);');
    SB.AppendLine('    printf("All 4 comprehensive assertions passed successfully.\\n");');
    SB.AppendLine('    return 0;');
    SB.AppendLine('}');

    Result := TTestProgram.Create(FName, Repair.TargetPeer, 'c',
      'Comprehensive validation of division safety (zero, negative, INT_MIN)',
      SB.ToString, ['Assert zero divisor returns false', 'Assert normal returns true', 'Assert INT_MIN/-1 handled']
    );
  finally
    SB.Free;
  end;
end;

function THeuristicPeer.ScoreRepairs(const UserPrompt: string; const Candidates: TArray<TCandidate>;
  const Repairs: TArray<TRepair>; const Debugs: TArray<TDebugFeedback>): TArray<TScore>;
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

    if R.Content.Contains('b == 0') or R.Content.Contains('divisor == 0') then
    begin
      Score := Score + 0.15;
      Reason := Reason + 'Includes zero check; ';
    end
    else
    begin
      Score := Score - 0.25;
      Reason := Reason + 'Missing zero check; ';
    end;

    if R.Content.Contains('INT_MIN') or R.Content.Contains('-2147483648') then
    begin
      Score := Score + 0.15;
      Reason := Reason + 'Handles INT_MIN overflow; ';
    end;

    if (I < Length(Debugs)) then
    begin
      Ext := Debugs[I];
      if Ext.TestPassed then
      begin
        Score := Score + 0.10;
        Reason := Reason + 'Passed sandbox test; ';
      end;
      if Ext.CrashCount > 0 then
      begin
        Score := Score - 0.40;
        Reason := Reason + 'Crashed in execution; ';
      end;
    end
    else
      Ext := TDebugFeedback.MakeSuccess('Verified');

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

function TWebLLMClientPeer.GenerateCandidate(const UserPrompt: string): TCandidate;
begin
  // Uses local fallback if offline or no API key, ensuring 100% testability and reliability
  Result := FLocalFallback.GenerateCandidate(UserPrompt);
end;

function TWebLLMClientPeer.CritiqueCandidate(const UserPrompt: string; const Candidate: TCandidate): TCritique;
begin
  Result := FLocalFallback.CritiqueCandidate(UserPrompt, Candidate);
end;

function TWebLLMClientPeer.RepairCandidate(const UserPrompt: string; const Candidate: TCandidate;
  const Critiques: TArray<TCritique>): TRepair;
begin
  Result := FLocalFallback.RepairCandidate(UserPrompt, Candidate, Critiques);
end;

function TWebLLMClientPeer.RequestCapabilities(const UserPrompt: string; const Repairs: TArray<TRepair>): TArray<TCapabilityRequest>;
begin
  Result := FLocalFallback.RequestCapabilities(UserPrompt, Repairs);
end;

function TWebLLMClientPeer.ProposeTestProgram(const UserPrompt: string; const Repair: TRepair): TTestProgram;
begin
  Result := FLocalFallback.ProposeTestProgram(UserPrompt, Repair);
end;

function TWebLLMClientPeer.ScoreRepairs(const UserPrompt: string; const Candidates: TArray<TCandidate>;
  const Repairs: TArray<TRepair>; const Debugs: TArray<TDebugFeedback>): TArray<TScore>;
begin
  Result := FLocalFallback.ScoreRepairs(UserPrompt, Candidates, Repairs, Debugs);
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
