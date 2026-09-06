unit unit_OpenAIProxy;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.DateUtils,
  System.SyncObjs,
  IdTCPClient,
  IdGlobal;

type
  TDebugLevel = (dlOff = 0, dlError = 1, dlInfo = 2, dlVerbose = 3);

  TDebugLogger = class
  private
    FLock: TCriticalSection;
    FEnabled: Boolean;
    FLevel: TDebugLevel;
    FLogFile: string;
    FWriter: TStreamWriter;
    procedure OpenLogFile;
    procedure CloseLogFile;
    function LevelToText(L: TDebugLevel): string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Configure(const AEnabled: Boolean; const ALevel: TDebugLevel; const ALogFile: string);
    procedure Log(const ALevel: TDebugLevel; const AMsg: string);
    property Enabled: Boolean read FEnabled;
    property Level: TDebugLevel read FLevel;
    property LogFile: string read FLogFile;
  end;

  TOpenAIProxy = class
  private
    mFirefoxPort: Integer;
    mLogger: TDebugLogger;
    mLastTabIndex: Integer;
    FOwnsLogger: Boolean;
    FShutdownRequested: Boolean;
    // internal helpers
    function SendFirefoxCommand(const ParaCommand: TJSONObject): TJSONObject;
    function ModelToSite(const ParaModel: string): string;
    function BuildFirefoxCommand(const ParaRequest: TJSONObject): TJSONObject;
    function BuildOpenAIResponse(const ParaFirefoxResponse: TJSONObject; const ParaModel: string): TJSONObject;
    function BuildErrorResponse(const ParaMessage, ParaErrorType, ParaCode: string): TJSONObject;
    function FindExistingTabIndex(const Site: string): Integer;
  public
    constructor Create(const ParaFirefoxPort: Integer; const ALogger: TDebugLogger = nil);
    destructor Destroy; override;

    procedure Shutdown; // graceful shutdown: stop threads, wait for completion

    function ProcessChatCompletion(const ParaRequestJson: string; out ParaHttpStatus: Integer): string;

    // runtime introspection only (no remote control)
    procedure SetDebugEnabled(const AEnabled: Boolean);
    procedure SetDebugLevel(const ALevel: Integer);
    procedure SetLogFile(const ALogFile: string);
    function GetDebugEnabled: Boolean;
    function GetDebugLevel: Integer;
    function GetLogFile: string;
  end;

implementation

{ TDebugLogger }

constructor TDebugLogger.Create;
begin
  inherited Create;
  // Create the lock first and keep it for the lifetime of the logger.
  FLock := TCriticalSection.Create;
  FEnabled := False;
  FLevel := dlOff;
  FLogFile := '';
  FWriter := nil;
end;

destructor TDebugLogger.Destroy;
begin
  // Ensure no background threads are using the logger before destroying it.
  // If you add a background thread to the logger, terminate and WaitFor it here.

  // Close file writer first, then free the lock.
  CloseLogFile;
  FreeAndNil(FLock);
  inherited Destroy;
end;

procedure TDebugLogger.OpenLogFile;
begin
  // Close any existing writer first
  CloseLogFile;
  if FLogFile = '' then
    Exit;
  try
    ForceDirectories(ExtractFilePath(FLogFile));
    // Create a TStreamWriter that appends to the file using UTF8 encoding.
    FWriter := TStreamWriter.Create(FLogFile, True, TEncoding.UTF8);
  except
    FreeAndNil(FWriter);
  end;
end;

procedure TDebugLogger.CloseLogFile;
begin
  FreeAndNil(FWriter);
end;

function TDebugLogger.LevelToText(L: TDebugLevel): string;
begin
  case L of
    dlError: Result := 'ERROR';
    dlInfo: Result := 'INFO';
    dlVerbose: Result := 'VERBOSE';
  else
    Result := 'OFF';
  end;
end;

procedure TDebugLogger.Configure(const AEnabled: Boolean; const ALevel: TDebugLevel; const ALogFile: string);
begin
  // Protect configuration with the lock to avoid races with Log calls.
  // If the lock is nil (during destruction), skip configuration.
  if Assigned(FLock) then
    FLock.Enter;
  try
    FEnabled := AEnabled;
    FLevel := ALevel;
    if ALogFile <> FLogFile then
    begin
      FLogFile := ALogFile;
      OpenLogFile;
    end;
  finally
    if Assigned(FLock) then
      FLock.Leave;
  end;
end;

procedure TDebugLogger.Log(const ALevel: TDebugLevel; const AMsg: string);
var
  s: string;
begin
  if not FEnabled then
    Exit;
  if Ord(ALevel) > Ord(FLevel) then
    Exit;

  s := Format('%s [%s] %s', [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now), LevelToText(ALevel), AMsg]);

  // Use the lock to serialize console/file writes.
  if Assigned(FLock) then
    FLock.Enter;
  try
    try
      Writeln(s);
    except
      // ignore console write errors
    end;
    if Assigned(FWriter) then
    begin
      try
        FWriter.WriteLine(s);
        FWriter.Flush;
      except
        // ignore file write errors
      end;
    end;
  finally
    if Assigned(FLock) then
      FLock.Leave;
  end;
end;

{ TOpenAIProxy }

constructor TOpenAIProxy.Create(const ParaFirefoxPort: Integer; const ALogger: TDebugLogger = nil);
begin
  inherited Create;
  mFirefoxPort := ParaFirefoxPort;
  FShutdownRequested := False;
  if Assigned(ALogger) then
  begin
    mLogger := ALogger;
    FOwnsLogger := False;
  end
  else
  begin
    mLogger := TDebugLogger.Create;
    mLogger.Configure(False, dlOff, '');
    FOwnsLogger := True;
  end;
  mLastTabIndex := -1;
end;

destructor TOpenAIProxy.Destroy;
begin
  // Ensure Shutdown was requested before freeing resources.
  // If Shutdown wasn't called, attempt a safe shutdown here.
  try
    Shutdown;
  except
    // ignore shutdown errors during destruction
  end;

  // Only free the logger if this instance created it.
  if FOwnsLogger then
    FreeAndNil(mLogger)
  else
    mLogger := nil;

  inherited Destroy;
end;

procedure TOpenAIProxy.Shutdown;
begin
  // Signal any internal workers to stop and wait for them to finish.
  // Currently this proxy does not spawn persistent worker threads,
  // but if you add them, implement Terminate + WaitFor here.
  if FShutdownRequested then
    Exit;
  FShutdownRequested := True;

  // Example:
  // if Assigned(FWorkerThread) then begin
  //   FWorkerThread.Terminate;
  //   FWorkerThread.WaitFor;
  //   FreeAndNil(FWorkerThread);
  // end;
end;

procedure TOpenAIProxy.SetDebugEnabled(const AEnabled: Boolean);
begin
  if Assigned(mLogger) then
    mLogger.Configure(AEnabled, mLogger.Level, mLogger.LogFile);
end;

procedure TOpenAIProxy.SetDebugLevel(const ALevel: Integer);
var
  L: TDebugLevel;
begin
  if ALevel <= 0 then L := dlOff
  else if ALevel = 1 then L := dlError
  else if ALevel = 2 then L := dlInfo
  else L := dlVerbose;
  if Assigned(mLogger) then
    mLogger.Configure(mLogger.Enabled, L, mLogger.LogFile);
end;

procedure TOpenAIProxy.SetLogFile(const ALogFile: string);
begin
  if Assigned(mLogger) then
    mLogger.Configure(mLogger.Enabled, mLogger.Level, ALogFile);
end;

function TOpenAIProxy.GetDebugEnabled: Boolean;
begin
  if Assigned(mLogger) then
    Result := mLogger.Enabled
  else
    Result := False;
end;

function TOpenAIProxy.GetDebugLevel: Integer;
begin
  if Assigned(mLogger) then
    Result := Ord(mLogger.Level)
  else
    Result := Ord(dlOff);
end;

function TOpenAIProxy.GetLogFile: string;
begin
  if Assigned(mLogger) then
    Result := mLogger.LogFile
  else
    Result := '';
end;

function TOpenAIProxy.ModelToSite(const ParaModel: string): string;
var
  vModel: string;
begin
  vModel := LowerCase(Trim(ParaModel));
  if vModel.StartsWith('deepseek') then
    Exit('deepseek');
  if vModel.StartsWith('gpt-') or vModel.StartsWith('chatgpt') then
    Exit('chatgpt');
  if vModel.StartsWith('claude') then
    Exit('claude');
  if vModel.StartsWith('gemini') then
    Exit('gemini');
  if vModel.StartsWith('grok') then
    Exit('grok');
  if vModel.StartsWith('copilot') then
    Exit('copilot');
  if vModel.StartsWith('perplexity') then
    Exit('perplexity');
  if vModel.StartsWith('inception') then
    Exit('inception');
  Result := 'deepseek';
end;

function TOpenAIProxy.SendFirefoxCommand(const ParaCommand: TJSONObject): TJSONObject;
var
  vClient: TIdTCPClient;
  vResponse: string;
  vJsonValue: TJSONValue;
begin
  Result := nil;
  vClient := TIdTCPClient.Create(nil);
  try
    vClient.Host := '127.0.0.1';
    vClient.Port := mFirefoxPort;
    vClient.ConnectTimeout := 5000;
    vClient.ReadTimeout := 300000;

    try
      vClient.Connect;
      vClient.IOHandler.MaxLineLength := 0;

      if Assigned(mLogger) then
        mLogger.Log(dlVerbose, '>>> Send to Firefox: ' + ParaCommand.ToJSON);

      vClient.IOHandler.WriteLn(ParaCommand.ToJSON);

      vResponse := vClient.IOHandler.ReadLn;
      if Assigned(mLogger) then
        mLogger.Log(dlVerbose, '<<< Reply from Firefox: ' + vResponse);

      if vResponse = '' then
        raise Exception.Create('Firefox automation server returned an empty response');

      vJsonValue := TJSONObject.ParseJSONValue(vResponse);
      if not Assigned(vJsonValue) then
        raise Exception.Create('Firefox automation server returned invalid JSON');

      if not (vJsonValue is TJSONObject) then
      begin
        vJsonValue.Free;
        raise Exception.Create('Firefox automation server response is not a JSON object');
      end;

      Result := TJSONObject(vJsonValue);

    except
      on E: Exception do
      begin
        if Assigned(mLogger) then
          mLogger.Log(dlError, 'SendFirefoxCommand exception: ' + E.ClassName + ' ' + E.Message);
        try
          vClient.Disconnect;
        except
          // ignore disconnect errors
        end;
        raise;
      end;
    end;
  finally
    vClient.Free;
  end;
end;

function TOpenAIProxy.FindExistingTabIndex(const Site: string): Integer;
var
  vClient: TIdTCPClient;
  vCmd, vResp: string;
  vJsonValue, vTabs: TJSONValue;
  vArr: TJSONArray;
  i: Integer;
  vTabObj: TJSONObject;
  vUrl, vTitle: string;
begin
  Result := -1;
  if Site = '' then
    Exit;

  vClient := TIdTCPClient.Create(nil);
  try
    vClient.Host := '127.0.0.1';
    vClient.Port := mFirefoxPort;
    vClient.ConnectTimeout := 2000;
    vClient.ReadTimeout := 5000;
    try
      vClient.Connect;
      vClient.IOHandler.MaxLineLength := 0;
      vCmd := '{"command":"getTabs"}';
      if Assigned(mLogger) then
        mLogger.Log(dlVerbose, 'FindExistingTabIndex: sending getTabs');
      vClient.IOHandler.WriteLn(vCmd);
      vResp := vClient.IOHandler.ReadLn;
      if Assigned(mLogger) then
        mLogger.Log(dlVerbose, 'FindExistingTabIndex: reply ' + vResp);
      if vResp = '' then
        Exit;
      vJsonValue := TJSONObject.ParseJSONValue(vResp);
      if not Assigned(vJsonValue) then
        Exit;
      try
        vTabs := (vJsonValue as TJSONObject).GetValue('tabs');
        if not Assigned(vTabs) then
          Exit;
        if not (vTabs is TJSONArray) then
          Exit;
        vArr := TJSONArray(vTabs);
        for i := 0 to vArr.Count - 1 do
        begin
          if not (vArr.Items[i] is TJSONObject) then
            Continue;
          vTabObj := TJSONObject(vArr.Items[i]);
          vUrl := vTabObj.GetValue<string>('url', '');
          vTitle := vTabObj.GetValue<string>('title', '');
          if (vUrl <> '') and (Pos(LowerCase(Site), LowerCase(vUrl)) > 0) then
          begin
            Result := vTabObj.GetValue<Integer>('index', -1);
            Exit;
          end;
          if (vTitle <> '') and (Pos(LowerCase(Site), LowerCase(vTitle)) > 0) then
          begin
            Result := vTabObj.GetValue<Integer>('index', -1);
            Exit;
          end;
        end;
      finally
        vJsonValue.Free;
      end;
    except
      on E: Exception do
      begin
        if Assigned(mLogger) then
          mLogger.Log(dlError, 'FindExistingTabIndex exception: ' + E.Message);
      end;
    end;
  finally
    vClient.Free;
  end;
end;

function TOpenAIProxy.BuildFirefoxCommand(const ParaRequest: TJSONObject): TJSONObject;
var
  vMessages: TJSONArray;
  vMessage: TJSONObject;
  vIndex: Integer;
  vModel, vUserText, vRole, vSite: string;
  vTabIndex: Integer;
begin
  Result := TJSONObject.Create;
  try
    vModel := ParaRequest.GetValue<string>('model', 'deepseek-chat');

    vMessages := ParaRequest.GetValue<TJSONArray>('messages', nil);
    if not Assigned(vMessages) then
      raise Exception.Create('OpenAI request contains no messages array');

    vUserText := '';
    for vIndex := vMessages.Count - 1 downto 0 do
    begin
      if not (vMessages.Items[vIndex] is TJSONObject) then
        Continue;
      vMessage := TJSONObject(vMessages.Items[vIndex]);
      vRole := vMessage.GetValue<string>('role', '');
      if SameText(vRole, 'user') then
      begin
        vUserText := vMessage.GetValue<string>('content', '');
        if vUserText <> '' then
          Break;
      end;
    end;

    if vUserText = '' then
      raise Exception.Create('No non-empty user message found in request');

    Result.AddPair('command', 'prompt');

    vSite := ModelToSite(vModel);
    Result.AddPair('site', vSite);
    Result.AddPair('text', vUserText);

    // Tab selection: reuse cached index if valid, otherwise try to find one
    vTabIndex := -1;
    if mLastTabIndex >= 0 then
    begin
      vTabIndex := mLastTabIndex;
      if Assigned(mLogger) then
        mLogger.Log(dlVerbose, 'Using cached tab index: ' + IntToStr(vTabIndex));
    end
    else
    begin
      vTabIndex := FindExistingTabIndex(vSite);
      if vTabIndex >= 0 then
      begin
        mLastTabIndex := vTabIndex;
        if Assigned(mLogger) then
          mLogger.Log(dlInfo, 'Found existing tab for ' + vSite + ' index=' + IntToStr(vTabIndex));
      end
      else if Assigned(mLogger) then
        mLogger.Log(dlVerbose, 'No existing tab found for ' + vSite + ', will use -1');
    end;

    Result.AddPair('tab', TJSONNumber.Create(vTabIndex));

    if Assigned(mLogger) then
      mLogger.Log(dlInfo, 'Built Firefox command: ' + Result.ToJSON);

  except
    Result.Free;
    raise;
  end;
end;

function TOpenAIProxy.BuildErrorResponse(const ParaMessage, ParaErrorType, ParaCode: string): TJSONObject;
var
  vError: TJSONObject;
begin
  Result := TJSONObject.Create;
  vError := TJSONObject.Create;
  vError.AddPair('message', ParaMessage);
  vError.AddPair('type', ParaErrorType);
  vError.AddPair('code', ParaCode);
  Result.AddPair('error', vError);
end;

function TOpenAIProxy.BuildOpenAIResponse(const ParaFirefoxResponse: TJSONObject; const ParaModel: string): TJSONObject;
var
  vText: string;
  vErrorMessage: string;
  vChoices: TJSONArray;
  vChoice, vMessage, vUsage: TJSONObject;
begin
  if Assigned(ParaFirefoxResponse) and ParaFirefoxResponse.TryGetValue<string>('error', vErrorMessage) then
  begin
    Result := BuildErrorResponse(vErrorMessage, 'firefox_automation_error', 'firefox_error');
    Exit;
  end;

  if Assigned(ParaFirefoxResponse) and ParaFirefoxResponse.TryGetValue<string>('text', vText) then
    vText := vText
  else
    vText := '';

  Result := TJSONObject.Create;
  try
    Result.AddPair('id', 'chatcmpl-' + IntToStr(Random(MaxInt)));
    Result.AddPair('object', 'chat.completion');
    Result.AddPair('created', TJSONNumber.Create(DateTimeToUnix(Now)));
    Result.AddPair('model', ParaModel);

    vChoices := TJSONArray.Create;
    vChoice := TJSONObject.Create;
    vChoice.AddPair('index', TJSONNumber.Create(0));

    vMessage := TJSONObject.Create;
    vMessage.AddPair('role', 'assistant');
    vMessage.AddPair('content', vText);

    vChoice.AddPair('message', vMessage);
    vChoice.AddPair('finish_reason', 'stop');
    vChoices.AddElement(vChoice);
    Result.AddPair('choices', vChoices);

    vUsage := TJSONObject.Create;
    vUsage.AddPair('prompt_tokens', TJSONNumber.Create(0));
    vUsage.AddPair('completion_tokens', TJSONNumber.Create(Length(vText) div 4));
    vUsage.AddPair('total_tokens', TJSONNumber.Create(Length(vText) div 4));
    Result.AddPair('usage', vUsage);
  except
    Result.Free;
    raise;
  end;
end;

function TOpenAIProxy.ProcessChatCompletion(const ParaRequestJson: string; out ParaHttpStatus: Integer): string;
var
  vRequestValue: TJSONValue;
  vRequest: TJSONObject;
  vFirefoxCommand, vFirefoxResponse, vOpenAIResponse: TJSONObject;
  vModel: string;
begin
  ParaHttpStatus := 500;
  vRequestValue := nil;
  vRequest := nil;
  vFirefoxCommand := nil;
  vFirefoxResponse := nil;
  vOpenAIResponse := nil;

  try
    vRequestValue := TJSONObject.ParseJSONValue(ParaRequestJson);
    if not Assigned(vRequestValue) then
    begin
      vOpenAIResponse := BuildErrorResponse('Invalid JSON request body', 'invalid_request_error', 'invalid_json');
      ParaHttpStatus := 400;
      Result := vOpenAIResponse.ToJSON;
      if Assigned(mLogger) then
        mLogger.Log(dlError, 'Invalid JSON request body');
      Exit;
    end;

    if not (vRequestValue is TJSONObject) then
    begin
      vOpenAIResponse := BuildErrorResponse('Request body must be a JSON object', 'invalid_request_error', 'invalid_request');
      ParaHttpStatus := 400;
      Result := vOpenAIResponse.ToJSON;
      if Assigned(mLogger) then
        mLogger.Log(dlError, 'Request body not a JSON object');
      Exit;
    end;

    vRequest := TJSONObject(vRequestValue);
    vRequestValue := nil;

    if Assigned(mLogger) then
      mLogger.Log(dlInfo, 'Incoming OpenAI request: ' + vRequest.ToJSON);

    vModel := vRequest.GetValue<string>('model', 'deepseek-chat');

    vFirefoxCommand := BuildFirefoxCommand(vRequest);

    try
      vFirefoxResponse := SendFirefoxCommand(vFirefoxCommand);
    except
      on E: Exception do
      begin
        vOpenAIResponse := BuildErrorResponse(E.Message, 'firefox_comm_error', 'firefox_comm');
        ParaHttpStatus := 502;
        Result := vOpenAIResponse.ToJSON;
        if Assigned(mLogger) then
          mLogger.Log(dlError, 'Error sending to Firefox: ' + E.Message);
        Exit;
      end;
    end;

    vOpenAIResponse := BuildOpenAIResponse(vFirefoxResponse, vModel);

    if Assigned(vOpenAIResponse.GetValue('error')) then
      ParaHttpStatus := 502
    else
      ParaHttpStatus := 200;

    Result := vOpenAIResponse.ToJSON;

    if Assigned(mLogger) then
      mLogger.Log(dlInfo, 'Returning OpenAI response: ' + Result);

  finally
    vOpenAIResponse.Free;
    vFirefoxResponse.Free;
    vFirefoxCommand.Free;
    vRequest.Free;
    vRequestValue.Free;
  end;
end;

end.

