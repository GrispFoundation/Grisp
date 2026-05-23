unit unit_GrispPattern_version_001;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  unit_GrispGraph_version_001;

type
  TNodeBinding = record
    Name: string;   // Variable name in pattern, e.g. 'X'
    Node: TGNode;   // Matched node in graph
  end;

  TValueBinding = record
    Name: string;   // Variable name in pattern, e.g. 'x'
    Value: TGValue; // Matched value in graph
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

    function IsLiteralIdentifier(const S: string): Boolean;
    function IsVariable(const AIdentifier: string): Boolean;
    function ValuesEqual(Val1, Val2: TGValue): Boolean;

    function MatchNodeConstraints(PatternNode, TargetNode: TGNode; Match: TMatchResult): Boolean;
    function MatchValue(PatternValue, TargetValue: TGValue; Match: TMatchResult): Boolean;
    function Search(VarIndex: Integer; Match: TMatchResult): Boolean;
  public
    constructor Create(AGraph: TGGraph);
    destructor Destroy; override;

    // Try to match the pattern rooted at PatternRoot somewhere in the graph.
    // Returns a TMatchResult (Success = True if matched).
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
  inherited;
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
  inherited;
end;

function TGrispPatternMatcher.IsLiteralIdentifier(const S: string): Boolean;
begin
  Result := (S = 'add') or (S = 'sub') or (S = 'mul') or (S = 'div') or
            (S = 'simplify') or (S = 'tool') or (S = 'call') or (S = 'result') or
            (S = 'returns') or (S = 'value') or (S = 'left') or (S = 'right') or
            (S = 'next') or (S = 'op') or (S = 'node') or (S = 'array') or
            (S = 'number') or (S = 'string') or (S = 'boolean') or (S = 'identifier') or
            (S = 'true') or (S = 'false') or (S = 'nil') or (S = 'null');
end;

function TGrispPatternMatcher.IsVariable(const AIdentifier: string): Boolean;
var
  C: Char;
begin
  // Rule 1: Any attribute key in the pattern root is a variable name.
  if FPatternVariables.Contains(AIdentifier) then
    Exit(True);

  // Rule 2: Any identifier value that is not a literal and not a node name is a variable.
  if IsLiteralIdentifier(AIdentifier) then
    Exit(False);

  if Assigned(FGraph) and (FGraph.FindNode(AIdentifier) <> nil) then
    Exit(False);

  if Length(AIdentifier) > 0 then
  begin
    C := AIdentifier[1];
    if ((C >= 'a') and (C <= 'z')) or ((C >= 'A') and (C <= 'Z')) then
      Exit(True);
  end;

  Result := False;
end;

function TGrispPatternMatcher.ValuesEqual(Val1, Val2: TGValue): Boolean;
var
  I: Integer;
begin
  if (Val1 = nil) or (Val2 = nil) then
    Exit((Val1 = nil) and (Val2 = nil));

  if Val1.Kind <> Val2.Kind then
    Exit(False);

  case Val1.Kind of
    vkNumber:
      Result := Val1.NumberValue = Val2.NumberValue;
    vkString:
      Result := Val1.StringValue = Val2.StringValue;
    vkBoolean:
      Result := Val1.BoolValue = Val2.BoolValue;
    vkIdentifier:
      Result := Val1.IdentifierValue = Val2.IdentifierValue;
    vkArray:
      begin
        if Val1.ArrayValue.Count <> Val2.ArrayValue.Count then
          Exit(False);
        for I := 0 to Val1.ArrayValue.Count - 1 do
        begin
          if not ValuesEqual(Val1.ArrayValue[I], Val2.ArrayValue[I]) then
            Exit(False);
        end;
        Result := True;
      end;
    vkNode:
      Result := Val1.NodeValue = Val2.NodeValue;
  else
    Result := False;
  end;
end;

function TGrispPatternMatcher.MatchNodeConstraints(PatternNode, TargetNode: TGNode; Match: TMatchResult): Boolean;
var
  Key: string;
  PatternVal, TargetVal: TGValue;
begin
  if (PatternNode = nil) or (TargetNode = nil) then
    Exit((PatternNode = nil) and (TargetNode = nil));

  for Key in PatternNode.Attributes.Keys do
  begin
    PatternVal := PatternNode.GetAttribute(Key);
    TargetVal := TargetNode.GetAttribute(Key);

    if TargetVal = nil then
      Exit(False);

    if not MatchValue(PatternVal, TargetVal, Match) then
      Exit(False);
  end;

  Result := True;
end;

function TGrispPatternMatcher.MatchValue(PatternValue, TargetValue: TGValue; Match: TMatchResult): Boolean;
var
  IdStr: string;
  BoundNode: TGNode;
  BoundValue: TGValue;
  TargetNodeRef: TGNode;
  I: Integer;
begin
  if (PatternValue = nil) or (TargetValue = nil) then
    Exit((PatternValue = nil) and (TargetValue = nil));

  if PatternValue.Kind <> TargetValue.Kind then
  begin
    // Special case: Node variable matched against an inline vkNode target attribute
    if (PatternValue.Kind = vkIdentifier) and IsVariable(PatternValue.IdentifierValue) and
       FPatternVariables.Contains(PatternValue.IdentifierValue) and (TargetValue.Kind = vkNode) then
    begin
      IdStr := PatternValue.IdentifierValue;
      TargetNodeRef := TargetValue.NodeValue;
      if TargetNodeRef = nil then
        Exit(False);

      if Match.TryGetNode(IdStr, BoundNode) then
        Exit(BoundNode = TargetNodeRef)
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
      Result := PatternValue.NumberValue = TargetValue.NumberValue;

    vkString:
      Result := PatternValue.StringValue = TargetValue.StringValue;

    vkBoolean:
      Result := PatternValue.BoolValue = TargetValue.BoolValue;

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
              Exit(False);

            if Match.TryGetNode(IdStr, BoundNode) then
              Result := (BoundNode = TargetNodeRef)
            else
            begin
              Match.AddNodeBinding(IdStr, TargetNodeRef);
              Result := True;
            end;
          end
          else
          begin
            if Match.TryGetValue(IdStr, BoundValue) then
              Result := ValuesEqual(BoundValue, TargetValue)
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
          Exit(False);
        for I := 0 to PatternValue.ArrayValue.Count - 1 do
        begin
          if not MatchValue(PatternValue.ArrayValue[I], TargetValue.ArrayValue[I], Match) then
            Exit(False);
        end;
        Result := True;
      end;

    vkNode:
      begin
        Result := MatchNodeConstraints(PatternValue.NodeValue, TargetValue.NodeValue, Match);
      end;
  else
    Result := False;
  end;
end;

function TGrispPatternMatcher.Search(VarIndex: Integer; Match: TMatchResult): Boolean;
var
  VarInfo: TNodeVarInfo;
  Candidate: TGNode;
  SavedNodeCount, SavedValueCount: Integer;
  AlreadyBound: TGNode;
  NodeBoundToOther: Boolean;
  B: TNodeBinding;
begin
  if VarIndex >= FNodeVars.Count then
    Exit(True);

  VarInfo := FNodeVars[VarIndex];

  if (VarInfo.VarName <> '') and Match.TryGetNode(VarInfo.VarName, AlreadyBound) then
  begin
    SavedNodeCount := Match.NodeBindings.Count;
    SavedValueCount := Match.ValueBindings.Count;

    if MatchNodeConstraints(VarInfo.PatternNode, AlreadyBound, Match) then
    begin
      if Search(VarIndex + 1, Match) then
        Exit(True);
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
      Continue;

    SavedNodeCount := Match.NodeBindings.Count;
    SavedValueCount := Match.ValueBindings.Count;

    if VarInfo.VarName <> '' then
      Match.AddNodeBinding(VarInfo.VarName, Candidate);

    if MatchNodeConstraints(VarInfo.PatternNode, Candidate, Match) then
    begin
      if Search(VarIndex + 1, Match) then
        Exit(True);
    end;

    Match.NodeBindings.Count := SavedNodeCount;
    Match.ValueBindings.Count := SavedValueCount;
  end;

  Result := False;
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
    Result.Success := True
  else
    Result.Success := False;
end;

end.
