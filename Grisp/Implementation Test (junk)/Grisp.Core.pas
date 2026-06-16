unit Grisp.Core;

interface

uses
  System.SysUtils, System.Generics.Collections;

type
  TValType = (vtNull, vtInteger, vtFixedPoint, vtBoolean, vtString, vtIdentifier, vtList, vtMap);

  TUInt128 = record
    Low: UInt64;
    High: UInt64;
    class function Create(ALow: UInt64; AHigh: UInt64 = 0): TUInt128; static;
    class function Mul64x64(A, B: UInt64): TUInt128; static;
    class function Div128by64(Num: TUInt128; Den: UInt64; out Rem: UInt64): TUInt128; static;
    class function Compare(const Left, Right: TUInt128): Integer; static;
  end;

  TFixedPoint = record
    Value: Int64;
    Scale: Byte;
    class function Create(AValue: Int64; AScale: Byte): TFixedPoint; static;
    function ToString: string;
  end;

  TIdentifier = record
    TypeName: string;
    SequenceNumber: Int64;
    class function Create(const ATypeName: string; ASeqNum: Int64): TIdentifier; static;
    function ToString: string;
  end;

  TValue = record
  public
    ValType: TValType;
    IntValue: Int64;
    FixValue: TFixedPoint;
    BoolValue: Boolean;
    StrValue: string;
    IdValue: TIdentifier;
    ListValue: TArray<TValue>;
    MapValue: TArray<TPair<string, TValue>>;

    class function CreateNull: TValue; static;
    class function CreateInteger(AVal: Int64): TValue; static;
    class function CreateFixedPoint(AVal: Int64; AScale: Byte): TValue; static;
    class function CreateBoolean(AVal: Boolean): TValue; static;
    class function CreateString(const AVal: string): TValue; static;
    class function CreateIdentifier(const ATypeName: string; ASeqNum: Int64): TValue; static;
    class function CreateList(const AList: TArray<TValue>): TValue; static;
    class function CreateMap(const AMap: TArray<TPair<string, TValue>>): TValue; static;

    function ToString: string;
    function EqualsValue(const Other: TValue): Boolean;
  end;

  TFieldEntry = record
    Name: string;
    Value: TValue;
  end;

  TNode = class
  public
    Id: TIdentifier;
    TypeName: string;
    Fields: TArray<TFieldEntry>;
    constructor Create(const AId: TIdentifier; const ATypeName: string);
    function FindField(const AName: string; out AValue: TValue): Boolean;
    procedure SetField(const AName: string; const AValue: TValue);
    function Clone: TNode;
  end;

  TEdge = class
  public
    Id: TIdentifier;
    TypeName: string;
    Src: TIdentifier;
    Tgt: TIdentifier;
    Fields: TArray<TFieldEntry>;
    constructor Create(const AId: TIdentifier; const ATypeName: string; const ASrc, ATgt: TIdentifier);
    function FindField(const AName: string; out AValue: TValue): Boolean;
    procedure SetField(const AName: string; const AValue: TValue);
    function Clone: TEdge;
  end;

  TReadType = (
    rtNodeExistence,
    rtEdgeExistence,
    rtFieldRead,
    rtExtent,
    rtPredicate,
    rtOrderingDependency,
    rtEdgeType,
    rtEdgePredicate,
    rtEdgeOrderingDependency,
    rtAdjacency
  );

  TReadEffect = record
    ReadType: TReadType;
	ElementId: TIdentifier;
    FieldName: string;
    TypeName: string;
    NodeId: TIdentifier;
    AdjEdgeType: string;
    Direction: string;
    VersionValue: Int64;

    class function NodeExistence(const AId: TIdentifier; AVersion: Int64): TReadEffect; static;
    class function EdgeExistence(const AId: TIdentifier; AVersion: Int64): TReadEffect; static;
    class function FieldRead(const AId: TIdentifier; const AFieldName: string; AVersion: Int64): TReadEffect; static;
    class function Extent(const ATypeName: string; AVersion: Int64): TReadEffect; static;
    class function Predicate(const ATypeName, AFieldName: string; AVersion: Int64): TReadEffect; static;
    class function OrderingDependency(const ATypeName, AFieldName: string; AVersion: Int64): TReadEffect; static;
    class function ReadEdgeType(const ATypeName: string; AVersion: Int64): TReadEffect; static;
    class function EdgePredicate(const ATypeName, AFieldName: string; AVersion: Int64): TReadEffect; static;
    class function EdgeOrderingDependency(const ATypeName, AFieldName: string; AVersion: Int64): TReadEffect; static;
    class function Adjacency(const ANodeId: TIdentifier; const AEdgeType: string; const ADir: string; AVersion: Int64): TReadEffect; static;

    function ToString: string;
    function EqualsEffect(const Other: TReadEffect): Boolean;
  end;

  TGraph = class
  public
    Nodes: TObjectList<TNode>;
    Edges: TObjectList<TEdge>;

    constructor Create;
    destructor Destroy; override;
    function FindNode(const AId: TIdentifier; out ANode: TNode): Boolean;
    function FindEdge(const AId: TIdentifier; out AEdge: TEdge): Boolean;
    procedure AddNode(ANode: TNode);
    procedure AddEdge(AEdge: TEdge);
    procedure DeleteNode(const AId: TIdentifier);
    procedure DeleteEdge(const AId: TIdentifier);
    function Clone: TGraph;
  end;

  TCounters = class
  public
    TickCounter: Int64;
    SequenceCounters: TDictionary<string, Int64>;

    ExtentVersions: TDictionary<string, Int64>;
    PredicateVersions: TDictionary<string, TDictionary<string, Int64>>;
    OrderingDependencyVersions: TDictionary<string, TDictionary<string, Int64>>;

    EdgeTypeVersions: TDictionary<string, Int64>;
    EdgePredicateVersions: TDictionary<string, TDictionary<string, Int64>>;
    EdgeOrderingDependencyVersions: TDictionary<string, TDictionary<string, Int64>>;

    AdjacencyVersions: TDictionary<string, TDictionary<string, TDictionary<string, Int64>>>;

    ExistenceVersions: TDictionary<string, Int64>;
    FieldVersions: TDictionary<string, TDictionary<string, Int64>>;

    constructor Create;
    destructor Destroy; override;

    function GetSequenceCounter(const AType: string): Int64;
    procedure SetSequenceCounter(const AType: string; AValue: Int64);
    function NextSequenceCounter(const AType: string): Int64;

    function GetExtentVersion(const AType: string): Int64;
    procedure IncExtentVersion(const AType: string);

    function GetPredicateVersion(const AType, AField: string): Int64;
    procedure IncPredicateVersion(const AType, AField: string);

    function GetOrderingDependencyVersion(const AType, AField: string): Int64;
    procedure IncOrderingDependencyVersion(const AType, AField: string);

    function GetEdgeTypeVersion(const AType: string): Int64;
    procedure IncEdgeTypeVersion(const AType: string);

    function GetEdgePredicateVersion(const AType, AField: string): Int64;
    procedure IncEdgePredicateVersion(const AType, AField: string);

    function GetEdgeOrderingDependencyVersion(const AType, AField: string): Int64;
    procedure IncEdgeOrderingDependencyVersion(const AType, AField: string);

    function GetAdjacencyVersion(const ANodeId: TIdentifier; const AEdgeType, ADir: string): Int64;
    procedure IncAdjacencyVersion(const ANodeId: TIdentifier; const AEdgeType, ADir: string);

    function GetExistenceVersion(const AId: TIdentifier): Int64;
    procedure SetExistenceVersion(const AId: TIdentifier; AVal: Int64);
    procedure IncExistenceVersion(const AId: TIdentifier);
    procedure RemoveExistenceVersion(const AId: TIdentifier);

    function GetFieldVersion(const AId: TIdentifier; const AField: string): Int64;
    procedure SetFieldVersion(const AId: TIdentifier; const AField: string; AVal: Int64);
    procedure IncFieldVersion(const AId: TIdentifier; const AField: string);
    procedure RemoveFieldVersions(const AId: TIdentifier);

    function Clone: TCounters;
  end;

  TMatchKey = record
    RuleId: string;
    Bindings: TArray<TPair<string, TValue>>;
    function ToString: string;
    function EqualsKey(const Other: TMatchKey): Boolean;
  end;

  TMatch = record
    MatchKey: TMatchKey;
    Bindings: TArray<TPair<string, TValue>>;
    ReadTrace: TArray<TReadEffect>;
    Age: Int64;
    Score: Int64;
  end;

  TState = class
  public
    Graph: TGraph;
    Counters: TCounters;
    TickNumber: Int64;
    PrevMatches: TDictionary<string, Int64>;

    constructor Create;
    destructor Destroy; override;
    function Clone: TState;
  end;

function CompareUTF8(const S1, S2: string): Integer;
function CompareIdentifiers(const A, B: TIdentifier): Integer;
function CompareValues(const A, B: TValue): Integer;
function CompareMatchKeys(const A, B: TMatchKey): Integer;

implementation

{ TUInt128 }

class function TUInt128.Create(ALow: UInt64; AHigh: UInt64): TUInt128;
begin
  Result.Low := ALow;
  Result.High := AHigh;
end;

class function TUInt128.Mul64x64(A, B: UInt64): TUInt128;
var
  A_lo, A_hi, B_lo, B_hi: UInt64;
  P0, P1, P2, P3: UInt64;
  Mid: UInt64;
begin
  A_lo := A and $FFFFFFFF;
  A_hi := A shr 32;
  B_lo := B and $FFFFFFFF;
  B_hi := B shr 32;

  P0 := A_lo * B_lo;
  P1 := A_lo * B_hi;
  P2 := A_hi * B_lo;
  P3 := A_hi * B_hi;

  Mid := P1 + P2;
  Result.High := P3 + (Mid shr 32);
  if Mid < P1 then
    Result.High := Result.High + UInt64($100000000);

  Result.Low := P0 + (Mid shl 32);
  if Result.Low < P0 then
    Result.High := Result.High + 1;
end;

class function TUInt128.Div128by64(Num: TUInt128; Den: UInt64; out Rem: UInt64): TUInt128;
var
  i: Integer;
  Carry: UInt64;
begin
  if Den = 0 then
    raise Exception.Create('DIVISION_BY_ZERO');

  Result.Low := 0;
  Result.High := 0;
  Rem := 0;

  for i := 127 downto 0 do
  begin
    if i >= 64 then
      Carry := (Num.High shr (i - 64)) and 1
    else
      Carry := (Num.Low shr i) and 1;

    Rem := (Rem shl 1) or Carry;

    if Rem >= Den then
    begin
      Rem := Rem - Den;
      if i >= 64 then
        Result.High := Result.High or (UInt64(1) shl (i - 64))
      else
        Result.Low := Result.Low or (UInt64(1) shl i);
    end;
  end;
end;

class function TUInt128.Compare(const Left, Right: TUInt128): Integer;
begin
  if Left.High < Right.High then Exit(-1);
  if Left.High > Right.High then Exit(1);
  if Left.Low < Right.Low then Exit(-1);
  if Left.Low > Right.Low then Exit(1);
  Result := 0;
end;

{ TFixedPoint }

class function TFixedPoint.Create(AValue: Int64; AScale: Byte): TFixedPoint;
begin
  Result.Value := AValue;
  Result.Scale := AScale;
end;

function TFixedPoint.ToString: string;
var
  SignStr, ValStr: string;
  DotPos: Integer;
begin
  if Value < 0 then
  begin
    SignStr := '-';
    ValStr := IntToStr(-Value);
  end
  else
  begin
    SignStr := '';
    ValStr := IntToStr(Value);
  end;

  if Scale = 0 then
  begin
    Result := SignStr + ValStr + '.0';
    Exit;
  end;

  while Length(ValStr) <= Scale do
    ValStr := '0' + ValStr;

  DotPos := Length(ValStr) - Scale;
  Result := SignStr + Copy(ValStr, 1, DotPos) + '.' + Copy(ValStr, DotPos + 1, Scale);
end;

{ TIdentifier }

class function TIdentifier.Create(const ATypeName: string; ASeqNum: Int64): TIdentifier;
begin
  Result.TypeName := ATypeName;
  Result.SequenceNumber := ASeqNum;
end;

function TIdentifier.ToString: string;
begin
  Result := TypeName + ':' + IntToStr(SequenceNumber);
end;

{ TValue }

class function TValue.CreateNull: TValue;
begin
  Result.ValType := vtNull;
end;

class function TValue.CreateInteger(AVal: Int64): TValue;
begin
  Result.ValType := vtInteger;
  Result.IntValue := AVal;
end;

class function TValue.CreateFixedPoint(AVal: Int64; AScale: Byte): TValue;
begin
  Result.ValType := vtFixedPoint;
  Result.FixValue := TFixedPoint.Create(AVal, AScale);
end;

class function TValue.CreateBoolean(AVal: Boolean): TValue;
begin
  Result.ValType := vtBoolean;
  Result.BoolValue := AVal;
end;

class function TValue.CreateString(const AVal: string): TValue;
begin
  Result.ValType := vtString;
  Result.StrValue := AVal;
end;

class function TValue.CreateIdentifier(const ATypeName: string; ASeqNum: Int64): TValue;
begin
  Result.ValType := vtIdentifier;
  Result.IdValue := TIdentifier.Create(ATypeName, ASeqNum);
end;

class function TValue.CreateList(const AList: TArray<TValue>): TValue;
begin
  Result.ValType := vtList;
  Result.ListValue := AList;
end;

class function TValue.CreateMap(const AMap: TArray<TPair<string, TValue>>): TValue;
begin
  Result.ValType := vtMap;
  Result.MapValue := AMap;
end;

function TValue.ToString: string;
var
  i: Integer;
  S: string;
begin
  case ValType of
    vtNull: Result := 'null';
    vtInteger: Result := IntToStr(IntValue);
    vtFixedPoint: Result := FixValue.ToString;
    vtBoolean: if BoolValue then Result := 'true' else Result := 'false';
    vtString: Result := '"' + StrValue + '"';
    vtIdentifier: Result := IdValue.ToString;
    vtList:
      begin
        S := '[';
        for i := 0 to High(ListValue) do
        begin
          if i > 0 then S := S + ',';
          S := S + ListValue[i].ToString;
        end;
        S := S + ']';
        Result := S;
      end;
    vtMap:
      begin
        S := '{';
        for i := 0 to High(MapValue) do
        begin
          if i > 0 then S := S + ',';
          S := S + '"' + MapValue[i].Key + '":' + MapValue[i].Value.ToString;
        end;
        S := S + '}';
        Result := S;
      end;
  else
    Result := '';
  end;
end;

function TValue.EqualsValue(const Other: TValue): Boolean;
begin
  Result := CompareValues(Self, Other) = 0;
end;

{ TNode }

constructor TNode.Create(const AId: TIdentifier; const ATypeName: string);
begin
  Id := AId;
  TypeName := ATypeName;
  Fields := nil;
end;

function TNode.FindField(const AName: string; out AValue: TValue): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(Fields) do
    if Fields[i].Name = AName then
    begin
      AValue := Fields[i].Value;
      Exit(True);
    end;
  Result := False;
end;

procedure TNode.SetField(const AName: string; const AValue: TValue);
var
  i, InsertPos: Integer;
begin
  InsertPos := -1;
  for i := 0 to High(Fields) do
  begin
    if Fields[i].Name = AName then
    begin
      Fields[i].Value := AValue;
      Exit;
    end
    else if (InsertPos = -1) and (CompareUTF8(Fields[i].Name, AName) > 0) then
      InsertPos := i;
  end;
  if InsertPos = -1 then
    InsertPos := Length(Fields);
  SetLength(Fields, Length(Fields) + 1);
  for i := High(Fields) downto InsertPos + 1 do
    Fields[i] := Fields[i - 1];
  Fields[InsertPos].Name := AName;
  Fields[InsertPos].Value := AValue;
end;

function TNode.Clone: TNode;
var
  i: Integer;
begin
  Result := TNode.Create(Id, TypeName);
  SetLength(Result.Fields, Length(Fields));
  for i := 0 to High(Fields) do
    Result.Fields[i] := Fields[i];
end;

{ TEdge }

constructor TEdge.Create(const AId: TIdentifier; const ATypeName: string; const ASrc, ATgt: TIdentifier);
begin
  Id := AId;
  TypeName := ATypeName;
  Src := ASrc;
  Tgt := ATgt;
  Fields := nil;
end;

function TEdge.FindField(const AName: string; out AValue: TValue): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(Fields) do
    if Fields[i].Name = AName then
    begin
      AValue := Fields[i].Value;
      Exit(True);
    end;
  Result := False;
end;

procedure TEdge.SetField(const AName: string; const AValue: TValue);
var
  i, InsertPos: Integer;
begin
  InsertPos := -1;
  for i := 0 to High(Fields) do
  begin
    if Fields[i].Name = AName then
    begin
      Fields[i].Value := AValue;
      Exit;
    end
    else if (InsertPos = -1) and (CompareUTF8(Fields[i].Name, AName) > 0) then
      InsertPos := i;
  end;
  if InsertPos = -1 then
    InsertPos := Length(Fields);
  SetLength(Fields, Length(Fields) + 1);
  for i := High(Fields) downto InsertPos + 1 do
    Fields[i] := Fields[i - 1];
  Fields[InsertPos].Name := AName;
  Fields[InsertPos].Value := AValue;
end;

function TEdge.Clone: TEdge;
var
  i: Integer;
begin
  Result := TEdge.Create(Id, TypeName, Src, Tgt);
  SetLength(Result.Fields, Length(Fields));
  for i := 0 to High(Fields) do
    Result.Fields[i] := Fields[i];
end;

{ TReadEffect }

class function TReadEffect.NodeExistence(const AId: TIdentifier; AVersion: Int64): TReadEffect;
begin
  Result.ReadType := rtNodeExistence;
  Result.ElementId := AId;
  Result.VersionValue := AVersion;
end;

class function TReadEffect.EdgeExistence(const AId: TIdentifier; AVersion: Int64): TReadEffect;
begin
  Result.ReadType := rtEdgeExistence;
  Result.ElementId := AId;
  Result.VersionValue := AVersion;
end;

class function TReadEffect.FieldRead(const AId: TIdentifier; const AFieldName: string; AVersion: Int64): TReadEffect;
begin
  Result.ReadType := rtFieldRead;
  Result.ElementId := AId;
  Result.FieldName := AFieldName;
  Result.VersionValue := AVersion;
end;

class function TReadEffect.Extent(const ATypeName: string; AVersion: Int64): TReadEffect;
begin
  Result.ReadType := rtExtent;
  Result.TypeName := ATypeName;
  Result.VersionValue := AVersion;
end;

class function TReadEffect.Predicate(const ATypeName, AFieldName: string; AVersion: Int64): TReadEffect;
begin
  Result.ReadType := rtPredicate;
  Result.TypeName := ATypeName;
  Result.FieldName := AFieldName;
  Result.VersionValue := AVersion;
end;

class function TReadEffect.OrderingDependency(const ATypeName, AFieldName: string; AVersion: Int64): TReadEffect;
begin
  Result.ReadType := rtOrderingDependency;
  Result.TypeName := ATypeName;
  Result.FieldName := AFieldName;
  Result.VersionValue := AVersion;
end;

class function TReadEffect.ReadEdgeType(const ATypeName: string; AVersion: Int64): TReadEffect;
begin
  Result.ReadType := rtEdgeType;
  Result.TypeName := ATypeName;
  Result.VersionValue := AVersion;
end;

class function TReadEffect.EdgePredicate(const ATypeName, AFieldName: string; AVersion: Int64): TReadEffect;
begin
  Result.ReadType := rtEdgePredicate;
  Result.TypeName := ATypeName;
  Result.FieldName := AFieldName;
  Result.VersionValue := AVersion;
end;

class function TReadEffect.EdgeOrderingDependency(const ATypeName, AFieldName: string; AVersion: Int64): TReadEffect;
begin
  Result.ReadType := rtEdgeOrderingDependency;
  Result.TypeName := ATypeName;
  Result.FieldName := AFieldName;
  Result.VersionValue := AVersion;
end;

class function TReadEffect.Adjacency(const ANodeId: TIdentifier; const AEdgeType: string; const ADir: string; AVersion: Int64): TReadEffect;
begin
  Result.ReadType := rtAdjacency;
  Result.NodeId := ANodeId;
  Result.AdjEdgeType := AEdgeType;
  Result.Direction := ADir;
  Result.VersionValue := AVersion;
end;

function TReadEffect.ToString: string;
begin
  case ReadType of
    rtNodeExistence: Result := 'NodeExistence(' + ElementId.ToString + ')=' + IntToStr(VersionValue);
    rtEdgeExistence: Result := 'EdgeExistence(' + ElementId.ToString + ')=' + IntToStr(VersionValue);
    rtFieldRead: Result := 'FieldRead(' + ElementId.ToString + ',' + FieldName + ')=' + IntToStr(VersionValue);
    rtExtent: Result := 'Extent(' + TypeName + ')=' + IntToStr(VersionValue);
    rtPredicate: Result := 'Predicate(' + TypeName + ',' + FieldName + ')=' + IntToStr(VersionValue);
    rtOrderingDependency: Result := 'OrderingDependency(' + TypeName + ',' + FieldName + ')=' + IntToStr(VersionValue);
    rtEdgeType: Result := 'EdgeType(' + TypeName + ')=' + IntToStr(VersionValue);
    rtEdgePredicate: Result := 'EdgePredicate(' + TypeName + ',' + FieldName + ')=' + IntToStr(VersionValue);
    rtEdgeOrderingDependency: Result := 'EdgeOrderingDependency(' + TypeName + ',' + FieldName + ')=' + IntToStr(VersionValue);
    rtAdjacency: Result := 'Adjacency(' + NodeId.ToString + ',' + AdjEdgeType + ',' + Direction + ')=' + IntToStr(VersionValue);
  else
    Result := 'UnknownReadEffect';
  end;
end;

function TReadEffect.EqualsEffect(const Other: TReadEffect): Boolean;
begin
  if ReadType <> Other.ReadType then Exit(False);
  case ReadType of
    rtNodeExistence, rtEdgeExistence: Result := CompareIdentifiers(ElementId, Other.ElementId) = 0;
    rtFieldRead: Result := (CompareIdentifiers(ElementId, Other.ElementId) = 0) and (FieldName = Other.FieldName);
    rtExtent, rtEdgeType: Result := TypeName = Other.TypeName;
    rtPredicate, rtOrderingDependency, rtEdgePredicate, rtEdgeOrderingDependency:
      Result := (TypeName = Other.TypeName) and (FieldName = Other.FieldName);
    rtAdjacency:
      Result := (CompareIdentifiers(NodeId, Other.NodeId) = 0) and (AdjEdgeType = Other.AdjEdgeType) and (Direction = Other.Direction);
  else
    Result := False;
  end;
end;

{ TGraph }

constructor TGraph.Create;
begin
  Nodes := TObjectList<TNode>.Create(True);
  Edges := TObjectList<TEdge>.Create(True);
end;

destructor TGraph.Destroy;
begin
  Nodes.Free;
  Edges.Free;
  inherited;
end;

function TGraph.FindNode(const AId: TIdentifier; out ANode: TNode): Boolean;
var
  L, H, M, Comp: Integer;
begin
  L := 0;
  H := Nodes.Count - 1;
  while L <= H do
  begin
    M := (L + H) div 2;
    Comp := CompareIdentifiers(Nodes[M].Id, AId);
    if Comp = 0 then
    begin
      ANode := Nodes[M];
      Exit(True);
    end
    else if Comp < 0 then
      L := M + 1
    else
      H := M - 1;
  end;
  Result := False;
end;

function TGraph.FindEdge(const AId: TIdentifier; out AEdge: TEdge): Boolean;
var
  L, H, M, Comp: Integer;
begin
  L := 0;
  H := Edges.Count - 1;
  while L <= H do
  begin
    M := (L + H) div 2;
    Comp := CompareIdentifiers(Edges[M].Id, AId);
    if Comp = 0 then
    begin
      AEdge := Edges[M];
      Exit(True);
    end
    else if Comp < 0 then
      L := M + 1
    else
      H := M - 1;
  end;
  Result := False;
end;

procedure TGraph.AddNode(ANode: TNode);
var
  i, InsertPos: Integer;
begin
  InsertPos := -1;
  for i := 0 to Nodes.Count - 1 do
    if CompareIdentifiers(Nodes[i].Id, ANode.Id) = 0 then
    begin
      Nodes[i] := ANode;
      Exit;
	end
    else if (InsertPos = -1) and (CompareIdentifiers(Nodes[i].Id, ANode.Id) > 0) then
      InsertPos := i;
  if InsertPos = -1 then
    Nodes.Add(ANode)
  else
    Nodes.Insert(InsertPos, ANode);
end;

procedure TGraph.AddEdge(AEdge: TEdge);
var
  i, InsertPos: Integer;
begin
  InsertPos := -1;
  for i := 0 to Edges.Count - 1 do
    if CompareIdentifiers(Edges[i].Id, AEdge.Id) = 0 then
    begin
      Edges[i] := AEdge;
      Exit;
    end
    else if (InsertPos = -1) and (CompareIdentifiers(Edges[i].Id, AEdge.Id) > 0) then
      InsertPos := i;
  if InsertPos = -1 then
    Edges.Add(AEdge)
  else
    Edges.Insert(InsertPos, AEdge);
end;

procedure TGraph.DeleteNode(const AId: TIdentifier);
var
  i: Integer;
begin
  for i := 0 to Nodes.Count - 1 do
    if CompareIdentifiers(Nodes[i].Id, AId) = 0 then
    begin
      Nodes.Delete(i);
      Break;
    end;
end;

procedure TGraph.DeleteEdge(const AId: TIdentifier);
var
  i: Integer;
begin
  for i := 0 to Edges.Count - 1 do
    if CompareIdentifiers(Edges[i].Id, AId) = 0 then
    begin
      Edges.Delete(i);
      Break;
    end;
end;

function TGraph.Clone: TGraph;
var
  N: TNode;
  E: TEdge;
begin
  Result := TGraph.Create;
  for N in Nodes do
    Result.Nodes.Add(N.Clone);
  for E in Edges do
    Result.Edges.Add(E.Clone);
end;

{ TCounters }

constructor TCounters.Create;
begin
  TickCounter := 0;
  SequenceCounters := TDictionary<string, Int64>.Create;
  ExtentVersions := TDictionary<string, Int64>.Create;
  PredicateVersions := TDictionary<string, TDictionary<string, Int64>>.Create;
  OrderingDependencyVersions := TDictionary<string, TDictionary<string, Int64>>.Create;
  EdgeTypeVersions := TDictionary<string, Int64>.Create;
  EdgePredicateVersions := TDictionary<string, TDictionary<string, Int64>>.Create;
  EdgeOrderingDependencyVersions := TDictionary<string, TDictionary<string, Int64>>.Create;
  AdjacencyVersions := TDictionary<string, TDictionary<string, TDictionary<string, Int64>>>.Create;
  ExistenceVersions := TDictionary<string, Int64>.Create;
  FieldVersions := TDictionary<string, TDictionary<string, Int64>>.Create;
end;

destructor TCounters.Destroy;
var
  Dict1: TDictionary<string, Int64>;
  Dict2: TDictionary<string, TDictionary<string, Int64>>;
  NodeKey: string;
begin
  SequenceCounters.Free;
  ExtentVersions.Free;
  for Dict1 in PredicateVersions.Values do Dict1.Free;
  PredicateVersions.Free;
  for Dict1 in OrderingDependencyVersions.Values do Dict1.Free;
  OrderingDependencyVersions.Free;
  EdgeTypeVersions.Free;
  for Dict1 in EdgePredicateVersions.Values do Dict1.Free;
  EdgePredicateVersions.Free;
  for Dict1 in EdgeOrderingDependencyVersions.Values do Dict1.Free;
  EdgeOrderingDependencyVersions.Free;
  for NodeKey in AdjacencyVersions.Keys do
  begin
    Dict2 := AdjacencyVersions[NodeKey];
    for Dict1 in Dict2.Values do Dict1.Free;
    Dict2.Free;
  end;
  AdjacencyVersions.Free;
  ExistenceVersions.Free;
  for Dict1 in FieldVersions.Values do Dict1.Free;
  FieldVersions.Free;
  inherited;
end;

function TCounters.GetSequenceCounter(const AType: string): Int64;
begin
  if not SequenceCounters.TryGetValue(AType, Result) then
    Result := 0;
end;

procedure TCounters.SetSequenceCounter(const AType: string; AValue: Int64);
begin
  SequenceCounters.AddOrSetValue(AType, AValue);
end;

function TCounters.NextSequenceCounter(const AType: string): Int64;
begin
  Result := GetSequenceCounter(AType);
  if Result = Int64.MaxValue then
    raise Exception.Create('COUNTER_OVERFLOW');
  SetSequenceCounter(AType, Result + 1);
end;

function TCounters.GetExtentVersion(const AType: string): Int64;
begin
  if not ExtentVersions.TryGetValue(AType, Result) then
    Result := 0;
end;

procedure TCounters.IncExtentVersion(const AType: string);
var
  V: Int64;
begin
  V := GetExtentVersion(AType);
  if V = Int64.MaxValue then raise Exception.Create('COUNTER_OVERFLOW');
  ExtentVersions.AddOrSetValue(AType, V + 1);
end;

function TCounters.GetPredicateVersion(const AType, AField: string): Int64;
var
  Dict: TDictionary<string, Int64>;
begin
  if PredicateVersions.TryGetValue(AType, Dict) and Dict.TryGetValue(AField, Result) then
    Exit;
  Result := 0;
end;

procedure TCounters.IncPredicateVersion(const AType, AField: string);
var
  Dict: TDictionary<string, Int64>;
  V: Int64;
begin
  if not PredicateVersions.TryGetValue(AType, Dict) then
  begin
    Dict := TDictionary<string, Int64>.Create;
    PredicateVersions.Add(AType, Dict);
  end;
  V := 0;
  Dict.TryGetValue(AField, V);
  if V = Int64.MaxValue then raise Exception.Create('COUNTER_OVERFLOW');
  Dict.AddOrSetValue(AField, V + 1);
end;

function TCounters.GetOrderingDependencyVersion(const AType, AField: string): Int64;
var
  Dict: TDictionary<string, Int64>;
begin
  if OrderingDependencyVersions.TryGetValue(AType, Dict) and Dict.TryGetValue(AField, Result) then
    Exit;
  Result := 0;
end;

procedure TCounters.IncOrderingDependencyVersion(const AType, AField: string);
var
  Dict: TDictionary<string, Int64>;
  V: Int64;
begin
  if not OrderingDependencyVersions.TryGetValue(AType, Dict) then
  begin
    Dict := TDictionary<string, Int64>.Create;
    OrderingDependencyVersions.Add(AType, Dict);
  end;
  V := 0;
  Dict.TryGetValue(AField, V);
  if V = Int64.MaxValue then raise Exception.Create('COUNTER_OVERFLOW');
  Dict.AddOrSetValue(AField, V + 1);
end;

function TCounters.GetEdgeTypeVersion(const AType: string): Int64;
begin
  if not EdgeTypeVersions.TryGetValue(AType, Result) then
    Result := 0;
end;

procedure TCounters.IncEdgeTypeVersion(const AType: string);
var
  V: Int64;
begin
  V := GetEdgeTypeVersion(AType);
  if V = Int64.MaxValue then raise Exception.Create('COUNTER_OVERFLOW');
  EdgeTypeVersions.AddOrSetValue(AType, V + 1);
end;

function TCounters.GetEdgePredicateVersion(const AType, AField: string): Int64;
var
  Dict: TDictionary<string, Int64>;
begin
  if EdgePredicateVersions.TryGetValue(AType, Dict) and Dict.TryGetValue(AField, Result) then
    Exit;
  Result := 0;
end;

procedure TCounters.IncEdgePredicateVersion(const AType, AField: string);
var
  Dict: TDictionary<string, Int64>;
  V: Int64;
begin
  if not EdgePredicateVersions.TryGetValue(AType, Dict) then
  begin
    Dict := TDictionary<string, Int64>.Create;
    EdgePredicateVersions.Add(AType, Dict);
  end;
  V := 0;
  Dict.TryGetValue(AField, V);
  if V = Int64.MaxValue then raise Exception.Create('COUNTER_OVERFLOW');
  Dict.AddOrSetValue(AField, V + 1);
end;

function TCounters.GetEdgeOrderingDependencyVersion(const AType, AField: string): Int64;
var
  Dict: TDictionary<string, Int64>;
begin
  if EdgeOrderingDependencyVersions.TryGetValue(AType, Dict) and Dict.TryGetValue(AField, Result) then
    Exit;
  Result := 0;
end;

procedure TCounters.IncEdgeOrderingDependencyVersion(const AType, AField: string);
var
  Dict: TDictionary<string, Int64>;
  V: Int64;
begin
  if not EdgeOrderingDependencyVersions.TryGetValue(AType, Dict) then
  begin
    Dict := TDictionary<string, Int64>.Create;
    EdgeOrderingDependencyVersions.Add(AType, Dict);
  end;
  V := 0;
  Dict.TryGetValue(AField, V);
  if V = Int64.MaxValue then raise Exception.Create('COUNTER_OVERFLOW');
  Dict.AddOrSetValue(AField, V + 1);
end;

function TCounters.GetAdjacencyVersion(const ANodeId: TIdentifier; const AEdgeType, ADir: string): Int64;
var
  NodeStr: string;
  Dict1: TDictionary<string, TDictionary<string, Int64>>;
  Dict2: TDictionary<string, Int64>;
begin
  NodeStr := ANodeId.ToString;
  if AdjacencyVersions.TryGetValue(NodeStr, Dict1) and
     Dict1.TryGetValue(AEdgeType, Dict2) and
     Dict2.TryGetValue(ADir, Result) then
    Exit;
  Result := 0;
end;

procedure TCounters.IncAdjacencyVersion(const ANodeId: TIdentifier; const AEdgeType, ADir: string);
var
  NodeStr: string;
  Dict1: TDictionary<string, TDictionary<string, Int64>>;
  Dict2: TDictionary<string, Int64>;
  V: Int64;
begin
  NodeStr := ANodeId.ToString;
  if not AdjacencyVersions.TryGetValue(NodeStr, Dict1) then
  begin
    Dict1 := TDictionary<string, TDictionary<string, Int64>>.Create;
    AdjacencyVersions.Add(NodeStr, Dict1);
  end;
  if not Dict1.TryGetValue(AEdgeType, Dict2) then
  begin
    Dict2 := TDictionary<string, Int64>.Create;
    Dict1.Add(AEdgeType, Dict2);
  end;
  V := 0;
  Dict2.TryGetValue(ADir, V);
  if V = Int64.MaxValue then raise Exception.Create('COUNTER_OVERFLOW');
  Dict2.AddOrSetValue(ADir, V + 1);
end;

function TCounters.GetExistenceVersion(const AId: TIdentifier): Int64;
begin
  if not ExistenceVersions.TryGetValue(AId.ToString, Result) then
    Result := 0;
end;

procedure TCounters.SetExistenceVersion(const AId: TIdentifier; AVal: Int64);
begin
  ExistenceVersions.AddOrSetValue(AId.ToString, AVal);
end;

procedure TCounters.IncExistenceVersion(const AId: TIdentifier);
var
  V: Int64;
begin
  V := GetExistenceVersion(AId);
  if V = Int64.MaxValue then raise Exception.Create('COUNTER_OVERFLOW');
  ExistenceVersions.AddOrSetValue(AId.ToString, V + 1);
end;

procedure TCounters.RemoveExistenceVersion(const AId: TIdentifier);
begin
  ExistenceVersions.Remove(AId.ToString);
end;

function TCounters.GetFieldVersion(const AId: TIdentifier; const AField: string): Int64;
var
  Dict: TDictionary<string, Int64>;
begin
  if FieldVersions.TryGetValue(AId.ToString, Dict) and Dict.TryGetValue(AField, Result) then
    Exit;
  Result := 0;
end;

procedure TCounters.SetFieldVersion(const AId: TIdentifier; const AField: string; AVal: Int64);
var
  Dict: TDictionary<string, Int64>;
begin
  if not FieldVersions.TryGetValue(AId.ToString, Dict) then
  begin
    Dict := TDictionary<string, Int64>.Create;
    FieldVersions.Add(AId.ToString, Dict);
  end;
  Dict.AddOrSetValue(AField, AVal);
end;

procedure TCounters.IncFieldVersion(const AId: TIdentifier; const AField: string);
var
  Dict: TDictionary<string, Int64>;
  V: Int64;
begin
  if not FieldVersions.TryGetValue(AId.ToString, Dict) then
  begin
    Dict := TDictionary<string, Int64>.Create;
    FieldVersions.Add(AId.ToString, Dict);
  end;
  V := 0;
  Dict.TryGetValue(AField, V);
  if V = Int64.MaxValue then raise Exception.Create('COUNTER_OVERFLOW');
  Dict.AddOrSetValue(AField, V + 1);
end;

procedure TCounters.RemoveFieldVersions(const AId: TIdentifier);
var
  Dict: TDictionary<string, Int64>;
begin
  if FieldVersions.TryGetValue(AId.ToString, Dict) then
  begin
    Dict.Free;
    FieldVersions.Remove(AId.ToString);
  end;
end;

function TCounters.Clone: TCounters;
var
  K, K2, K3: string;
  Dict1: TDictionary<string, Int64>;
  Dict1Clone: TDictionary<string, Int64>;
  Dict2: TDictionary<string, TDictionary<string, Int64>>;
  Dict2Clone: TDictionary<string, TDictionary<string, Int64>>;
begin
  Result := TCounters.Create;
  Result.TickCounter := TickCounter;
  for K in SequenceCounters.Keys do Result.SequenceCounters.Add(K, SequenceCounters[K]);
  for K in ExtentVersions.Keys do Result.ExtentVersions.Add(K, ExtentVersions[K]);

  for K in PredicateVersions.Keys do
  begin
    Dict1 := PredicateVersions[K];
    Dict1Clone := TDictionary<string, Int64>.Create;
    for K2 in Dict1.Keys do Dict1Clone.Add(K2, Dict1[K2]);
    Result.PredicateVersions.Add(K, Dict1Clone);
  end;

  for K in OrderingDependencyVersions.Keys do
  begin
    Dict1 := OrderingDependencyVersions[K];
    Dict1Clone := TDictionary<string, Int64>.Create;
    for K2 in Dict1.Keys do Dict1Clone.Add(K2, Dict1[K2]);
    Result.OrderingDependencyVersions.Add(K, Dict1Clone);
  end;

  for K in EdgeTypeVersions.Keys do Result.EdgeTypeVersions.Add(K, EdgeTypeVersions[K]);

  for K in EdgePredicateVersions.Keys do
  begin
    Dict1 := EdgePredicateVersions[K];
    Dict1Clone := TDictionary<string, Int64>.Create;
    for K2 in Dict1.Keys do Dict1Clone.Add(K2, Dict1[K2]);
    Result.EdgePredicateVersions.Add(K, Dict1Clone);
  end;

  for K in EdgeOrderingDependencyVersions.Keys do
  begin
    Dict1 := EdgeOrderingDependencyVersions[K];
    Dict1Clone := TDictionary<string, Int64>.Create;
    for K2 in Dict1.Keys do Dict1Clone.Add(K2, Dict1[K2]);
    Result.EdgeOrderingDependencyVersions.Add(K, Dict1Clone);
  end;

  for K in AdjacencyVersions.Keys do
  begin
    Dict2 := AdjacencyVersions[K];
    Dict2Clone := TDictionary<string, TDictionary<string, Int64>>.Create;
    for K2 in Dict2.Keys do
    begin
      Dict1 := Dict2[K2];
      Dict1Clone := TDictionary<string, Int64>.Create;
      for K3 in Dict1.Keys do Dict1Clone.Add(K3, Dict1[K3]);
      Dict2Clone.Add(K2, Dict1Clone);
    end;
    Result.AdjacencyVersions.Add(K, Dict2Clone);
  end;

  for K in ExistenceVersions.Keys do Result.ExistenceVersions.Add(K, ExistenceVersions[K]);

  for K in FieldVersions.Keys do
  begin
    Dict1 := FieldVersions[K];
    Dict1Clone := TDictionary<string, Int64>.Create;
    for K2 in Dict1.Keys do Dict1Clone.Add(K2, Dict1[K2]);
    Result.FieldVersions.Add(K, Dict1Clone);
  end;
end;

{ TMatchKey }

function TMatchKey.ToString: string;
var
  S: string;
  i: Integer;
begin
  S := '{"rule_id":"' + RuleId + '","bindings":{';
  for i := 0 to High(Bindings) do
  begin
    if i > 0 then S := S + ',';
    S := S + '"' + Bindings[i].Key + '":' + Bindings[i].Value.ToString;
  end;
  S := S + '}}';
  Result := S;
end;

function TMatchKey.EqualsKey(const Other: TMatchKey): Boolean;
begin
  Result := CompareMatchKeys(Self, Other) = 0;
end;

{ TState }

constructor TState.Create;
begin
  Graph := TGraph.Create;
  Counters := TCounters.Create;
  TickNumber := 0;
  PrevMatches := TDictionary<string, Int64>.Create;
end;

destructor TState.Destroy;
begin
  Graph.Free;
  Counters.Free;
  PrevMatches.Free;
  inherited;
end;

function TState.Clone: TState;
var
  K: string;
begin
  Result := TState.Create;
  Result.Graph.Free;
  Result.Graph := Graph.Clone;
  Result.Counters.Free;
  Result.Counters := Counters.Clone;
  Result.TickNumber := TickNumber;
  for K in PrevMatches.Keys do
    Result.PrevMatches.Add(K, PrevMatches[K]);
end;

{ Canonical Comparisons }

function CompareUTF8(const S1, S2: string): Integer;
begin
  if S1 < S2 then Result := -1
  else if S1 > S2 then Result := 1
  else Result := 0;
end;

function CompareIdentifiers(const A, B: TIdentifier): Integer;
begin
  Result := CompareUTF8(A.TypeName, B.TypeName);
  if Result = 0 then
  begin
    if A.SequenceNumber < B.SequenceNumber then Result := -1
    else if A.SequenceNumber > B.SequenceNumber then Result := 1
    else Result := 0;
  end;
end;

function CompareFixedPointValues(V1: Int64; S1: Byte; V2: Int64; S2: Byte): Integer;
var
  Sign1, Sign2: Integer;
  AbsV1, AbsV2: UInt64;
  U128_1, U128_2: TUInt128;
  PowerDiff: Byte;
  Mult: UInt64;
  i: Integer;
begin
  if V1 < 0 then Sign1 := -1 else if V1 > 0 then Sign1 := 1 else Sign1 := 0;
  if V2 < 0 then Sign2 := -1 else if V2 > 0 then Sign2 := 1 else Sign2 := 0;
  if Sign1 <> Sign2 then Exit(Sign1 - Sign2);
  if Sign1 = 0 then Exit(0);

  AbsV1 := UInt64(Abs(V1));
  AbsV2 := UInt64(Abs(V2));

  if S1 = S2 then
  begin
    if AbsV1 < AbsV2 then Result := -Sign1
    else if AbsV1 > AbsV2 then Result := Sign1
    else Result := 0;
    Exit;
  end;

  if S1 < S2 then
  begin
    PowerDiff := S2 - S1;
    Mult := 1;
    for i := 1 to PowerDiff do
    begin
      if Mult > UInt64.MaxValue div 10 then
        raise Exception.Create('INTEGER_OVERFLOW');
      Mult := Mult * 10;
    end;
    U128_1 := TUInt128.Mul64x64(AbsV1, Mult);
    U128_2 := TUInt128.Create(AbsV2, 0);
  end
  else
  begin
    PowerDiff := S1 - S2;
    Mult := 1;
    for i := 1 to PowerDiff do
    begin
      if Mult > UInt64.MaxValue div 10 then
        raise Exception.Create('INTEGER_OVERFLOW');
      Mult := Mult * 10;
    end;
    U128_1 := TUInt128.Create(AbsV1, 0);
    U128_2 := TUInt128.Mul64x64(AbsV2, Mult);
  end;

  Result := TUInt128.Compare(U128_1, U128_2);
  if Sign1 < 0 then
    Result := -Result;
end;

function CompareValues(const A, B: TValue): Integer;
var
  i, MinLen, Comp: Integer;
begin
  if A.ValType <> B.ValType then
    Exit(Ord(A.ValType) - Ord(B.ValType));

  case A.ValType of
    vtNull: Result := 0;
    vtInteger:
      begin
        if A.IntValue < B.IntValue then Result := -1
        else if A.IntValue > B.IntValue then Result := 1
        else Result := 0;
      end;
    vtFixedPoint:
      Result := CompareFixedPointValues(A.FixValue.Value, A.FixValue.Scale,
                                        B.FixValue.Value, B.FixValue.Scale);
    vtBoolean:
      begin
        if A.BoolValue = B.BoolValue then Result := 0
        else if not A.BoolValue then Result := -1
        else Result := 1;
      end;
    vtString: Result := CompareUTF8(A.StrValue, B.StrValue);
    vtIdentifier: Result := CompareIdentifiers(A.IdValue, B.IdValue);
    vtList:
      begin
        MinLen := Length(A.ListValue);
        if Length(B.ListValue) < MinLen then MinLen := Length(B.ListValue);
        for i := 0 to MinLen - 1 do
        begin
          Comp := CompareValues(A.ListValue[i], B.ListValue[i]);
          if Comp <> 0 then Exit(Comp);
        end;
        Result := Length(A.ListValue) - Length(B.ListValue);
      end;
    vtMap:
      begin
        MinLen := Length(A.MapValue);
        if Length(B.MapValue) < MinLen then MinLen := Length(B.MapValue);
        for i := 0 to MinLen - 1 do
        begin
          Comp := CompareUTF8(A.MapValue[i].Key, B.MapValue[i].Key);
          if Comp <> 0 then Exit(Comp);
          Comp := CompareValues(A.MapValue[i].Value, B.MapValue[i].Value);
          if Comp <> 0 then Exit(Comp);
        end;
        Result := Length(A.MapValue) - Length(B.MapValue);
      end;
  else
    Result := 0;
  end;
end;

function CompareMatchKeys(const A, B: TMatchKey): Integer;
var
  i, MinLen, Comp: Integer;
begin
  Result := CompareUTF8(A.RuleId, B.RuleId);
  if Result <> 0 then Exit;

  MinLen := Length(A.Bindings);
  if Length(B.Bindings) < MinLen then MinLen := Length(B.Bindings);
  for i := 0 to MinLen - 1 do
  begin
    Comp := CompareUTF8(A.Bindings[i].Key, B.Bindings[i].Key);
    if Comp <> 0 then Exit(Comp);
    Comp := CompareValues(A.Bindings[i].Value, B.Bindings[i].Value);
    if Comp <> 0 then Exit(Comp);
  end;
  Result := Length(A.Bindings) - Length(B.Bindings);
end;

end.
