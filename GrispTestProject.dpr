program GrispTestProject;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Generics.Collections,
  unit_Builder_TGrispGraphBuilder_version_001 in 'unit_Builder_TGrispGraphBuilder_version_001.pas',
  unit_Core_TGrispExpression_version_001 in 'unit_Core_TGrispExpression_version_001.pas',
  unit_Core_TGrispExpressionEvaluator_version_001 in 'unit_Core_TGrispExpressionEvaluator_version_001.pas',
  unit_Core_TGrispType_version_001 in 'unit_Core_TGrispType_version_001.pas',
  unit_Core_TGrispValueBase_version_001 in 'unit_Core_TGrispValueBase_version_001.pas',
  unit_Debug_TGrispDebug_version_001 in 'unit_Debug_TGrispDebug_version_001.pas',
  unit_Graph_TGrispEdge_TGrispNode_version_001 in 'unit_Graph_TGrispEdge_TGrispNode_version_001.pas',
  unit_Graph_TGrispGraph_version_001 in 'unit_Graph_TGrispGraph_version_001.pas',
  unit_Lexer_TGrispLexer_version_001 in 'unit_Lexer_TGrispLexer_version_001.pas',
  unit_Parser_TGrispUnifiedParser_version_001 in 'unit_Parser_TGrispUnifiedParser_version_001.pas',
  unit_Pattern_TGrispMatchResult_version_001 in 'unit_Pattern_TGrispMatchResult_version_001.pas',
  unit_Pattern_TGrispNodeBinding_version_001 in 'unit_Pattern_TGrispNodeBinding_version_001.pas',
  unit_Pattern_TGrispNodeVarInfo_version_001 in 'unit_Pattern_TGrispNodeVarInfo_version_001.pas',
  unit_Pattern_TGrispPatternMatcher_version_001 in 'unit_Pattern_TGrispPatternMatcher_version_001.pas',
  unit_Pattern_TGrispValueBinding_version_001 in 'unit_Pattern_TGrispValueBinding_version_001.pas',
  unit_Rewrite_TGrispRewriteOperation_version_001 in 'unit_Rewrite_TGrispRewriteOperation_version_001.pas',
  unit_Rewrite_TGrispRewriter_version_001 in 'unit_Rewrite_TGrispRewriter_version_001.pas',
  unit_Runtime_TGrispRuntime_version_001 in 'unit_Runtime_TGrispRuntime_version_001.pas',
  unit_Runtime_TGrispRuntimeConfig_version_001 in 'unit_Runtime_TGrispRuntimeConfig_version_001.pas',
  unit_Runtime_TGrispRuntimeEngine_version_001 in 'unit_Runtime_TGrispRuntimeEngine_version_001.pas',
  unit_Strategy_TGrispStrategy_version_001 in 'unit_Strategy_TGrispStrategy_version_001.pas',
  unit_Strategy_TGrispStrategyBuilder_version_001 in 'unit_Strategy_TGrispStrategyBuilder_version_001.pas',
  unit_Strategy_TGrispStrategyEngine_version_001 in 'unit_Strategy_TGrispStrategyEngine_version_001.pas',
  unit_Strategy_TGrispStrategyKind_version_001 in 'unit_Strategy_TGrispStrategyKind_version_001.pas',
  unit_Token_TGrispToken_version_001 in 'unit_Token_TGrispToken_version_001.pas',
  unit_Token_TGrispTokenHelper_version_001 in 'unit_Token_TGrispTokenHelper_version_001.pas',
  unit_Token_TGrispTokenKind_version_001 in 'unit_Token_TGrispTokenKind_version_001.pas';

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
  Tok: TGrispToken;
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
  Graph: TGrispGraph;
  Source: string;
  NodeA, NodeB: TGrispNode;
  ValAttr: TGrispValue;
  Edge: TGrispEdge;
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

  Graph := BuildGraphFromSource(Source);
  try
    AssertTrue(Graph <> nil, 'Parser successfully created a graph');
    AssertEquals(2, Graph.Nodes.Count, 'Graph contains 2 nodes');

    NodeA := Graph.FindNode('A');
    AssertTrue(NodeA <> nil, 'Node "A" exists');
    AssertEqualsStr('node', NodeA.NodeType, 'Node "A" type is "node"');

    ValAttr := NodeA.GetValueAttribute('value');
    AssertTrue((ValAttr <> nil) and (ValAttr.Kind = gvkNumber), 'Attribute "value" of "A" is a number');
    AssertEquals(10, ValAttr.NumberValue, 'Attribute "value" of "A" equals 10');

    NodeB := Graph.FindNode('B');
    AssertTrue(NodeB <> nil, 'Node "B" exists');

    AssertEquals(1, Graph.Edges.Count, 'One edge registered in graph');
    Edge := Graph.Edges[0];
    AssertTrue(Edge.Source = NodeA, 'Edge source is A');
    AssertTrue(Edge.Target = NodeB, 'Edge target is B');
    AssertEqualsStr('next', Edge.LabelName, 'Edge label is "next"');

    ValAttr := NodeB.GetValueAttribute('arr');
    AssertTrue((ValAttr <> nil) and (ValAttr.Kind = gvkArray), 'Attribute "arr" on "B" is an array');
    AssertEquals(3, ValAttr.ArrayValue.Count, 'Array "arr" has 3 elements');
  finally
    Graph.Free;
  end;
end;

procedure TestPatternMatcher;
var
  Graph: TGrispGraph;
  PatternGraph: TGrispGraph;
  Matcher: TGrispPatternMatcher;
  Match: TGrispMatchResult;
  NodeA, NodeB: TGrispNode;
  PatRoot: TGrispNode;
  PatX, PatY, PatXLink: TGrispValue;
  PatXNode, PatYNode: TGrispNode;
begin
  Writeln('Running Pattern Matcher Tests...');

  Graph := TGrispGraph.Create;
  try
    NodeA := Graph.AddNode('A', 'node');
    NodeB := Graph.AddNode('B', 'node');

    NodeA.SetValueAttribute('val', TGrispValue.Create(gvkNumber));
    NodeA.GetValueAttribute('val').NumberValue := 100;
    NodeB.SetValueAttribute('val', TGrispValue.Create(gvkNumber));
    NodeB.GetValueAttribute('val').NumberValue := 200;

    Graph.AddEdge(NodeA, NodeB, 'link');

    PatternGraph := TGrispGraph.Create;
    try
      PatRoot := PatternGraph.AddNode('PatternRoot', 'node');

      // Create pattern node X
      PatXNode := PatternGraph.AddNode('', 'pattern');
      PatXNode.SetValueAttribute('val', TGrispValue.Create(gvkNumber));
      PatXNode.GetValueAttribute('val').NumberValue := 100;

      PatX := TGrispValue.Create(gvkNode);
      PatX.SetNodeReference(PatXNode.Id, PatXNode.Name);

      // Create link from X to Y
      PatXLink := TGrispValue.Create(gvkIdentifier);
      PatXLink.IdentifierValue := 'Y';
      PatXNode.SetValueAttribute('link', PatXLink);

      // Create pattern node Y
      PatYNode := PatternGraph.AddNode('', 'pattern');
      PatYNode.SetValueAttribute('val', TGrispValue.Create(gvkNumber));
      PatYNode.GetValueAttribute('val').NumberValue := 200;

      PatY := TGrispValue.Create(gvkNode);
      PatY.SetNodeReference(PatYNode.Id, PatYNode.Name);

      PatRoot.SetValueAttribute('X', PatX);
      PatRoot.SetValueAttribute('Y', PatY);

      Matcher := TGrispPatternMatcher.Create(Graph);
      try
        Match := Matcher.MatchPattern(PatRoot);
        try
          AssertTrue(Match.Success, 'Pattern matched successfully');

          var BoundX: TGrispNode := nil;
          var BoundY: TGrispNode := nil;
          AssertTrue(Match.TryGetNode('X', BoundX), 'Variable "X" is bound');
          AssertTrue(Match.TryGetNode('Y', BoundY), 'Variable "Y" is bound');

          AssertTrue(BoundX = NodeA, 'Variable "X" bound to Node A');
          AssertTrue(BoundY = NodeB, 'Variable "Y" bound to Node B');
        finally
          Match.Free;
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

procedure TestSwapIfGreater;
var
  Graph: TGrispGraph;
  Source: string;
  NodeA, NodeB: TGrispNode;
  RuleNode: TGrispNode;
  PatternRoot: TGrispNode;
  Matcher: TGrispPatternMatcher;
  Match: TGrispMatchResult;
  StepsRun: Integer;
  MatchValue: TGrispValue;
  NodeId: Integer;
  NodeName: string;
begin
  Writeln('Running Minimal Swap-If-Greater Integration Test...');

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
    '        X: node = {' + #13#10 +
    '            value: number = 2' + #13#10 +
    '            next: identifier = Y' + #13#10 +
    '        }' + #13#10 +
    '        Y: node = {' + #13#10 +
    '            value: number = 1' + #13#10 +
    '        }' + #13#10 +
    '    }' + #13#10 +
    '' + #13#10 +
    '    rewrite: node = {' + #13#10 +
    '        X: node = {' + #13#10 +
    '            value: number = 1' + #13#10 +
    '            next: identifier = Y' + #13#10 +
    '        }' + #13#10 +
    '        Y: node = {' + #13#10 +
    '            value: number = 2' + #13#10 +
    '        }' + #13#10 +
    '    }' + #13#10 +
    '}';

  Graph := BuildGraphFromSource(Source);
  try
    AssertTrue(Graph <> nil, 'Swap-if-greater source successfully parsed');
    AssertEquals(1, Graph.Rules.Count, '1 rule registered in the graph');

    RuleNode := Graph.Rules[0];
    AssertEqualsStr('rule.swap_if_greater', RuleNode.Name, 'Rule name is "rule.swap_if_greater"');

    // Fixed: Get the match value and extract the node reference properly
    MatchValue := RuleNode.GetValueAttribute('match');
    if (MatchValue <> nil) and (MatchValue.Kind = gvkNode) then
    begin
      MatchValue.GetNodeReference(NodeId, NodeName);
      PatternRoot := Graph.FindNode(NodeName);
    end
    else
      PatternRoot := nil;

    Matcher := TGrispPatternMatcher.Create(Graph);
    try
      Match := Matcher.MatchPattern(PatternRoot);
      try
        AssertTrue(not Match.Success, 'Pattern does not match in initial configuration (A=1, B=2)');
      finally
        Match.Free;
      end;

      StepsRun := TGrispRuntime.Run(Graph, 10);
      AssertEquals(0, StepsRun, 'Runtime execution run 0 steps in initial configuration');

      NodeA := Graph.FindNode('A');
      NodeB := Graph.FindNode('B');

      NodeA.GetValueAttribute('value').NumberValue := 2;
      NodeB.GetValueAttribute('value').NumberValue := 1;

      Match := Matcher.MatchPattern(PatternRoot);
      try
        AssertTrue(Match.Success, 'Pattern matches after manually swapping values (A=2, B=1)');

        var BoundX, BoundY: TGrispNode;
        AssertTrue(Match.TryGetNode('X', BoundX) and (BoundX = NodeA), 'X bound to A');
        AssertTrue(Match.TryGetNode('Y', BoundY) and (BoundY = NodeB), 'Y bound to B');
      finally
        Match.Free;
      end;

      StepsRun := TGrispRuntime.Run(Graph, 10);
      AssertEquals(1, StepsRun, 'Runtime successfully ran exactly 1 rewrite step');

      AssertEquals(1, NodeA.GetValueAttribute('value').NumberValue, 'Node A value restored to 1');
      AssertEquals(2, NodeB.GetValueAttribute('value').NumberValue, 'Node B value restored to 2');

      AssertEquals(1, NodeA.Outgoing.Count, 'Node A still has exactly 1 outgoing edge');
      AssertEqualsStr('next', NodeA.Outgoing[0].LabelName, 'Outgoing edge label is "next"');
      AssertTrue(NodeA.Outgoing[0].Target = NodeB, 'Outgoing edge still points to Node B');

    finally
      Matcher.Free;
    end;
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

    TestPatternMatcher;
    Writeln;

    TestSwapIfGreater;
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
