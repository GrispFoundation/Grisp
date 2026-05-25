program GrispTestHarness;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Generics.Collections,
  System.IOUtils,
  unit_Token_TGrispTokenKind_version_001,
  unit_Token_TGrispToken_version_001,
  unit_Token_TGrispTokenHelper_version_001,
  unit_Lexer_TGrispLexer_version_001,
  unit_Graph_TGrispGraph_version_001,
  unit_Graph_TGrispEdge_TGrispNode_version_001,
  unit_Core_TGrispValueBase_version_001,
  unit_Core_TGrispExpression_version_001,
  unit_Core_TGrispExpressionEvaluator_version_001,
  unit_Core_TGrispType_version_001,
  unit_Parser_TGrispParserBase_version_001,
  unit_Parser_TGrispNodeParser_version_001,
  unit_Parser_TGrispTypeParser_version_001,
  unit_Parser_TGrispStrategyParser_version_001,
  unit_Parser_TGrispFullParser_version_001,
  unit_Builder_TGrispGraphBuilder_version_001,
  unit_Pattern_TGrispNodeBinding_version_001,
  unit_Pattern_TGrispValueBinding_version_001,
  unit_Pattern_TGrispMatchResult_version_001,
  unit_Pattern_TGrispNodeVarInfo_version_001,
  unit_Pattern_TGrispPatternMatcher_version_001,
  unit_Rewrite_TGrispRewriteOperation_version_001,
  unit_Rewrite_TGrispRewriter_version_001,
  unit_Strategy_TGrispStrategyKind_version_001,
  unit_Strategy_TGrispStrategy_version_001,
  unit_Strategy_TGrispStrategyBuilder_version_001,
  unit_Strategy_TGrispStrategyEngine_version_001,
  unit_Runtime_TGrispRuntimeConfig_version_001,
  unit_Runtime_TGrispRuntimeEngine_version_001,
  unit_Runtime_TGrispRuntime_version_001;

type
  TTestResult = record
    Name: string;
    Passed: Boolean;
    Message: string;
    DurationMs: Integer;
  end;

  TTestHarness = class
  private
    FResults: TList<TTestResult>;
    FTotalPassed: Integer;
    FTotalFailed: Integer;
    FTotalTime: Integer;
    procedure AddResult(const Name: string; Passed: Boolean; const Msg: string; DurationMs: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    procedure RunTest(const Name: string; TestProc: TProc);
    procedure RunSuite(const SuiteName: string; SuiteProc: TProc);
    procedure Summary;
  end;

  // Test fixtures
  TTestFixtures = class
  public
	class function CreateSimpleGraph: TGrispGraph;
    class function CreateRuleGraph: TGrispGraph;
    class function CreateListGraph(Count: Integer): TGrispGraph;
    class function CreateLinkedList(const Values: array of Double): TGrispGraph;
	class procedure CleanupGraph(var Graph: TGrispGraph);
  end;

{ TTestHarness }

constructor TTestHarness.Create;
begin
  inherited Create;
  FResults := TList<TTestResult>.Create;
  FTotalPassed := 0;
  FTotalFailed := 0;
  FTotalTime := 0;
end;

destructor TTestHarness.Destroy;
begin
  FResults.Free;
  inherited Destroy;
end;

procedure TTestHarness.AddResult(const Name: string; Passed: Boolean; const Msg: string; DurationMs: Integer);
var
  Result: TTestResult;
begin
  Result.Name := Name;
  Result.Passed := Passed;
  Result.Message := Msg;
  Result.DurationMs := DurationMs;
  FResults.Add(Result);

  if Passed then
    Inc(FTotalPassed)
  else
    Inc(FTotalFailed);

  Inc(FTotalTime, DurationMs);

  if Passed then
    Writeln(Format('  [PASS] %s (%.3f ms)', [Name, DurationMs / 1000]))
  else
    Writeln(Format('  [FAIL] %s: %s (%.3f ms)', [Name, Msg, DurationMs / 1000]));
end;

procedure TTestHarness.RunTest(const Name: string; TestProc: TProc);
var
  StartTime: TDateTime;
  DurationMs: Integer;
  Passed: Boolean;
  Msg: string;
begin
  StartTime := Now;
  Passed := True;
  Msg := '';

  try
    TestProc();
  except
    on E: Exception do
    begin
      Passed := False;
      Msg := E.Message;
    end;
  end;

  DurationMs := Round((Now - StartTime) * 24 * 60 * 60 * 1000);
  AddResult(Name, Passed, Msg, DurationMs);
end;

procedure TTestHarness.RunSuite(const SuiteName: string; SuiteProc: TProc);
begin
  Writeln;
  Writeln('=== ' + SuiteName + ' ===');
  SuiteProc();
end;

procedure TTestHarness.Summary;
var
  i: Integer;
begin
  Writeln;
  Writeln('========================================');
  Writeln('TEST SUMMARY');
  Writeln('========================================');
  Writeln(Format('Total Tests: %d', [FResults.Count]));
  Writeln(Format('Passed: %d', [FTotalPassed]));
  Writeln(Format('Failed: %d', [FTotalFailed]));
  Writeln(Format('Total Time: %.3f seconds', [FTotalTime / 1000]));
  Writeln('========================================');

  if FTotalFailed > 0 then
  begin
    Writeln;
    Writeln('Failed Tests:');
    for i := 0 to FResults.Count - 1 do
      if not FResults[i].Passed then
        Writeln(Format('  - %s: %s', [FResults[i].Name, FResults[i].Message]));
  end;
end;

{ TTestFixtures }

class function TTestFixtures.CreateSimpleGraph: TGrispGraph;
begin
  Result := TGrispGraph.Create;
  Result.AddNode('A', 'node');
  Result.AddNode('B', 'node');
  Result.AddNode('C', 'node');
  Result.AddEdge(Result.FindNode('A'), Result.FindNode('B'), 'next');
  Result.AddEdge(Result.FindNode('B'), Result.FindNode('C'), 'next');
end;

class function TTestFixtures.CreateRuleGraph: TGrispGraph;
var
  Graph: TGrispGraph;
  MatchNode, RewriteNode: TGrispNode;
  MatchVal, RewriteVal: TGrispValue;
  XNode, YNode: TGrispNode;
begin
  Graph := TGrispGraph.Create;

  // Create data nodes
  Graph.AddNode('A', 'node');
  Graph.FindNode('A').SetValueAttribute('value', TGrispValue.Create(gvkNumber));
  Graph.FindNode('A').GetValueAttribute('value').NumberValue := 5;

  Graph.AddNode('B', 'node');
  Graph.FindNode('B').SetValueAttribute('value', TGrispValue.Create(gvkNumber));
  Graph.FindNode('B').GetValueAttribute('value').NumberValue := 3;

  Graph.AddEdge(Graph.FindNode('A'), Graph.FindNode('B'), 'next');

  // Create rule node
  var Rule := Graph.AddNode('rule.swap', 'rule');
  Graph.RegisterRule(Rule);

  // Create match pattern
  MatchNode := Graph.AddNode('', 'pattern');
  XNode := Graph.AddNode('', 'pattern');
  YNode := Graph.AddNode('', 'pattern');

  XNode.SetValueAttribute('value', TGrispValue.Create(gvkIdentifier));
  XNode.GetValueAttribute('value').IdentifierValue := 'VX';
  XNode.SetValueAttribute('next', TGrispValue.Create(gvkIdentifier));
  XNode.GetValueAttribute('next').IdentifierValue := 'Y';

  YNode.SetValueAttribute('value', TGrispValue.Create(gvkIdentifier));
  YNode.GetValueAttribute('value').IdentifierValue := 'VY';

  MatchVal := TGrispValue.Create(gvkNode);
  MatchVal.SetNodeReference(XNode.Id, XNode.Name);
  MatchNode.SetValueAttribute('X', MatchVal);

  MatchVal := TGrispValue.Create(gvkNode);
  MatchVal.SetNodeReference(YNode.Id, YNode.Name);
  MatchNode.SetValueAttribute('Y', MatchVal);

  MatchVal := TGrispValue.Create(gvkNode);
  MatchVal.SetNodeReference(MatchNode.Id, MatchNode.Name);
  Rule.SetValueAttribute('match', MatchVal);

  // Create rewrite pattern (simplified)
  RewriteNode := Graph.AddNode('', 'pattern');
  RewriteVal := TGrispValue.Create(gvkNode);
  RewriteVal.SetNodeReference(RewriteNode.Id, RewriteNode.Name);
  Rule.SetValueAttribute('rewrite', RewriteVal);

  Result := Graph;
end;

class function TTestFixtures.CreateListGraph(Count: Integer): TGrispGraph;
var
  i: Integer;
  PrevNode, CurrNode: TGrispNode;
begin
  Result := TGrispGraph.Create;
  PrevNode := nil;
  for i := 1 to Count do
  begin
    CurrNode := Result.AddNode('N' + IntToStr(i), 'node');
    CurrNode.SetValueAttribute('value', TGrispValue.Create(gvkNumber));
    CurrNode.GetValueAttribute('value').NumberValue := Random(100);

    if PrevNode <> nil then
      Result.AddEdge(PrevNode, CurrNode, 'next');

    PrevNode := CurrNode;
  end;
end;

class function TTestFixtures.CreateLinkedList(const Values: array of Double): TGrispGraph;
var
  i: Integer;
  PrevNode, CurrNode: TGrispNode;
begin
  Result := TGrispGraph.Create;
  PrevNode := nil;
  for i := 0 to High(Values) do
  begin
	CurrNode := Result.AddNode('N' + IntToStr(i+1), 'node');
    var Val := TGrispValue.Create(gvkNumber);
    Val.NumberValue := Values[i];
    CurrNode.SetValueAttribute('value', Val);

    if PrevNode <> nil then
      Result.AddEdge(PrevNode, CurrNode, 'next');

    PrevNode := CurrNode;
  end;
end;

class procedure TTestFixtures.CleanupGraph(var Graph: TGrispGraph);
begin
  FreeAndNil(Graph);
end;

{ Actual Test Procedures }

procedure TestLexerBasics;
var
  Lexer: TGrispLexer;
  Tok: TGrispToken;
begin
  Lexer := TGrispLexer.Create('node test { key: string = "hello" }');
  try
    Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkKeywordNode, 'Should recognize "node"');

    Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkIdentifier, 'Should recognize identifier');
    Assert(Tok.Lexeme = 'test', 'Identifier should be "test"');

    Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkLBrace, 'Should recognize "{"');

    Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkIdentifier, 'Should recognize attribute key');

    Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkColon, 'Should recognize ":"');

    Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkIdentifier, 'Should recognize type');

    Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkEquals, 'Should recognize "="');

    Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkString, 'Should recognize string');

    Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkRBrace, 'Should recognize "}"');

    Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkEOF, 'Should reach EOF');
  finally
    Lexer.Free;
  end;
end;

procedure TestLexerOperators;
var
  Lexer: TGrispLexer;
  Tok: TGrispToken;
begin
  Lexer := TGrispLexer.Create('-> <= >= <> = < > + - * /');
  try
    Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkArrow, 'Should recognize "->"');

    Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkLessEqual, 'Should recognize "<="');

    Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkGreaterEqual, 'Should recognize ">="');

    Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkNotEqual, 'Should recognize "<>"');

    Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkEquals, 'Should recognize "="');

    Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkLess, 'Should recognize "<"');

    Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkGreater, 'Should recognize ">"');

    Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkOperator, 'Should recognize "+"');

    Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkOperator, 'Should recognize "-"');

    Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkOperator, 'Should recognize "*"');

    Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkOperator, 'Should recognize "/"');
  finally
    Lexer.Free;
  end;
end;

procedure TestLexerNumbers;
var
  Lexer: TGrispLexer;
  Tok: TGrispToken;
begin
  Lexer := TGrispLexer.Create('123 -456 78.9 -0.5 1e10 2.5e-3');
  try
    Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkNumber, 'Should recognize integer');
    Assert(Tok.Lexeme = '123', 'Integer value');

    Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkNumber, 'Should recognize negative integer');
    Assert(Tok.Lexeme = '-456', 'Negative integer');

    Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkNumber, 'Should recognize float');
    Assert(Tok.Lexeme = '78.9', 'Float value');

    Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkNumber, 'Should recognize negative float');
    Assert(Tok.Lexeme = '-0.5', 'Negative float');

    Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkNumber, 'Should recognize scientific notation');
    Assert(Tok.Lexeme = '1e10', 'Scientific');

	Tok := Lexer.NextToken;
    Assert(Tok.Kind = tkNumber, 'Should recognize negative exponent');
    Assert(Tok.Lexeme = '2.5e-3', 'Negative exponent');
  finally
    Lexer.Free;
  end;
end;

procedure TestParserSimpleNode;
var
  Graph: TGrispGraph;
  Source: string;
  Node: TGrispNode;
begin
  Source :=
    'node MyNode {' + sLineBreak +
    '  count: number = 42' + sLineBreak +
    '  name: string = "test"' + sLineBreak +
    '}';

  Graph := BuildGraphFromSource(Source);
  try
    Assert(Graph <> nil, 'Graph should be created');
    Assert(Graph.Nodes.Count = 1, 'Should have 1 node');

    Node := Graph.FindNode('MyNode');
    Assert(Node <> nil, 'Node "MyNode" should exist');
    Assert(Node.NodeType = 'node', 'Node type should be "node"');

    var CountVal := Node.GetValueAttribute('count');
    Assert(CountVal <> nil, 'Attribute "count" should exist');
    Assert(CountVal.Kind = gvkNumber, '"count" should be number');
    Assert(CountVal.NumberValue = 42, '"count" should be 42');

    var NameVal := Node.GetValueAttribute('name');
    Assert(NameVal <> nil, 'Attribute "name" should exist');
    Assert(NameVal.Kind = gvkString, '"name" should be string');
    Assert(NameVal.StringValue = 'test', '"name" should be "test"');
  finally
    Graph.Free;
  end;
end;

procedure TestParserArrayAttribute;
var
  Graph: TGrispGraph;
  Source: string;
  Node: TGrispNode;
  ArrVal: TGrispValue;
begin
  Source :=
    'node Data {' + sLineBreak +
    '  values: array<number> = [1, 2, 3, 4, 5]' + sLineBreak +
    '}';

  Graph := BuildGraphFromSource(Source);
  try
    Node := Graph.FindNode('Data');
    Assert(Node <> nil, 'Node should exist');

    ArrVal := Node.GetValueAttribute('values');
    Assert(ArrVal <> nil, 'Array attribute should exist');
    Assert(ArrVal.Kind = gvkArray, 'Should be array type');
    Assert(ArrVal.ArrayValue.Count = 5, 'Array should have 5 elements');

    for var i := 0 to 4 do
      Assert(ArrVal.ArrayValue[i].NumberValue = i + 1, Format('Element %d should be %d', [i, i+1]));
  finally
    Graph.Free;
  end;
end;

procedure TestParserNestedNode;
var
  Graph: TGrispGraph;
  Source: string;
  Node: TGrispNode;
  NestedVal: TGrispValue;
  NodeId: Integer;
  NodeName: string;
begin
  Source :=
    'node Parent {' + sLineBreak +
    '  child: node = {' + sLineBreak +
    '    name: string = "ChildNode"' + sLineBreak +
    '    value: number = 99' + sLineBreak +
    '  }' + sLineBreak +
    '}';

  Graph := BuildGraphFromSource(Source);
  try
    Node := Graph.FindNode('Parent');
    Assert(Node <> nil, 'Parent node should exist');

    NestedVal := Node.GetValueAttribute('child');
    Assert(NestedVal <> nil, 'Child attribute should exist');
    Assert(NestedVal.Kind = gvkNode, 'Should be node type');

    NestedVal.GetNodeReference(NodeId, NodeName);
    var ChildNode := Graph.FindNode(NodeName);
    Assert(ChildNode <> nil, 'Child node should exist');

    var NameVal := ChildNode.GetValueAttribute('name');
    Assert(NameVal <> nil, 'Child name attribute should exist');
    Assert(NameVal.StringValue = 'ChildNode', 'Child name should match');

    var ValueVal := ChildNode.GetValueAttribute('value');
    Assert(ValueVal <> nil, 'Child value attribute should exist');
    Assert(ValueVal.NumberValue = 99, 'Child value should be 99');
  finally
    Graph.Free;
  end;
end;

procedure TestGraphOperations;
var
  Graph: TGrispGraph;
  NodeA, NodeB, NodeC: TGrispNode;
  Edge: TGrispEdge;
begin
  Graph := TGrispGraph.Create;
  try
    NodeA := Graph.AddNode('A', 'node');
    NodeB := Graph.AddNode('B', 'node');
    NodeC := Graph.AddNode('C', 'node');

    Assert(Graph.Nodes.Count = 3, 'Should have 3 nodes');
    Assert(Graph.FindNode('A') = NodeA, 'FindNode should return correct node');

    Graph.AddEdge(NodeA, NodeB, 'next');
    Graph.AddEdge(NodeB, NodeC, 'next');

    Assert(Graph.Edges.Count = 2, 'Should have 2 edges');
    Assert(NodeA.Outgoing.Count = 1, 'NodeA should have 1 outgoing edge');
    Assert(NodeC.Incoming.Count = 1, 'NodeC should have 1 incoming edge');

    Edge := NodeA.Outgoing[0];
    Assert(Edge.LabelName = 'next', 'Edge label should be "next"');
    Assert(Edge.Target = NodeB, 'Edge should point to B');

    Graph.RemoveEdge(Edge);
	Assert(Graph.Edges.Count = 1, 'Should have 1 edge after removal');
    Assert(NodeA.Outgoing.Count = 0, 'NodeA should have 0 outgoing edges');
  finally
    Graph.Free;
  end;
end;

procedure TestPatternMatching;
var
  Graph: TGrispGraph;
  Matcher: TGrispPatternMatcher;
  RuleNode: TGrispNode;
  MatchRoot: TGrispNode;
  MatchResult: TGrispMatchResult;
  NodeId: Integer;
  NodeName: string;
  Source: string;
begin
  Source :=
    'node A { value: number = 10; next: identifier = B }' + sLineBreak +
    'node B { value: number = 20 }' + sLineBreak +
    '' + sLineBreak +
    'node rule.test {' + sLineBreak +
    '  match: node = {' + sLineBreak +
    '    X: node = { value: number = VX; next: identifier = Y }' + sLineBreak +
    '    Y: node = { value: number = VY }' + sLineBreak +
    '  }' + sLineBreak +
    '  rewrite: node = {}' + sLineBreak +
    '  where VX < VY' + sLineBreak +
    '}';

  Graph := BuildGraphFromSource(Source);
  try
    Matcher := TGrispPatternMatcher.Create(Graph);
    try
      RuleNode := Graph.Rules[0];
      Matcher.SetCurrentRule(RuleNode);

      var MatchVal := RuleNode.GetValueAttribute('match');
      Assert(MatchVal <> nil, 'Match attribute should exist');
      Assert(MatchVal.Kind = gvkNode, 'Match should be node');

      MatchVal.GetNodeReference(NodeId, NodeName);
      MatchRoot := Graph.FindNode(NodeName);
      Assert(MatchRoot <> nil, 'Match root should exist');

      MatchResult := Matcher.MatchPattern(MatchRoot);
      try
        Assert(MatchResult.Success, 'Pattern should match');

        var XNode: TGrispNode;
        Assert(MatchResult.TryGetNode('X', XNode), 'Should bind X');
        Assert(XNode.Name = 'A', 'X should be A');

        var YNode: TGrispNode;
        Assert(MatchResult.TryGetNode('Y', YNode), 'Should bind Y');
        Assert(YNode.Name = 'B', 'Y should be B');
      finally
        MatchResult.Free;
      end;
    finally
      Matcher.Free;
    end;
  finally
    Graph.Free;
  end;
end;

procedure TestFindAllMatches;
var
  Graph: TGrispGraph;
  Matcher: TGrispPatternMatcher;
  RuleNode: TGrispNode;
  MatchRoot: TGrispNode;
  Matches: TList<TGrispMatchResult>;
  Source: string;
  NodeId: Integer;
  NodeName: string;
begin
  Source :=
    'node N1 { value: number = 5; next: identifier = N2 }' + sLineBreak +
    'node N2 { value: number = 3; next: identifier = N3 }' + sLineBreak +
    'node N3 { value: number = 7; next: identifier = N4 }' + sLineBreak +
    'node N4 { value: number = 1 }' + sLineBreak +
    '' + sLineBreak +
    'node rule.find_all {' + sLineBreak +
    '  match: node = {' + sLineBreak +
    '    X: node = { next: identifier = Y }' + sLineBreak +
    '    Y: node = {}' + sLineBreak +
    '  }' + sLineBreak +
    '  rewrite: node = {}' + sLineBreak +
    '}';

  Graph := BuildGraphFromSource(Source);
  try
    Matcher := TGrispPatternMatcher.Create(Graph);
    try
      RuleNode := Graph.Rules[0];
      Matcher.SetCurrentRule(RuleNode);

      var MatchVal := RuleNode.GetValueAttribute('match');
      MatchVal.GetNodeReference(NodeId, NodeName);
      MatchRoot := Graph.FindNode(NodeName);

      Matches := Matcher.FindAllMatches(MatchRoot);
      try
        Assert(Matches.Count = 3, Format('Should find 3 matches, found %d', [Matches.Count]));

        for var i := 0 to Matches.Count - 1 do
        begin
          var XNode: TGrispNode;
          var YNode: TGrispNode;
          Assert(Matches[i].TryGetNode('X', XNode), Format('Match %d should bind X', [i]));
          Assert(Matches[i].TryGetNode('Y', YNode), Format('Match %d should bind Y', [i]));
          Assert(XNode.Outgoing.Count > 0, 'X should have outgoing edge');
          Assert(XNode.Outgoing[0].Target = YNode, 'X.next should point to Y');
        end;
      finally
        Matches.Free;
      end;
    finally
      Matcher.Free;
    end;
  finally
    Graph.Free;
  end;
end;

procedure TestRewriteOperation;
var
  Graph: TGrispGraph;
  Source: string;
  NodeA, NodeB: TGrispNode;
  Steps: Integer;
begin
  Source :=
    'node A { value: number = 5; next: identifier = B }' + sLineBreak +
    'node B { value: number = 3 }' + sLineBreak +
    '' + sLineBreak +
    'node rule.swap_if_greater {' + sLineBreak +
    '  match: node = {' + sLineBreak +
    '    X: node = { value: number = VX; next: identifier = Y }' + sLineBreak +
    '    Y: node = { value: number = VY }' + sLineBreak +
    '  }' + sLineBreak +
    '  rewrite: node = {' + sLineBreak +
    '    X: node = { value: number = VY; next: identifier = Y }' + sLineBreak +
    '    Y: node = { value: number = VX }' + sLineBreak +
    '  }' + sLineBreak +
    '  where VX > VY' + sLineBreak +
    '}';

  Graph := BuildGraphFromSource(Source);
  try
    NodeA := Graph.FindNode('A');
    NodeB := Graph.FindNode('B');

    Assert(NodeA.GetValueAttribute('value').NumberValue = 5, 'A value should be 5');
    Assert(NodeB.GetValueAttribute('value').NumberValue = 3, 'B value should be 3');

    Steps := TGrispRuntime.Run(Graph, 10);
    Assert(Steps = 1, Format('Should apply 1 rewrite, applied %d', [Steps]));

    Assert(NodeA.GetValueAttribute('value').NumberValue = 3, 'A value should become 3');
    Assert(NodeB.GetValueAttribute('value').NumberValue = 5, 'B value should become 5');
  finally
    Graph.Free;
  end;
end;

procedure TestBubbleSort;
var
  Graph: TGrispGraph;
  Source: string;
  Steps: Integer;
  Values: array[1..10] of Integer;
  i: Integer;
begin
  Source :=
    'node N1  { value: number = 9; next: identifier = N2 }' + sLineBreak +
    'node N2  { value: number = 3; next: identifier = N3 }' + sLineBreak +
    'node N3  { value: number = 7; next: identifier = N4 }' + sLineBreak +
    'node N4  { value: number = 1; next: identifier = N5 }' + sLineBreak +
    'node N5  { value: number = 8; next: identifier = N6 }' + sLineBreak +
    'node N6  { value: number = 2; next: identifier = N7 }' + sLineBreak +
    'node N7  { value: number = 5; next: identifier = N8 }' + sLineBreak +
    'node N8  { value: number = 4; next: identifier = N9 }' + sLineBreak +
    'node N9  { value: number = 6; next: identifier = N10 }' + sLineBreak +
    'node N10 { value: number = 0 }' + sLineBreak +
    '' + sLineBreak +
    'node rule.bubble_swap {' + sLineBreak +
    '  match: node = {' + sLineBreak +
    '    X: node = { value: number = VX; next: identifier = Y }' + sLineBreak +
    '    Y: node = { value: number = VY }' + sLineBreak +
    '  }' + sLineBreak +
    '  rewrite: node = {' + sLineBreak +
    '    X: node = { value: number = VY; next: identifier = Y }' + sLineBreak +
    '    Y: node = { value: number = VX }' + sLineBreak +
    '  }' + sLineBreak +
	'  where VX > VY' + sLineBreak +
    '}';

  Graph := BuildGraphFromSource(Source);
  try
    Steps := TGrispRuntime.Run(Graph, 100);
    Assert(Steps = 58, Format('Expected 58 steps, got %d', [Steps]));

    for i := 1 to 10 do
      Values[i] := Trunc(Graph.FindNode('N' + IntToStr(i)).GetValueAttribute('value').NumberValue);

    for i := 1 to 9 do
      Assert(Values[i] <= Values[i+1], Format('Array should be sorted at position %d', [i]));

    Assert(Values[1] = 0, 'Minimum should be 0');
    Assert(Values[10] = 9, 'Maximum should be 9');
  finally
    Graph.Free;
  end;
end;

procedure TestStrategyBuilder;
var
  Builder: TGrispStrategyBuilder;
  Strategy: TGrispStrategy;
begin
  Builder := TGrispStrategyBuilder.Create;
  try
    Strategy := Builder
      .Sequence
      .Rule('rule1')
      .Rule('rule2')
      .RepeatStrategy
      .Rule('rule3')
      .Build;

    Assert(Strategy <> nil, 'Strategy should be created');
    Assert(Strategy.Kind = gskSequence, 'Root should be sequence');
    Assert(Strategy.Strategies.Count = 3, 'Sequence should have 3 strategies');
    Assert(Strategy.Strategies[0].Kind = gskRule, 'First should be rule');
    Assert(Strategy.Strategies[0].RuleName = 'rule1', 'First rule name');
    Assert(Strategy.Strategies[1].Kind = gskRule, 'Second should be rule');
    Assert(Strategy.Strategies[1].RuleName = 'rule2', 'Second rule name');
    Assert(Strategy.Strategies[2].Kind = gskRepeat, 'Third should be repeat');
    Assert(Strategy.Strategies[2].Strategies[0].RuleName = 'rule3', 'Nested rule name');
  finally
    Builder.Free;
  end;
end;

procedure TestExpressionEvaluator;
var
  Bindings: TDictionary<string, TGrispValue>;
  Expr: TGrispExpression;
  Result: TGrispValue;
begin
  Bindings := TDictionary<string, TGrispValue>.Create;
  try
    // Test literal
    Expr := TGrispExpression.Create(gekLiteral);
    Expr.Value := TGrispValue.Create(gvkNumber);
    TGrispValue(Expr.Value).NumberValue := 42;
    Result := TGrispExpressionEvaluator.Evaluate(Expr, Bindings);
    try
      Assert(Result.NumberValue = 42, 'Literal should be 42');
    finally
	  Result.Free;
    end;
    Expr.Free;

    // Test variable
    var VarVal := TGrispValue.Create(gvkNumber);
    VarVal.NumberValue := 100;
    Bindings.Add('x', VarVal);

    Expr := TGrispExpression.Create(gekVariable);
    Expr.Name := 'x';
    Result := TGrispExpressionEvaluator.Evaluate(Expr, Bindings);
    try
      Assert(Result.NumberValue = 100, 'Variable should be 100');
    finally
      Result.Free;
    end;
    Expr.Free;

    // Test binary addition
    var Left := TGrispExpression.Create(gekLiteral);
    Left.Value := TGrispValue.Create(gvkNumber);
    TGrispValue(Left.Value).NumberValue := 5;

    var Right := TGrispExpression.Create(gekLiteral);
    Right.Value := TGrispValue.Create(gvkNumber);
    TGrispValue(Right.Value).NumberValue := 3;

    Expr := TGrispExpression.Create(gekBinary);
    Expr.OperatorSymbol := '+';
    Expr.Left := Left;
    Expr.Right := Right;

    Result := TGrispExpressionEvaluator.Evaluate(Expr, Bindings);
    try
      Assert(Result.NumberValue = 8, '5 + 3 should be 8');
    finally
      Result.Free;
    end;
    // Don't free Left/Right - they are owned by Expr
    Expr.Free;
  finally
    Bindings.Free;
  end;
end;

procedure TestTypeSystem;
var
  Graph: TGrispGraph;
  Source: string;
  NumberType, StringType: TGrispType;
begin
  Source :=
    'type Counter = number' + sLineBreak +
    'type Message = string' + sLineBreak +
    'type Flag = boolean' + sLineBreak +
    'type NodeList = array<node>' + sLineBreak +
    '' + sLineBreak +
    'node Test {' + sLineBreak +
    '  count: Counter = 10' + sLineBreak +
    '  msg: Message = "hello"' + sLineBreak +
    '  active: Flag = true' + sLineBreak +
    '}';

  Graph := BuildGraphFromSource(Source);
  try
	NumberType := Graph.FindType('Counter');
    Assert(NumberType <> nil, 'Counter type should exist');
    Assert(NumberType.Kind = gtkNumber, 'Counter should be number');

    StringType := Graph.FindType('Message');
    Assert(StringType <> nil, 'Message type should exist');
    Assert(StringType.Kind = gtkString, 'Message should be string');

    var ListNode := Graph.FindNode('Test');
    Assert(ListNode <> nil, 'Test node should exist');
    Assert(ListNode.GetValueAttribute('count').NumberValue = 10, 'Count should be 10');
    Assert(ListNode.GetValueAttribute('msg').StringValue = 'hello', 'Msg should be hello');
    Assert(ListNode.GetValueAttribute('active').BoolValue = True, 'Active should be true');
  finally
    Graph.Free;
  end;
end;

procedure TestRuntimePhases;
var
  Graph: TGrispGraph;
  Source: string;
  Steps: Integer;
  Config: TGrispRuntimeConfig;
begin
  Source :=
    'node A { value: number = 5; phase: number = 1 }' + sLineBreak +
    'node B { value: number = 3; phase: number = 2 }' + sLineBreak +
    '' + sLineBreak +
    'node rule.increment_phase1 {' + sLineBreak +
    '  phase 1' + sLineBreak +
    '  match: node = { value: number = V }' + sLineBreak +
    '  rewrite: node = { value: number = V + 1 }' + sLineBreak +
    '}' + sLineBreak +
    '' + sLineBreak +
    'node rule.double_phase2 {' + sLineBreak +
    '  phase 2' + sLineBreak +
    '  match: node = { value: number = V }' + sLineBreak +
    '  rewrite: node = { value: number = V * 2 }' + sLineBreak +
    '}';

  Graph := BuildGraphFromSource(Source);
  try
    Config.SetDefaults;
    Config.MaxPhases := 2;
    Config.MaxStepsPerPhase := 10;

    Steps := TGrispRuntime.RunWithPhases(Graph, 2, 10);
    Assert(Steps > 0, 'Should apply some rewrites');

    var NodeA := Graph.FindNode('A');
    var NodeB := Graph.FindNode('B');

    // Phase 1: increment (5 -> 6, 3 -> 4)
    // Phase 2: double (6 -> 12, 4 -> 8)
    Assert(NodeA.GetValueAttribute('value').NumberValue = 12, 'A should be 12');
    Assert(NodeB.GetValueAttribute('value').NumberValue = 8, 'B should be 8');
  finally
    Graph.Free;
  end;
end;

procedure TestGarbageCollection;
var
  Graph: TGrispGraph;
  Source: string;
  OrphanCount: Integer;
begin
  Source :=
    'node Root { next: identifier = Child }' + sLineBreak +
    'node Child { value: number = 42 }' + sLineBreak +
    'node Orphan { value: number = 99 }  // This node is unreachable' + sLineBreak +
    '' + sLineBreak +
    'node rule.test { match: node = Root rewrite: node = Root }';

  Graph := BuildGraphFromSource(Source);
  try
    OrphanCount := 0;
    for var Node in Graph.Nodes do
      if Node.Name = 'Orphan' then
        Inc(OrphanCount);

    Assert(OrphanCount = 1, 'Orphan should exist before GC');

    Graph.GarbageCollect;

    OrphanCount := 0;
    for var Node in Graph.Nodes do
      if Node.Name = 'Orphan' then
        Inc(OrphanCount);

    Assert(OrphanCount = 0, 'Orphan should be collected');
    Assert(Graph.FindNode('Root') <> nil, 'Root should still exist');
    Assert(Graph.FindNode('Child') <> nil, 'Child should still exist');
  finally
    Graph.Free;
  end;
end;

procedure TestSerialization;
var
  Graph: TGrispGraph;
  DOT: string;
  JSON: string;
begin
  Graph := TTestFixtures.CreateLinkedList([10, 20, 30, 40, 50]);
  try
    DOT := Graph.ToDOT;
    Assert(DOT.Contains('digraph G'), 'DOT should start with digraph');
    Assert(DOT.Contains('->'), 'DOT should contain edges');

    JSON := Graph.ToJSON;
    Assert(JSON.Contains('"nodes"'), 'JSON should contain nodes');
    Assert(JSON.Contains('"edges"'), 'JSON should contain edges');
    Assert(JSON.Contains('"source"'), 'JSON should contain source');
    Assert(JSON.Contains('"target"'), 'JSON should contain target');
  finally
    Graph.Free;
  end;
end;

var
  Harness: TTestHarness;
begin
  Harness := TTestHarness.Create;
  try
    // Lexer Tests
    Harness.RunSuite('Lexer Tests', procedure
    begin
      Harness.RunTest('Basic tokens', TestLexerBasics);
      Harness.RunTest('Operators', TestLexerOperators);
      Harness.RunTest('Numbers', TestLexerNumbers);
	end);

    // Parser Tests
    Harness.RunSuite('Parser Tests', procedure
    begin
      Harness.RunTest('Simple node', TestParserSimpleNode);
      Harness.RunTest('Array attribute', TestParserArrayAttribute);
      Harness.RunTest('Nested node', TestParserNestedNode);
    end);

    // Graph Tests
    Harness.RunSuite('Graph Tests', procedure
    begin
      Harness.RunTest('Graph operations', TestGraphOperations);
      Harness.RunTest('Serialization', TestSerialization);
      Harness.RunTest('Garbage collection', TestGarbageCollection);
    end);

    // Pattern Matching Tests
    Harness.RunSuite('Pattern Matching Tests', procedure
    begin
      Harness.RunTest('Basic pattern matching', TestPatternMatching);
      Harness.RunTest('Find all matches', TestFindAllMatches);
    end);

    // Rewrite Tests
    Harness.RunSuite('Rewrite Tests', procedure
    begin
      Harness.RunTest('Rewrite operation', TestRewriteOperation);
      Harness.RunTest('Bubble sort', TestBubbleSort);
    end);

    // Strategy Tests
    Harness.RunSuite('Strategy Tests', procedure
    begin
      Harness.RunTest('Strategy builder', TestStrategyBuilder);
    end);

    // Expression Tests
    Harness.RunSuite('Expression Tests', procedure
    begin
      Harness.RunTest('Expression evaluator', TestExpressionEvaluator);
    end);

    // Type System Tests
    Harness.RunSuite('Type System Tests', procedure
    begin
      Harness.RunTest('Type declarations', TestTypeSystem);
    end);

    // Runtime Tests
    Harness.RunSuite('Runtime Tests', procedure
    begin
      Harness.RunTest('Runtime phases', TestRuntimePhases);
    end);

    // Summary
    Harness.Summary;

    if Harness.FTotalFailed > 0 then
      ExitCode := 1
    else
      ExitCode := 0;
  finally
    Harness.Free;
  end;
end.
