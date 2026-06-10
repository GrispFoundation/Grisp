program Grisp;

{$APPTYPE CONSOLE}

{

usage:

type Number = number
type String = string
type Boolean = boolean
type List = array<Node>
type NodeType = Node

strategy bubble_sort = repeat(bubble_swap)
strategy selection_sort = repeat(phase(1), phase(2), phase(3))
strategy hybrid = choice(bubble_sort, selection_sort)

}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  unit_Core_TGrispExpression_version_001,
  unit_Core_TGrispExpressionEvaluator_version_001,
  unit_Core_TGrispType_version_001,
  unit_Core_TGrispValueBase_version_001,
  unit_Graph_TGrispGraph_version_001,
  unit_Graph_TGrispEdge_TGrispNode_version_001,
  unit_Pattern_TGrispNodeBinding_version_001,
  unit_Pattern_TGrispValueBinding_version_001,
  unit_Pattern_TGrispMatchResult_version_001,
  unit_Pattern_TGrispNodeVarInfo_version_001,
  unit_Pattern_TGrispPatternMatcher_version_001,
  unit_Parser_TGrispParserBase_version_001,
  unit_Parser_TGrispNodeParser_version_001,
  unit_Parser_TGrispTypeParser_version_001,
  unit_Parser_TGrispStrategyParser_version_001,
  unit_Parser_TGrispFullParser_version_001,
  unit_Strategy_TGrispStrategyKind_version_001,
  unit_Strategy_TGrispStrategy_version_001,
  unit_Strategy_TGrispStrategyEngine_version_001,
  unit_Strategy_TGrispStrategyBuilder_version_001,
  unit_Token_TGrispTokenKind_version_001,
  unit_Token_TGrispToken_version_001,
  unit_Token_TGrispTokenHelper_version_001,
  unit_Lexer_TGrispLexer_version_001,
  unit_Rewrite_TGrispRewriteOperation_version_001,
  unit_Rewrite_TGrispRewriter_version_001,
  unit_Builder_TGrispGraphBuilder_version_001,
  unit_Runtime_TGrispRuntimeConfig_version_001,
  unit_Runtime_TGrispRuntimeEngine_version_001,
  unit_Runtime_TGrispRuntime_version_001;

const
  GRISP_VERSION = '0.02';
  GRISP_DATE = '24 May 2026';

// colored banner
procedure PrintBanner;
const
  ESC   = #27'[0m';     // reset
  GREEN = #27'[32m';    // bright green
begin
  Writeln('======================================================');
  Writeln(GREEN + '                       +-------+                      ' + ESC);
  Writeln(GREEN + '                     ->|  o o  |<-                    ' + ESC);
  Writeln(GREEN + '                    /  |   o   |  \                   ' + ESC);
  Writeln(GREEN + '                   |   +-------+   |                  ' + ESC);
  Writeln(GREEN + '                    \      ^      /                   ' + ESC);
  Writeln(GREEN + '                     \_____|_____/                    ' + ESC);
  Writeln;
  Writeln(' GRISP - Graph Rewrite Information Symbolic Processor ');
  Writeln(' Deterministic Graph Execution Engine                 ');
  Writeln(Format(' Version %s %s', [GRISP_VERSION, GRISP_DATE]));
  Writeln('======================================================');
  Writeln;
end;

procedure PrintUsage;
begin
  Writeln('Usage: grisp.exe <file.grisp>');
end;

procedure PrintGraph(Graph: TGrispGraph);
var
  Node: TGrispNode;
  Val: TGrispValue;
  First: Boolean;
begin
  First := True;
  for Node in Graph.Nodes do
  begin
    if Node.Name.StartsWith('rule.') then Continue;
    if Node.Name.StartsWith('#') then Continue;

    Val := Node.GetValueAttribute('value');
    if not Assigned(Val) then Continue;
    if Val.Kind <> gvkNumber then Continue;

    if not First then Write(' ');
    First := False;
    Write(Trunc(Val.NumberValue));
  end;
  Writeln;
end;

procedure RunFile(const FileName: string);
var
  Source: string;
  Graph: TGrispGraph;
  Builder: TGrispGraphBuilder;
  Steps: Integer;
  Trace: TStringList;
  UsePhases: Boolean;
  Rule: TGrispNode;
begin
  if not TFile.Exists(FileName) then
    raise Exception.CreateFmt('File not found: %s', [FileName]);

  Writeln('Loading: ', FileName);
  Writeln;

  Source := TFile.ReadAllText(FileName);

  Builder := TGrispGraphBuilder.Create(Source);
  try
    Graph := Builder.Build;
    try
	  // Check if any rule has a phase attribute
      UsePhases := False;
      for Rule in Graph.Rules do
      begin
        if Rule.HasAttribute('phase') then
        begin
          UsePhases := True;
          Break;
        end;
      end;

      Writeln('Initial state:');
      PrintGraph(Graph);
      Writeln;

      Trace := TStringList.Create;
      try
        if UsePhases then
        begin
          Writeln('Using phase-based execution...');
          Steps := TGrispRuntime.RunWithPhases(Graph, 10, 100, Trace);
        end
        else
        begin
          Writeln('Using standard execution...');
          Steps := TGrispRuntime.Run(Graph, 1000, Trace);
        end;
      finally
        Trace.Free;
      end;

      Writeln;
      Writeln('----------------------------------------');
      Writeln(Format('Stable after %d steps.', [Steps]));
      Writeln('Final state:');
      PrintGraph(Graph);
      Writeln('----------------------------------------');
    finally
      Graph.Free;
    end;
  finally
    Builder.Free;
  end;
end;

begin
  try
    PrintBanner;

    if ParamCount = 0 then
    begin
      PrintUsage;
      ExitCode := 1;
      Exit;
    end;

    RunFile(ParamStr(1));
    ExitCode := 0;
  except
    on E: Exception do
    begin
      Writeln;
      Writeln('Error: ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
