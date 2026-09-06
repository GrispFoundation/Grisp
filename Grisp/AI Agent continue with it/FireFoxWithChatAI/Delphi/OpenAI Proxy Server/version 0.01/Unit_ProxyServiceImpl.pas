unit Unit_ProxyServiceImpl;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.DateUtils,
  System.Generics.Collections,
  IdTCPClient,
  IdGlobal,
  IdException,
  Unit_ProxyService;

type
  TOpenAIProxy = class(TInterfacedObject, IOpenAIProxy)
  private
    FFirefoxPort: Integer;
    function SendCommand(const Cmd: TJSONObject): TJSONObject;
    function ModelToSite(const Model: string): string;
    function BuildInternalCommand(const Request: TJSONObject): TJSONObject;
    function BuildOpenAIResponse(const InternalResponse: TJSONObject; const Model: string): TJSONObject;
  public
    constructor Create(APort: Integer);
    // *** This must match the interface exactly ***
    procedure ChatCompletion(const Request: TJSONObject; out Response: TJSONObject);
  end;

implementation

constructor TOpenAIProxy.Create(APort: Integer);
begin
  inherited Create;
  FFirefoxPort := APort;
end;

function TOpenAIProxy.SendCommand(const Cmd: TJSONObject): TJSONObject;
var
  Client: TIdTCPClient;
  Response: string;
begin
  Result := nil;
  Client := TIdTCPClient.Create(nil);
  try
    Client.Host := 'localhost';
    Client.Port := FFirefoxPort;
    Client.ConnectTimeout := 5000;
    Client.ReadTimeout := 120000;
    try
      Client.Connect;
      Client.IOHandler.MaxLineLength := 0;
      Client.IOHandler.WriteLn(Cmd.ToJSON);
      Response := Client.IOHandler.ReadLn;
      if Response <> '' then
        Result := TJSONObject.ParseJSONValue(Response) as TJSONObject;
      if Result = nil then
        raise Exception.Create('Invalid JSON response from Firefox server');
    except
      on E: EIdConnClosedGracefully do
        raise Exception.Create('Firefox connection closed unexpectedly');
      on E: Exception do
        raise;
    end;
  finally
    Client.Free;
  end;
end;

function TOpenAIProxy.ModelToSite(const Model: string): string;
begin
  if Model.StartsWith('deepseek') then
    Result := 'deepseek'
  else if Model.StartsWith('gpt-') or Model.StartsWith('chatgpt') then
    Result := 'chatgpt'
  else if Model.StartsWith('claude') then
    Result := 'claude'
  else if Model.StartsWith('gemini') then
    Result := 'gemini'
  else if Model.StartsWith('grok') then
    Result := 'grok'
  else if Model.StartsWith('copilot') then
    Result := 'copilot'
  else
    Result := 'deepseek';
end;

function TOpenAIProxy.BuildInternalCommand(const Request: TJSONObject): TJSONObject;
var
  Messages: TJSONArray;
  MsgObj: TJSONObject;
  i: Integer;
  LastUserContent: string;
  Model: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('command', 'prompt');

  Model := Request.GetValue<string>('model', 'deepseek-chat');
  Result.AddPair('site', ModelToSite(Model));

  Messages := Request.GetValue<TJSONArray>('messages', nil);
  if Assigned(Messages) then
  begin
    for i := Messages.Count - 1 downto 0 do
    begin
      MsgObj := Messages.Items[i] as TJSONObject;
      if MsgObj.GetValue<string>('role', '') = 'user' then
      begin
        LastUserContent := MsgObj.GetValue<string>('content', '');
        Break;
      end;
    end;
  end;

  if LastUserContent = '' then
    raise Exception.Create('No user message found in request');

  Result.AddPair('text', LastUserContent);
  Result.AddPair('tab', TJSONNumber.Create(-1));
end;

function TOpenAIProxy.BuildOpenAIResponse(const InternalResponse: TJSONObject; const Model: string): TJSONObject;
var
  Text: string;
  ErrorMsg: string;
  Choice, MessageObj, Usage: TJSONObject;
  Choices: TJSONArray;
begin
  Result := TJSONObject.Create;
  try
    if InternalResponse.TryGetValue<string>('error', ErrorMsg) then
    begin
      Result.AddPair('error', ErrorMsg);
      Exit;
    end;

    if not InternalResponse.TryGetValue<string>('text', Text) then
      Text := 'No response received.';

    Result.AddPair('id', 'chatcmpl-' + IntToStr(Random(MaxInt)));
    Result.AddPair('object', 'chat.completion');
    Result.AddPair('created', TJSONNumber.Create(DateTimeToUnix(Now)));
    Result.AddPair('model', Model);

    Choices := TJSONArray.Create;
    Choice := TJSONObject.Create;
    Choice.AddPair('index', TJSONNumber.Create(0));

    MessageObj := TJSONObject.Create;
    MessageObj.AddPair('role', 'assistant');
    MessageObj.AddPair('content', Text);
    Choice.AddPair('message', MessageObj);
    Choice.AddPair('finish_reason', 'stop');

    Choices.Add(Choice);
    Result.AddPair('choices', Choices);

    Usage := TJSONObject.Create;
    Usage.AddPair('prompt_tokens', TJSONNumber.Create(0));
    Usage.AddPair('completion_tokens', TJSONNumber.Create(Length(Text) div 4));
    Usage.AddPair('total_tokens', TJSONNumber.Create(0));
    Result.AddPair('usage', Usage);
  except
    Result.Free;
    raise;
  end;
end;

// *** Implementation of the interface method – MUST match exactly ***
procedure TOpenAIProxy.ChatCompletion(const Request: TJSONObject; out Response: TJSONObject);
var
  InternalCmd, InternalResp: TJSONObject;
  Model: string;
begin
  Response := nil;
  InternalCmd := nil;
  InternalResp := nil;
  try
    InternalCmd := BuildInternalCommand(Request);
    InternalResp := SendCommand(InternalCmd);
    Model := Request.GetValue<string>('model', 'deepseek-chat');
    Response := BuildOpenAIResponse(InternalResp, Model);
  finally
    InternalCmd.Free;
    InternalResp.Free;
  end;
end;

end.
