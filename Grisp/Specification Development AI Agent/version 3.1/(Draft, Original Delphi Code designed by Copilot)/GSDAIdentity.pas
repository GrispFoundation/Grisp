unit GSDAIdentity;

interface

uses
  System.SysUtils,
  System.JSON,
  GSDACanonicalJson;

type
  // ------------------------------------------------------------
  // Base identity type
  // ------------------------------------------------------------
  TGSDAIdentity = class
  private
    FValue: string;
  public
    constructor Create(const AValue: string);
    property Value: string read FValue;
    function ToString: string; override;
  end;

  // ------------------------------------------------------------
  // SEMANTIC IDENTITY
  // Deterministic, content-based, independent of run/peer/time.
  // ------------------------------------------------------------
  TSemanticIdentity = class(TGSDAIdentity)
  public
    class function FromJson(const Schema: string; const Obj: TJSONObject): TSemanticIdentity;
  end;

  // ------------------------------------------------------------
  // EXECUTION IDENTITY
  // Deterministic within a run; depends on run_id, peer_id, round_id.
  // ------------------------------------------------------------
  TExecutionIdentity = class(TGSDAIdentity)
  public
    class function Build(const Schema, RunID, PeerID, RoundID: string;
                         const Extra: TJSONObject): TExecutionIdentity;
  end;

  // ------------------------------------------------------------
  // COORDINATOR-ASSIGNED IDENTITY
  // Assigned by kernel; typically UUID-based.
  // ------------------------------------------------------------
  TCoordinatorIdentity = class(TGSDAIdentity)
  public
    class function New(const Prefix: string): TCoordinatorIdentity;
  end;

  // ------------------------------------------------------------
  // DERIVED EXECUTION IDENTITY
  // Derived deterministically from execution context.
  // ------------------------------------------------------------
  TDerivedExecutionIdentity = class(TGSDAIdentity)
  public
    class function Build(const Schema, RunID: string; Index: Integer): TDerivedExecutionIdentity;
  end;

implementation

uses
  System.Hash;

{ TGSDAIdentity }

constructor TGSDAIdentity.Create(const AValue: string);
begin
  FValue := AValue;
end;

function TGSDAIdentity.ToString: string;
begin
  Result := FValue;
end;

{ TSemanticIdentity }

class function TSemanticIdentity.FromJson(const Schema: string; const Obj: TJSONObject): TSemanticIdentity;
var
  Canon: string;
  Hash: string;
begin
  Canon := TGSDACanonicalJson.Canonicalize(Obj);
  Hash := THashSHA2.GetHashString(Canon);
  Result := TSemanticIdentity.Create(Schema + ':' + Hash);
end;

{ TExecutionIdentity }

class function TExecutionIdentity.Build(const Schema, RunID, PeerID, RoundID: string;
                                        const Extra: TJSONObject): TExecutionIdentity;
var
  CanonObj: TJSONObject;
  Canon: string;
  Hash: string;
begin
  CanonObj := TJSONObject.Create;
  try
    CanonObj.AddPair('schema', Schema);
    CanonObj.AddPair('run_id', RunID);
    CanonObj.AddPair('peer_id', PeerID);
    CanonObj.AddPair('round_id', RoundID);

    if Extra <> nil then
      CanonObj.AddPair('extra', Extra.Clone as TJSONObject);

    Canon := TGSDACanonicalJson.Canonicalize(CanonObj);
    Hash := THashSHA2.GetHashString(Canon);

    Result := TExecutionIdentity.Create(Schema + ':' + Hash);
  finally
    CanonObj.Free;
  end;
end;

{ TCoordinatorIdentity }

class function TCoordinatorIdentity.New(const Prefix: string): TCoordinatorIdentity;
var
  GUIDStr: string;
begin
  GUIDStr := GUIDToString(TGUID.NewGuid);
  Result := TCoordinatorIdentity.Create(Prefix + ':' + GUIDStr);
end;

{ TDerivedExecutionIdentity }

class function TDerivedExecutionIdentity.Build(const Schema, RunID: string; Index: Integer): TDerivedExecutionIdentity;
var
  Obj: TJSONObject;
  Canon: string;
  Hash: string;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema', Schema);
    Obj.AddPair('run_id', RunID);
    Obj.AddPair('index', Index.ToString);

    Canon := TGSDACanonicalJson.Canonicalize(Obj);
    Hash := THashSHA2.GetHashString(Canon);

    Result := TDerivedExecutionIdentity.Create(Schema + ':' + Hash);
  finally
    Obj.Free;
  end;
end;

end.
