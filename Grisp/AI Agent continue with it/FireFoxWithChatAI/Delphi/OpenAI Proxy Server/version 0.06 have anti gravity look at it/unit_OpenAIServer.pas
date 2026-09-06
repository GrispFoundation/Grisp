unit unit_OpenAIServer;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  Unit_OpenAIProxy,
  mormot.core.base,
  mormot.core.text,
  mormot.rest.core,
  mormot.rest.memserver,
  mormot.rest.server,
  mormot.net.http;

type
  TOpenAIRestServer = class(TRestServerFullMemory)
  private
    mProxy: TOpenAIProxy;
    mLogger: TDebugLogger;
    procedure ReturnJson(Ctxt: TRestServerUriContext; const ParaJson: string; const ParaHttpStatus: Integer);
  public
    constructor Create(const ParaFirefoxPort: Integer; const AEnableDebug: Boolean = False; const ADebugLevel: Integer = 0; const ALogFile: string = '');
    destructor Destroy; override;
  published
    procedure V1ChatCompletions(Ctxt: TRestServerUriContext);
    procedure V1Models(Ctxt: TRestServerUriContext);
    // Read-only debug status
    procedure V1Debug(Ctxt: TRestServerUriContext);
  end;

implementation

{ TOpenAIRestServer }

constructor TOpenAIRestServer.Create(const ParaFirefoxPort: Integer; const AEnableDebug: Boolean = False; const ADebugLevel: Integer = 0; const ALogFile: string = '');
var
  vLogger: TDebugLogger;
  vLevel: TDebugLevel;
begin
  inherited CreateWithOwnModel([], False, 'api');

  // Create logger and configure it. Server will keep ownership of the logger
  vLogger := TDebugLogger.Create;
  if ADebugLevel <= 0 then vLevel := dlOff
  else if ADebugLevel = 1 then vLevel := dlError
  else if ADebugLevel = 2 then vLevel := dlInfo
  else vLevel := dlVerbose;
  vLogger.Configure(AEnableDebug, vLevel, ALogFile);

  mLogger := vLogger;

  // Pass the logger to the proxy; proxy will not free it because it did not create it.
  mProxy := TOpenAIProxy.Create(ParaFirefoxPort, mLogger);
end;

destructor TOpenAIRestServer.Destroy;
begin
  // 1) Stop accepting new requests if TRestServerFullMemory/TRestHttpServer exposes a stop method.
  //    If you have a reference to the TRestHttpServer instance, call its Stop method before freeing.
  //    Here we ensure the proxy is shutdown first.

  try
    if Assigned(mProxy) then
    begin
      try
        mProxy.Shutdown; // ensure proxy stops any internal workers
      except
        // ignore shutdown errors
      end;
    end;
  except
    // ignore
  end;

  // 2) Free proxy first. If proxy owns the logger it will free it; otherwise logger remains assigned.
  FreeAndNil(mProxy);

  // 3) Free logger if still assigned (server owns it)
  FreeAndNil(mLogger);

  inherited Destroy;
end;

procedure TOpenAIRestServer.ReturnJson(Ctxt: TRestServerUriContext; const ParaJson: string; const ParaHttpStatus: Integer);
var
  vJson: RawUtf8;
  constJsonType: RawUtf8;
begin
  constJsonType := 'Content-Type: application/json; charset=utf-8';
  vJson := RawUtf8(ParaJson);
  if Assigned(mLogger) then
    mLogger.Log(dlVerbose, Format('HTTP Response status=%d body=%s', [ParaHttpStatus, ParaJson]));
  Ctxt.Returns(vJson, ParaHttpStatus, constJsonType);
end;

procedure TOpenAIRestServer.V1ChatCompletions(Ctxt: TRestServerUriContext);
var
  vRequestJson: string;
  vResponseJson: string;
  vHttpStatus: Integer;
begin
  if Ctxt.Method <> mPOST then
  begin
    ReturnJson(Ctxt,
      '{"error":{"message":"Method not allowed","type":"invalid_request_error","code":"method_not_allowed"}}',
      405);
    Exit;
  end;

  vRequestJson := UTF8ToString(Ctxt.Call.InBody);
  if Assigned(mLogger) then
    mLogger.Log(dlInfo, 'HTTP POST /api/V1ChatCompletions body: ' + vRequestJson);

  if vRequestJson = '' then
  begin
    ReturnJson(Ctxt,
      '{"error":{"message":"Request body is empty","type":"invalid_request_error","code":"empty_request"}}',
      400);
    Exit;
  end;

  // Ensure proxy is available
  if not Assigned(mProxy) then
  begin
    ReturnJson(Ctxt,
      '{"error":{"message":"Server not initialized","type":"server_error","code":"server_not_ready"}}',
      500);
    Exit;
  end;

  vResponseJson := mProxy.ProcessChatCompletion(vRequestJson, vHttpStatus);
  ReturnJson(Ctxt, vResponseJson, vHttpStatus);
end;

procedure TOpenAIRestServer.V1Models(Ctxt: TRestServerUriContext);
const
  EnginesJson =
    '{"object":"list","data":[' +
    '{"id":"deepseek-chat","site":"deepseek","name":"DeepSeek Chat","url":"https://chat.deepseek.com/"},' +
    '{"id":"chatgpt","site":"chatgpt","name":"ChatGPT","url":"https://chatgpt.com/"},' +
    '{"id":"gemini","site":"gemini","name":"Google Gemini","url":"https://gemini.google.com/app"},' +
    '{"id":"copilot","site":"copilot","name":"Microsoft Copilot","url":"https://copilot.microsoft.com/"},' +
    '{"id":"grok","site":"grok","name":"Grok","url":"https://grok.com/"}' +
    ']}';
begin
  if Ctxt.Method <> mGET then
  begin
    ReturnJson(Ctxt,
      '{"error":{"message":"Method not allowed","type":"invalid_request_error","code":"method_not_allowed"}}',
      405);
    Exit;
  end;
  if Assigned(mLogger) then
    mLogger.Log(dlInfo, 'HTTP GET /api/V1Models');
  ReturnJson(Ctxt, EnginesJson, 200);
end;

procedure TOpenAIRestServer.V1Debug(Ctxt: TRestServerUriContext);
var
  vResp: TJSONObject;
  vEnabled: Boolean;
  vLevel: Integer;
  vLogFile: string;
begin
  // Read-only debug status endpoint. No POST allowed.
  if Ctxt.Method <> mGET then
  begin
    ReturnJson(Ctxt, '{"error":"Method not allowed"}', 405);
    Exit;
  end;

  if Assigned(mProxy) then
  begin
    vEnabled := mProxy.GetDebugEnabled;
    vLevel := mProxy.GetDebugLevel;
    vLogFile := mProxy.GetLogFile;
  end
  else
  begin
    vEnabled := False;
    vLevel := 0;
    vLogFile := '';
  end;

  vResp := TJSONObject.Create;
  try
    vResp.AddPair('enabled', TJSONBool.Create(vEnabled));
    vResp.AddPair('level', TJSONNumber.Create(vLevel));
    vResp.AddPair('logfile', vLogFile);
    ReturnJson(Ctxt, vResp.ToJSON, 200);
  finally
    vResp.Free;
  end;
end;


end.

