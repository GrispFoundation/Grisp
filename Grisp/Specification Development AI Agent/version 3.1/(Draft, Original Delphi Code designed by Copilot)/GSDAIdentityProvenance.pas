unit GSDAIdentityProvenance;

interface

uses
  System.SysUtils,
  System.JSON,
  GSDAIdentity;

type
  // Trust zones for provenance
  TGSDAProvenanceZone = (
    pzUnknown,
    pzSemanticFactory,
    pzExecutionFactory,
    pzCoordinatorFactory,
    pzDerivedFactory,
    pzAdapterSanitization,
    pzKernelValidation,
    pzKernelStateCommit
  );

  // Provenance record
  TGSDAIdentityProvenance = class
  private
    FIdentityValue: string;
    FIdentityKind: string;
    FSchema: string;
    FCanonicalInput: string;
    FHash: string;
    FTrustZone: TGSDAProvenanceZone;
    FFields: TArray<string>;
    FTimestamp: TDateTime;
  public
    constructor Create(const AIdentityValue, AIdentityKind, ASchema,
                       ACanonicalInput, AHash: string;
                       ATrustZone: TGSDAProvenanceZone;
                       const AFields: TArray<string>);

    property IdentityValue: string read FIdentityValue;
    property IdentityKind: string read FIdentityKind;
    property Schema: string read FSchema;
    property CanonicalInput: string read FCanonicalInput;
    property Hash: string read FHash;
    property TrustZone: TGSDAProvenanceZone read FTrustZone;
    property Fields: TArray<string> read FFields;
    property Timestamp: TDateTime read FTimestamp;

    function ToJson: TJSONObject;
  end;

  // Provenance registry
  TGSDAIdentityProvenanceRegistry = class
  private
    FRecords: TArray<TGSDAIdentityProvenance>;
  public
    procedure AddRecord(Rec: TGSDAIdentityProvenance);
    function FindByIdentity(const IdentityValue: string): TGSDAIdentityProvenance;
    function All: TArray<TGSDAIdentityProvenance>;
  end;

implementation

{ TGSDAIdentityProvenance }

constructor TGSDAIdentityProvenance.Create(const AIdentityValue, AIdentityKind,
                                           ASchema, ACanonicalInput, AHash: string;
                                           ATrustZone: TGSDAProvenanceZone;
                                           const AFields: TArray<string>);
begin
  FIdentityValue := AIdentityValue;
  FIdentityKind := AIdentityKind;
  FSchema := ASchema;
  FCanonicalInput := ACanonicalInput;
  FHash := AHash;
  FTrustZone := ATrustZone;
  FFields := AFields;
  FTimestamp := Now;
end;

function TGSDAIdentityProvenance.ToJson: TJSONObject;
var
  Obj: TJSONObject;
  Arr: TJSONArray;
  S: string;
begin
  Obj := TJSONObject.Create;
  Obj.AddPair('identity_value', FIdentityValue);
  Obj.AddPair('identity_kind', FIdentityKind);
  Obj.AddPair('schema', FSchema);
  Obj.AddPair('canonical_input', FCanonicalInput);
  Obj.AddPair('hash', FHash);
  Obj.AddPair('trust_zone', Ord(FTrustZone).ToString);
  Obj.AddPair('timestamp', DateTimeToStr(FTimestamp));

  Arr := TJSONArray.Create;
  for S in FFields do
    Arr.Add(S);
  Obj.AddPair('fields', Arr);

  Result := Obj;
end;

{ TGSDAIdentityProvenanceRegistry }

procedure TGSDAIdentityProvenanceRegistry.AddRecord(Rec: TGSDAIdentityProvenance);
var
  L: TArray<TGSDAIdentityProvenance>;
begin
  L := FRecords;
  SetLength(L, Length(L) + 1);
  L[High(L)] := Rec;
  FRecords := L;
end;

function TGSDAIdentityProvenanceRegistry.FindByIdentity(const IdentityValue: string): TGSDAIdentityProvenance;
var
  Rec: TGSDAIdentityProvenance;
begin
  Result := nil;
  for Rec in FRecords do
    if Rec.IdentityValue = IdentityValue then
      Exit(Rec);
end;

function TGSDAIdentityProvenanceRegistry.All: TArray<TGSDAIdentityProvenance>;
begin
  Result := FRecords;
end;

end.
