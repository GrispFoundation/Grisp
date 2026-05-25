program Grisp;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  unit_GrispGBlocks_version_001 in 'unit_GrispGBlocks_version_001.pas',
  unit_GrispGraph_version_001 in 'unit_GrispGraph_version_001.pas',
  unit_GrispLexer_version_001 in 'unit_GrispLexer_version_001.pas',
  unit_GrispParser_version_001 in 'unit_GrispParser_version_001.pas',
  unit_GrispPattern_version_001 in 'unit_GrispPattern_version_001.pas',
  unit_GrispRewrite_version_001 in 'unit_GrispRewrite_version_001.pas',
  unit_GrispRuntime_version_001 in 'unit_GrispRuntime_version_001.pas',
  unit_GrispTokens_version_001 in 'unit_GrispTokens_version_001.pas';

const
  GRISP_VERSION = '0.02';
  GRISP_DATE = '24 May 2026';

{
procedure PrintBanner;
begin
  //       123456789012345678901234567765432109876543210987654321
  Writeln('======================================================');
  Writeln('                       +-------+                      ');
  Writeln('                     ->|  o o  |<-                    ');
  Writeln('                    /  |   o   |  \                   ');
  Writeln('                   |   +-------+   |                  ');
  Writeln('                    \      ^      /                   ');
  Writeln('                     \_____|_____/                    ');
  Writeln('                                                      ');
  Writeln(' GRISP - Graph Rewrite Information Symbolic Processor ');
  Writeln(' Deterministic Graph Execution Engine                 ');
  Writeln(Format(' Version %s %s', [GRISP_VERSION, GRISP_DATE]));
  //       123456789012345678901234567765432109876543210987654321
  Writeln('======================================================');
  Writeln;
end;
}

// colored banner
procedure PrintBanner;
const
  ESC   = #27'[0m';     // reset
  GREEN = #27'[32m';    // bright green
begin
  //       123456789012345678901234567765432109876543210987654321
  Writeln('======================================================');

  Writeln(GREEN + '                       +-------+                      ' + ESC);
  Writeln(GREEN + '                     ->|  o o  |<-                    ' + ESC);
  Writeln(GREEN + '                    /  |   o   |  \                   ' + ESC);
  Writeln(GREEN + '                   |   +-------+   |                  ' + ESC);
  Writeln(GREEN + '                    \      ^      /                   ' + ESC);
  Writeln(GREEN + '                     \_____|_____/                    ' + ESC);

  Writeln('                                                      ');
  Writeln(' GRISP - Graph Rewrite Information Symbolic Processor ');
  Writeln(' Deterministic Graph Execution Engine                 ');
  Writeln(Format(' Version %s %s', [GRISP_VERSION, GRISP_DATE]));

  //       123456789012345678901234567765432109876543210987654321
  Writeln('======================================================');
  Writeln;
end;

procedure PrintUsage;
begin
  Writeln('Usage: grisp.exe <file.grisp>');
end;

procedure PrintGraph(Graph: TGGraph);
var
  Node: TGNode;
  Val: TGValue;
  First: Boolean;
begin
  First := True;
  for Node in Graph.Nodes do
  begin
    if Node.Name.StartsWith('rule.') then Continue;
    if Node.Name.StartsWith('#') then Continue;

    Val := Node.GetAttribute('value');
    if not Assigned(Val) then Continue;
    if Val.Kind <> vkNumber then Continue;

    if not First then Write(' ');
    First := False;
    Write(Trunc(Val.NumberValue));
  end;
  Writeln;
end;

procedure RunFile(const FileName: string);
var
  Source: string;
  Graph: TGGraph;
  Parser: TGrispParser;
  Steps: Integer;
  Trace: TStringList;
begin
  if not TFile.Exists(FileName) then
    raise Exception.CreateFmt('File not found: %s', [FileName]);

  Writeln('Loading: ', FileName);
  Writeln;

  Source := TFile.ReadAllText(FileName);

  Graph := TGGraph.Create;
  try
    Parser := TGrispParser.Create(Source, Graph);
    try
      Parser.ParseFile;
    finally
      Parser.Free;
    end;

    Graph.RegisterEdgesFromIdentifiers;

    Writeln('Initial state:');
    PrintGraph(Graph);
    Writeln;

    Trace := TStringList.Create;
    try
      Steps := TGrispRuntime.Run(Graph, 1000, Trace);

      // Optional: print trace if needed
      // for var I := 0 to Trace.Count - 1 do
      //   Writeln(Trace[I]);
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


