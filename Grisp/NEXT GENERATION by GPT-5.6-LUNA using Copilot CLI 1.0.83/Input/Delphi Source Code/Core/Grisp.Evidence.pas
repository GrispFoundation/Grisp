unit Grisp.Evidence;

interface

uses
  System.SysUtils, System.Generics.Collections, Grisp.Types;

type
  IGrispEvidenceStore = interface
    ['{2C9E4F75-6E03-4DD4-9A64-5C1F6E2CF10A}']
    function RecordEvidence(const AEvidence: TGrispEvidence): TGrispEvidenceId;
    function GetEvidence(const AId: TGrispEvidenceId): TGrispEvidence;
    function Count: Integer;
  end;

  TGrispMemoryEvidenceStore = class(TInterfacedObject, IGrispEvidenceStore)
  private
    FItems: TDictionary<string, TGrispEvidence>;
  public
    constructor Create;
    destructor Destroy; override;
    function RecordEvidence(const AEvidence: TGrispEvidence): TGrispEvidenceId;
    function GetEvidence(const AId: TGrispEvidenceId): TGrispEvidence;
    function Count: Integer;
  end;

implementation

constructor TGrispMemoryEvidenceStore.Create;
begin
  inherited;
  FItems := TDictionary<string, TGrispEvidence>.Create;
end;

destructor TGrispMemoryEvidenceStore.Destroy;
begin
  FItems.Free;
  inherited;
end;

function TGrispMemoryEvidenceStore.RecordEvidence(const AEvidence: TGrispEvidence): TGrispEvidenceId;
var
  Item: TGrispEvidence;
begin
  Item := AEvidence;
  if Item.EvidenceId = '' then Item.EvidenceId := NewUuid;
  if FItems.ContainsKey(Item.EvidenceId) then
    raise EArgumentException.Create('Evidence is immutable and already exists');
  FItems.Add(Item.EvidenceId, Item);
  Result := Item.EvidenceId;
end;

function TGrispMemoryEvidenceStore.GetEvidence(const AId: TGrispEvidenceId): TGrispEvidence;
begin
  if not FItems.TryGetValue(AId, Result) then
    raise EArgumentException.Create('Evidence not found: ' + AId);
end;

function TGrispMemoryEvidenceStore.Count: Integer;
begin
  Result := FItems.Count;
end;

end.
