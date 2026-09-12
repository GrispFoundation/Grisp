unit GSDARevisionLineageV2;

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections;

type
  // A single revision entry
  TGSDARevisionEntry = class
  private
    FSpecContentID: string;
    FPreviousSpecContentID: string;
    FTimestamp: TDateTime;
    FHumanAccepted: Boolean;
    FPublicationSignature: string;
    FDiffSummary: string;
  public
    constructor Create(const ASpecContentID, APreviousSpecContentID: string;
                       AHumanAccepted: Boolean;
                       const APublicationSignature, ADiffSummary: string);

    property SpecContentID: string read FSpecContentID;
    property PreviousSpecContentID: string read FPreviousSpecContentID;
    property Timestamp: TDateTime read FTimestamp;
    property HumanAccepted: Boolean read FHumanAccepted;
    property PublicationSignature: string read FPublicationSignature;
    property DiffSummary: string read FDiffSummary;

    function ToJson: TJSONObject;
  end;

  // Revision lineage registry
  TGSDARevisionLineageV2 = class
  private
    FRevisions: TObjectList<TGSDARevisionEntry>;
  public
    constructor Create;
    destructor Destroy; override;

    procedure AddRevision(Entry: TGSDARevisionEntry);

    function Latest: TGSDARevisionEntry;
    function FindBySpecContentID(const ID: string): TGSDARevisionEntry;

    function ToJson: TJSONObject;
  end;

implementation

{ TGSDARevisionEntry }

constructor TGSDARevisionEntry.Create(const ASpecContentID, APreviousSpecContentID: string;
                                      AHumanAccepted: Boolean;
                                      const APublicationSignature, ADiffSummary: string);
begin
  FSpecContentID := ASpecContentID;
  FPreviousSpecContentID := APreviousSpecContentID;
  FTimestamp := Now;
  FHumanAccepted := AHumanAccepted;
  FPublicationSignature := APublicationSignature;
  FDiffSummary := ADiffSummary;
end;

function TGSDARevisionEntry.ToJson: TJSONObject;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  Obj.AddPair('spec_content_id', FSpecContentID);
  Obj.AddPair('previous_spec_content_id', FPreviousSpecContentID);
  Obj.AddPair('timestamp', DateTimeToStr(FTimestamp));
  Obj.AddPair('human_accepted', BoolToStr(FHumanAccepted, True));
  Obj.AddPair('publication_signature', FPublicationSignature);
  Obj.AddPair('diff_summary', FDiffSummary);
  Result := Obj;
end;

{ TGSDARevisionLineageV2 }

constructor TGSDARevisionLineageV2.Create;
begin
  FRevisions := TObjectList<TGSDARevisionEntry>.Create(True);
end;

destructor TGSDARevisionLineageV2.Destroy;
begin
  FRevisions.Free;
  inherited;
end;

procedure TGSDARevisionLineageV2.AddRevision(Entry: TGSDARevisionEntry);
begin
  FRevisions.Add(Entry);
end;

function TGSDARevisionLineageV2.Latest: TGSDARevisionEntry;
begin
  if FRevisions.Count = 0 then
    Result := nil
  else
    Result := FRevisions.Last;
end;

function TGSDARevisionLineageV2.FindBySpecContentID(const ID: string): TGSDARevisionEntry;
var
  R: TGSDARevisionEntry;
begin
  Result := nil;
  for R in FRevisions do
    if R.SpecContentID = ID then
      Exit(R);
end;

function TGSDARevisionLineageV2.ToJson: TJSONObject;
var
  Obj: TJSONObject;
  Arr: TJSONArray;
  R: TGSDARevisionEntry;
begin
  Obj := TJSONObject.Create;
  Arr := TJSONArray.Create;

  for R in FRevisions do
    Arr.Add(R.ToJson);

  Obj.AddPair('revision_lineage', Arr);
  Result := Obj;
end;

end.
