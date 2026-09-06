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
  // CreateWithOwnModel(Model, HandleAuthentication, Root)
//  inherited CreateWithOwnModel([], True, 'api');
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
  // Use explicit JSON content type to avoid missing constant across mORMot2 versions
  constJsonType := 'application/json; charset=utf-8';
  vJson := RawUtf8(ParaJson);
  // TRestServerUriContext.Returns(const aContent: RawUtf8; aStatus: integer; const aContentType: RawUtf8);
  Ctxt.Returns(vJson, ParaHttpStatus, constJsonType);
end;

procedure TOpenAIRestServer.V1ChatCompletions(Ctxt: TRestServerUriContext);
var
  vRequestJson: string;
  vResponseJson: string;
  vHttpStatus: Integer;
begin
  // mPOST constant is provided by mormot.net.http
  if Ctxt.Method <> mPOST then
  begin
    ReturnJson(Ctxt,
      '{"error":{"message":"Method not allowed","type":"invalid_request_error","code":"method_not_allowed"}}',
      405); // HTTP 405 Method Not Allowed
    Exit;
  end;

  // Call.InBody is RawUtf8; convert to string
  vRequestJson := UTF8ToString(Ctxt.Call.InBody);
  if vRequestJson = '' then
  begin
    ReturnJson(Ctxt,
      '{"error":{"message":"Request body is empty","type":"invalid_request_error","code":"empty_request"}}',
      400); // HTTP 400 Bad Request
    Exit;
  end;

  // Delegate to your proxy implementation; it returns JSON and HTTP status
  vResponseJson := mProxy.ProcessChatCompletion(vRequestJson, vHttpStatus);
  ReturnJson(Ctxt, vResponseJson, vHttpStatus);
end;

procedure TOpenAIRestServer.V1Models(Ctxt: TRestServerUriContext);
begin
  if Ctxt.Method <> mGET then
  begin
    ReturnJson(Ctxt,
      '{"error":{"message":"Method not allowed","type":"invalid_request_error","code":"method_not_allowed"}}',
      405); // HTTP 405 Method Not Allowed
    Exit;
  end;

  ReturnJson(Ctxt,
    '{"object":"list","data":[' +
    '{"id":"deepseek-chat","object":"model","owned_by":"firefox-deepseek"},' +
    '{"id":"deepseek","object":"model","owned_by":"firefox-deepseek"}' +
    ']}',
    200); // HTTP 200 OK
end;

end.

