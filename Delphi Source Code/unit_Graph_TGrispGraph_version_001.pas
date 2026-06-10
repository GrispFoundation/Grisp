unit unit_Graph_TGrispGraph_version_001;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  unit_Core_TGrispValueBase_version_001,
  unit_Core_TGrispExpression_version_001,
  unit_Core_TGrispExpressionEvaluator_version_001,
  unit_Core_TGrispType_version_001,
  unit_Graph_TGrispEdge_TGrispNode_version_001,
  unit_Strategy_TGrispStrategy_version_001;  // Added for TGrispStrategy

type
  TGrispGraph = class
  private
    FNextId: Integer;
    FNodes: TObjectList<TGrispNode>;
    FEdges: TObjectList<TGrispEdge>;
    FNodeIndex: TObjectDictionary<string, TGrispNode>;
    FRules: TObjectList<TGrispNode>;
    FTypes: TObjectDictionary<string, TGrispType>;
    FStrategies: TObjectDictionary<string, TGrispStrategy>;  // NEW: owns strategies
    FModified: Boolean;

    procedure MarkReachable(Node: TGrispNode);
    procedure SweepUnmarked;
  public
    constructor Create;
    destructor Destroy; override;

    function AddNode(const AName: string; const ANodeType: string): TGrispNode;
    function FindNode(const AName: string): TGrispNode;
    procedure RemoveNode(Node: TGrispNode);
    procedure RemoveNodeByName(const AName: string);

    function AddEdge(ASource: TGrispNode; ATarget: TGrispNode; const ALabel: string; const AEdgeType: string = ''): TGrispEdge;
    procedure RemoveEdge(Edge: TGrispEdge);
    procedure RemoveEdgesBetween(Source, Target: TGrispNode; const ALabel: string = '');

    procedure RegisterRule(ANode: TGrispNode);
    property Rules: TObjectList<TGrispNode> read FRules;

    procedure AddType(const Name: string; TypeObj: TGrispType);
    function FindType(const Name: string): TGrispType;
    property Types: TObjectDictionary<string, TGrispType> read FTypes;

    // NEW: Strategy management
    procedure AddStrategy(const Name: string; Strategy: TGrispStrategy);
    function GetStrategy(const Name: string): TGrispStrategy;
    property Strategies: TObjectDictionary<string, TGrispStrategy> read FStrategies;

    property Nodes: TObjectList<TGrispNode> read FNodes;
    property Edges: TObjectList<TGrispEdge> read FEdges;
    property NodeIndex: TObjectDictionary<string, TGrispNode> read FNodeIndex;

    procedure RegisterEdgesFromIdentifiers;
    procedure GarbageCollect;
    function GetNodesByType(const ANodeType: string): TArray<TGrispNode>;
    function GetNodesByAttribute(const Key: string; Value: TGrispValue): TList<TGrispNode>;

    function ToDOT: string;
    function ToJSON: string;

	property Modified: Boolean read FModified write FModified;
  end;

implementation

constructor TGrispGraph.Create;
begin
  inherited Create;
  FNodes := TObjectList<TGrispNode>.Create(True);
  FEdges := TObjectList<TGrispEdge>.Create(True);
  FNodeIndex := TObjectDictionary<string, TGrispNode>.Create;
  FRules := TObjectList<TGrispNode>.Create(False);
  FTypes := TObjectDictionary<string, TGrispType>.Create([doOwnsValues]);
  FStrategies := TObjectDictionary<string, TGrispStrategy>.Create([doOwnsValues]);  // NEW: owns strategies
  FNextId := 1;
  FModified := False;
end;

destructor TGrispGraph.Destroy;
begin
  FStrategies.Free;  // NEW: free strategies
  FRules.Free;
  FTypes.Free;
  FNodeIndex.Free;
  FEdges.Free;
  FNodes.Free;
  inherited Destroy;
end;

function TGrispGraph.AddNode(const AName: string; const ANodeType: string): TGrispNode;
begin
  if (AName <> '') and FNodeIndex.ContainsKey(AName) then
    raise Exception.CreateFmt('Duplicate node name "%s"', [AName]);
  Result := TGrispNode.Create(FNextId, AName, ANodeType);
  Inc(FNextId);
  FNodes.Add(Result);
  if AName <> '' then FNodeIndex.Add(AName, Result);
  FModified := True;
end;

procedure TGrispGraph.RemoveNode(Node: TGrispNode);
var
  i: Integer;
  Edge: TGrispEdge;
begin
  if Node = nil then Exit;

  // Remove all outgoing edges (they will free themselves via RemoveEdge)
  for i := Node.Outgoing.Count - 1 downto 0 do
  begin
    Edge := Node.Outgoing[i];
	RemoveEdge(Edge);
  end;

  // Remove all incoming edges
  for i := Node.Incoming.Count - 1 downto 0 do
  begin
    Edge := Node.Incoming[i];
    RemoveEdge(Edge);
  end;

  if Node.Name <> '' then
    FNodeIndex.Remove(Node.Name);
  FRules.Remove(Node);
  FNodes.Remove(Node);  // <- This frees Node
  // NO Node.Free here!
  FModified := True;
end;

procedure TGrispGraph.RemoveNodeByName(const AName: string);
var
  Node: TGrispNode;
begin
  Node := FindNode(AName);
  if Node <> nil then
    RemoveNode(Node);
end;

function TGrispGraph.FindNode(const AName: string): TGrispNode;
begin
  if not FNodeIndex.TryGetValue(AName, Result) then Result := nil;
end;

function TGrispGraph.AddEdge(ASource: TGrispNode; ATarget: TGrispNode; const ALabel: string; const AEdgeType: string): TGrispEdge;
var
  E: TGrispEdge;
begin
  for E in FEdges do
    if (E.Source = ASource) and (E.Target = ATarget) and SameText(E.LabelName, ALabel) then
      Exit(E);

  Result := TGrispEdge.Create(ASource, ATarget, ALabel, AEdgeType);
  FEdges.Add(Result);
  if Assigned(ASource) then ASource.AddOutgoingEdge(Result);
  if Assigned(ATarget) then ATarget.AddIncomingEdge(Result);
  FModified := True;
end;

procedure TGrispGraph.RemoveEdge(Edge: TGrispEdge);
begin
  if Edge = nil then Exit;

  if Assigned(Edge.Source) then
    Edge.Source.RemoveOutgoingEdge(Edge);
  if Assigned(Edge.Target) then
    Edge.Target.RemoveIncomingEdge(Edge);

  FEdges.Remove(Edge);  // <- This frees Edge (OwnsObjects = True)
  // NO Edge.Free here!
  FModified := True;
end;

procedure TGrispGraph.RemoveEdgesBetween(Source, Target: TGrispNode; const ALabel: string);
var
  Edge: TGrispEdge;
  i: Integer;
begin
  for i := FEdges.Count - 1 downto 0 do
  begin
    Edge := FEdges[i];
    if (Edge.Source = Source) and (Edge.Target = Target) then
      if (ALabel = '') or SameText(Edge.LabelName, ALabel) then
        RemoveEdge(Edge);
  end;
end;

procedure TGrispGraph.RegisterRule(ANode: TGrispNode);
begin
  if FRules.IndexOf(ANode) < 0 then
    FRules.Add(ANode);
end;

procedure TGrispGraph.AddType(const Name: string; TypeObj: TGrispType);
begin
  FTypes.AddOrSetValue(Name, TypeObj);
end;

function TGrispGraph.FindType(const Name: string): TGrispType;
begin
  if not FTypes.TryGetValue(Name, Result) then Result := nil;
end;

// NEW: Strategy management
procedure TGrispGraph.AddStrategy(const Name: string; Strategy: TGrispStrategy);
begin
  FStrategies.AddOrSetValue(Name, Strategy);
end;

function TGrispGraph.GetStrategy(const Name: string): TGrispStrategy;
begin
  if not FStrategies.TryGetValue(Name, Result) then Result := nil;
end;

procedure TGrispGraph.RegisterEdgesFromIdentifiers;
var N: TGrispNode; Key: string; Val: TGrispValue; Target: TGrispNode;
begin
  for N in FNodes do
    for Key in N.GetAttributeKeys do
    begin
      Val := N.GetValueAttribute(Key);
      if Assigned(Val) and (Val.Kind = gvkIdentifier) then
      begin
        Target := FindNode(Val.IdentifierValue);
        if Assigned(Target) then
          AddEdge(N, Target, Key, 'ref');
      end;
    end;
  FModified := True;
end;

procedure TGrispGraph.MarkReachable(Node: TGrispNode);
var
  Edge: TGrispEdge;
begin
  if (Node = nil) or Node.Marked then Exit;

  Node.Marked := True;
  for Edge in Node.Outgoing do
    if Edge.Target <> nil then
      MarkReachable(Edge.Target);
  for Edge in Node.Incoming do
    if Edge.Source <> nil then
      MarkReachable(Edge.Source);
end;

procedure TGrispGraph.SweepUnmarked;
var
  Node: TGrispNode;
  i: Integer;
begin
  for i := FNodes.Count - 1 downto 0 do
  begin
    Node := FNodes[i];
    if not Node.Marked then
      RemoveNode(Node)
    else
      Node.Marked := False;
  end;
end;

procedure TGrispGraph.GarbageCollect;
var
  Root: TGrispNode;
  Key: string;
  Val: TGrispValue;
  Target: TGrispNode;
begin
  for Root in FRules do
    MarkReachable(Root);

  for Root in FRules do
  begin
    for Key in Root.GetAttributeKeys do
    begin
      Val := Root.GetValueAttribute(Key);
      if (Val <> nil) and (Val.Kind = gvkIdentifier) then
      begin
        Target := FindNode(Val.IdentifierValue);
        if Target <> nil then
          MarkReachable(Target);
      end;
    end;
  end;

  SweepUnmarked;
  FModified := True;
end;

function TGrispGraph.GetNodesByType(const ANodeType: string): TArray<TGrispNode>;
var N: TGrispNode; List: TList<TGrispNode>;
begin
  List := TList<TGrispNode>.Create;
  try
    for N in FNodes do
      if SameText(N.NodeType, ANodeType) then List.Add(N);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function TGrispGraph.GetNodesByAttribute(const Key: string; Value: TGrispValue): TList<TGrispNode>;
var
  Node: TGrispNode;
  Attr: TGrispValue;
begin
  Result := TList<TGrispNode>.Create;
  for Node in FNodes do
  begin
	Attr := Node.GetValueAttribute(Key);
    if Attr <> nil then
    begin
      if Value = nil then
        Result.Add(Node)
      else if Attr.Kind = Value.Kind then
      begin
        case Attr.Kind of
          gvkNumber:
            if Attr.NumberValue = Value.NumberValue then Result.Add(Node);
          gvkString:
            if Attr.StringValue = Value.StringValue then Result.Add(Node);
          gvkBoolean:
            if Attr.BoolValue = Value.BoolValue then Result.Add(Node);
          gvkIdentifier:
            if Attr.IdentifierValue = Value.IdentifierValue then Result.Add(Node);
        end;
      end;
    end;
  end;
end;

function TGrispGraph.ToDOT: string;
var N: TGrispNode; E: TGrispEdge;
begin
  Result := 'digraph G {' + sLineBreak;
  for N in FNodes do
    Result := Result + Format('  %d [label="%s"];', [N.Id, N.Name]) + sLineBreak;
  for E in FEdges do
    if Assigned(E.Source) and Assigned(E.Target) then
      Result := Result + Format('  %d -> %d [label="%s"];', [E.Source.Id, E.Target.Id, E.LabelName]) + sLineBreak;
  Result := Result + '}' + sLineBreak;
end;

function TGrispGraph.ToJSON: string;
var
  N: TGrispNode;
  E: TGrispEdge;
  First: Boolean;
begin
  Result := '{' + sLineBreak;
  Result := Result + '  "nodes": [' + sLineBreak;

  First := True;
  for N in FNodes do
  begin
    if not First then Result := Result + ',' + sLineBreak;
    First := False;
    Result := Result + Format('    {"id": %d, "name": "%s", "type": "%s"}', [N.Id, N.Name, N.NodeType]);
  end;

  Result := Result + sLineBreak + '  ],' + sLineBreak;
  Result := Result + '  "edges": [' + sLineBreak;

  First := True;
  for E in FEdges do
  begin
    if not First then Result := Result + ',' + sLineBreak;
    First := False;
    Result := Result + Format('    {"source": %d, "target": %d, "label": "%s"}', [E.Source.Id, E.Target.Id, E.LabelName]);
  end;

  Result := Result + sLineBreak + '  ]' + sLineBreak;
  Result := Result + '}' + sLineBreak;
end;

end.
