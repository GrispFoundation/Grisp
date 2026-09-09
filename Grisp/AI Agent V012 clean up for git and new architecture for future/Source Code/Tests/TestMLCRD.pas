unit TestMLCRD;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.JSON,
  MLCRD_Types, MLCRD_Interfaces, MLCRD_Algorithms, MLCRD_Adapters, MLCRD_Peers,
  MLCRD_FirefoxPeer, MLCRD_Coordinator, MLCRD_Utils, GrispCapabilities, GrispVfs, GrispGraph, GrispCore;

type
  TTestMLCRDRunner = class
  private
    FPassed: Integer;
    FFailed: Integer;
    procedure AssertTrue(Condition: Boolean; const Msg: string);
    procedure AssertEquals(const Expected, Actual, Msg: string);
  public
    constructor Create;
    procedure RunAllTests;

    procedure TestCandidateCritiqueRepairFlow;
    procedure TestCapabilityNegotiation;
    procedure TestScoringCalculation;
    procedure TestReliabilityEvolution;
    procedure TestEndToEndMultiPeerAgent;
    procedure TestFirefoxProtocolParsing;
    procedure TestFirefoxPeerFallbackAndIntegration;

    property Passed: Integer read FPassed;
    property Failed: Integer read FFailed;
  end;

implementation

constructor TTestMLCRDRunner.Create;
begin
  inherited Create;
  FPassed := 0;
  FFailed := 0;
end;

procedure TTestMLCRDRunner.AssertTrue(Condition: Boolean; const Msg: string);
begin
  if Condition then
  begin
    Inc(FPassed);
    Writeln('  [PASS] ' + Msg);
  end
  else
  begin
    Inc(FFailed);
    Writeln('  [FAIL] ' + Msg);
  end;
end;

procedure TTestMLCRDRunner.AssertEquals(const Expected, Actual, Msg: string);
begin
  if Expected = Actual then
  begin
    Inc(FPassed);
    Writeln('  [PASS] ' + Msg);
  end
  else
  begin
    Inc(FFailed);
    Writeln(Format('  [FAIL] %s - Expected: "%s", Actual: "%s"', [Msg, Expected, Actual]));
  end;
end;

procedure TTestMLCRDRunner.TestCandidateCritiqueRepairFlow;
var
  PeerA, PeerB: IWebLLMPeer;
  CandA, CandB: TCandidate;
  CritA, CritB: TCritique;
  RepairAtoB, RepairBtoA: TRepair;
begin
  Writeln('--- TestCandidateCritiqueRepairFlow ---');
  PeerA := THeuristicPeer.Create('PeerA_Safety', psSafety);
  PeerB := THeuristicPeer.Create('PeerB_Perf', psPerformance);

  // 1. Generation
  CandA := PeerA.GenerateCandidate('Write safe divide function');
  CandB := PeerB.GenerateCandidate('Write safe divide function');
  AssertTrue(CandA.PeerName = 'PeerA_Safety', 'Candidate A peer matches');
  AssertTrue(CandB.PeerName = 'PeerB_Perf', 'Candidate B peer matches');

  // 2. Critique
  CritA := PeerA.CritiqueCandidate('Write safe divide function', CandB);
  CritB := PeerB.CritiqueCandidate('Write safe divide function', CandA);
  AssertTrue(CritA.FromPeer = 'PeerA_Safety', 'Critique A from peer');
  AssertTrue(CritA.TargetPeer = 'PeerB_Perf', 'Critique A targets PeerB');

  // 3. Cross-Repair
  RepairAtoB := PeerA.RepairCandidate('Write safe divide function', CandB, [CritA]);
  RepairBtoA := PeerB.RepairCandidate('Write safe divide function', CandA, [CritB]);

  AssertTrue(RepairAtoB.FromPeer = 'PeerA_Safety', 'Repair A->B from PeerA');
  AssertTrue(RepairAtoB.TargetPeer = 'PeerB_Perf', 'Repair A->B targets PeerB');
  AssertTrue(RepairAtoB.Content.Contains('b == 0'), 'Repaired B has zero divisor check');
end;

procedure TTestMLCRDRunner.TestCapabilityNegotiation;
var
  Reqs: TArray<TCapabilityRequest>;
  Activated: TArray<string>;
  ActStr: string;
begin
  Writeln('--- TestCapabilityNegotiation ---');
  Reqs := [
    TCapabilityRequest.Create('PeerA', 'all', ['compile', 'syntax_check'], 'Standard check'),
    TCapabilityRequest.Create('PeerB', 'all', ['compile', 'test_execute'], 'Edge case test')
  ];

  // Standard threshold = 2
  Activated := NegotiateCapabilities(Reqs, 2, 'Simple task');
  ActStr := string.Join(',', Activated);
  AssertTrue(ActStr.Contains('compile'), 'Compile requested by 2 peers is activated');
  AssertTrue(not ActStr.Contains('test_execute'), 'Single request not activated under threshold 2 for standard task');

  // Risk task override
  Activated := NegotiateCapabilities(Reqs, 2, 'Task with pointer memory division overflow');
  ActStr := string.Join(',', Activated);
  AssertTrue(ActStr.Contains('test_execute'), 'High risk task activates test_execute capability');
end;

procedure TTestMLCRDRunner.TestScoringCalculation;
var
  DebugOK, DebugCrash: TDebugFeedback;
  ExtOK, ExtCrash: Double;
  Repair: TRepair;
  Scores: TArray<TScore>;
  PeerInfos: TArray<TPeerInfo>;
  AggScore: Double;
begin
  Writeln('--- TestScoringCalculation ---');
  DebugOK := TDebugFeedback.MakeSuccess('All passed');
  DebugCrash := TDebugFeedback.MakeFailure('SIGSEGV');

  ExtOK := ComputeExternalScore(DebugOK);
  ExtCrash := ComputeExternalScore(DebugCrash);

  AssertTrue(ExtOK > 0.8, Format('External score for successful debug is high: %.2f', [ExtOK]));
  AssertTrue(ExtCrash < 0.2, Format('External score for crashed debug is low: %.2f', [ExtCrash]));

  Repair := TRepair.Create('PeerA', 'PeerB', 'orig', [], 'int code() { return 0; }');
  Scores := [
    TScore.Create('PeerA', 'PeerB', 'PeerA', 0.9, 0.9, DebugOK, 'Good repair'),
    TScore.Create('PeerB', 'PeerB', 'PeerA', 0.8, 0.8, DebugOK, 'Good repair')
  ];
  PeerInfos := [TPeerInfo.Create('PeerA', 1.0), TPeerInfo.Create('PeerB', 1.0)];

  AggScore := AggregateRepairScore(Repair, Scores, PeerInfos, 0.5, 0.5);
  AssertTrue(AggScore > 0.7, Format('Aggregated repair score is high: %.2f', [AggScore]));
end;

procedure TTestMLCRDRunner.TestReliabilityEvolution;
var
  PeerList: TList<TPeerInfo>;
  ScoresGood, ScoresBad: TArray<TScore>;
  DebugOK, DebugBad: TDebugFeedback;
  Reqs: TArray<TCapabilityRequest>;
begin
  Writeln('--- TestReliabilityEvolution ---');
  PeerList := TList<TPeerInfo>.Create;
  try
    PeerList.Add(TPeerInfo.Create('PeerGood', 0.80));
    PeerList.Add(TPeerInfo.Create('PeerBad', 0.80));

    DebugOK := TDebugFeedback.MakeSuccess;
    DebugBad := TDebugFeedback.MakeFailure('Crash');

    ScoresGood := [TScore.Create('PeerGood', 'PeerGood', 'PeerGood', 0.9, 0.9, DebugOK, 'OK')];
    ScoresBad := [TScore.Create('PeerBad', 'PeerBad', 'PeerBad', 0.2, 0.9, DebugBad, 'Crash')];

    Reqs := [];

    // Update PeerGood on success
    UpdatePeerReliability('PeerGood', PeerList, ScoresGood, DebugOK, True, Reqs);
    AssertTrue(PeerList[0].Reliability > 0.80, Format('PeerGood reliability increased to: %.3f', [PeerList[0].Reliability]));
    AssertTrue(PeerList[0].SuccessfulRepairs = 1, 'PeerGood successful repair count incremented');

    // Update PeerBad on failure
    UpdatePeerReliability('PeerBad', PeerList, ScoresBad, DebugBad, True, Reqs);
    AssertTrue(PeerList[1].Reliability < 0.80, Format('PeerBad reliability decreased to: %.3f', [PeerList[1].Reliability]));
    AssertTrue(PeerList[1].FailedTests = 1, 'PeerBad failed tests incremented');
  finally
    PeerList.Free;
  end;
end;

procedure TTestMLCRDRunner.TestEndToEndMultiPeerAgent;
var
  Peers: TArray<IWebLLMPeer>;
  Graph: TGrispGraph;
  Vfs: TGrispVfs;
  CapSet: TGrispCapabilitySet;
  Cap: IGrispCapability;
  Engine: TGrispEngine;
  VfsAdapter: IGrispVfs;
  TestAdapter: IGrispTestAdapter;
  HarnessAdapter: IGrispHarnessAdapter;
  Agent: TMultiLLMAgent;
  OutputReport: string;
  Trace: TProtocolTrace;
begin
  Writeln('--- TestEndToEndMultiPeerAgent ---');
  Peers := [
    THeuristicPeer.Create('SafetyExpert', psSafety),
    THeuristicPeer.Create('PerformanceExpert', psPerformance),
    TStubPeer.Create('GeneralPeer', 0.80)
  ];

  Graph := TGrispGraph.Create;
  Vfs := TGrispVfs.Create('', False);
  CapSet := TGrispCapabilitySet.Create;
  try
    Cap := TGrispCapability.Create('workspace-cap', '/workspace',
      [grRead, grWrite, grList, grCompile, grRun, grTestExecute], ['text/plain', 'text/x-c'], 65536);
    CapSet.Add(Cap);

    Engine := TGrispEngine.Create(Graph, Vfs, CapSet);
    try
      VfsAdapter := TGrispVfsAdapter.Create(Vfs, Cap);
      TestAdapter := TGrispTestAdapterImpl.Create(Vfs);
      HarnessAdapter := TGrispHarnessAdapterImpl.Create(Engine, 'workspace-cap');

      Agent := TMultiLLMAgent.Create(Peers, VfsAdapter, TestAdapter, HarnessAdapter);
      try
        OutputReport := Agent.RunTask('Implement a robust and safe integer division function guarding against zero and INT_MIN overflow');

        AssertTrue(OutputReport.Contains('CHOSEN FINAL SOLUTION'), 'Report contains final chosen solution');
        AssertTrue(OutputReport.Contains('GRISP Sandbox Status: TRUE'), 'GRISP sandbox accepted plan');

        Trace := Agent.GetLastTrace;
        AssertTrue(Length(Trace.Candidates) = 3, '3 candidates generated');
        AssertTrue(Length(Trace.Critiques) = 9, '9 critiques generated (3x3)');
        AssertTrue(Length(Trace.Repairs) = 9, '9 cross-repairs generated in matrix (3x3)');
        AssertTrue(Length(Trace.TestPrograms) > 0, 'Test programs proposed and executed');
        AssertTrue(Trace.ChosenFinalPlan.Contains('safe_divide') or Trace.ChosenFinalPlan.Contains('calculate'), 'Chosen plan contains division function');

        Writeln('  [INFO] Output Report Snippet:');
        Writeln('  ' + Copy(OutputReport, 1, 200) + '...');
      finally
        Agent.Free;
      end;
    finally
      Engine.Free;
    end;
  finally
    CapSet.Free;
    Vfs.Free;
    Graph.Free;
  end;
end;

procedure TTestMLCRDRunner.TestFirefoxProtocolParsing;
var
  CodeMd, Extracted, Fix: string;
  Issues, Caps: TArray<string>;
  Score: Double;
  Sites: TArray<string>;
  S: string;
begin
  Writeln('--- TestFirefoxProtocolParsing ---');

  // 1. Markdown code block extraction
  CodeMd := 'Here is the code you asked for:'#13#10 +
            '```c'#13#10 +
            'int safe_div(int a, int b) {'#13#10 +
            '    if (b == 0) return -1;'#13#10 +
            '    return a / b;'#13#10 +
            '}'#13#10 +
            '```'#13#10 +
            'Hope this helps!';
  Extracted := ExtractCodeBlock(CodeMd);
  AssertTrue(Extracted.Contains('int safe_div'), 'ExtractCodeBlock pulls C function');
  AssertTrue(not Extracted.Contains('```'), 'Code block fences stripped');
  AssertTrue(not Extracted.Contains('Here is the code'), 'Introductory prose stripped');

  // 2. Issue bullet point extraction
  Issues := ExtractBulletIssues('Review comments:'#13#10'- Missing null check'#13#10'- Possible divide by zero'#13#10'* Integer overflow on INT_MIN');
  AssertTrue(Length(Issues) = 3, 'Extracted 3 bullet issues');
  AssertEquals('Missing null check', Issues[0], 'First issue text matches');
  AssertEquals('Possible divide by zero', Issues[1], 'Second issue text matches');

  // 3. Suggested fix extraction
  Fix := ExtractSuggestedFix('The code needs work. Suggestion: add a guard condition for b == 0 before division.');
  AssertTrue(Fix.Contains('guard condition'), 'Extracted suggested fix');

  // 4. Score extraction from text
  Score := ExtractScoreFromText('I would rate this solution 0.92 based on correctness and safety.');
  AssertTrue(Abs(Score - 0.92) < 0.001, 'Extracted 0.92 score from review text');

  // 5. Capability extraction
  Caps := ExtractCapabilitiesFromText('This solution requires compile, run, and test_execute capabilities.');
  AssertTrue(string.Join(',', Caps).Contains('compile'), 'Extracted compile capability');
  AssertTrue(string.Join(',', Caps).Contains('test_execute'), 'Extracted test_execute capability');

  // 6. Site validation for all 8 supported sites
  Sites := ['deepseek', 'gemini', 'claude', 'chatgpt', 'copilot', 'grok', 'perplexity', 'inception'];
  for S in Sites do
    AssertTrue(IsSupportedFirefoxSite(S), 'Recognize supported site: ' + S);

  AssertTrue(not IsSupportedFirefoxSite('unknown_ai'), 'Reject unsupported site');
  AssertEquals('deepseek', NormalizeFirefoxSite('invalid_site'), 'Normalize unknown site to default deepseek');
end;

procedure TTestMLCRDRunner.TestFirefoxPeerFallbackAndIntegration;
var
  Peers: TArray<IWebLLMPeer>;
  Peer: IWebLLMPeer;
  Cand: TCandidate;
  Crit: TCritique;
  Repair: TRepair;
  Scores: TArray<TScore>;
begin
  Writeln('--- TestFirefoxPeerFallbackAndIntegration ---');

  // Factory function
  Peers := CreateFirefoxPeers(['deepseek', 'gemini'], 54321); // offline port to verify graceful fallback
  AssertTrue(Length(Peers) = 2, 'Created 2 Firefox peers');
  AssertEquals('Firefox_deepseek', Peers[0].GetName, 'Peer 0 named Firefox_deepseek');
  AssertEquals('Firefox_gemini', Peers[1].GetName, 'Peer 1 named Firefox_gemini');

  // Test offline fallback generates candidate safely
  Peer := Peers[0];
  Cand := Peer.GenerateCandidate('Write safe divide function');
  AssertTrue(Cand.Content <> '', 'Candidate generated via fallback when offline');

  // Test offline critique
  Crit := Peer.CritiqueCandidate('Write safe divide function', Cand);
  AssertTrue(Length(Crit.Issues) > 0, 'Critique generated via fallback when offline');

  // Test offline repair
  Repair := Peer.RepairCandidate('Write safe divide function', Cand, [Crit]);
  AssertTrue(Repair.Content <> '', 'Repair generated via fallback when offline');

  // Test offline scoring
  Scores := Peer.ScoreRepairs('Write safe divide function', [Cand], [Repair], [TDebugFeedback.MakeSuccess]);
  AssertTrue(Length(Scores) = 1, 'Score generated via fallback when offline');
  AssertTrue(Scores[0].ScoreValue > 0.0, 'Score value is valid');
end;

procedure TTestMLCRDRunner.RunAllTests;
begin
  Writeln('========================================');
  Writeln('   RUNNING MLCRD MULTI-AGENT TESTS      ');
  Writeln('========================================');
  TestCandidateCritiqueRepairFlow;
  TestCapabilityNegotiation;
  TestScoringCalculation;
  TestReliabilityEvolution;
  TestEndToEndMultiPeerAgent;
  TestFirefoxProtocolParsing;
  TestFirefoxPeerFallbackAndIntegration;
  Writeln('----------------------------------------');
  Writeln(Format('MLCRD Tests Completed: %d Passed, %d Failed', [FPassed, FFailed]));
  Writeln('========================================');
end;

end.
