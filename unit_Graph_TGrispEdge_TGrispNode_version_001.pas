unit unit_Graph_TGrispEdge_TGrispNode_version_001;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  unit_Core_TGrispValueBase_version_001;

type
  TGrispNode = class;
  TGrispEdge = class;

  // Edge class - connects two nodes
  TGrispEdge = class
  public
    LabelName: string;
    EdgeType: string;
    Source: TGrispNode;
    Target: TGrispNode;
    constructor Create(ASource: TGrispNode; ATarget: TGrispNode; const ALabel: string; const AEdgeType: string);
  end;

  // Node class - graph vertex with attributes and edges
  TGrispNode = class
  private
    FAttributes: TObjectDictionary<string, TGrispValue>;
    FOutgoing: TObjectList<TGrispEdge>;
    FIncoming: TObjectList<TGrispEdge>;
    FMarked: Boolean;
    FId: Integer;
    FName: string;
    FNodeType: string;
  public
    constructor Create(AId: Integer; const AName: string; const ANodeType: string);
    destructor Destroy; override;

    // Properties
    property Id: Integer read FId;
    property Name: string read FName write FName;
    property NodeType: string read FNodeType;
    property Outgoing: TObjectList<TGrispEdge> read FOutgoing;
    property Incoming: TObjectList<TGrispEdge> read FIncoming;
    property Marked: Boolean read FMarked write FMarked;

    // Attribute operations
	function GetValueAttribute(const Key: string): TGrispValue;
    procedure SetValueAttribute(const Key: string; AValue: TGrispValue);
    procedure RemoveAttribute(const Key: string);
    function HasAttribute(const Key: string): Boolean;
    function GetNumber(const Key: string; Default: Double = 0): Double;
    function GetIdentifier(const Key: string): string;
    function GetAttributeKeys: TList<string>;

    // Edge operations
    procedure AddOutgoingEdge(Edge: TGrispEdge);
    procedure AddIncomingEdge(Edge: TGrispEdge);
    procedure RemoveOutgoingEdge(Edge: TGrispEdge);
    procedure RemoveIncomingEdge(Edge: TGrispEdge);

    function ToString: string; override;
  end;

implementation

{ TGrispEdge }

constructor TGrispEdge.Create(ASource: TGrispNode; ATarget: TGrispNode; const ALabel: string; const AEdgeType: string);
begin
  inherited Create;
  Source := ASource;
  Target := ATarget;
  LabelName := ALabel;
  EdgeType := AEdgeType;
end;

{ TGrispNode }

constructor TGrispNode.Create(AId: Integer; const AName: string; const ANodeType: string);
begin
  inherited Create;
  FId := AId;
  FName := AName;
  FNodeType := ANodeType;
  FAttributes := TObjectDictionary<string, TGrispValue>.Create([doOwnsValues]);
  FOutgoing := TObjectList<TGrispEdge>.Create(False);
  FIncoming := TObjectList<TGrispEdge>.Create(False);
  FMarked := False;
end;

destructor TGrispNode.Destroy;
begin
  FIncoming.Free;
  FOutgoing.Free;
  FAttributes.Free;
  inherited Destroy;
end;

function TGrispNode.GetValueAttribute(const Key: string): TGrispValue;
begin
  if not FAttributes.TryGetValue(Key, Result) then Result := nil;
end;

procedure TGrispNode.SetValueAttribute(const Key: string; AValue: TGrispValue);
begin
  if (AValue <> nil) and (AValue.Kind = gvkNode) then
    AValue.SetNodeReference(FId, FName);
  FAttributes.AddOrSetValue(Key, AValue);
end;

procedure TGrispNode.RemoveAttribute(const Key: string);
begin
  FAttributes.Remove(Key);
end;

function TGrispNode.HasAttribute(const Key: string): Boolean;
begin
  Result := FAttributes.ContainsKey(Key);
end;

function TGrispNode.GetNumber(const Key: string; Default: Double): Double;
var V: TGrispValue;
begin
  V := GetValueAttribute(Key);
  if Assigned(V) and (V.Kind = gvkNumber) then Exit(V.NumberValue);
  Result := Default;
end;

function TGrispNode.GetIdentifier(const Key: string): string;
var V: TGrispValue;
begin
  V := GetValueAttribute(Key);
  if Assigned(V) and (V.Kind = gvkIdentifier) then Exit(V.IdentifierValue);
  Result := '';
end;

function TGrispNode.GetAttributeKeys: TList<string>;
begin
  Result := TList<string>.Create;
  for var Key in FAttributes.Keys do
    Result.Add(Key);
end;

procedure TGrispNode.AddOutgoingEdge(Edge: TGrispEdge);
begin
  FOutgoing.Add(Edge);
end;

procedure TGrispNode.AddIncomingEdge(Edge: TGrispEdge);
begin
  FIncoming.Add(Edge);
end;

procedure TGrispNode.RemoveOutgoingEdge(Edge: TGrispEdge);
begin
  FOutgoing.Remove(Edge);
end;

procedure TGrispNode.RemoveIncomingEdge(Edge: TGrispEdge);
begin
  FIncoming.Remove(Edge);
end;

function TGrispNode.ToString: string;
begin
  Result := Format('Node %d "%s" [%s]', [FId, FName, FNodeType]);
end;

end.
