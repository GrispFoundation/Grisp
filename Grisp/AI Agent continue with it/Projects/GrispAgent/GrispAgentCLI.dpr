program GrispAgentCLI;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
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
  MLCRD_FirefoxPeer in '..\..\Source Code\Agent\MLCRD_FirefoxPeer.pas',
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
  Writeln('  --firefox               Enable Firefox Web AI automation integration');
  Writeln('  --port <port>           Set Firefox TCP port (default: 9999)');
  Writeln('  --sites <list>          Comma-separated AI sites (deepseek,gemini,claude,...)');
  Writeln('  --list-tabs             List all open Firefox tabs and exit');
  Writeln('  --open-tab <url>        Open a URL in Firefox and exit');
  Writeln('  -h, --help              Display this help message');
  Writeln;
  Writeln('Examples:');
  Writeln('  GrispAgentCLI -t "Write a safe integer division function in C" --trace');
  Writeln('  GrispAgentCLI -t "Implement safe integer division" --sites deepseek,gemini');
  Writeln('  GrispAgentCLI --list-tabs');
  Writeln('  GrispAgentCLI -i');
end;

procedure PrintTabs(const ResponseJson: string);
var
  JsonObj: TJSONObject;
  Tabs: TJSONArray;
  TabObj: TJSONObject;
  I, Index: Integer;
  IsSelected: Boolean;
  SelectedStr, Title, Url: string;
begin
  JsonObj := TJSONObject.ParseJSONValue(ResponseJson) as TJSONObject;
  if JsonObj = nil then
  begin
    Writeln('Error: Invalid tabs response format');
    Exit;
  end;
  try
    if not JsonObj.TryGetValue<TJSONArray>('tabs', Tabs) then
    begin
      Writeln('No tabs array in response');
      Exit;
    end;

    Writeln(Format('%-6s %-10s %-40s %s', ['Index', 'Selected', 'Title', 'URL']));
    Writeln(StringOfChar('-', 100));

    for I := 0 to Tabs.Count - 1 do
    begin
      TabObj := Tabs.Items[I] as TJSONObject;
      Index := TabObj.GetValue<Integer>('index', -1);
      IsSelected := TabObj.GetValue<Boolean>('selected', False);
      if IsSelected then SelectedStr := '*' else SelectedStr := '';
      Title := TabObj.GetValue<string>('title', '');
      Url := TabObj.GetValue<string>('url', '');
      if Length(Title) > 38 then Title := Copy(Title, 1, 38);
      Writeln(Format('%-6d %-10s %-40s %s', [Index, SelectedStr, Title, Url]));
    end;
  finally
    JsonObj.Free;
  end;
end;

var
  TaskPrompt: string;
  InteractiveMode: Boolean;
  ShowTrace: Boolean;
  OutputJson: Boolean;
  WorkspacePath: string;
  UseFirefox: Boolean;
  FirefoxPort: Integer;
  SitesArg: string;
  ListTabsMode: Boolean;
  OpenTabUrl: string;
  SitesList: TArray<string>;

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
  FClient: TFirefoxClient;
  TabsJson: string;

begin
  TaskPrompt := '';
  InteractiveMode := False;
  ShowTrace := False;
  OutputJson := False;
  WorkspacePath := '';
  UseFirefox := False;
  FirefoxPort := DEFAULT_FIREFOX_PORT;
  SitesArg := '';
  ListTabsMode := False;
  OpenTabUrl := '';

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
    end
    else if Arg = '--firefox' then
      UseFirefox := True
    else if Arg = '--port' then
    begin
      Inc(I);
      if I <= ParamCount then
        FirefoxPort := StrToIntDef(ParamStr(I), DEFAULT_FIREFOX_PORT);
    end
    else if Arg = '--sites' then
    begin
      Inc(I);
      if I <= ParamCount then
      begin
        SitesArg := ParamStr(I);
        UseFirefox := True;
      end;
    end
    else if Arg = '--list-tabs' then
      ListTabsMode := True
    else if Arg = '--open-tab' then
    begin
      Inc(I);
      if I <= ParamCount then
        OpenTabUrl := ParamStr(I);
    end;
    Inc(I);
  end;

  if ListTabsMode then
  begin
    PrintBanner;
    Writeln(Format('Querying Firefox tabs on localhost:%d...', [FirefoxPort]));
    FClient := TFirefoxClient.Create('localhost', FirefoxPort, 3000, 5000);
    try
      if FClient.GetTabs(TabsJson) then
        PrintTabs(TabsJson)
      else
        Writeln(Format('Notice: Could not reach Firefox on localhost:%d. Ensure Firefox is running with the AI automation service active.', [FirefoxPort]));
    finally
      FClient.Free;
    end;
    Exit;
  end;

  if OpenTabUrl <> '' then
  begin
    PrintBanner;
    Writeln(Format('Opening "%s" in Firefox on localhost:%d...', [OpenTabUrl, FirefoxPort]));
    FClient := TFirefoxClient.Create('localhost', FirefoxPort, 3000, 5000);
    try
      if FClient.OpenTab(OpenTabUrl) then
        Writeln('Tab opened successfully.')
      else
        Writeln(Format('Notice: Failed to open tab in Firefox on localhost:%d.', [FirefoxPort]));
    finally
      FClient.Free;
    end;
    Exit;
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
  if UseFirefox or (SitesArg <> '') then
  begin
    if SitesArg <> '' then
      SitesList := SitesArg.Split([',', ';', ' '])
    else
      SitesList := ['deepseek'];

    FClient := TFirefoxClient.Create('localhost', FirefoxPort, 1500, 2000);
    try
      if FClient.IsOnline then
        Writeln(Format('[INFO] Connected to Firefox Web AI on port %d with site(s): %s', [FirefoxPort, string.Join(', ', SitesList)]))
      else
        Writeln(Format('[NOTICE] Firefox automation not detected on localhost:%d. Using reliable heuristic fallback peers.', [FirefoxPort]));
    finally
      FClient.Free;
    end;

    Peers := CreateFirefoxPeers(SitesList, FirefoxPort);
  end
  else
  begin
    Peers := [
      THeuristicPeer.Create('SafetySentinel', psSafety),
      THeuristicPeer.Create('PerformanceOptimizer', psPerformance),
      THeuristicPeer.Create('VerificationAuditor', psVerification),
      TStubPeer.Create('GeneralConsensusPeer', 0.85)
    ];
  end;

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
