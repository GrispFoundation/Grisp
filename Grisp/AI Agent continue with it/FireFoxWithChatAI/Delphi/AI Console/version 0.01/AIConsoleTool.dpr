program AIConsoleTool;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  IdTCPClient,
  IdGlobal,
  IdException,         // for EIdConnClosedGracefully
  Windows;             // for SetConsoleOutputCP and CP_UTF8

const
  DEFAULT_PORT = 9999;
  CP_UTF8 = 65001;

type
  TActionType = (atNone, atListTabs, atOpenUrl, atDuplicate, atClose, atPrompt);

  TOptions = record
    Port: Integer;
    Action: TActionType;
    PromptText: string;
    Site: string;
    Tab: string;
    OpenUrl: string;
    Duplicate: Boolean;
    Close: Boolean;
    ListTabs: Boolean;
  end;

function SendCommand(const Cmd: TJSONObject; Port: Integer): TJSONObject;
var
  Client: TIdTCPClient;
  Response: string;
begin
  Result := nil;
  Client := TIdTCPClient.Create(nil);
  try
    Client.Host := 'localhost';
    Client.Port := Port;
    Client.ConnectTimeout := 5000;
    Client.ReadTimeout := 500000;
    try
      Client.Connect;
      // FIX: Remove the maximum line length limit to handle very long AI responses
      Client.IOHandler.MaxLineLength := 0;
      Client.IOHandler.WriteLn(Cmd.ToJSON);
      Response := Client.IOHandler.ReadLn;
      if Response <> '' then
        Result := TJSONObject.ParseJSONValue(Response) as TJSONObject;
      if Result = nil then
        raise Exception.Create('Invalid JSON response from server');
    except
      on E: Exception do
      begin
        // Re-raise with a user-friendly message
        if E is EIdConnClosedGracefully then
          raise Exception.Create('Connection closed by server')
        else
          raise;
      end;
    end;
  finally
    Client.Free;
  end;
end;

procedure PrintHelp;
begin
  Writeln('AI Automation Console Tool');
  Writeln;
  Writeln('Usage:');
  Writeln('  --port <port>         Port Firefox is listening on (default 9999)');
  Writeln;
  Writeln('Actions:');
  Writeln('  --prompt <text>       The chat prompt to send');
  Writeln('  --list-tabs           List all open tabs');
  Writeln('  --open-url <url>      Open a URL in a new tab');
  Writeln('  --duplicate           Duplicate tab specified by --tab');
  Writeln('  --close               Close tab specified by --tab');
  Writeln;
  Writeln('Parameters:');
  Writeln('  --site <site>         The AI website/model to use (required for --prompt if --tab is not used)');
  Writeln('  --tab <index/title/url> Index, Title, or URL of the tab to re-use or manage');
end;

function ParseCommandLine: TOptions;
var
  i: Integer;
  Arg: string;
begin
  Result.Port := DEFAULT_PORT;
  Result.Action := atNone;
  Result.PromptText := '';
  Result.Site := '';
  Result.Tab := '';
  Result.OpenUrl := '';
  Result.Duplicate := False;
  Result.Close := False;
  Result.ListTabs := False;

  i := 1;
  while i <= ParamCount do
  begin
    Arg := ParamStr(i);
    if Arg = '--port' then
    begin
      Inc(i);
      if i <= ParamCount then
        Result.Port := StrToIntDef(ParamStr(i), DEFAULT_PORT)
      else
        raise Exception.Create('--port requires a value');
    end
    else if Arg = '--list-tabs' then
    begin
      Result.ListTabs := True;
      Result.Action := atListTabs;
    end
    else if Arg = '--open-url' then
    begin
      Inc(i);
      if i <= ParamCount then
      begin
        Result.OpenUrl := ParamStr(i);
        Result.Action := atOpenUrl;
      end
      else
        raise Exception.Create('--open-url requires a URL');
    end
    else if Arg = '--duplicate' then
    begin
      Result.Duplicate := True;
      Result.Action := atDuplicate;
    end
    else if Arg = '--close' then
    begin
      Result.Close := True;
      Result.Action := atClose;
    end
    else if Arg = '--prompt' then
    begin
      Inc(i);
      if i <= ParamCount then
      begin
        Result.PromptText := ParamStr(i);
        Result.Action := atPrompt;
      end
      else
        raise Exception.Create('--prompt requires text');
    end
    else if Arg = '--site' then
    begin
      Inc(i);
      if i <= ParamCount then
        Result.Site := ParamStr(i)
      else
        raise Exception.Create('--site requires a value');
    end
    else if Arg = '--tab' then
    begin
      Inc(i);
      if i <= ParamCount then
        Result.Tab := ParamStr(i)
      else
        raise Exception.Create('--tab requires a value');
    end
    else
      raise Exception.Create('Unknown argument: ' + Arg);
    Inc(i);
  end;

  // Validate combinations
  if Result.Action = atDuplicate then
  begin
    if Result.Tab = '' then
      raise Exception.Create('Error: --tab is required for --duplicate');
  end
  else if Result.Action = atClose then
  begin
    if Result.Tab = '' then
      raise Exception.Create('Error: --tab is required for --close');
  end
  else if Result.Action = atPrompt then
  begin
    if (Result.Site = '') and (Result.Tab = '') then
      raise Exception.Create('Error: --site or --tab is required for --prompt');
  end;
end;

procedure PrintTabs(const Response: TJSONObject);
var
  Tabs: TJSONArray;
  TabObj: TJSONObject;
  i: Integer;
  Index: Integer;
  IsSelected: Boolean;
  SelectedStr: string;
  Title: string;
  Url: string;
begin
  if not Response.TryGetValue<TJSONArray>('tabs', Tabs) then
  begin
    Writeln('No tabs array in response');
    Exit;
  end;

  Writeln(Format('%-6s %-10s %-40s %s', ['Index', 'Selected', 'Title', 'URL']));
  Writeln(StringOfChar('-', 100));

  for i := 0 to Tabs.Count - 1 do
  begin
    TabObj := Tabs.Items[i] as TJSONObject;
    Index := TabObj.GetValue<Integer>('index', -1);
    IsSelected := TabObj.GetValue<Boolean>('selected', False);
    if IsSelected then
      SelectedStr := '*'
    else
      SelectedStr := '';
    Title := TabObj.GetValue<string>('title', '');
    Url := TabObj.GetValue<string>('url', '');

    // Truncate title to 38 characters
    if Length(Title) > 38 then
      Title := Copy(Title, 1, 38);

    Writeln(Format('%-6d %-10s %-40s %s', [Index, SelectedStr, Title, Url]));
  end;
end;

procedure ProcessOptions(const Options: TOptions);
var
  Cmd: TJSONObject;
  Resp: TJSONObject;
  ErrorMsg: string;
  LastSeen: string;
begin
  Cmd := nil;
  Resp := nil;
  try
    case Options.Action of
      atListTabs:
        begin
          Cmd := TJSONObject.Create;
          Cmd.AddPair('command', 'getTabs');
          Resp := SendCommand(Cmd, Options.Port);
          PrintTabs(Resp);
        end;

      atOpenUrl:
        begin
          Cmd := TJSONObject.Create;
          Cmd.AddPair('command', 'openTab');
          Cmd.AddPair('url', Options.OpenUrl);
          Resp := SendCommand(Cmd, Options.Port);
          Writeln(Resp.ToJSON);
        end;

      atDuplicate:
        begin
          Cmd := TJSONObject.Create;
          Cmd.AddPair('command', 'duplicateTab');
          Cmd.AddPair('tab', Options.Tab);
          Resp := SendCommand(Cmd, Options.Port);
          Writeln(Resp.ToJSON);
        end;

      atClose:
        begin
          Cmd := TJSONObject.Create;
          Cmd.AddPair('command', 'closeTab');
          Cmd.AddPair('tab', Options.Tab);
          Resp := SendCommand(Cmd, Options.Port);
          Writeln(Resp.ToJSON);
        end;

      atPrompt:
        begin
          Cmd := TJSONObject.Create;
          Cmd.AddPair('command', 'prompt');
          if Options.Site <> '' then
            Cmd.AddPair('site', Options.Site);
          Cmd.AddPair('text', Options.PromptText);
          if Options.Tab <> '' then
            Cmd.AddPair('tab', Options.Tab)
          else
            Cmd.AddPair('tab', TJSONNumber.Create(-1));

          Resp := SendCommand(Cmd, Options.Port);

          if Resp.TryGetValue<string>('error', ErrorMsg) then
          begin
            Writeln('Error: ' + ErrorMsg);
            if Resp.TryGetValue<string>('lastSeen', LastSeen) then
              Writeln('Last seen text: ' + LastSeen);
          end
          else
          begin
            if not Resp.TryGetValue<string>('text', LastSeen) then
              LastSeen := 'No response text received.';
            Writeln(LastSeen);
          end;
        end;

      else
        PrintHelp;
    end;
  finally
    Cmd.Free;
    Resp.Free;
  end;
end;

begin
  try
    // Set console output to UTF-8 for proper Unicode display
    SetConsoleOutputCP(CP_UTF8);

    if ParamCount = 0 then
    begin
      PrintHelp;
      Exit;
    end;

    var Options := ParseCommandLine;
    ProcessOptions(Options);
  except
    on E: Exception do
    begin
      Writeln('Error: ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
