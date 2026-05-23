unit unit_GrispGraph_version_001;

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TGValueKind = (
    vkNumber,
    vkString,
    vkBoolean,
    vkIdentifier,
    vkArray,
    vkNode
  );

  TGNode = class; // forward

  TGValue = class
  public
    Kind: TGValueKind;
    NumberValue: Double;
    StringValue: string;
    BoolValue: Boolean;
    IdentifierValue: string;
    ArrayValue: TObjectList<TGValue>;
    NodeValue: TGNode;

    constructor Create(AKind: TGValueKind);
    destructor Destroy; override;
  end;

  TGEdge = class
  public
    LabelName: string;
    EdgeType: string;
    Source: TGNode;
    Target: TGNode;

    constructor Create(ASource, ATarget: TGNode; const ALabel, AEdgeType: string);
  end;

  TGNode = class
  public
    Id: Integer;
    Name: string;
    NodeType: string;
    Attributes: TObjectDictionary<string, TGValue>;
    Outgoing: TObjectList<TGEdge>;

    constructor Create(AId: Integer; const AName, ANodeType: string);
    destructor Destroy; override;

    function GetAttribute(const Key: string): TGValue;
    procedure SetAttribute(const Key: string; AValue: TGValue);
  end;

  TGGraph = class
  private
    FNextId: Integer;
  public
    Nodes: TObjectList<TGNode>;
    Edges: TObjectList<TGEdge>;
    NodeIndex: TObjectDictionary<string, TGNode>;
    Rules: TObjectList<TGNode>; // nodes whose Name starts with 'rule.' or have kind 'rule'

    constructor Create;
    destructor Destroy; override;

    function AddNode(const AName, ANodeType: string): TGNode;
    function AddEdge(ASource, ATarget: TGNode; const ALabel: string; const AEdgeType: string = ''): TGEdge;
    function FindNode(const AName: string): TGNode;
    procedure RegisterRule(ANode: TGNode);
  end;

implementation

{ TGValue }

constructor TGValue.Create(AKind: TGValueKind);
begin
  inherited Create;
  Kind := AKind;
  case Kind of
    vkArray:
      ArrayValue := TObjectList<TGValue>.Create(True);
  end;
end;

destructor TGValue.Destroy;
begin
  ArrayValue.Free;
  inherited;
end;

{ TGEdge }

constructor TGEdge.Create(ASource, ATarget: TGNode; const ALabel, AEdgeType: string);
begin
  inherited Create;
  Source := ASource;
  Target := ATarget;
  LabelName := ALabel;
  EdgeType := AEdgeType;
end;

{ TGNode }

constructor TGNode.Create(AId: Integer; const AName, ANodeType: string);
begin
  inherited Create;
  Id := AId;
  Name := AName;
  NodeType := ANodeType;
  Attributes := TObjectDictionary<string, TGValue>.Create([doOwnsValues]);
  Outgoing := TObjectList<TGEdge>.Create(False);
end;

destructor TGNode.Destroy;
begin
  Outgoing.Free;
  Attributes.Free;
  inherited;
end;

{ TGNode }

function TGNode.GetAttribute(const Key: string): TGValue;
begin
  if not Attributes.TryGetValue(Key, Result) then
    Result := nil;
end;

procedure TGNode.SetAttribute(const Key: string; AValue: TGValue);
begin
  Attributes.AddOrSetValue(Key, AValue);
end;

{ TGGraph }

constructor TGGraph.Create;
begin
  inherited Create;
  Nodes := TObjectList<TGNode>.Create(True);
  Edges := TObjectList<TGEdge>.Create(True);
  NodeIndex := TObjectDictionary<string, TGNode>.Create;
  Rules := TObjectList<TGNode>.Create(False);
  FNextId := 1;
end;

destructor TGGraph.Destroy;
begin
  Rules.Free;
  NodeIndex.Free;
  Edges.Free;
  Nodes.Free;
  inherited;
end;

function TGGraph.AddNode(const AName, ANodeType: string): TGNode;
begin
  Result := TGNode.Create(FNextId, AName, ANodeType);
  Inc(FNextId);
  Nodes.Add(Result);
  if AName <> '' then
    NodeIndex.AddOrSetValue(AName, Result);
end;

function TGGraph.AddEdge(ASource, ATarget: TGNode; const ALabel, AEdgeType: string): TGEdge;
begin
  Result := TGEdge.Create(ASource, ATarget, ALabel, AEdgeType);
  Edges.Add(Result);
  if Assigned(ASource) then
    ASource.Outgoing.Add(Result);
end;

function TGGraph.FindNode(const AName: string): TGNode;
begin
  if not NodeIndex.TryGetValue(AName, Result) then
    Result := nil;
end;

procedure TGGraph.RegisterRule(ANode: TGNode);
begin
  if Rules.IndexOf(ANode) < 0 then
    Rules.Add(ANode);
end;

end.
