unit unit_OpenAIServer;

interface

uses
  System.SysUtils,
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
    procedure ReturnJson(Ctxt: TRestServerUriContext; const ParaJson: string; const ParaHttpStatus: Integer);
  public
    constructor Create(const ParaFirefoxPort: Integer);
    destructor Destroy; override;
  published
    procedure V1ChatCompletions(Ctxt: TRestServerUriContext);
    procedure V1Models(Ctxt: TRestServerUriContext);
  end;

implementation

{ TOpenAIRestServer }

constructor TOpenAIRestServer.Create(const ParaFirefoxPort: Integer);
begin
  // Disable mORMot URI authentication for local testing (False).
  inherited CreateWithOwnModel([], False, 'api');
  mProxy := TOpenAIProxy.Create(ParaFirefoxPort);
end;

destructor TOpenAIRestServer.Destroy;
begin
  mProxy.Free;
  inherited Destroy;
end;

procedure TOpenAIRestServer.ReturnJson(Ctxt: TRestServerUriContext; const ParaJson: string; const ParaHttpStatus: Integer);
var
  vJson: RawUtf8;
  constJsonType: RawUtf8;
begin
  // mORMot2 builds differ: pass a full header line to be safe on all versions
  constJsonType := 'Content-Type: application/json; charset=utf-8';
  vJson := RawUtf8(ParaJson);
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
  if vRequestJson = '' then
  begin
    ReturnJson(Ctxt,
      '{"error":{"message":"Request body is empty","type":"invalid_request_error","code":"empty_request"}}',
      400);
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
  ReturnJson(Ctxt, EnginesJson, 200);
end;

end.

