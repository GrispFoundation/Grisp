unit unit_Rewrite_TGrispRewriteOperation_version_001;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  unit_Graph_TGrispEdge_TGrispNode_version_001,  // For TGrispNode and TGrispEdge
  unit_Core_TGrispValueBase_version_001;          // For TGrispValue

type
  TGrispRewriteOperation = record
    TargetNode: TGrispNode;
    Attributes: TDictionary<string, TGrispValue>;
    EdgesToAdd: TList<TPair<string, TGrispNode>>;
    EdgesToRemove: TList<TPair<string, TGrispNode>>;
    NodesToRemove: TList<TGrispNode>;

    procedure Init;
    procedure Free;
    function HasChanges: Boolean;
    procedure Clear;
  end;

implementation

procedure TGrispRewriteOperation.Init;
begin
  Attributes := TDictionary<string, TGrispValue>.Create;
  EdgesToAdd := TList<TPair<string, TGrispNode>>.Create;
  EdgesToRemove := TList<TPair<string, TGrispNode>>.Create;
  NodesToRemove := TList<TGrispNode>.Create;
end;

procedure TGrispRewriteOperation.Free;
begin
  Attributes.Free;
  EdgesToAdd.Free;
  EdgesToRemove.Free;
  NodesToRemove.Free;
end;

function TGrispRewriteOperation.HasChanges: Boolean;
begin
  Result := (Attributes.Count > 0) or (EdgesToAdd.Count > 0) or
            (EdgesToRemove.Count > 0) or (NodesToRemove.Count > 0);
end;

procedure TGrispRewriteOperation.Clear;
begin
  Attributes.Clear;
  EdgesToAdd.Clear;
  EdgesToRemove.Clear;
  NodesToRemove.Clear;
end;

end.
