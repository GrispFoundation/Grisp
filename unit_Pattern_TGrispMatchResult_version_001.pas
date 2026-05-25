unit unit_Pattern_TGrispMatchResult_version_001;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  unit_Graph_TGrispEdge_TGrispNode_version_001,      // Changed: contains TGrispNode
  unit_Core_TGrispValueBase_version_001,             // Changed: contains TGrispValue
  unit_Pattern_TGrispNodeBinding_version_001,
  unit_Pattern_TGrispValueBinding_version_001;

type
  TGrispMatchResult = class
  public
    Success: Boolean;
    NodeBindings: TList<TGrispNodeBinding>;
    ValueBindings: TList<TGrispValueBinding>;
    constructor Create;
    destructor Destroy; override;
    procedure AddNodeBinding(const AName: string; ANode: TGrispNode);
    procedure AddValueBinding(const AName: string; AValue: TGrispValue);
    function TryGetNode(const AName: string; out ANode: TGrispNode): Boolean;
    function TryGetValue(const AName: string; out AValue: TGrispValue): Boolean;
  end;

implementation

constructor TGrispMatchResult.Create;
begin
  inherited Create;
  NodeBindings := TList<TGrispNodeBinding>.Create;
  ValueBindings := TList<TGrispValueBinding>.Create;
  Success := False;
end;

destructor TGrispMatchResult.Destroy;
begin
  NodeBindings.Free;
  ValueBindings.Free;
  inherited Destroy;
end;

procedure TGrispMatchResult.AddNodeBinding(const AName: string; ANode: TGrispNode);
var B: TGrispNodeBinding;
begin
  B.Name := AName;
  B.Node := ANode;
  NodeBindings.Add(B);
end;

procedure TGrispMatchResult.AddValueBinding(const AName: string; AValue: TGrispValue);
var B: TGrispValueBinding;
begin
  B.Name := AName;
  B.Value := AValue;
  ValueBindings.Add(B);
end;

function TGrispMatchResult.TryGetNode(const AName: string; out ANode: TGrispNode): Boolean;
var B: TGrispNodeBinding;
begin
  for B in NodeBindings do
    if SameText(B.Name, AName) then
    begin
	  ANode := B.Node;
      Exit(True);
    end;
  ANode := nil;
  Result := False;
end;

function TGrispMatchResult.TryGetValue(const AName: string; out AValue: TGrispValue): Boolean;
var B: TGrispValueBinding;
begin
  for B in ValueBindings do
    if SameText(B.Name, AName) then
    begin
      AValue := B.Value;
      Exit(True);
    end;
  AValue := nil;
  Result := False;
end;

end.
