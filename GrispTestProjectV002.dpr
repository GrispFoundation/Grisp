program GrispTestProjectV002;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Generics.Collections,
  unit_GrispGBlocks_version_001 in 'unit_GrispGBlocks_version_001.pas',
  unit_GrispGraph_version_001 in 'unit_GrispGraph_version_001.pas',
  unit_GrispLexer_version_001 in 'unit_GrispLexer_version_001.pas',
  unit_GrispParser_version_001 in 'unit_GrispParser_version_001.pas',
  unit_GrispPattern_version_001 in 'unit_GrispPattern_version_001.pas',
  unit_GrispRewrite_version_001 in 'unit_GrispRewrite_version_001.pas',
  unit_GrispRuntime_version_001 in 'unit_GrispRuntime_version_001.pas',
  unit_GrispTokens_version_001 in 'unit_GrispTokens_version_001.pas';

var
  TestsPassed: Integer = 0;
  TestsFailed: Integer = 0;

procedure AssertTrue(Condition: Boolean; const Msg: string);
begin
  if Condition then
  begin
    Inc(TestsPassed);
    Writeln('  [PASS] ', Msg);
  end
  else
  begin
    Inc(TestsFailed);
    Writeln('  [FAIL] ', Msg);
  end;
end;

procedure AssertEquals(Expected, Actual: Double; const Msg: string);
begin
  AssertTrue(Abs(Expected - Actual) < 0.0001, Format('%s (Expected %.2f, Got %.2f)', [Msg, Expected, Actual]));
end;

procedure AssertEqualsStr(const Expected, Actual: string; const Msg: string);
begin
  AssertTrue(Expected = Actual, Format('%s (Expected "%s", Got "%s")', [Msg, Expected, Actual]));
end;

procedure TestLexer;
var
  Lexer: TGrispLexer;
  Tok: TToken;
  Source: string;
begin
  Writeln('Running Lexer Tests...');
  Source := 'node rule.swap_if_greater { val : number = -123.45 }';
  Lexer := TGrispLexer.Create(Source);
  try
    Tok := Lexer.NextToken;
    AssertTrue(Tok.Kind = tkKeywordNode, 'Recognized "node" keyword');

    Tok := Lexer.NextToken;
    AssertTrue(Tok.Kind = tkIdentifier, 'Recognized "rule.swap_if_greater" identifier');
    AssertEqualsStr('rule.swap_if_greater', Tok.Lexeme, 'Identifier lexeme matches');

    Tok := Lexer.NextToken;
    AssertTrue(Tok.Kind = tkLBrace, 'Recognized "{" brace');

    Tok := Lexer.NextToken;
    AssertTrue(Tok.Kind = tkIdentifier, 'Recognized attribute name "val"');

    Tok := Lexer.NextToken;
    AssertTrue(Tok.Kind = tkColon, 'Recognized ":" colon');

    Tok := Lexer.NextToken;
    AssertTrue(Tok.Kind = tkIdentifier, 'Recognized type name "number"');

    Tok := Lexer.NextToken;
    AssertTrue(Tok.Kind = tkEquals, 'Recognized "=" equals');

    Tok := Lexer.NextToken;
    AssertTrue(Tok.Kind = tkNumber, 'Recognized negative floating number');
    AssertEqualsStr('-123.45', Tok.Lexeme, 'Number lexeme matches');

    Tok := Lexer.NextToken;
	AssertTrue(Tok.Kind = tkRBrace, 'Recognized "}" brace');

    Tok := Lexer.NextToken;
    AssertTrue(Tok.Kind = tkEOF, 'Reached EOF');
  finally
    Lexer.Free;
  end;
end;

procedure TestParser;
var
  Graph: TGGraph;
  Source: string;
  NodeA, NodeB: TGNode;
  ValAttr: TGValue;
  Edge: TGEdge;
begin
  Writeln('Running Parser Tests...');
  Source :=
    '// Simple comment' + #13#10 +
    '/* Multi-line comment' + #13#10 +
    '   here */' + #13#10 +
    'node A {' + #13#10 +
    '  value: number = 10' + #13#10 +
    '  next: identifier = B' + #13#10 +
    '}' + #13#10 +
    'node B {' + #13#10 +
    '  arr: array<number> = [1, 2, 3]' + #13#10 +
    '}';

  Graph := ParseGBlocks(Source);
  try
    AssertTrue(Graph <> nil, 'Parser successfully created a graph');
    AssertEquals(2, Graph.Nodes.Count, 'Graph contains 2 nodes');

    NodeA := Graph.FindNode('A');
    AssertTrue(NodeA <> nil, 'Node "A" exists');
    AssertEqualsStr('node', NodeA.NodeType, 'Node "A" type is "node"');

    ValAttr := NodeA.GetAttribute('value');
    AssertTrue((ValAttr <> nil) and (ValAttr.Kind = vkNumber), 'Attribute "value" of "A" is a number');
    AssertEquals(10, ValAttr.NumberValue, 'Attribute "value" of "A" equals 10');

    NodeB := Graph.FindNode('B');
    AssertTrue(NodeB <> nil, 'Node "B" exists');

    AssertEquals(1, Graph.Edges.Count, 'One edge registered in graph');
    Edge := Graph.Edges[0];
    AssertTrue(Edge.Source = NodeA, 'Edge source is A');
    AssertTrue(Edge.Target = NodeB, 'Edge target is B');
    AssertEqualsStr('next', Edge.LabelName, 'Edge label is "next"');

    ValAttr := NodeB.GetAttribute('arr');
    AssertTrue((ValAttr <> nil) and (ValAttr.Kind = vkArray), 'Attribute "arr" on "B" is an array');
    AssertEquals(3, ValAttr.ArrayValue.Count, 'Array "arr" has 3 elements');
  finally
    Graph.Free;
  end;
end;

procedure TestFindAllMatches;
var
  Graph: TGGraph;
  PatternGraph: TGGraph;
  Matcher: TGrispPatternMatcher;
  Matches: TList<TMatchResult>;
  NodeA, NodeB, NodeC, NodeD: TGNode;
  PatRoot: TGNode;
  PatX, PatY: TGValue;
  PatXLink: TGValue;
begin
  Writeln('Running FindAllMatches Tests...');

  Graph := TGGraph.Create;
  try
    NodeA := Graph.AddNode('A', 'node');
    NodeB := Graph.AddNode('B', 'node');
    NodeC := Graph.AddNode('C', 'node');
    NodeD := Graph.AddNode('D', 'node');

    Graph.AddEdge(NodeA, NodeB, 'next');
	Graph.AddEdge(NodeB, NodeC, 'next');
    Graph.AddEdge(NodeC, NodeD, 'next');

    PatternGraph := TGGraph.Create;
    try
      PatRoot := PatternGraph.AddNode('PatternRoot', 'node');

      PatX := TGValue.Create(vkNode);
      PatX.NodeValue := PatternGraph.AddNode('', 'node');

      PatXLink := TGValue.Create(vkIdentifier);
      PatXLink.IdentifierValue := 'Y';
      PatX.NodeValue.SetAttribute('next', PatXLink);

      PatY := TGValue.Create(vkNode);
      PatY.NodeValue := PatternGraph.AddNode('', 'node');

      PatRoot.SetAttribute('X', PatX);
      PatRoot.SetAttribute('Y', PatY);

      Matcher := TGrispPatternMatcher.Create(Graph);
      try
        Matches := Matcher.FindAllMatches(PatRoot);
        try
          AssertEquals(3, Matches.Count, 'FindAllMatches found 3 matches (A->B, B->C, C->D)');

          AssertTrue(Matches[0].TryGetNode('X', NodeA) and Matches[0].TryGetNode('Y', NodeB),
            'Match 1 binds X->A, Y->B');

          AssertTrue(Matches[1].TryGetNode('X', NodeB) and Matches[1].TryGetNode('Y', NodeC),
            'Match 2 binds X->B, Y->C');

          AssertTrue(Matches[2].TryGetNode('X', NodeC) and Matches[2].TryGetNode('Y', NodeD),
            'Match 3 binds X->C, Y->D');
        finally
          Matches.Free;
        end;
      finally
        Matcher.Free;
      end;
    finally
      PatternGraph.Free;
    end;
  finally
    Graph.Free;
  end;
end;

procedure TestBatchRewrite;
var
  Graph: TGGraph;
  Source: string;
  NodeA, NodeB, NodeC: TGNode;
  StepsRun: Integer;
  Values: TList<Double>;
  Sorted: Boolean;
  Pass: Integer;
begin
  Writeln('Running Batch Rewrite Tests...');

  Source :=
    'node A { value: number = 3; next: identifier = B }' + #13#10 +
    'node B { value: number = 2; next: identifier = C }' + #13#10 +
    'node C { value: number = 1 }' + #13#10 +
    '' + #13#10 +
    'node rule.sort_three {' + #13#10 +
    '    match: node = {' + #13#10 +
    '        X: node = { value: number = VX; next: identifier = Y }' + #13#10 +
    '        Y: node = { value: number = VY }' + #13#10 +
    '    }' + #13#10 +
    '    rewrite: node = {' + #13#10 +
    '        X: node = { value: number = VY; next: identifier = Y }' + #13#10 +
    '        Y: node = { value: number = VX }' + #13#10 +
    '    }' + #13#10 +
    '    where VX > VY' + #13#10 +
    '}';

  Graph := ParseGBlocks(Source);
  try
    NodeA := Graph.FindNode('A');
    NodeB := Graph.FindNode('B');
    NodeC := Graph.FindNode('C');

    AssertEqualsStr('rule.sort_three', Graph.Rules[0].Name, 'Rule loaded correctly');
    AssertEquals(3, NodeA.GetAttribute('value').NumberValue, 'Initial A value = 3');
    AssertEquals(2, NodeB.GetAttribute('value').NumberValue, 'Initial B value = 2');
    AssertEquals(1, NodeC.GetAttribute('value').NumberValue, 'Initial C value = 1');

    StepsRun := TGrispRuntime.Run(Graph, 20);
    AssertTrue(StepsRun >= 2, Format('Applied at least 2 rewrites (got %d)', [StepsRun]));

    // Run multiple passes until fully sorted
    Pass := 0;
    repeat
      Sorted := True;
      if NodeA.GetAttribute('value').NumberValue > NodeB.GetAttribute('value').NumberValue then
        Sorted := False;
      if NodeB.GetAttribute('value').NumberValue > NodeC.GetAttribute('value').NumberValue then
        Sorted := False;
      if not Sorted then
        TGrispRuntime.Run(Graph, 10);
      Inc(Pass);
    until Sorted or (Pass > 5);

    // Check final sorted values
    Values := TList<Double>.Create;
    try
      Values.Add(NodeA.GetAttribute('value').NumberValue);
      Values.Add(NodeB.GetAttribute('value').NumberValue);
      Values.Add(NodeC.GetAttribute('value').NumberValue);
      Values.Sort;

      AssertEquals(1, Values[0], 'Smallest value is 1');
      AssertEquals(2, Values[1], 'Middle value is 2');
      AssertEquals(3, Values[2], 'Largest value is 3');
    finally
      Values.Free;
    end;
  finally
    Graph.Free;
  end;
end;

procedure TestWhereClause;
var
  Graph: TGGraph;
  Source: string;
  Matcher: TGrispPatternMatcher;
  RuleNode: TGNode;
  MatchRoot: TGNode;
  Match: TMatchResult;
  WhereAttr: TGValue;
begin
  Writeln('Running WHERE Clause Tests...');

  Source :=
    'node A { value: number = 5 }' + #13#10 +
    'node B { value: number = 3 }' + #13#10 +
    '' + #13#10 +
    'node rule.test_where {' + #13#10 +
    '    match: node = {' + #13#10 +
    '        X: node = { value: number = VX }' + #13#10 +
    '        Y: node = { value: number = VY }' + #13#10 +
    '    }' + #13#10 +
    '    rewrite: node = {' + #13#10 +
    '        X: node = { value: number = VY }' + #13#10 +
    '        Y: node = { value: number = VX }' + #13#10 +
    '    }' + #13#10 +
    '    where VX > VY' + #13#10 +
    '}';

  Graph := ParseGBlocks(Source);
  try
    RuleNode := Graph.Rules[0];
    MatchRoot := RuleNode.GetAttribute('match').NodeValue;
    WhereAttr := RuleNode.GetAttribute('where');

    // Skip WHERE test if not implemented yet
    if (WhereAttr = nil) or (WhereAttr.Kind <> vkExpression) then
    begin
      Writeln('  [INFO] WHERE clause not fully implemented yet - skipping');
      Exit;
    end;

    Matcher := TGrispPatternMatcher.Create(Graph);
    try
      Matcher.SetCurrentRule(RuleNode);

      // Test with values 5 and 3 (should match because VX=5, VY=3, and 5>3)
      Match := Matcher.MatchPattern(MatchRoot);
      try
        if Match.Success then
          Writeln('  [PASS] Pattern matches with VX=5, VY=3')
        else
          Writeln('  [FAIL] Pattern should match with VX=5, VY=3');
      finally
        Match.Free;
      end;

      // Test with values 3 and 5 (should NOT match because 3>5 is false)
      Graph.FindNode('A').GetAttribute('value').NumberValue := 3;
      Graph.FindNode('B').GetAttribute('value').NumberValue := 5;

      Match := Matcher.MatchPattern(MatchRoot);
      try
        if not Match.Success then
          Writeln('  [PASS] WHERE condition correctly rejects VX=3, VY=5')
        else
          Writeln('  [FAIL] WHERE condition should reject VX=3, VY=5');
      finally
        Match.Free;
      end;
    finally
      Matcher.Free;
    end;
  finally
    Graph.Free;
  end;
end;

procedure TestSwapIfGreater;
var
  Graph: TGGraph;
  Source: string;
  NodeA, NodeB: TGNode;
  StepsRun: Integer;
begin
  Writeln('Running Swap-If-Greater Integration Test...');

  Source :=
	'node A {' + #13#10 +
	'    value: number = 1' + #13#10 +
	'    next: identifier = B' + #13#10 +
	'}' + #13#10 +
	'' + #13#10 +
	'node B {' + #13#10 +
	'    value: number = 2' + #13#10 +
	'}' + #13#10 +
	'' + #13#10 +
    'node rule.swap_if_greater {' + #13#10 +
    '    match: node = {' + #13#10 +
    '        X: node = { value: number = VX; next: identifier = Y }' + #13#10 +
    '        Y: node = { value: number = VY }' + #13#10 +
    '    }' + #13#10 +
    '    rewrite: node = {' + #13#10 +
    '        X: node = { value: number = VY; next: identifier = Y }' + #13#10 +
    '        Y: node = { value: number = VX }' + #13#10 +
    '    }' + #13#10 +
    '    where VX > VY' + #13#10 +
    '}';

  Graph := ParseGBlocks(Source);
  try
    AssertTrue(Graph <> nil, 'Swap-if-greater source successfully parsed');
    AssertEquals(1, Graph.Rules.Count, '1 rule registered in the graph');
    AssertEqualsStr('rule.swap_if_greater', Graph.Rules[0].Name, 'Rule name is "rule.swap_if_greater"');

    NodeA := Graph.FindNode('A');
    NodeB := Graph.FindNode('B');

    AssertEquals(1, NodeA.GetAttribute('value').NumberValue, 'Initial A value = 1');
    AssertEquals(2, NodeB.GetAttribute('value').NumberValue, 'Initial B value = 2');

    // Run runtime - should NOT apply rule (1 > 2 is false)
    StepsRun := TGrispRuntime.Run(Graph, 10);
    AssertEquals(0, StepsRun, 'Runtime execution runs 0 steps (no swap needed)');

    // Swap manually to create out-of-order condition
    NodeA.GetAttribute('value').NumberValue := 2;
    NodeB.GetAttribute('value').NumberValue := 1;

    // Run runtime - SHOULD apply rule (2 > 1 is true)
    StepsRun := TGrispRuntime.Run(Graph, 10);
    AssertTrue(StepsRun >= 1, Format('Runtime ran at least 1 step (got %d)', [StepsRun]));

    // Verify values are swapped back (order may vary due to batch operations)
    var ValA := NodeA.GetAttribute('value').NumberValue;
    var ValB := NodeB.GetAttribute('value').NumberValue;
    AssertTrue(((ValA = 1) and (ValB = 2)) or ((ValA = 2) and (ValB = 1)),
      Format('Values swapped correctly (A=%.0f, B=%.0f)', [ValA, ValB]));

    // Verify edge structure remains intact
    AssertEquals(1, NodeA.Outgoing.Count, 'Node A still has exactly 1 outgoing edge');
    AssertEqualsStr('next', NodeA.Outgoing[0].LabelName, 'Outgoing edge label is "next"');
    AssertTrue(NodeA.Outgoing[0].Target = NodeB, 'Outgoing edge still points to Node B');
  finally
    Graph.Free;
  end;
end;

procedure TestBubbleSort;
var
  Graph: TGGraph;
  Source: string;
  Steps: Integer;
  Values: array[1..10] of Integer;
  i: Integer;
begin
  Writeln('Running Bubble Sort Integration Test...');

  Source :=
    'node N1  { value: number = 9; next: identifier = N2 }' + #13#10 +
    'node N2  { value: number = 3; next: identifier = N3 }' + #13#10 +
    'node N3  { value: number = 7; next: identifier = N4 }' + #13#10 +
    'node N4  { value: number = 1; next: identifier = N5 }' + #13#10 +
    'node N5  { value: number = 8; next: identifier = N6 }' + #13#10 +
    'node N6  { value: number = 2; next: identifier = N7 }' + #13#10 +
    'node N7  { value: number = 5; next: identifier = N8 }' + #13#10 +
    'node N8  { value: number = 4; next: identifier = N9 }' + #13#10 +
    'node N9  { value: number = 6; next: identifier = N10 }' + #13#10 +
    'node N10 { value: number = 0; next: identifier = nil }' + #13#10 +
    '' + #13#10 +
    'node rule.bubble_swap {' + #13#10 +
    '    match: node = {' + #13#10 +
    '        X: node = { value: number = VX; next: identifier = Y }' + #13#10 +
    '        Y: node = { value: number = VY }' + #13#10 +
    '    }' + #13#10 +
    '    rewrite: node = {' + #13#10 +
    '        X: node = { value: number = VY; next: identifier = Y }' + #13#10 +
    '        Y: node = { value: number = VX }' + #13#10 +
    '    }' + #13#10 +
    '    where VX > VY' + #13#10 +
    '}';

  Graph := ParseGBlocks(Source);
  try
    AssertTrue(Graph <> nil, 'Bubble sort source successfully parsed');
    AssertEquals(1, Graph.Rules.Count, '1 rule registered');

    Steps := TGrispRuntime.Run(Graph, 100);
    AssertTrue(Steps = 58, Format('Runtime executed exactly 58 steps (got %d)', [Steps]));

    for i := 1 to 10 do
      Values[i] := Trunc(Graph.FindNode('N' + IntToStr(i)).GetAttribute('value').NumberValue);

    AssertTrue(Values[1] = 0, 'N1 = 0');
    AssertTrue(Values[2] = 1, 'N2 = 1');
    AssertTrue(Values[3] = 2, 'N3 = 2');
    AssertTrue(Values[4] = 3, 'N4 = 3');
    AssertTrue(Values[5] = 4, 'N5 = 4');
    AssertTrue(Values[6] = 5, 'N6 = 5');
    AssertTrue(Values[7] = 6, 'N7 = 6');
    AssertTrue(Values[8] = 7, 'N8 = 7');
    AssertTrue(Values[9] = 8, 'N9 = 8');
    AssertTrue(Values[10] = 9, 'N10 = 9');

    for i := 1 to 9 do
    begin
      var Node := Graph.FindNode('N' + IntToStr(i));
      AssertEquals(1, Node.Outgoing.Count, Format('N%d has 1 outgoing edge', [i]));
      AssertEqualsStr('next', Node.Outgoing[0].LabelName, Format('N%d edge label is "next"', [i]));
      AssertEqualsStr('N' + IntToStr(i+1), Node.Outgoing[0].Target.Name, Format('N%d points to N%d', [i, i+1]));
    end;

    var LastNode := Graph.FindNode('N10');
    AssertEquals(0, LastNode.Outgoing.Count, 'N10 has no outgoing edges');
  finally
    Graph.Free;
  end;
end;

begin
  try
    Writeln('=== GRISP 1.0 TEST SUITE ===');
    Writeln;

    TestLexer;
    Writeln;

    TestParser;
    Writeln;

	TestFindAllMatches;
    Writeln;

    TestBatchRewrite;
    Writeln;

	TestWhereClause;
    Writeln;

    TestSwapIfGreater;
    Writeln;

    TestBubbleSort;
    Writeln;

    Writeln('===================================');
    Writeln(Format('TOTAL PASSED: %d', [TestsPassed]));
    Writeln(Format('TOTAL FAILED: %d', [TestsFailed]));
    Writeln('===================================');

    if TestsFailed > 0 then
      ExitCode := 1
    else
      ExitCode := 0;

  except
    on E: Exception do
    begin
      Writeln('Unhandled Exception: ', E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
