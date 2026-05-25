unit unit_Pattern_TGrispNodeVarInfo_version_001;

interface

uses
  unit_Graph_TGrispEdge_TGrispNode_version_001;  // Changed: contains TGrispNode

type
  TGrispNodeVarInfo = record
    VarName: string;
    PatternNode: TGrispNode;
  end;

implementation

end.
