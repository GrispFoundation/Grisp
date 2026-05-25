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
    FCurrentRule: TGNode;
    FTraceEnabled: Boolean;
    procedure Trace(const Msg: string; Depth: Integer);
    function IsVariable(const AIdentifier: string): Boolean;
    function ValuesEqual(Val1: TGValue; Val2: TGValue): Boolean;
    function GetNodeAttrOrEdge(TargetNode: TGNode; const Key: string; out OutVal: TGValue): Boolean;
    function MatchNodeConstraints(PatternNode: TGNode; TargetNode: TGNode; Match: TMatchResult): Boolean;
    function MatchValue(PatternValue: TGValue; TargetValue: TGValue; Match: TMatchResult): Boolean;
    function CheckPatternEdges(PatternNode: TGNode; TargetNode: TGNode; const PartialMatch: TMatchResult): Boolean;
    function Search(VarIndex: Integer; Match: TMatchResult): Boolean;
    function HasWhere: Boolean;
    function EvalWhere(Match: TMatchResult): Boolean;
    procedure CollectVariables(Node: TGNode);
  public
    constructor Create(AGraph: TGGraph);
    destructor Destroy; override;
    procedure SetCurrentRule(Rule: TGNode);
    property TraceEnabled: Boolean read FTraceEnabled write FTraceEnabled;
    function MatchPattern(PatternRoot: TGNode): TMatchResult;
    function FindAllMatches(PatternRoot: TGNode): TList<TMatchResult>;
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
var B: TNodeBinding;
begin
  B.Name := AName;
  B.Node := ANode;
  NodeBindings.Add(B);
end;

procedure TMatchResult.AddValueBinding(const AName: string; AValue: TGValue);
var B: TValueBinding;
begin
  B.Name := AName;
  B.Value := AValue;
  ValueBindings.Add(B);
end;

function TMatchResult.TryGetNode(const AName: string; out ANode: TGNode): Boolean;
var B: TNodeBinding;
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

function TMatchResult.TryGetValue(const AName: string; out AValue: TGValue): Boolean;
var B: TValueBinding;
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

procedure TGrispPatternMatcher.SetCurrentRule(Rule: TGNode);
begin
  FCurrentRule := Rule;
end;

procedure TGrispPatternMatcher.Trace(const Msg: string; Depth: Integer);
begin
  if not FTraceEnabled then Exit;
  Writeln(StringOfChar(' ', Depth * 2) + Msg);
end;

function TGrispPatternMatcher.IsVariable(const AIdentifier: string): Boolean;
begin
  Result := (Length(AIdentifier) = 1) and CharInSet(AIdentifier[1], ['A'..'Z']) or
            (Length(AIdentifier) >= 2) and (AIdentifier[1] = 'V') and CharInSet(AIdentifier[2], ['A'..'Z']);
end;

function TGrispPatternMatcher.ValuesEqual(Val1: TGValue; Val2: TGValue): Boolean;
var I: Integer;
begin
  if (Val1 = nil) or (Val2 = nil) then Exit((Val1 = nil) and (Val2 = nil));
  if Val1.Kind <> Val2.Kind then Exit(False);
  case Val1.Kind of
    vkNumber: Result := Val1.NumberValue = Val2.NumberValue;
    vkString: Result := Val1.StringValue = Val2.StringValue;
    vkBoolean: Result := Val1.BoolValue = Val2.BoolValue;
    vkIdentifier: Result := Val1.IdentifierValue = Val2.IdentifierValue;
    vkArray:
      begin
        if Val1.ArrayValue.Count <> Val2.ArrayValue.Count then Exit(False);
        for I := 0 to Val1.ArrayValue.Count - 1 do
          if not ValuesEqual(Val1.ArrayValue[I], Val2.ArrayValue[I]) then Exit(False);
        Result := True;
      end;
    vkNode: Result := Val1.NodeValue = Val2.NodeValue;
  else
    Result := False;
  end;
end;

function TGrispPatternMatcher.GetNodeAttrOrEdge(TargetNode: TGNode; const Key: string; out OutVal: TGValue): Boolean;
var Edge: TGEdge;
begin
  OutVal := TargetNode.GetAttribute(Key);
  if OutVal <> nil then Exit(True);
  for Edge in TargetNode.Outgoing do
    if SameText(Edge.LabelName, Key) then
    begin
      OutVal := TGValue.Create(vkIdentifier);
      OutVal.IdentifierValue := Edge.Target.Name;
      Exit(True);
    end;
  OutVal := nil;
  Result := False;
end;

function TGrispPatternMatcher.MatchNodeConstraints(PatternNode: TGNode; TargetNode: TGNode; Match: TMatchResult): Boolean;
var
  Key: string;
  PatternVal, TargetVal: TGValue;
  NeedFree: Boolean;
  Edge: TGEdge;
  FoundEdge: Boolean;
begin
  if (PatternNode = nil) or (TargetNode = nil) then Exit(False);

  for Key in PatternNode.Attributes.Keys do
  begin
    PatternVal := PatternNode.GetAttribute(Key);
    NeedFree := False;

    if (Key = 'next') then
    begin
      FoundEdge := False;
      for Edge in TargetNode.Outgoing do
      begin
        if SameText(Edge.LabelName, 'next') then
        begin
          TargetVal := TGValue.Create(vkIdentifier);
          TargetVal.IdentifierValue := Edge.Target.Name;
          NeedFree := True;
          FoundEdge := True;
          Break;
        end;
      end;

      if not FoundEdge then
      begin
        if not GetNodeAttrOrEdge(TargetNode, Key, TargetVal) then
          Exit(False);
        if TargetVal <> TargetNode.GetAttribute(Key) then
          NeedFree := True;
      end;
    end
    else
    begin
      if not GetNodeAttrOrEdge(TargetNode, Key, TargetVal) then
        Exit(False);
      if TargetVal <> TargetNode.GetAttribute(Key) then
        NeedFree := True;
    end;

    if not MatchValue(PatternVal, TargetVal, Match) then
    begin
      if NeedFree then TargetVal.Free;
	  Exit(False);
    end;

    if NeedFree then TargetVal.Free;
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
  Result := False;

  if (PatternValue = nil) or (TargetValue = nil) then
    Exit((PatternValue = nil) and (TargetValue = nil));

  // Handle pattern identifier (variable or literal)
  if (PatternValue.Kind = vkIdentifier) then
  begin
    IdStr := PatternValue.IdentifierValue;

    // Node variable (single uppercase letter like X, Y)
    if (Length(IdStr) = 1) and CharInSet(IdStr[1], ['A'..'Z']) then
    begin
      // Target should be a node (either as identifier or node value)
      if TargetValue.Kind = vkIdentifier then
      begin
        TargetNodeRef := FGraph.FindNode(TargetValue.IdentifierValue);
        if TargetNodeRef = nil then Exit(False);
        if Match.TryGetNode(IdStr, BoundNode) then
          Exit(BoundNode = TargetNodeRef);
        Match.AddNodeBinding(IdStr, TargetNodeRef);
        Exit(True);
      end
      else if TargetValue.Kind = vkNode then
      begin
        TargetNodeRef := TargetValue.NodeValue;
        if TargetNodeRef = nil then Exit(False);
        if Match.TryGetNode(IdStr, BoundNode) then
          Exit(BoundNode = TargetNodeRef);
        Match.AddNodeBinding(IdStr, TargetNodeRef);
        Exit(True);
      end
      else
        Exit(False);
    end

    // Value variable (starts with V followed by uppercase, like VX, VY)
    else if (Length(IdStr) >= 2) and (IdStr[1] = 'V') and CharInSet(IdStr[2], ['A'..'Z']) then
    begin
      // Check if this variable is already bound
      if Match.TryGetValue(IdStr, BoundValue) then
      begin
        // Already bound - verify equality
        Result := ValuesEqual(BoundValue, TargetValue);
        Exit;
      end
      else
      begin
        // Not bound yet - bind it if target is a number or boolean
        if (TargetValue.Kind = vkNumber) or (TargetValue.Kind = vkBoolean) then
        begin
          Match.AddValueBinding(IdStr, TargetValue.Clone);
          Result := True;
          Exit;
        end
        else
        begin
          // Value variable cannot bind to non-number/boolean
          Exit(False);
        end;
      end;
    end

    // Literal identifier (not a variable)
    else
    begin
      if TargetValue.Kind = vkIdentifier then
        Result := IdStr = TargetValue.IdentifierValue
      else
        Result := False;
      Exit;
    end;
  end;

  // Pattern is not an identifier - compare kinds
  if PatternValue.Kind <> TargetValue.Kind then
    Exit(False);

  // Compare based on kind
  case PatternValue.Kind of
    vkNumber:
      Result := PatternValue.NumberValue = TargetValue.NumberValue;

    vkString:
      Result := PatternValue.StringValue = TargetValue.StringValue;

    vkBoolean:
      Result := PatternValue.BoolValue = TargetValue.BoolValue;

    vkIdentifier:
      Result := PatternValue.IdentifierValue = TargetValue.IdentifierValue;

    vkArray:
      begin
        if PatternValue.ArrayValue.Count <> TargetValue.ArrayValue.Count then
          Exit(False);
        for I := 0 to PatternValue.ArrayValue.Count - 1 do
          if not MatchValue(PatternValue.ArrayValue[I], TargetValue.ArrayValue[I], Match) then
            Exit(False);
        Result := True;
      end;

    vkNode:
      Result := MatchNodeConstraints(PatternValue.NodeValue, TargetValue.NodeValue, Match);

    vkExpression:
      Result := False;  // Expressions are not directly comparable
  end;
end;

function TGrispPatternMatcher.CheckPatternEdges(PatternNode: TGNode; TargetNode: TGNode; const PartialMatch: TMatchResult): Boolean;
var Key: string; PatVal: TGValue; TargetVar: string; TargetHN: TGNode; Edge: TGEdge; Found: Boolean;
begin
  Result := True;
  for Key in PatternNode.Attributes.Keys do
  begin
    PatVal := PatternNode.GetAttribute(Key);
    if (PatVal = nil) or (PatVal.Kind <> vkIdentifier) then Continue;
    TargetVar := PatVal.IdentifierValue;
    if not FPatternVariables.Contains(TargetVar) then Continue;
    if not PartialMatch.TryGetNode(TargetVar, TargetHN) then Continue;
    Found := False;
    for Edge in TargetNode.Outgoing do
      if SameText(Edge.LabelName, Key) and (Edge.Target = TargetHN) then
      begin
        Found := True;
        Break;
      end;
    if not Found then
    begin
      Trace(Format('Missing edge %s --%s--> %s', [TargetNode.Name, Key, TargetHN.Name]), FNodeVars.Count);
      Exit(False);
    end;
  end;
end;

function TGrispPatternMatcher.Search(VarIndex: Integer; Match: TMatchResult): Boolean;
var VarInfo: TNodeVarInfo; Candidate: TGNode; SavedNodeCount, SavedValueCount: Integer;
    AlreadyBound: TGNode; NodeBoundToOther: Boolean; B: TNodeBinding;
begin
  if VarIndex >= FNodeVars.Count then Exit(True);

  VarInfo := FNodeVars[VarIndex];
  Trace(Format('Search[%d] var=%s', [VarIndex, VarInfo.VarName]), VarIndex);

  if (VarInfo.VarName <> '') and Match.TryGetNode(VarInfo.VarName, AlreadyBound) then
  begin
    SavedNodeCount := Match.NodeBindings.Count;
    SavedValueCount := Match.ValueBindings.Count;
    if MatchNodeConstraints(VarInfo.PatternNode, AlreadyBound, Match) and
       CheckPatternEdges(VarInfo.PatternNode, AlreadyBound, Match) then
    begin
      if Search(VarIndex + 1, Match) then Exit(True);
    end;
    Match.NodeBindings.Count := SavedNodeCount;
    Match.ValueBindings.Count := SavedValueCount;
    Exit(False);
  end;

  for Candidate in FGraph.Nodes do
  begin
    NodeBoundToOther := False;
    for B in Match.NodeBindings do
      if B.Node = Candidate then begin NodeBoundToOther := True; Break; end;
    if NodeBoundToOther then Continue;

    SavedNodeCount := Match.NodeBindings.Count;
    SavedValueCount := Match.ValueBindings.Count;

    if VarInfo.VarName <> '' then Match.AddNodeBinding(VarInfo.VarName, Candidate);

    Trace(Format('Try %s -> %s', [VarInfo.VarName, Candidate.Name]), VarIndex);

    if MatchNodeConstraints(VarInfo.PatternNode, Candidate, Match) then
    begin
      Trace(' constraints ok', VarIndex);
      if CheckPatternEdges(VarInfo.PatternNode, Candidate, Match) then
      begin
        Trace(' edges ok', VarIndex);
        if Search(VarIndex + 1, Match) then Exit(True);
      end
      else Trace(' edges fail', VarIndex);
    end
    else Trace(' constraints fail', VarIndex);

    Match.NodeBindings.Count := SavedNodeCount;
    Match.ValueBindings.Count := SavedValueCount;
  end;
  Result := False;
end;

function TGrispPatternMatcher.HasWhere: Boolean;
var V: TGValue;
begin
  Result := Assigned(FCurrentRule) and FCurrentRule.Attributes.TryGetValue('where', V) and (V.Kind = vkExpression);
end;

function TGrispPatternMatcher.EvalWhere(Match: TMatchResult): Boolean;
var
  V: TGValue;
  Bindings: TDictionary<string, TGValue>;
  Res: TGValue;
  B: TValueBinding;
  BNode: TNodeBinding;
  Pair: TPair<string, TGValue>;
begin
  Result := True;
  if not Assigned(FCurrentRule) then Exit;
  if not FCurrentRule.Attributes.TryGetValue('where', V) then Exit;
  if V.Kind <> vkExpression then Exit;

  Bindings := TDictionary<string, TGValue>.Create;
  try
    // Add value bindings (VX, VY, etc.) - these are numbers
    for B in Match.ValueBindings do
    begin
      if Assigned(B.Value) then
        Bindings.Add(B.Name, B.Value.Clone)
      else
        Bindings.Add(B.Name, TGValue.Create(vkNumber));
    end;

    // Add node bindings as identifiers for WHERE clause
    for BNode in Match.NodeBindings do
    begin
      if Assigned(BNode.Node) then
      begin
        var NodeVal := TGValue.Create(vkIdentifier);
        NodeVal.IdentifierValue := BNode.Node.Name;
        Bindings.Add(BNode.Name, NodeVal);
      end;
    end;

    // Debug output (uncomment to debug)
    // Writeln('EvalWhere: Expression = ', V.ExpressionValue.Name);
    // for Pair in Bindings do
    //   Writeln('  Binding: ', Pair.Key, ' = ', Pair.Value.ToString);

    Res := TGrispExpressionEvaluator.Evaluate(V.ExpressionValue, Bindings);
    try
      if Assigned(Res) then
      begin
        Result := (Res.Kind = vkBoolean) and Res.BoolValue;
        // Writeln('EvalWhere result = ', BoolToStr(Result, True));
      end
      else
        Result := False;
    finally
      Res.Free;
    end;
  finally
    for Pair in Bindings do
      Pair.Value.Free;
    Bindings.Free;
  end;
end;

procedure TGrispPatternMatcher.CollectVariables(Node: TGNode);
var
  K: string;
  V: TGValue;
  VarInfo: TNodeVarInfo;
begin
  if Node = nil then Exit;

  for K in Node.Attributes.Keys do
  begin
    V := Node.GetAttribute(K);
    if (V <> nil) and (V.Kind = vkNode) then
    begin
      if IsVariable(K) then
      begin
        VarInfo.VarName := K;
        VarInfo.PatternNode := V.NodeValue;
        FNodeVars.Add(VarInfo);
        FPatternVariables.Add(K);
      end;
      CollectVariables(V.NodeValue);
    end
    else if (V <> nil) and (V.Kind = vkIdentifier) then
    begin
      if IsVariable(V.IdentifierValue) then
      begin
        FPatternVariables.Add(V.IdentifierValue);
      end;
    end;
  end;
end;

function TGrispPatternMatcher.MatchPattern(PatternRoot: TGNode): TMatchResult;
var
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

  CollectVariables(PatternRoot);

  if FNodeVars.Count = 0 then
  begin
    VarInfo.VarName := '';
    VarInfo.PatternNode := PatternRoot;
    FNodeVars.Add(VarInfo);
  end;

  if Search(0, Result) then
  begin
    if HasWhere then
      Result.Success := EvalWhere(Result)
    else
      Result.Success := True;
  end
  else
	Result.Success := False;
end;

function TGrispPatternMatcher.FindAllMatches(PatternRoot: TGNode): TList<TMatchResult>;
var
  ResultList: TList<TMatchResult>;
  TempMatch: TMatchResult;
  VarInfo: TNodeVarInfo;

  procedure SearchAll(VarIndex: Integer; CurrentMatch: TMatchResult);
  var
    VI: TNodeVarInfo;
    Candidate: TGNode;
    SavedNodeCount, SavedValueCount: Integer;
    NodeBoundToOther: Boolean;
    BNode: TNodeBinding;
    BValue: TValueBinding;
    NewMatch: TMatchResult;
  begin
    if VarIndex >= FNodeVars.Count then
    begin
      // Found a complete match
      if HasWhere then
      begin
        if EvalWhere(CurrentMatch) then
        begin
          NewMatch := TMatchResult.Create;
          NewMatch.Success := True;
          for BNode in CurrentMatch.NodeBindings do
            NewMatch.AddNodeBinding(BNode.Name, BNode.Node);
          for BValue in CurrentMatch.ValueBindings do
            NewMatch.AddValueBinding(BValue.Name, BValue.Value.Clone);
          ResultList.Add(NewMatch);
        end;
      end
      else
      begin
        NewMatch := TMatchResult.Create;
        NewMatch.Success := True;
        for BNode in CurrentMatch.NodeBindings do
          NewMatch.AddNodeBinding(BNode.Name, BNode.Node);
        for BValue in CurrentMatch.ValueBindings do
          NewMatch.AddValueBinding(BValue.Name, BValue.Value.Clone);
        ResultList.Add(NewMatch);
      end;
      Exit;
    end;

    VI := FNodeVars[VarIndex];

    if (VI.VarName <> '') and CurrentMatch.TryGetNode(VI.VarName, Candidate) then
    begin
      SavedNodeCount := CurrentMatch.NodeBindings.Count;
      SavedValueCount := CurrentMatch.ValueBindings.Count;
      if MatchNodeConstraints(VI.PatternNode, Candidate, CurrentMatch) and
         CheckPatternEdges(VI.PatternNode, Candidate, CurrentMatch) then
      begin
        SearchAll(VarIndex + 1, CurrentMatch);
      end;
      CurrentMatch.NodeBindings.Count := SavedNodeCount;
      CurrentMatch.ValueBindings.Count := SavedValueCount;
      Exit;
    end;

    for Candidate in FGraph.Nodes do
    begin
      NodeBoundToOther := False;
      for BNode in CurrentMatch.NodeBindings do
        if BNode.Node = Candidate then
        begin
          NodeBoundToOther := True;
          Break;
        end;
      if NodeBoundToOther then Continue;

      SavedNodeCount := CurrentMatch.NodeBindings.Count;
      SavedValueCount := CurrentMatch.ValueBindings.Count;

      if VI.VarName <> '' then
        CurrentMatch.AddNodeBinding(VI.VarName, Candidate);

      if MatchNodeConstraints(VI.PatternNode, Candidate, CurrentMatch) then
      begin
        if CheckPatternEdges(VI.PatternNode, Candidate, CurrentMatch) then
        begin
          SearchAll(VarIndex + 1, CurrentMatch);
        end;
      end;

      CurrentMatch.NodeBindings.Count := SavedNodeCount;
      CurrentMatch.ValueBindings.Count := SavedValueCount;
    end;
  end;

begin
  ResultList := TList<TMatchResult>.Create;
  Result := ResultList;

  FPatternVariables.Clear;
  FNodeVars.Clear;

  if PatternRoot = nil then
    Exit;

  CollectVariables(PatternRoot);

  if FNodeVars.Count = 0 then
  begin
    VarInfo.VarName := '';
    VarInfo.PatternNode := PatternRoot;
    FNodeVars.Add(VarInfo);
  end;

  TempMatch := TMatchResult.Create;
  try
    SearchAll(0, TempMatch);
  finally
    TempMatch.Free;
  end;
end;

end.
