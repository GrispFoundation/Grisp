unit unit_OpenAIProxy;

interface

uses
  System.SysUtils,
  System.JSON,
  System.DateUtils,
  System.Generics.Collections,
  IdTCPClient,
  IdException;

type
  TOpenAIProxy = class
  private
    mFirefoxPort: Integer;

    function SendFirefoxCommand(
      const ParaCommand: TJSONObject): TJSONObject;

    function ModelToSite(
      const ParaModel: string): string;

    function BuildFirefoxCommand(
      const ParaRequest: TJSONObject): TJSONObject;

    function BuildOpenAIResponse(
      const ParaFirefoxResponse: TJSONObject;
      const ParaModel: string): TJSONObject;

    function BuildErrorResponse(
      const ParaMessage: string;
      const ParaErrorType: string;
      const ParaCode: string): TJSONObject;

  public
    constructor Create(
      const ParaFirefoxPort: Integer);

    function ProcessChatCompletion(
      const ParaRequestJson: string;
      out ParaHttpStatus: Integer): string;
  end;

implementation

constructor TOpenAIProxy.Create(
  const ParaFirefoxPort: Integer);
begin
  inherited Create;

  mFirefoxPort := ParaFirefoxPort;
end;


function TOpenAIProxy.ModelToSite(
  const ParaModel: string): string;
var
  vModel: string;
begin
  vModel := LowerCase(ParaModel);

  if vModel.StartsWith('deepseek') then
    Result := 'deepseek'
  else if vModel.StartsWith('gpt-') or
          vModel.StartsWith('chatgpt') then
    Result := 'chatgpt'
  else if vModel.StartsWith('claude') then
    Result := 'claude'
  else if vModel.StartsWith('gemini') then
    Result := 'gemini'
  else if vModel.StartsWith('grok') then
    Result := 'grok'
  else if vModel.StartsWith('copilot') then
    Result := 'copilot'
  else if vModel.StartsWith('perplexity') then
    Result := 'perplexity'
  else if vModel.StartsWith('inception') then
    Result := 'inception'
  else
    Result := 'deepseek';
end;


function TOpenAIProxy.SendFirefoxCommand(
  const ParaCommand: TJSONObject): TJSONObject;
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
    vClient.ReadTimeout := 500000;

    try
      vClient.Connect;

      vClient.IOHandler.MaxLineLength := 0;

      vClient.IOHandler.WriteLn(
        ParaCommand.ToJSON
      );

      vResponse := vClient.IOHandler.ReadLn;

      if vResponse = '' then
        raise Exception.Create(
          'Firefox automation server returned an empty response'
        );

      vJsonValue := TJSONObject.ParseJSONValue(vResponse);

      if not Assigned(vJsonValue) then
        raise Exception.Create(
          'Firefox automation server returned invalid JSON'
        );

      if not (vJsonValue is TJSONObject) then
      begin
        vJsonValue.Free;
        raise Exception.Create(
          'Firefox automation server response is not a JSON object'
        );
      end;

      Result := TJSONObject(vJsonValue);

    except
      on E: EIdConnClosedGracefully do
        raise Exception.Create(
          'Firefox automation server closed the connection unexpectedly'
        );
    end;

  finally
    vClient.Free;
  end;
end;


function TOpenAIProxy.BuildFirefoxCommand(
  const ParaRequest: TJSONObject): TJSONObject;
var
  vMessages: TJSONArray;
  vMessage: TJSONObject;
  vIndex: Integer;
  vModel: string;
  vUserText: string;
  vRole: string;
begin
  Result := TJSONObject.Create;

  try
    vModel :=
      ParaRequest.GetValue<string>(
        'model',
        'deepseek-chat'
      );

    vMessages :=
      ParaRequest.GetValue<TJSONArray>(
        'messages',
        nil
      );

    if not Assigned(vMessages) then
      raise Exception.Create(
        'OpenAI request contains no messages array'
      );

    vUserText := '';

    for vIndex := vMessages.Count - 1 downto 0 do
    begin
      if not (
        vMessages.Items[vIndex] is TJSONObject
      ) then
        Continue;

      vMessage :=
        TJSONObject(
          vMessages.Items[vIndex]
        );

      vRole :=
        vMessage.GetValue<string>(
          'role',
          ''
        );

      if SameText(vRole, 'user') then
      begin
        vUserText :=
          vMessage.GetValue<string>(
            'content',
            ''
          );

        if vUserText <> '' then
          Break;
      end;
    end;

    if vUserText = '' then
      raise Exception.Create(
        'No non-empty user message found in request'
      );

    Result.AddPair(
      'command',
      'prompt'
    );

    Result.AddPair(
      'site',
      ModelToSite(vModel)
    );

    Result.AddPair(
      'text',
      vUserText
    );

    Result.AddPair(
      'tab',
      TJSONNumber.Create(-1)
    );

  except
    Result.Free;
    raise;
  end;
end;


function TOpenAIProxy.BuildErrorResponse(
  const ParaMessage: string;
  const ParaErrorType: string;
  const ParaCode: string): TJSONObject;
var
  vError: TJSONObject;
begin
  Result := TJSONObject.Create;

  try
    vError := TJSONObject.Create;

    vError.AddPair(
      'message',
      ParaMessage
    );

    vError.AddPair(
      'type',
      ParaErrorType
    );

    vError.AddPair(
      'code',
      ParaCode
    );

    Result.AddPair(
      'error',
      vError
    );

  except
    Result.Free;
    raise;
  end;
end;


function TOpenAIProxy.BuildOpenAIResponse(
  const ParaFirefoxResponse: TJSONObject;
  const ParaModel: string): TJSONObject;
var
  vText: string;
  vErrorMessage: string;
  vChoices: TJSONArray;
  vChoice: TJSONObject;
  vMessage: TJSONObject;
  vUsage: TJSONObject;
begin
  if ParaFirefoxResponse.TryGetValue<string>(
    'error',
    vErrorMessage
  ) then
  begin
    Result :=
      BuildErrorResponse(
        vErrorMessage,
        'firefox_automation_error',
        'firefox_error'
      );

    Exit;
  end;

  if not ParaFirefoxResponse.TryGetValue<string>(
    'text',
    vText
  ) then
    vText := '';

  Result := TJSONObject.Create;

  try
    Result.AddPair(
      'id',
      'chatcmpl-' + IntToStr(Random(MaxInt))
    );

    Result.AddPair(
      'object',
      'chat.completion'
    );

    Result.AddPair(
      'created',
      TJSONNumber.Create(
        DateTimeToUnix(Now)
      )
    );

    Result.AddPair(
      'model',
      ParaModel
    );

    vChoices := TJSONArray.Create;
    vChoice := TJSONObject.Create;

    vChoice.AddPair(
      'index',
      TJSONNumber.Create(0)
    );

    vMessage := TJSONObject.Create;

    vMessage.AddPair(
      'role',
      'assistant'
    );

    vMessage.AddPair(
      'content',
      vText
    );

    vChoice.AddPair(
      'message',
      vMessage
    );

    vChoice.AddPair(
      'finish_reason',
      'stop'
    );

    vChoices.AddElement(vChoice);

    Result.AddPair(
      'choices',
      vChoices
    );

    vUsage := TJSONObject.Create;

    vUsage.AddPair(
      'prompt_tokens',
      TJSONNumber.Create(0)
    );

    vUsage.AddPair(
      'completion_tokens',
      TJSONNumber.Create(
        Length(vText) div 4
      )
    );

    vUsage.AddPair(
      'total_tokens',
      TJSONNumber.Create(
        Length(vText) div 4
      )
    );

    Result.AddPair(
      'usage',
      vUsage
    );

  except
    Result.Free;
    raise;
  end;
end;


function TOpenAIProxy.ProcessChatCompletion(
  const ParaRequestJson: string;
  out ParaHttpStatus: Integer): string;
var
  vRequestValue: TJSONValue;
  vRequest: TJSONObject;
  vFirefoxCommand: TJSONObject;
  vFirefoxResponse: TJSONObject;
  vOpenAIResponse: TJSONObject;
  vModel: string;
begin
  ParaHttpStatus := 500;

  vRequestValue := nil;
  vRequest := nil;
  vFirefoxCommand := nil;
  vFirefoxResponse := nil;
  vOpenAIResponse := nil;

  try
    try
      vRequestValue :=
        TJSONObject.ParseJSONValue(
          ParaRequestJson
        );

      if not Assigned(vRequestValue) then
      begin
        vOpenAIResponse :=
          BuildErrorResponse(
            'Invalid JSON request body',
            'invalid_request_error',
            'invalid_json'
          );

        ParaHttpStatus := 400;

        Result :=
          vOpenAIResponse.ToJSON;

        Exit;
      end;

      if not (
        vRequestValue is TJSONObject
      ) then
      begin
        vOpenAIResponse :=
          BuildErrorResponse(
            'Request body must be a JSON object',
            'invalid_request_error',
            'invalid_request'
          );

        ParaHttpStatus := 400;

        Result :=
          vOpenAIResponse.ToJSON;

        Exit;
      end;

      vRequest :=
        TJSONObject(vRequestValue);

      vRequestValue := nil;

      vModel :=
        vRequest.GetValue<string>(
          'model',
          'deepseek-chat'
        );

      vFirefoxCommand :=
        BuildFirefoxCommand(
          vRequest
        );

      vFirefoxResponse :=
        SendFirefoxCommand(
          vFirefoxCommand
        );

      vOpenAIResponse :=
        BuildOpenAIResponse(
          vFirefoxResponse,
          vModel
        );

      if Assigned(
        vOpenAIResponse.GetValue('error')
      ) then
        ParaHttpStatus := 502
      else
        ParaHttpStatus := 200;

      Result :=
        vOpenAIResponse.ToJSON;

    except
      on E: Exception do
      begin
        FreeAndNil(vOpenAIResponse);

        vOpenAIResponse :=
          BuildErrorResponse(
            E.Message,
            'proxy_error',
            'internal_error'
          );

        ParaHttpStatus := 500;

        Result :=
          vOpenAIResponse.ToJSON;
      end;
    end;

  finally
    vOpenAIResponse.Free;
    vFirefoxResponse.Free;
    vFirefoxCommand.Free;
    vRequest.Free;
    vRequestValue.Free;
  end;
end;

end.
