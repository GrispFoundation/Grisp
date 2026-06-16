unit Grisp.Core.Graph;

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  Grisp.Core.Types,
  Grisp.Core.Ordering;

function GetIncidentEdgesSorted(const Node: TNodeId; const G: TGraph): TEdgeIdList;
procedure CheckNoDanglingEdges(const G: TGraph);
procedure CheckNoDanglingIdentifiers(const G: TGraph);
procedure CheckNoIdentifierCycles(const G: TGraph);

implementation

function GetIncidentEdgesSorted(const Node: TNodeId; const G: TGraph): TEdgeIdList;
var
  NodeRec: TNode;
  EdgeSet: TDictionary<TEdgeId, Boolean>;
  EdgeId: TEdgeId;
begin
  if not G.Nodes.TryGetValue(Node, NodeRec) then
    Exit([]);
  EdgeSet := TDictionary<TEdgeId, Boolean>.Create(EdgeIdComparer);
  try
    for EdgeId in NodeRec.OutEdges do
      EdgeSet.AddOrSetValue(EdgeId, True);
    for EdgeId in NodeRec.InEdges do
      EdgeSet.AddOrSetValue(EdgeId, True);
    Result := EdgeSet.Keys.ToArray;
    TArray.Sort<TEdgeId>(Result, EdgeIdComparer);
  finally
    EdgeSet.Free;
  end;
end;

procedure CheckNoDanglingEdges(const G: TGraph);
var
  Edge: TEdge;
begin
  for Edge in G.Edges.Values do
  begin
    if not G.Nodes.ContainsKey(Edge.Src) then
      raise Exception.Create('INVARIANT_VIOLATION: dangling source');
    if not G.Nodes.ContainsKey(Edge.Tgt) then
      raise Exception.Create('INVARIANT_VIOLATION: dangling target');
  end;
end;

procedure CheckNoDanglingIdentifiers(const G: TGraph);
begin
  // Stub for now – full implementation would recursively traverse all values
end;

procedure CheckNoIdentifierCycles(const G: TGraph);
begin
  // Stub for now
end;

end.
