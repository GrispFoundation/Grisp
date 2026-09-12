unit GSDAIdentityTraceGraph;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  GSDAIdentity,
  GSDAIdentityRegistry;

type
  // Node kinds
  TTraceNodeKind = (tnRequirement, tnArtifact, tnEvidence, tnDecision);

  // Graph node
  TTraceNode = class
  private
    FIdentityValue: string;
    FKind: TTraceNodeKind;
    FOutgoing: TList<string>; // identity values of targets
    FIncoming: TList<string>; // identity values of sources
  public
    constructor Create(const AIdentityValue: string; AKind: TTraceNodeKind);
    destructor Destroy; override;

    property IdentityValue: string read FIdentityValue;
    property Kind: TTraceNodeKind read FKind;
    property Outgoing: TList<string> read FOutgoing;
    property Incoming: TList<string> read FIncoming;

    procedure AddOutgoing(const TargetId: string);
    procedure AddIncoming(const SourceId: string);
  end;

  // Traceability graph
  TGSDAIdentityTraceGraph = class
  private
    FNodes: TObjectDictionary<string, TTraceNode>;
  public
    constructor Create;
    destructor Destroy; override;

    function GetOrCreateNode(const IdentityValue: string; Kind: TTraceNodeKind): TTraceNode;

    procedure Link(const SourceId: string; SourceKind: TTraceNodeKind;
                   const TargetId: string; TargetKind: TTraceNodeKind);

    function FindNode(const IdentityValue: string): TTraceNode;
    function AllNodes: TArray<TTraceNode>;
  end;

implementation

{ TTraceNode }

constructor TTraceNode.Create(const AIdentityValue: string; AKind: TTraceNodeKind);
begin
  FIdentityValue := AIdentityValue;
  FKind := AKind;
  FOutgoing := TList<string>.Create;
  FIncoming := TList<string>.Create;
end;

destructor TTraceNode.Destroy;
begin
  FOutgoing.Free;
  FIncoming.Free;
  inherited;
end;

procedure TTraceNode.AddOutgoing(const TargetId: string);
begin
  if not FOutgoing.Contains(TargetId) then
    FOutgoing.Add(TargetId);
end;

procedure TTraceNode.AddIncoming(const SourceId: string);
begin
  if not FIncoming.Contains(SourceId) then
    FIncoming.Add(SourceId);
end;

{ TGSDAIdentityTraceGraph }

constructor TGSDAIdentityTraceGraph.Create;
begin
  FNodes := TObjectDictionary<string, TTraceNode>.Create([doOwnsValues]);
end;

destructor TGSDAIdentityTraceGraph.Destroy;
begin
  FNodes.Free;
  inherited;
end;

function TGSDAIdentityTraceGraph.GetOrCreateNode(const IdentityValue: string;
                                                 Kind: TTraceNodeKind): TTraceNode;
begin
  if FNodes.ContainsKey(IdentityValue) then
    Result := FNodes[IdentityValue]
  else
  begin
    Result := TTraceNode.Create(IdentityValue, Kind);
    FNodes.Add(IdentityValue, Result);
  end;
end;

procedure TGSDAIdentityTraceGraph.Link(const SourceId: string; SourceKind: TTraceNodeKind;
                                       const TargetId: string; TargetKind: TTraceNodeKind);
var
  SourceNode, TargetNode: TTraceNode;
begin
  SourceNode := GetOrCreateNode(SourceId, SourceKind);
  TargetNode := GetOrCreateNode(TargetId, TargetKind);

  SourceNode.AddOutgoing(TargetId);
  TargetNode.AddIncoming(SourceId);
end;

function TGSDAIdentityTraceGraph.FindNode(const IdentityValue: string): TTraceNode;
begin
  if FNodes.ContainsKey(IdentityValue) then
    Result := FNodes[IdentityValue]
  else
    Result := nil;
end;

function TGSDAIdentityTraceGraph.AllNodes: TArray<TTraceNode>;
var
  Node: TTraceNode;
  L: TList<TTraceNode>;
begin
  L := TList<TTraceNode>.Create;
  try
    for Node in FNodes.Values do
      L.Add(Node);
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

end.
