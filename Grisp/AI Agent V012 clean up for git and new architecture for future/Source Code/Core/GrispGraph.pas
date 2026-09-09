unit GrispGraph;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.JSON, System.Math;

type
  TGrispValueKind = (
    vkNull,
    vkInteger,
    vkFixedPoint,
    vkBoolean,
    vkString,
    vkIdentifier,
    vkList,
    vkMap
  );

  TGrispValue = record
    Kind: TGrispValueKind;
    IntVal: Int64;
    Scale: Integer;
    BoolVal: Boolean;
    StrVal: string;
    ListVal: TArray<TGrispValue>;
    MapKeys: TArray<string>;
    MapVals: TArray<TGrispValue>;

    class function MakeNull: TGrispValue; static;
    class function MakeInt(V: Int64): TGrispValue; static;
    class function MakeFixed(V: Int64; AScale: Integer): TGrispValue; static;
    class function MakeBool(B: Boolean): TGrispValue; static;
    class function MakeString(const S: string): TGrispValue; static;
    class function MakeIdent(const AType: string; ASeq: Int64): TGrispValue; static;

    function ToString: string;
    function ToJSONString: string;
  end;

  TGrispNode = class
  public
    Id: string;           // "Person:1"
    NodeType: string;     // "Person"
    SequenceNum: Int64;   // 1
    Fields: TDictionary<string, TGrispValue>;
    ElementVersion: Int64;

    constructor Create(const AId, ANodeType: string; ASeq: Int64);
    destructor Destroy; override;
    function Clone: TGrispNode;
  end;

  TGrispEdge = class
  public
    Id: string;           // "Knows:1"
    EdgeType: string;     // "Knows"
    SequenceNum: Int64;
    SourceId: string;
    TargetId: string;
    Fields: TDictionary<string, TGrispValue>;
    ElementVersion: Int64;

    constructor Create(const AId, AEdgeType, ASrc, ATgt: string; ASeq: Int64);
    destructor Destroy; override;
    function Clone: TGrispEdge;
  end;

  TGrispGraph = class
  private
    FNodes: TObjectDictionary<string, TGrispNode>;
    FEdges: TObjectDictionary<string, TGrispEdge>;
    FSeqCounters: TDictionary<string, Int64>;
    FTypeExtentVersions: TDictionary<string, Int64>;
    FTickCounter: Int64;

    function NextSeqForType(const AType: string): Int64;
    procedure IncTypeExtent(const AType: string);
  public
    constructor Create;
    destructor Destroy; override;

    function CreateNode(const AType: string; const InitialFields: TDictionary<string, TGrispValue> = nil): TGrispNode;
    function CreateEdge(const AType, ASrcId, ATgtId: string; const InitialFields: TDictionary<string, TGrispValue> = nil): TGrispEdge;

    function UpdateNodeField(const NodeId, FieldName: string; const Value: TGrispValue): Boolean;
    function UpdateEdgeField(const EdgeId, FieldName: string; const Value: TGrispValue): Boolean;

    function DeleteNode(const NodeId: string): Boolean;
    function DeleteEdge(const EdgeId: string): Boolean;

    function FindNode(const NodeId: string; out Node: TGrispNode): Boolean;
    function FindEdge(const EdgeId: string; out Edge: TGrispEdge): Boolean;

    function NodeCount: Integer;
    function EdgeCount: Integer;
    function Tick: Int64;
    procedure AdvanceTick;

    function ToCanonicalJSON: string;
    procedure Clear;

    property TickCounter: Int64 read FTickCounter write FTickCounter;
  end;

implementation

{ TGrispValue }

class function TGrispValue.MakeNull: TGrispValue;
begin
  Result.Kind := vkNull;
  Result.IntVal := 0;
  Result.Scale := 0;
  Result.BoolVal := False;
  Result.StrVal := '';
  SetLength(Result.ListVal, 0);
  SetLength(Result.MapKeys, 0);
  SetLength(Result.MapVals, 0);
end;

class function TGrispValue.MakeInt(V: Int64): TGrispValue;
begin
  Result := MakeNull;
  Result.Kind := vkInteger;
  Result.IntVal := V;
end;

class function TGrispValue.MakeFixed(V: Int64; AScale: Integer): TGrispValue;
begin
  Result := MakeNull;
  Result.Kind := vkFixedPoint;
  Result.IntVal := V;
  Result.Scale := AScale;
end;

class function TGrispValue.MakeBool(B: Boolean): TGrispValue;
begin
  Result := MakeNull;
  Result.Kind := vkBoolean;
  Result.BoolVal := B;
end;

class function TGrispValue.MakeString(const S: string): TGrispValue;
begin
  Result := MakeNull;
  Result.Kind := vkString;
  Result.StrVal := S;
end;

class function TGrispValue.MakeIdent(const AType: string; ASeq: Int64): TGrispValue;
begin
  Result := MakeNull;
  Result.Kind := vkIdentifier;
  Result.StrVal := AType + ':' + IntToStr(ASeq);
  Result.IntVal := ASeq;
end;

function TGrispValue.ToString: string;
var
  I: Integer;
  D: Double;
begin
  case Kind of
    vkNull: Result := 'null';
    vkInteger: Result := IntToStr(IntVal);
    vkFixedPoint:
      begin
        if Scale = 0 then
          Result := IntToStr(IntVal)
        else
        begin
          D := IntVal / System.Math.Power(10, Scale);
          Result := FormatFloat('0.' + StringOfChar('0', Scale), D);
        end;
      end;
    vkBoolean: Result := BoolToStr(BoolVal, True).ToLower;
    vkString, vkIdentifier: Result := StrVal;
    vkList:
      begin
        Result := '[';
        for I := 0 to High(ListVal) do
        begin
          if I > 0 then Result := Result + ', ';
          Result := Result + ListVal[I].ToString;
        end;
        Result := Result + ']';
      end;
    vkMap:
      begin
        Result := '{';
        for I := 0 to High(MapKeys) do
        begin
          if I > 0 then Result := Result + ', ';
          Result := Result + '"' + MapKeys[I] + '": ' + MapVals[I].ToString;
        end;
        Result := Result + '}';
      end;
  else
    Result := '';
  end;
end;

function TGrispValue.ToJSONString: string;
var
  I: Integer;
begin
  case Kind of
    vkNull: Result := 'null';
    vkInteger: Result := IntToStr(IntVal);
    vkFixedPoint:
      begin
        if Scale = 0 then
          Result := IntToStr(IntVal)
        else
          Result := '"' + ToString + '"';
      end;
    vkBoolean: Result := BoolToStr(BoolVal, True).ToLower;
    vkString, vkIdentifier:
      Result := '"' + StringReplace(StringReplace(StrVal, '\', '\\', [rfReplaceAll]), '"', '\"', [rfReplaceAll]) + '"';
    vkList:
      begin
        Result := '[';
        for I := 0 to High(ListVal) do
        begin
          if I > 0 then Result := Result + ',';
          Result := Result + ListVal[I].ToJSONString;
        end;
        Result := Result + ']';
      end;
    vkMap:
      begin
        Result := '{';
        for I := 0 to High(MapKeys) do
        begin
          if I > 0 then Result := Result + ',';
          Result := Result + '"' + MapKeys[I] + '":' + MapVals[I].ToJSONString;
        end;
        Result := Result + '}';
      end;
  else
    Result := 'null';
  end;
end;

{ TGrispNode }

constructor TGrispNode.Create(const AId, ANodeType: string; ASeq: Int64);
begin
  inherited Create;
  Id := AId;
  NodeType := ANodeType;
  SequenceNum := ASeq;
  Fields := TDictionary<string, TGrispValue>.Create;
  ElementVersion := 1;
end;

destructor TGrispNode.Destroy;
begin
  Fields.Free;
  inherited Destroy;
end;

function TGrispNode.Clone: TGrispNode;
var
  Pair: TPair<string, TGrispValue>;
begin
  Result := TGrispNode.Create(Id, NodeType, SequenceNum);
  Result.ElementVersion := ElementVersion;
  for Pair in Fields do
    Result.Fields.Add(Pair.Key, Pair.Value);
end;

{ TGrispEdge }

constructor TGrispEdge.Create(const AId, AEdgeType, ASrc, ATgt: string; ASeq: Int64);
begin
  inherited Create;
  Id := AId;
  EdgeType := AEdgeType;
  SequenceNum := ASeq;
  SourceId := ASrc;
  TargetId := ATgt;
  Fields := TDictionary<string, TGrispValue>.Create;
  ElementVersion := 1;
end;

destructor TGrispEdge.Destroy;
begin
  Fields.Free;
  inherited Destroy;
end;

function TGrispEdge.Clone: TGrispEdge;
var
  Pair: TPair<string, TGrispValue>;
begin
  Result := TGrispEdge.Create(Id, EdgeType, SourceId, TargetId, SequenceNum);
  Result.ElementVersion := ElementVersion;
  for Pair in Fields do
    Result.Fields.Add(Pair.Key, Pair.Value);
end;

{ TGrispGraph }

constructor TGrispGraph.Create;
begin
  inherited Create;
  FNodes := TObjectDictionary<string, TGrispNode>.Create([doOwnsValues]);
  FEdges := TObjectDictionary<string, TGrispEdge>.Create([doOwnsValues]);
  FSeqCounters := TDictionary<string, Int64>.Create;
  FTypeExtentVersions := TDictionary<string, Int64>.Create;
  FTickCounter := 0;
end;

destructor TGrispGraph.Destroy;
begin
  FNodes.Free;
  FEdges.Free;
  FSeqCounters.Free;
  FTypeExtentVersions.Free;
  inherited Destroy;
end;

function TGrispGraph.NextSeqForType(const AType: string): Int64;
var
  Seq: Int64;
begin
  if not FSeqCounters.TryGetValue(AType, Seq) then
    Seq := 1
  else
    Inc(Seq);

  FSeqCounters.AddOrSetValue(AType, Seq);
  Result := Seq;
end;

procedure TGrispGraph.IncTypeExtent(const AType: string);
var
  Ver: Int64;
begin
  if not FTypeExtentVersions.TryGetValue(AType, Ver) then
    Ver := 1
  else
    Inc(Ver);

  FTypeExtentVersions.AddOrSetValue(AType, Ver);
end;

function TGrispGraph.CreateNode(const AType: string; const InitialFields: TDictionary<string, TGrispValue>): TGrispNode;
var
  Seq: Int64;
  Id: string;
  Node: TGrispNode;
  Pair: TPair<string, TGrispValue>;
begin
  Seq := NextSeqForType(AType);
  Id := AType + ':' + IntToStr(Seq);
  Node := TGrispNode.Create(Id, AType, Seq);

  if Assigned(InitialFields) then
    for Pair in InitialFields do
      Node.Fields.Add(Pair.Key, Pair.Value);

  FNodes.Add(Id, Node);
  IncTypeExtent(AType);
  Result := Node;
end;

function TGrispGraph.CreateEdge(const AType, ASrcId, ATgtId: string;
  const InitialFields: TDictionary<string, TGrispValue>): TGrispEdge;
var
  Seq: Int64;
  Id: string;
  Edge: TGrispEdge;
  Pair: TPair<string, TGrispValue>;
begin
  Seq := NextSeqForType(AType);
  Id := AType + ':' + IntToStr(Seq);
  Edge := TGrispEdge.Create(Id, AType, ASrcId, ATgtId, Seq);

  if Assigned(InitialFields) then
    for Pair in InitialFields do
      Edge.Fields.Add(Pair.Key, Pair.Value);

  FEdges.Add(Id, Edge);
  IncTypeExtent(AType);
  Result := Edge;
end;

function TGrispGraph.UpdateNodeField(const NodeId, FieldName: string; const Value: TGrispValue): Boolean;
var
  Node: TGrispNode;
begin
  if FNodes.TryGetValue(NodeId, Node) then
  begin
    Node.Fields.AddOrSetValue(FieldName, Value);
    Inc(Node.ElementVersion);
    Exit(True);
  end;
  Result := False;
end;

function TGrispGraph.UpdateEdgeField(const EdgeId, FieldName: string; const Value: TGrispValue): Boolean;
var
  Edge: TGrispEdge;
begin
  if FEdges.TryGetValue(EdgeId, Edge) then
  begin
    Edge.Fields.AddOrSetValue(FieldName, Value);
    Inc(Edge.ElementVersion);
    Exit(True);
  end;
  Result := False;
end;

function TGrispGraph.DeleteNode(const NodeId: string): Boolean;
var
  Node: TGrispNode;
  EdgeId: string;
  EdgeList: TList<string>;
  Edge: TGrispEdge;
begin
  if FNodes.TryGetValue(NodeId, Node) then
  begin
    // Cascade delete incident edges
    EdgeList := TList<string>.Create;
    try
      for EdgeId in FEdges.Keys do
      begin
        Edge := FEdges[EdgeId];
        if (Edge.SourceId = NodeId) or (Edge.TargetId = NodeId) then
          EdgeList.Add(EdgeId);
      end;
      for EdgeId in EdgeList do
        DeleteEdge(EdgeId);
    finally
      EdgeList.Free;
    end;

    IncTypeExtent(Node.NodeType);
    FNodes.Remove(NodeId);
    Exit(True);
  end;
  Result := False;
end;

function TGrispGraph.DeleteEdge(const EdgeId: string): Boolean;
var
  Edge: TGrispEdge;
begin
  if FEdges.TryGetValue(EdgeId, Edge) then
  begin
    IncTypeExtent(Edge.EdgeType);
    FEdges.Remove(EdgeId);
    Exit(True);
  end;
  Result := False;
end;

function TGrispGraph.FindNode(const NodeId: string; out Node: TGrispNode): Boolean;
begin
  Result := FNodes.TryGetValue(NodeId, Node);
end;

function TGrispGraph.FindEdge(const EdgeId: string; out Edge: TGrispEdge): Boolean;
begin
  Result := FEdges.TryGetValue(EdgeId, Edge);
end;

function TGrispGraph.NodeCount: Integer;
begin
  Result := FNodes.Count;
end;

function TGrispGraph.EdgeCount: Integer;
begin
  Result := FEdges.Count;
end;

function TGrispGraph.Tick: Int64;
begin
  Result := FTickCounter;
end;

procedure TGrispGraph.AdvanceTick;
begin
  Inc(FTickCounter);
end;

function TGrispGraph.ToCanonicalJSON: string;
var
  SB: TStringBuilder;
  NodeKeys, EdgeKeys, FieldKeys: TList<string>;
  K, FK: string;
  Node: TGrispNode;
  Edge: TGrispEdge;
  I, J: Integer;
begin
  SB := TStringBuilder.Create;
  NodeKeys := TList<string>.Create;
  EdgeKeys := TList<string>.Create;
  FieldKeys := TList<string>.Create;
  try
    for K in FNodes.Keys do NodeKeys.Add(K);
    for K in FEdges.Keys do EdgeKeys.Add(K);
    NodeKeys.Sort;
    EdgeKeys.Sort;

    SB.Append('{"tick":');
    SB.Append(IntToStr(FTickCounter));
    SB.Append(',"nodes":[');

    for I := 0 to NodeKeys.Count - 1 do
    begin
      if I > 0 then SB.Append(',');
      Node := FNodes[NodeKeys[I]];
      SB.Append('{"id":"');
      SB.Append(Node.Id);
      SB.Append('","type":"');
      SB.Append(Node.NodeType);
      SB.Append('","version":');
      SB.Append(IntToStr(Node.ElementVersion));
      SB.Append(',"fields":{');

      FieldKeys.Clear;
      for FK in Node.Fields.Keys do FieldKeys.Add(FK);
      FieldKeys.Sort;
      for J := 0 to FieldKeys.Count - 1 do
      begin
        if J > 0 then SB.Append(',');
        SB.Append('"');
        SB.Append(FieldKeys[J]);
        SB.Append('":');
        SB.Append(Node.Fields[FieldKeys[J]].ToJSONString);
      end;
      SB.Append('}}');
    end;

    SB.Append('],"edges":[');

    for I := 0 to EdgeKeys.Count - 1 do
    begin
      if I > 0 then SB.Append(',');
      Edge := FEdges[EdgeKeys[I]];
      SB.Append('{"id":"');
      SB.Append(Edge.Id);
      SB.Append('","type":"');
      SB.Append(Edge.EdgeType);
      SB.Append('","source":"');
      SB.Append(Edge.SourceId);
      SB.Append('","target":"');
      SB.Append(Edge.TargetId);
      SB.Append('","version":');
      SB.Append(IntToStr(Edge.ElementVersion));
      SB.Append(',"fields":{');

      FieldKeys.Clear;
      for FK in Edge.Fields.Keys do FieldKeys.Add(FK);
      FieldKeys.Sort;
      for J := 0 to FieldKeys.Count - 1 do
      begin
        if J > 0 then SB.Append(',');
        SB.Append('"');
        SB.Append(FieldKeys[J]);
        SB.Append('":');
        SB.Append(Edge.Fields[FieldKeys[J]].ToJSONString);
      end;
      SB.Append('}}');
    end;

    SB.Append(']}');
    Result := SB.ToString;
  finally
    SB.Free;
    NodeKeys.Free;
    EdgeKeys.Free;
    FieldKeys.Free;
  end;
end;

procedure TGrispGraph.Clear;
begin
  FNodes.Clear;
  FEdges.Clear;
  FSeqCounters.Clear;
  FTypeExtentVersions.Clear;
  FTickCounter := 0;
end;

end.
