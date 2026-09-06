unit Unit_ProxyService;

interface

uses
  System.JSON,
  mormot.core.interfaces;

type
  IOpenAIProxy = interface(IInvokable)
    ['{A7B8C9D0-1234-5678-9ABC-DEF012345678}']
    procedure ChatCompletion(const Request: TJSONObject; out Response: TJSONObject);
  end;

implementation

initialization
  TInterfaceFactory.RegisterInterfaces([TypeInfo(IOpenAIProxy)]);

end.
