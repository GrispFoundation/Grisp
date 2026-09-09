unit unit_Pattern_TGrispNodeBinding_version_001;

interface

uses
  unit_Graph_TGrispEdge_TGrispNode_version_001;  // Changed: use combined core unit

type
  TGrispNodeBinding = record
    Name: string;
    Node: TGrispNode;
  end;

implementation

end.
