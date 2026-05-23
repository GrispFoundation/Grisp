program GrispTestProject;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Generics.Collections,
  unit_GrispTokens_version_001 in 'unit_GrispTokens_version_001.pas',
  unit_GrispLexer_version_001 in 'unit_GrispLexer_version_001.pas',
  unit_GrispGraph_version_001 in 'unit_GrispGraph_version_001.pas',
  unit_GrispParser_version_001 in 'unit_GrispParser_version_001.pas',
  unit_GrispGBlocks_version_001 in 'unit_GrispGBlocks_version_001.pas',
  unit_GrispPattern_version_001 in 'unit_GrispPattern_version_001.pas',
  unit_GrispRewrite_version_001 in 'unit_GrispRewrite_version_001.pas',
  unit_GrispRuntime_version_001 in 'unit_GrispRuntime_version_001.pas';

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
  AssertTrue(Abs(Expected - Actual) < 0.0001, Format('%s (Expected %f, Got %f)', [Msg, Expected, Actual]));
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
    
    // Check edge created from next: identifier = B
    AssertEquals(1, Graph.Edges.Count, 'One edge registered in graph');
    Edge := Graph.Edges[0];
    AssertTrue(Edge.Source = NodeA, 'Edge source is A');
    AssertTrue(Edge.Target = NodeB, 'Edge target is B');
    AssertEqualsStr('next', Edge.LabelName, 'Edge label is "next"');
    
    // Check array attribute on node B
    ValAttr := NodeB.GetAttribute('arr');
    AssertTrue((ValAttr <> nil) and (ValAttr.Kind = vkArray), 'Attribute "arr" on "B" is an array');
    AssertEquals(3, ValAttr.ArrayValue.Count, 'Array "arr" has 3 elements');
  finally
    Graph.Free;
  end;
end;

procedure TestPatternMatcher;
var
  Graph: TGGraph;
  PatternGraph: TGGraph;
  Matcher: TGrispPatternMatcher;
  Match: TMatchResult;
  NodeA, NodeB: TGNode;
begin
  Writeln('Running Pattern Matcher Tests...');
  
  // Construct a small graph manually
  Graph := TGGraph.Create;
  try
    NodeA := Graph.AddNode('A', 'node');
    NodeB := Graph.AddNode('B', 'node');
    
    // Set value attributes
    NodeA.SetAttribute('val', TGValue.Create(vkNumber));
    NodeA.GetAttribute('val').NumberValue := 100;
    NodeB.SetAttribute('val', TGValue.Create(vkNumber));
    NodeB.GetAttribute('val').NumberValue := 200;
    
    Graph.AddEdge(NodeA, NodeB, 'link');

    // Create a pattern graph representing: Match a node X with val = 100 pointing to Y with val = 200
    PatternGraph := TGGraph.Create;
    try
      // A pattern is just a pattern root with attributes matching node vars
      // We will construct this mimicking parser output:
      // node PatternRoot {
      //   X: node = { val: number = 100, link: identifier = Y }
      //   Y: node = { val: number = 200 }
      // }
      var PatRoot := PatternGraph.AddNode('PatternRoot', 'node');
      
      var PatX := TGValue.Create(vkNode);
      PatX.NodeValue := PatternGraph.AddNode('', 'node');
      PatX.NodeValue.SetAttribute('val', TGValue.Create(vkNumber));
      PatX.NodeValue.GetAttribute('val').NumberValue := 100;
      
      var PatXLink := TGValue.Create(vkIdentifier);
      PatXLink.IdentifierValue := 'Y';
      PatX.NodeValue.SetAttribute('link', PatXLink);

      var PatY := TGValue.Create(vkNode);
      PatY.NodeValue := PatternGraph.AddNode('', 'node');
      PatY.NodeValue.SetAttribute('val', TGValue.Create(vkNumber));
      PatY.NodeValue.GetAttribute('val').NumberValue := 200;

      PatRoot.SetAttribute('X', PatX);
      PatRoot.SetAttribute('Y', PatY);

      Matcher := TGrispPatternMatcher.Create(Graph);
      try
        Match := Matcher.MatchPattern(PatRoot);
        try
          AssertTrue(Match.Success, 'Pattern matched successfully');
          
          var BoundX: TGNode := nil;
          var BoundY: TGNode := nil;
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
  Graph: TGGraph;
  Source: string;
  NodeA, NodeB: TGNode;
  RuleNode, PatternRoot: TGNode;
  Matcher: TGrispPatternMatcher;
  Match: TMatchResult;
  StepsRun: Integer;
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

  Graph := ParseGBlocks(Source);
  try
    AssertTrue(Graph <> nil, 'Swap-if-greater source successfully parsed');
    AssertEquals(1, Graph.Rules.Count, '1 rule registered in the graph');
    
    RuleNode := Graph.Rules[0];
    AssertEqualsStr('rule.swap_if_greater', RuleNode.Name, 'Rule name is "rule.swap_if_greater"');
    
    PatternRoot := RuleNode.GetAttribute('match').NodeValue;
    
    Matcher := TGrispPatternMatcher.Create(Graph);
    try
      // 1. Initial State: A = 1, B = 2. A -> B.
      // The pattern requires X (with value = 2) to point to Y (with value = 1).
      // Since B has 2 but no next, and A has 1 but points to B, there should be NO match!
      Match := Matcher.MatchPattern(PatternRoot);
      try
        AssertTrue(not Match.Success, 'Pattern does not match in initial configuration (A=1, B=2)');
      finally
        Match.Free;
      end;
      
      // Call runtime loop in initial state
      StepsRun := TGrispRuntime.Run(Graph, 10);
      AssertEquals(0, StepsRun, 'Runtime execution run 0 steps in initial configuration');

      // 2. Swapped State (A = 2, B = 1).
      // Now A (value 2) points to B (value 1). So X matches A, Y matches B.
      // This should successfully match and trigger the rule!
      NodeA := Graph.FindNode('A');
      NodeB := Graph.FindNode('B');
      
      // Update values manually to simulate swap
      NodeA.GetAttribute('value').NumberValue := 2;
      NodeB.GetAttribute('value').NumberValue := 1;
      
      Match := Matcher.MatchPattern(PatternRoot);
      try
        AssertTrue(Match.Success, 'Pattern matches after manually swapping values (A=2, B=1)');
        
        var BoundX, BoundY: TGNode;
        AssertTrue(Match.TryGetNode('X', BoundX) and (BoundX = NodeA), 'X bound to A');
        AssertTrue(Match.TryGetNode('Y', BoundY) and (BoundY = NodeB), 'Y bound to B');
      finally
        Match.Free;
      end;

      // Run the runtime execution loop (deterministic)
      StepsRun := TGrispRuntime.Run(Graph, 10);
      AssertEquals(1, StepsRun, 'Runtime successfully ran exactly 1 rewrite step');
      
      // Verify values are swapped back to A=1, B=2 by the rewrite engine
      AssertEquals(1, NodeA.GetAttribute('value').NumberValue, 'Node A value restored to 1');
      AssertEquals(2, NodeB.GetAttribute('value').NumberValue, 'Node B value restored to 2');
      
      // Verify edge structure remains intact (A next -> B)
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
