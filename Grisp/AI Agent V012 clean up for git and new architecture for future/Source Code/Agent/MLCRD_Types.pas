// Filename: MLCRD_Types.pas
unit MLCRD_Types;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  // ---- Language and Configuration ----
  TAgentLanguage = (alUnknown, alPascal, alDelphi, alC, alPython);

  TAgentConfiguration = record
    PreferredLanguage: TAgentLanguage;
    PreferredCompiler: string;
    CompilerPath: string;
    GenerateTests: Boolean;
    RunSandboxed: Boolean;
    MaxTestRuns: Integer;
    TraceLevel: Integer;
    TimeoutMs: Integer;
    EnablePromptTagging: Boolean;
    constructor Create(ALang: TAgentLanguage; const ACompiler: string = '');
  end;

  // ---- File entry for multiple files ----
  TFileEntry = record
    FileName: string;
    Content: string;
  end;

  // ---- Existing types ----
  TCandidate = record
    PeerName: string;
    Content: string;
    TimestampUtc: TDateTime;
    class function Create(const APeer, AContent: string): TCandidate; static;
  end;

  TCritique = record
    FromPeer: string;
    TargetPeer: string;
    Issues: TArray<string>;
    SuggestedFix: string;
    Confidence: Double;
    class function Create(const AFrom, ATarget: string; const AIssues: TArray<string>;
      const ASuggestedFix: string; AConfidence: Double): TCritique; static;
  end;

  TRepair = record
    FromPeer: string;
    TargetPeer: string;
    Original: string;
    Critiques: TArray<TCritique>;
    Content: string;
    Language: string;
    Metadata: TDictionary<string, string>;
    Files: TArray<TFileEntry>;
    class function Create(const AFrom, ATarget, AOriginal: string;
      const ACritiques: TArray<TCritique>; const AContent: string;
      const ALanguage: string = 'text'; const AFiles: TArray<TFileEntry> = []): TRepair; static;
  end;

  TCapabilityRequest = record
    FromPeer: string;
    TargetPeer: string;
    Capabilities: TArray<string>;
    Reason: string;
    Confidence: Double;
    class function Create(const AFrom, ATarget: string; const ACaps: TArray<string>;
      const AReason: string; AConfidence: Double = 1.0): TCapabilityRequest; static;
  end;

  TTestProgram = record
    FromPeer: string;
    TargetPeer: string;
    Language: string;
    Purpose: string;
    Code: string;
    Hints: TArray<string>;
    class function Create(const AFrom, ATarget, ALang, APurpose, ACode: string;
      const AHints: TArray<string> = nil): TTestProgram; static;
  end;

  TDebugFeedback = record
    SyntaxOK: Boolean;
    SemanticOK: Boolean;
    CompileOK: Boolean;
    RuntimeOK: Boolean;
    CrashCount: Integer;
    TimeoutCount: Integer;
    BreakpointHits: Integer;
    BreakpointViolations: Integer;
    StackTrace: string;
    VariableDump: string;
    Diagnostics: string;
    TestOutput: string;
    TestExitCode: Integer;
    TestPassed: Boolean;
    ElapsedMs: Integer;
    class function MakeSuccess(const AMsg: string = 'OK'): TDebugFeedback; static;
    class function MakeFailure(const ADiag: string; AExitCode: Integer = 1): TDebugFeedback; static;
  end;

  TScore = record
    FromPeer: string;
    TargetPeer: string;
    RepairPeer: string;
    ScoreValue: Double;
    Confidence: Double;
    External: TDebugFeedback;
    Reason: string;
    class function Create(const AFrom, ATarget, ARepairPeer: string;
      AScoreVal, AConf: Double; const AExt: TDebugFeedback; const AReason: string): TScore; static;
  end;

  TPeerInfo = record
    Name: string;
    Reliability: Double;
    ChosenCount: Integer;
    FailedTests: Integer;
    GrispRejects: Integer;
    SuccessfulRepairs: Integer;
    SpuriousDebugRequests: Integer;
    class function Create(const AName: string; AReliability: Double = 1.0): TPeerInfo; static;
  end;

  TDecision = record
    TargetPeer: string;
    ChosenRepairPeer: string;
    FinalContent: string;
    FinalScore: Double;
    EvidenceScores: TArray<TScore>;
    EvidenceDebug: TArray<TDebugFeedback>;
    class function Create(const ATarget, AChosen: string; const AContent: string;
      AScore: Double): TDecision; static;
  end;

  TProtocolTrace = record
    TaskPrompt: string;
    StartedUtc: TDateTime;
    FinishedUtc: TDateTime;
    Candidates: TArray<TCandidate>;
    Critiques: TArray<TCritique>;
    Repairs: TArray<TRepair>;
    CapabilityRequests: TArray<TCapabilityRequest>;
    ActivatedCapabilities: TArray<string>;
    LightDebug: TArray<TDebugFeedback>;
    TestPrograms: TArray<TTestProgram>;
    TestResults: TArray<TDebugFeedback>;
    Scores: TArray<TScore>;
    Decisions: TArray<TDecision>;
    ChosenFinalPlan: string;
    GrispAccepted: Boolean;
    GrispDiagnostics: string;
    ExecutionOutput: string;
    PeerInfosBefore: TArray<TPeerInfo>;
    PeerInfosAfter: TArray<TPeerInfo>;
  end;

implementation

{ TAgentConfiguration }

constructor TAgentConfiguration.Create(ALang: TAgentLanguage; const ACompiler: string);
begin
  PreferredLanguage := ALang;
  PreferredCompiler := ACompiler;
  CompilerPath := '';
  GenerateTests := True;
  RunSandboxed := False;
  MaxTestRuns := 3;
  TraceLevel := 1;
  TimeoutMs := 30000;
  EnablePromptTagging := False;
end;

{ TCandidate }
class function TCandidate.Create(const APeer, AContent: string): TCandidate;
begin
  Result.PeerName := APeer;
  Result.Content := AContent;
  Result.TimestampUtc := Now;
end;

{ TCritique }
class function TCritique.Create(const AFrom, ATarget: string; const AIssues: TArray<string>;
  const ASuggestedFix: string; AConfidence: Double): TCritique;
var
  I: Integer;
begin
  Result.FromPeer := AFrom;
  Result.TargetPeer := ATarget;
  SetLength(Result.Issues, Length(AIssues));
  for I := 0 to High(AIssues) do
    Result.Issues[I] := AIssues[I];
  Result.SuggestedFix := ASuggestedFix;
  Result.Confidence := AConfidence;
end;

{ TRepair }
class function TRepair.Create(const AFrom, ATarget, AOriginal: string;
  const ACritiques: TArray<TCritique>; const AContent: string;
  const ALanguage: string; const AFiles: TArray<TFileEntry>): TRepair;
var
  I: Integer;
  FileEntry: TFileEntry;
begin
  Result.FromPeer := AFrom;
  Result.TargetPeer := ATarget;
  Result.Original := AOriginal;
  SetLength(Result.Critiques, Length(ACritiques));
  for I := 0 to High(ACritiques) do
    Result.Critiques[I] := ACritiques[I];
  Result.Content := AContent;
  Result.Language := ALanguage;
  Result.Metadata := TDictionary<string, string>.Create;

  SetLength(Result.Files, Length(AFiles));
  for I := 0 to High(AFiles) do
    Result.Files[I] := AFiles[I];

  if (Length(Result.Files) = 0) and (Result.Content <> '') then
  begin
    SetLength(Result.Files, 1);
    if SameText(ALanguage, 'pascal') or SameText(ALanguage, 'delphi') then
      FileEntry.FileName := 'program.pas'
    else if SameText(ALanguage, 'c') then
      FileEntry.FileName := 'program.c'
    else if SameText(ALanguage, 'python') then
      FileEntry.FileName := 'program.py'
    else
      FileEntry.FileName := 'program.txt';
    FileEntry.Content := Result.Content;
    Result.Files[0] := FileEntry;
  end;
end;

{ TCapabilityRequest }
class function TCapabilityRequest.Create(const AFrom, ATarget: string; const ACaps: TArray<string>;
  const AReason: string; AConfidence: Double): TCapabilityRequest;
var
  I: Integer;
begin
  Result.FromPeer := AFrom;
  Result.TargetPeer := ATarget;
  SetLength(Result.Capabilities, Length(ACaps));
  for I := 0 to High(ACaps) do
    Result.Capabilities[I] := ACaps[I];
  Result.Reason := AReason;
  Result.Confidence := AConfidence;
end;

{ TTestProgram }
class function TTestProgram.Create(const AFrom, ATarget, ALang, APurpose, ACode: string;
  const AHints: TArray<string>): TTestProgram;
var
  I: Integer;
begin
  Result.FromPeer := AFrom;
  Result.TargetPeer := ATarget;
  Result.Language := ALang;
  Result.Purpose := APurpose;
  Result.Code := ACode;
  SetLength(Result.Hints, Length(AHints));
  for I := 0 to High(AHints) do
    Result.Hints[I] := AHints[I];
end;

{ TDebugFeedback }
class function TDebugFeedback.MakeSuccess(const AMsg: string): TDebugFeedback;
begin
  Result.SyntaxOK := True;
  Result.SemanticOK := True;
  Result.CompileOK := True;
  Result.RuntimeOK := True;
  Result.CrashCount := 0;
  Result.TimeoutCount := 0;
  Result.BreakpointHits := 0;
  Result.BreakpointViolations := 0;
  Result.StackTrace := '';
  Result.VariableDump := '';
  Result.Diagnostics := AMsg;
  Result.TestOutput := AMsg;
  Result.TestExitCode := 0;
  Result.TestPassed := True;
  Result.ElapsedMs := 5;
end;

class function TDebugFeedback.MakeFailure(const ADiag: string; AExitCode: Integer): TDebugFeedback;
begin
  Result.SyntaxOK := False;
  Result.SemanticOK := False;
  Result.CompileOK := False;
  Result.RuntimeOK := False;
  Result.CrashCount := 1;
  Result.TimeoutCount := 0;
  Result.BreakpointHits := 0;
  Result.BreakpointViolations := 0;
  Result.StackTrace := ADiag;
  Result.VariableDump := '';
  Result.Diagnostics := ADiag;
  Result.TestOutput := ADiag;
  Result.TestExitCode := AExitCode;
  Result.TestPassed := False;
  Result.ElapsedMs := 10;
end;

{ TScore }
class function TScore.Create(const AFrom, ATarget, ARepairPeer: string;
  AScoreVal, AConf: Double; const AExt: TDebugFeedback; const AReason: string): TScore;
begin
  Result.FromPeer := AFrom;
  Result.TargetPeer := ATarget;
  Result.RepairPeer := ARepairPeer;
  Result.ScoreValue := AScoreVal;
  Result.Confidence := AConf;
  Result.External := AExt;
  Result.Reason := AReason;
end;

{ TPeerInfo }
class function TPeerInfo.Create(const AName: string; AReliability: Double): TPeerInfo;
begin
  Result.Name := AName;
  Result.Reliability := AReliability;
  Result.ChosenCount := 0;
  Result.FailedTests := 0;
  Result.GrispRejects := 0;
  Result.SuccessfulRepairs := 0;
  Result.SpuriousDebugRequests := 0;
end;

{ TDecision }
class function TDecision.Create(const ATarget, AChosen: string; const AContent: string;
  AScore: Double): TDecision;
begin
  Result.TargetPeer := ATarget;
  Result.ChosenRepairPeer := AChosen;
  Result.FinalContent := AContent;
  Result.FinalScore := AScore;
  SetLength(Result.EvidenceScores, 0);
  SetLength(Result.EvidenceDebug, 0);
end;

end.