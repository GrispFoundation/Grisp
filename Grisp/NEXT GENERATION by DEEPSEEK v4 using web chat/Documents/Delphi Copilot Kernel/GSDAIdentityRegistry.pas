unit GSDAIdentityRegistry;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  GSDAIdentity,
  GSDAIdentityProvenance;

type
  // Registry entry
  TGSDAIdentityRecord = class
  private
    FIdentityValue: string;
    FIdentityKind: string;
    FProvenance: TGSDAIdentityProvenance;
  public
    constructor Create(const AIdentityValue, AIdentityKind: string;
                       AProvenance: TGSDAIdentityProvenance);

    property IdentityValue: string read FIdentityValue;
    property IdentityKind: string read FIdentityKind;
    property Provenance: TGSDAIdentityProvenance read FProvenance;
  end;

  // Identity registry
  TGSDAIdentityRegistry = class
  private
    FRecords: TObjectDictionary<string, TGSDAIdentityRecord>;
  public
    constructor Create;
    destructor Destroy; override;

    // Add identity + provenance
    procedure RegisterIdentity(const IdentityValue, IdentityKind: string;
                               Provenance: TGSDAIdentityProvenance);

    // Lookup
    function Find(const IdentityValue: string): TGSDAIdentityRecord;

    // Collision detection
    function Exists(const IdentityValue: string): Boolean;

    // Export all
    function All: TArray<TGSDAIdentityRecord>;
  end;

implementation

{ TGSDAIdentityRecord }

constructor TGSDAIdentityRecord.Create(const AIdentityValue, AIdentityKind: string;
                                       AProvenance: TGSDAIdentityProvenance);
begin
  FIdentityValue := AIdentityValue;
  FIdentityKind := AIdentityKind;
  FProvenance := AProvenance;
end;

{ TGSDAIdentityRegistry }

constructor TGSDAIdentityRegistry.Create;
begin
  FRecords := TObjectDictionary<string, TGSDAIdentityRecord>.Create([doOwnsValues]);
end;

destructor TGSDAIdentityRegistry.Destroy;
begin
  FRecords.Free;
  inherited;
end;

procedure TGSDAIdentityRegistry.RegisterIdentity(const IdentityValue,
                                                 IdentityKind: string;
                                                 Provenance: TGSDAIdentityProvenance);
var
  Rec: TGSDAIdentityRecord;
begin
  if FRecords.ContainsKey(IdentityValue) then
    raise Exception.CreateFmt(
      'Identity collision: "%s" already exists in registry',
      [IdentityValue]
    );

  Rec := TGSDAIdentityRecord.Create(IdentityValue, IdentityKind, Provenance);
  FRecords.Add(IdentityValue, Rec);
end;

function TGSDAIdentityRegistry.Find(const IdentityValue: string): TGSDAIdentityRecord;
begin
  if FRecords.ContainsKey(IdentityValue) then
    Result := FRecords[IdentityValue]
  else
    Result := nil;
end;

function TGSDAIdentityRegistry.Exists(const IdentityValue: string): Boolean;
begin
  Result := FRecords.ContainsKey(IdentityValue);
end;

function TGSDAIdentityRegistry.All: TArray<TGSDAIdentityRecord>;
var
  Rec: TGSDAIdentityRecord;
  L: TList<TGSDAIdentityRecord>;
begin
  L := TList<TGSDAIdentityRecord>.Create;
  try
    for Rec in FRecords.Values do
      L.Add(Rec);
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

end.
