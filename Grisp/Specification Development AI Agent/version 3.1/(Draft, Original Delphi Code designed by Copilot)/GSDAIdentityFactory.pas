unit GSDAIdentityFactory;

interface

uses
  System.SysUtils,
  System.JSON,
  GSDAIdentity,
  GSDACanonicalJson;

type
  TGSDAIdentityFactory = class
  private
    class function CanonicalHash(const Schema: string; Obj: TJSONObject): string; static;
  public
    // SEMANTIC
    class function MakeSemantic(const Schema: string; const Content: TJSONObject): TSemanticIdentity; static;

    // EXECUTION
    class function MakeExecution(const Schema, RunID, PeerID, RoundID: string;
                                 const Extra: TJSONObject): TExecutionIdentity; static;

    // COORDINATOR
    class function MakeCoordinator(const Prefix: string): TCoordinatorIdentity; static;

    // DERIVED EXECUTION
    class function MakeDerived(const Schema, RunID: string; Index: Integer): TDerivedExecutionIdentity; static;
  end;

implementation

uses
  System.Hash;

{ TGSDAIdentityFactory }

class function TGSDAIdentityFactory.CanonicalHash(const Schema: string; Obj: TJSONObject): string;
var
  Canon: string;
begin
  Canon := TGSDACanonicalJson.Canonicalize(Obj);
  Result := Schema + ':' + THashSHA2.GetHashString(Canon);
end;

class function TGSDAIdentityFactory.MakeSemantic(const Schema: string;
                                                 const Content: TJSONObject): TSemanticIdentity;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema', Schema);
    Obj.AddPair('content', Content.Clone as TJSONObject);
    Result := TSemanticIdentity.Create(CanonicalHash(Schema, Obj));
  finally
    Obj.Free;
  end;
end;

class function TGSDAIdentityFactory.MakeExecution(const Schema, RunID, PeerID, RoundID: string;
                                                  const Extra: TJSONObject): TExecutionIdentity;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema', Schema);
    Obj.AddPair('run_id', RunID);
    Obj.AddPair('peer_id', PeerID);
    Obj.AddPair('round_id', RoundID);

    if Extra <> nil then
      Obj.AddPair('extra', Extra.Clone as TJSONObject);

    Result := TExecutionIdentity.Create(CanonicalHash(Schema, Obj));
  finally
    Obj.Free;
  end;
end;

class function TGSDAIdentityFactory.MakeCoordinator(const Prefix: string): TCoordinatorIdentity;
var
  GUIDStr: string;
begin
  GUIDStr := GUIDToString(TGUID.NewGuid);
  Result := TCoordinatorIdentity.Create(Prefix + ':' + GUIDStr);
end;

class function TGSDAIdentityFactory.MakeDerived(const Schema, RunID: string; Index: Integer): TDerivedExecutionIdentity;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema', Schema);
    Obj.AddPair('run_id', RunID);
    Obj.AddPair('index', Index.ToString);

    Result := TDerivedExecutionIdentity.Create(CanonicalHash(Schema, Obj));
  finally
    Obj.Free;
  end;
end;

end.
