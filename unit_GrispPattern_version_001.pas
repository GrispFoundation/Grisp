unit unit_GrispPattern_version_001;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  unit_GrispGraph_version_001;

type
  TNodeBinding = record
    Name: string;
    Node: TGNode;
  end;

  TValueBinding = record
    Name: string;
    Value: TGValue;
  end;

  TMatchResult = class
  public
    Success: Boolean;
    NodeBindings: TList<TNodeBinding>;
    ValueBindings: TList<TValueBinding>;
    constructor Create;
    destructor Destroy; override;
    procedure AddNodeBinding(const AName: string; ANode: TGNode);
    procedure AddValueBinding(const AName: string; AValue: TGValue);
    function TryGetNode(const AName: string; out ANode: TGNode): Boolean;
    function TryGetValue(const AName: string; out AValue: TGValue): Boolean;
  end;

  TNodeVarInfo = record
    VarName: string;
    PatternNode: TGNode;
  end;

  TGrispPatternMatcher = class
  private
    FGraph: TGGraph;
    FPatternVariables: THashSet<string>;
    FNodeVars: TList<TNodeVarInfo>;
    function IsVariable(const AIdentifier: string): Boolean;
    function ValuesEqual(Val1: TGValue; Val2: TGValue): Boolean;
    function GetNodeAttrOrEdge(TargetNode: TGNode; const Key: string; out OutVal: TGValue): Boolean;
    function MatchNodeConstraints(PatternNode: TGNode; TargetNode: TGNode; Match: TMatchResult): Boolean;
    function MatchValue(PatternValue: TGValue; TargetValue: TGValue; Match: TMatchResult): Boolean;
    function Search(VarIndex: Integer; Match: TMatchResult): Boolean;
    function HasWhere(PatternRoot: TGNode): Boolean;
    function EvalWhere(PatternRoot: TGNode; Match: TMatchResult): Boolean;
  public
    constructor Create(AGraph: TGGraph);
    destructor Destroy; override;
    function MatchPattern(PatternRoot: TGNode): TMatchResult;
  end;

implementation

{ TMatchResult }

constructor TMatchResult.Create;
begin
  inherited Create;
  NodeBindings := TList<TNodeBinding>.Create;
  ValueBindings := TList<TValueBinding>.Create;
  Success := False;
end;

destructor TMatchResult.Destroy;
begin
  NodeBindings.Free;
  ValueBindings.Free;
  inherited Destroy;
end;

procedure TMatchResult.AddNodeBinding(const AName: string; ANode: TGNode);
var
  B: TNodeBinding;
begin
  B.Name := AName;
  B.Node := ANode;
  NodeBindings.Add(B);
end;

procedure TMatchResult.AddValueBinding(const AName: string; AValue: TGValue);
var
  B: TValueBinding;
begin
  B.Name := AName;
  B.Value := AValue;
  ValueBindings.Add(B);
end;

function TMatchResult.TryGetNode(const AName: string; out ANode: TGNode): Boolean;
var
  B: TNodeBinding;
begin
  for B in NodeBindings do
  begin
    if B.Name = AName then
    begin
      ANode := B.Node;
      Exit(True);
    end;
  end;
  ANode := nil;
  Result := False;
end;

function TMatchResult.TryGetValue(const AName: string; out AValue: TGValue): Boolean;
var
  B: TValueBinding;
begin
  for B in ValueBindings do
  begin
    if B.Name = AName then
    begin
      AValue := B.Value;
      Exit(True);
    end;
  end;
  AValue := nil;
  Result := False;
end;

{ TGrispPatternMatcher }

constructor TGrispPatternMatcher.Create(AGraph: TGGraph);
begin
  inherited Create;
  FGraph := AGraph;
  FPatternVariables := THashSet<string>.Create;
  FNodeVars := TList<TNodeVarInfo>.Create;
end;

destructor TGrispPatternMatcher.Destroy;
begin
  FNodeVars.Free;
  FPatternVariables.Free;
  inherited Destroy;
end;

function TGrispPatternMatcher.IsVariable(const AIdentifier: string): Boolean;
begin
  if FPatternVariables.Contains(AIdentifier) then
  begin
    Exit(True);
  end;
  if Assigned(FGraph) and (FGraph.FindNode(AIdentifier) <> nil) then
  begin
    Exit(False);
  end;
  Result := Length(AIdentifier) > 0;
end;

function TGrispPatternMatcher.ValuesEqual(Val1: TGValue; Val2: TGValue): Boolean;
var
  I: Integer;
begin
  if (Val1 = nil) or (Val2 = nil) then
  begin
    Exit((Val1 = nil) and (Val2 = nil));
  end;
  if Val1.Kind <> Val2.Kind then
  begin
    Exit(False);
  end;
  case Val1.Kind of
    vkNumber:
      begin
        Result := Val1.NumberValue = Val2.NumberValue;
      end;
    vkString:
      begin
        Result := Val1.StringValue = Val2.StringValue;
      end;
    vkBoolean:
      begin
        Result := Val1.BoolValue = Val2.BoolValue;
      end;
    vkIdentifier:
      begin
        Result := Val1.IdentifierValue = Val2.IdentifierValue;
      end;
    vkArray:
      begin
        if Val1.ArrayValue.Count <> Val2.ArrayValue.Count then
        begin
          Exit(False);
        end;
        for I := 0 to Val1.ArrayValue.Count - 1 do
        begin
          if not ValuesEqual(Val1.ArrayValue[I], Val2.ArrayValue[I]) then
          begin
            Exit(False);
          end;
        end;
        Result := True;
      end;
    vkNode:
      begin
        Result := Val1.NodeValue = Val2.NodeValue;
      end;
  else
    begin
      Result := False;
    end;
  end;
end;

function TGrispPatternMatcher.GetNodeAttrOrEdge(TargetNode: TGNode; const Key: string; out OutVal: TGValue): Boolean;
var
  Edge: TGEdge;
begin
  OutVal := TargetNode.GetAttribute(Key);
  if OutVal <> nil then
  begin
    Exit(True);
  end;
  for Edge in TargetNode.Outgoing do
  begin
    if SameText(Edge.LabelName, Key) then
    begin
      OutVal := TGValue.Create(vkIdentifier);
      OutVal.IdentifierValue := Edge.Target.Name;
      Exit(True);
    end;
  end;
  OutVal := nil;
  Result := False;
end;

function TGrispPatternMatcher.MatchNodeConstraints(PatternNode: TGNode; TargetNode: TGNode; Match: TMatchResult): Boolean;
var
  Key: string;
  PatternVal: TGValue;
  TargetVal: TGValue;
  NeedFree: Boolean;
begin
  if (PatternNode = nil) or (TargetNode = nil) then
  begin
    Exit(False);
  end;
  for Key in PatternNode.Attributes.Keys do
  begin
    PatternVal := PatternNode.GetAttribute(Key);
    NeedFree := False;
    if not GetNodeAttrOrEdge(TargetNode, Key, TargetVal) then
    begin
      Exit(False);
    end;
    if TargetVal <> TargetNode.GetAttribute(Key) then
    begin
      NeedFree := True;
    end;
    if not MatchValue(PatternVal, TargetVal, Match) then
    begin
      if NeedFree then
      begin
        TargetVal.Free;
      end;
      Exit(False);
    end;
    if NeedFree then
    begin
      TargetVal.Free;
    end;
  end;
  Result := True;
end;

function TGrispPatternMatcher.MatchValue(PatternValue: TGValue; TargetValue: TGValue; Match: TMatchResult): Boolean;
var
  IdStr: string;
  BoundNode: TGNode;
  BoundValue: TGValue;
  TargetNodeRef: TGNode;
  I: Integer;
begin
  if (PatternValue = nil) or (TargetValue = nil) then
  begin
    Exit((PatternValue = nil) and (TargetValue = nil));
  end;
  if PatternValue.Kind <> TargetValue.Kind then
  begin
    if (PatternValue.Kind = vkIdentifier) and IsVariable(PatternValue.IdentifierValue) and FPatternVariables.Contains(PatternValue.IdentifierValue) and (TargetValue.Kind = vkNode) then
    begin
      IdStr := PatternValue.IdentifierValue;
      TargetNodeRef := TargetValue.NodeValue;
      if TargetNodeRef = nil then
      begin
        Exit(False);
      end;
      if Match.TryGetNode(IdStr, BoundNode) then
      begin
        Exit(BoundNode = TargetNodeRef);
      end
      else
      begin
        Match.AddNodeBinding(IdStr, TargetNodeRef);
        Exit(True);
      end;
    end;
    Exit(False);
  end;
  case PatternValue.Kind of
    vkNumber:
      begin
        Result := PatternValue.NumberValue = TargetValue.NumberValue;
      end;
    vkString:
      begin
        Result := PatternValue.StringValue = TargetValue.StringValue;
      end;
    vkBoolean:
      begin
        Result := PatternValue.BoolValue = TargetValue.BoolValue;
      end;
    vkIdentifier:
      begin
        IdStr := PatternValue.IdentifierValue;
        if not IsVariable(IdStr) then
        begin
          Result := IdStr = TargetValue.IdentifierValue;
        end
        else
        begin
          if FPatternVariables.Contains(IdStr) then
          begin
            TargetNodeRef := FGraph.FindNode(TargetValue.IdentifierValue);
            if TargetNodeRef = nil then
            begin
              Exit(False);
            end;
            if Match.TryGetNode(IdStr, BoundNode) then
            begin
              Result := BoundNode = TargetNodeRef;
            end
            else
            begin
              Match.AddNodeBinding(IdStr, TargetNodeRef);
              Result := True;
            end;
          end
          else
          begin
            if Match.TryGetValue(IdStr, BoundValue) then
            begin
              Result := ValuesEqual(BoundValue, TargetValue);
            end
            else
            begin
              Match.AddValueBinding(IdStr, TargetValue);
              Result := True;
            end;
          end;
        end;
      end;
    vkArray:
      begin
        if PatternValue.ArrayValue.Count <> TargetValue.ArrayValue.Count then
        begin
          Exit(False);
        end;
        for I := 0 to PatternValue.ArrayValue.Count - 1 do
        begin
          if not MatchValue(PatternValue.ArrayValue[I], TargetValue.ArrayValue[I], Match) then
          begin
            Exit(False);
          end;
        end;
        Result := True;
      end;
    vkNode:
      begin
        Result := MatchNodeConstraints(PatternValue.NodeValue, TargetValue.NodeValue, Match);
      end;
  else
    begin
      Result := False;
    end;
  end;
end;

function TGrispPatternMatcher.Search(VarIndex: Integer; Match: TMatchResult): Boolean;
var
  VarInfo: TNodeVarInfo;
  Candidate: TGNode;
  SavedNodeCount: Integer;
  SavedValueCount: Integer;
  AlreadyBound: TGNode;
  NodeBoundToOther: Boolean;
  B: TNodeBinding;
begin
  if VarIndex >= FNodeVars.Count then
  begin
    Exit(True);
  end;
  VarInfo := FNodeVars[VarIndex];
  if (VarInfo.VarName <> '') and Match.TryGetNode(VarInfo.VarName, AlreadyBound) then
  begin
    SavedNodeCount := Match.NodeBindings.Count;
    SavedValueCount := Match.ValueBindings.Count;
    if MatchNodeConstraints(VarInfo.PatternNode, AlreadyBound, Match) then
    begin
      if Search(VarIndex + 1, Match) then
      begin
        Exit(True);
      end;
    end;
    Match.NodeBindings.Count := SavedNodeCount;
    Match.ValueBindings.Count := SavedValueCount;
    Exit(False);
  end;
  for Candidate in FGraph.Nodes do
  begin
    NodeBoundToOther := False;
    for B in Match.NodeBindings do
    begin
      if B.Node = Candidate then
      begin
        NodeBoundToOther := True;
        Break;
      end;
    end;
    if NodeBoundToOther then
    begin
      Continue;
    end;
    SavedNodeCount := Match.NodeBindings.Count;
    SavedValueCount := Match.ValueBindings.Count;
    if VarInfo.VarName <> '' then
    begin
      Match.AddNodeBinding(VarInfo.VarName, Candidate);
    end;
    if MatchNodeConstraints(VarInfo.PatternNode, Candidate, Match) then
    begin
      if Search(VarIndex + 1, Match) then
      begin
        Exit(True);
      end;
    end;
    Match.NodeBindings.Count := SavedNodeCount;
    Match.ValueBindings.Count := SavedValueCount;
  end;
  Result := False;
end;

function TGrispPatternMatcher.HasWhere(PatternRoot: TGNode): Boolean;
var
  V: TGValue;
begin
  V := PatternRoot.GetAttribute('where');
  Result := Assigned(V) and (V.Kind = vkExpression);
end;

function TGrispPatternMatcher.EvalWhere(PatternRoot: TGNode; Match: TMatchResult): Boolean;
var
  V: TGValue;
  Bindings: TDictionary<string, TGValue>;
  Res: TGValue;
  B: TValueBinding;
begin
  Result := True;
  V := PatternRoot.GetAttribute('where');
  if not Assigned(V) then
  begin
    Exit;
  end;
  if V.Kind <> vkExpression then
  begin
    Exit;
  end;
  Bindings := TDictionary<string, TGValue>.Create;
  try
    for B in Match.ValueBindings do
    begin
      Bindings.Add(B.Name, B.Value);
    end;
    Res := TGrispExpressionEvaluator.Evaluate(V.ExpressionValue, Bindings);
    try
      Result := Assigned(Res) and (Res.Kind = vkBoolean) and Res.BoolValue;
    finally
      Res.Free;
    end;
  finally
    Bindings.Free;
  end;
end;

function TGrispPatternMatcher.MatchPattern(PatternRoot: TGNode): TMatchResult;
var
  Key: string;
  Val: TGValue;
  HasNodeVars: Boolean;
  VarInfo: TNodeVarInfo;
begin
  Result := TMatchResult.Create;
  FPatternVariables.Clear;
  FNodeVars.Clear;
  if PatternRoot = nil then
  begin
    Result.Success := False;
    Exit;
  end;
  HasNodeVars := False;
  for Key in PatternRoot.Attributes.Keys do
  begin
    Val := PatternRoot.GetAttribute(Key);
    if (Val <> nil) and (Val.Kind = vkNode) then
    begin
      HasNodeVars := True;
      FPatternVariables.Add(Key);
      VarInfo.VarName := Key;
      VarInfo.PatternNode := Val.NodeValue;
      FNodeVars.Add(VarInfo);
    end;
  end;
  if not HasNodeVars then
  begin
    VarInfo.VarName := '';
    VarInfo.PatternNode := PatternRoot;
    FNodeVars.Add(VarInfo);
  end;
  if Search(0, Result) then
  begin
    if HasWhere(PatternRoot) then
    begin
      Result.Success := EvalWhere(PatternRoot, Result);
    end
    else
    begin
      Result.Success := True;
    end;
  end;
end;

end.
