program GrispAgentCLI;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  GrispCapabilities in '..\..\Source Code\Core\GrispCapabilities.pas',
  GrispVfs in '..\..\Source Code\Core\GrispVfs.pas',
  GrispGraph in '..\..\Source Code\Core\GrispGraph.pas',
  GrispCore in '..\..\Source Code\Core\GrispCore.pas',
  MLCRD_Types in '..\..\Source Code\Agent\MLCRD_Types.pas',
  MLCRD_Interfaces in '..\..\Source Code\Agent\MLCRD_Interfaces.pas',
  MLCRD_Utils in '..\..\Source Code\Agent\MLCRD_Utils.pas',
  MLCRD_Algorithms in '..\..\Source Code\Agent\MLCRD_Algorithms.pas',
  MLCRD_Adapters in '..\..\Source Code\Agent\MLCRD_Adapters.pas',
  MLCRD_Peers in '..\..\Source Code\Agent\MLCRD_Peers.pas',
  MLCRD_Coordinator in '..\..\Source Code\Agent\MLCRD_Coordinator.pas';

procedure PrintBanner;
begin
  Writeln('================================================================');
  Writeln('    GRISP ADVANCED COOPERATIVE AI AGENT (MLCRD + VFS KERNEL)    ');
  Writeln('================================================================');
  Writeln('  Multi-LLM Cross-Repair | Sandboxed Debugging | GRISP Kernel  ');
  Writeln('================================================================');
  Writeln;
end;

procedure PrintHelp;
begin
  Writeln('Usage: GrispAgentCLI [options]');
  Writeln;
  Writeln('Options:');
  Writeln('  -t, --task <prompt>     Execute a single task prompt');
  Writeln('  -i, --interactive       Start interactive multi-peer session');
  Writeln('  --trace                 Display full 12-phase protocol audit trace');
  Writeln('  --json                  Output execution trace as JSON');
  Writeln('  --workspace <path>      Set local directory for sandboxed /workspace');
  Writeln('  -h, --help              Display this help message');
  Writeln;
  Writeln('Examples:');
  Writeln('  GrispAgentCLI -t "Write a safe integer division function in C" --trace');
  Writeln('  GrispAgentCLI -t "Create a GRISP rule to initialize audit task"');
  Writeln('  GrispAgentCLI -i');
end;

var
  TaskPrompt: string;
  InteractiveMode: Boolean;
  ShowTrace: Boolean;
  OutputJson: Boolean;
  WorkspacePath: string;

  I: Integer;
  Arg: string;

  Graph: TGrispGraph;
  Vfs: TGrispVfs;
  CapSet: TGrispCapabilitySet;
  CapWorkspace: IGrispCapability;
  CapTests: IGrispCapability;
  Engine: TGrispEngine;

  VfsAdapter: IGrispVfs;
  TestAdapter: IGrispTestAdapter;
  HarnessAdapter: IGrispHarnessAdapter;

  Peers: TArray<IWebLLMPeer>;
  Agent: TMultiLLMAgent;
  Report: string;
  InputLine: string;

begin
  TaskPrompt := '';
  InteractiveMode := False;
  ShowTrace := False;
  OutputJson := False;
  WorkspacePath := '';

  I := 1;
  while I <= ParamCount do
  begin
    Arg := ParamStr(I);
    if (Arg = '-h') or (Arg = '--help') then
    begin
      PrintBanner;
      PrintHelp;
      Exit;
    end
    else if (Arg = '-t') or (Arg = '--task') then
    begin
      Inc(I);
      if I <= ParamCount then
        TaskPrompt := ParamStr(I);
    end
    else if (Arg = '-i') or (Arg = '--interactive') then
      InteractiveMode := True
    else if Arg = '--trace' then
      ShowTrace := True
    else if Arg = '--json' then
      OutputJson := True
    else if Arg = '--workspace' then
    begin
      Inc(I);
      if I <= ParamCount then
        WorkspacePath := ParamStr(I);
    end;
    Inc(I);
  end;

  if (TaskPrompt = '') and not InteractiveMode then
  begin
    PrintBanner;
    PrintHelp;
    Exit;
  end;

  if not OutputJson then
    PrintBanner;

  // Initialize GRISP Kernel components
  Graph := TGrispGraph.Create;
  Vfs := TGrispVfs.Create(WorkspacePath, True);
  CapSet := TGrispCapabilitySet.Create;

  CapWorkspace := TGrispCapability.Create('workspace-cap', '/workspace',
    [grRead, grWrite, grList, grDelete, grCompile, grRun, grSyntaxCheck, grSemanticCheck],
    ['text/plain', 'text/x-c', 'text/x-pascal', 'text/x-python', 'application/json'], 1048576);
  CapSet.Add(CapWorkspace);

  CapTests := TGrispCapability.Create('test-cap', '/workspace/tests',
    [grRead, grWrite, grList, grDelete, grCompile, grRun, grDebug, grTestExecute, grStackTrace],
    ['text/plain', 'text/x-c', 'text/x-pascal', 'text/x-python'], 1048576);
  CapSet.Add(CapTests);

  Engine := TGrispEngine.Create(Graph, Vfs, CapSet);
  VfsAdapter := TGrispVfsAdapter.Create(Vfs, CapWorkspace);
  TestAdapter := TGrispTestAdapterImpl.Create(Vfs);
  HarnessAdapter := TGrispHarnessAdapterImpl.Create(Engine, 'workspace-cap');

  // Initialize Multi-Peer Team
  Peers := [
    THeuristicPeer.Create('SafetySentinel', psSafety),
    THeuristicPeer.Create('PerformanceOptimizer', psPerformance),
    THeuristicPeer.Create('VerificationAuditor', psVerification),
    TStubPeer.Create('GeneralConsensusPeer', 0.85)
  ];

  Agent := TMultiLLMAgent.Create(Peers, VfsAdapter, TestAdapter, HarnessAdapter);
  try
    if InteractiveMode then
    begin
      Writeln('Interactive mode started. Type task prompt and press Enter (or "quit" to exit):');
      Writeln;
      while True do
      begin
        Write('Agent> ');
        ReadLn(InputLine);
        if (InputLine.Trim = '') or SameText(InputLine.Trim, 'quit') or SameText(InputLine.Trim, 'exit') then
          Break;

        Report := Agent.RunTask(InputLine.Trim);
        if OutputJson then
          Writeln(Agent.GetLastTraceJSON)
        else
        begin
          Writeln(Report);
          if ShowTrace then
          begin
            Writeln('--- JSON PROTOCOL TRACE ---');
            Writeln(Agent.GetLastTraceJSON);
            Writeln('---------------------------');
          end;
        end;
        Writeln;
      end;
    end
    else
    begin
      Report := Agent.RunTask(TaskPrompt);
      if OutputJson then
        Writeln(Agent.GetLastTraceJSON)
      else
      begin
        Writeln(Report);
        if ShowTrace then
        begin
          Writeln;
          Writeln('--- COMPLETE PROTOCOL AUDIT TRACE (JSON) ---');
          Writeln(Agent.GetLastTraceJSON);
          Writeln('--------------------------------------------');
        end;
      end;
    end;

  finally
    Agent.Free;
    Engine.Free;
    CapSet.Free;
    Vfs.Free;
    Graph.Free;
  end;
end.
