unit unit_Pattern_TGrispPatternMatcher_version_001;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  unit_Graph_TGrispGraph_version_001,
  unit_Graph_TGrispEdge_TGrispNode_version_001,
  unit_Core_TGrispValueBase_version_001,
  unit_Core_TGrispExpressionEvaluator_version_001,
  unit_Core_TGrispExpression_version_001,
  unit_Pattern_TGrispMatchResult_version_001,
  unit_Pattern_TGrispNodeVarInfo_version_001,
  unit_Pattern_TGrispNodeBinding_version_001,
  unit_Pattern_TGrispValueBinding_version_001;

type
  TGrispPatternMatcher = class
  private
    FGraph: TGrispGraph;
    FPatternVariables: THashSet<string>;
    FNodeVars: TList<TGrispNodeVarInfo>;
    FCurrentRule: TGrispNode;
    FTraceEnabled: Boolean;
    FCurrentPhase: Integer;
    procedure Trace(const Msg: string; Depth: Integer);
    function IsVariable(const AIdentifier: string): Boolean;
    function ValuesEqual(Val1: TGrispValue; Val2: TGrispValue): Boolean;
    function GetNodeAttrOrEdge(TargetNode: TGrispNode; const Key: string; out OutVal: TGrispValue): Boolean;
    function MatchNodeConstraints(PatternNode: TGrispNode; TargetNode: TGrispNode; Match: TGrispMatchResult): Boolean;
    function MatchValue(PatternValue: TGrispValue; TargetValue: TGrispValue; Match: TGrispMatchResult): Boolean;
    function CheckPatternEdges(PatternNode: TGrispNode; TargetNode: TGrispNode; const PartialMatch: TGrispMatchResult): Boolean;
    function Search(VarIndex: Integer; Match: TGrispMatchResult): Boolean;
    function HasWhere: Boolean;
    function EvalWhere(Match: TGrispMatchResult): Boolean;
    procedure CollectVariables(Node: TGrispNode; IsTempPattern: Boolean = False);
    function GetAttributeKeys(Node: TGrispNode): TList<string>;
  public
    constructor Create(AGraph: TGrispGraph);
    destructor Destroy; override;
    procedure SetCurrentRule(Rule: TGrispNode);
    procedure SetPhase(Phase: Integer);
    property TraceEnabled: Boolean read FTraceEnabled write FTraceEnabled;
    property CurrentPhase: Integer read FCurrentPhase;
    function MatchPattern(PatternRoot: TGrispNode): TGrispMatchResult;
    function FindAllMatches(PatternRoot: TGrispNode): TList<TGrispMatchResult>;
  end;

implementation

constructor TGrispPatternMatcher.Create(AGraph: TGrispGraph);
begin
  inherited Create;
  FGraph := AGraph;
  FPatternVariables := THashSet<string>.Create;
  FNodeVars := TList<TGrispNodeVarInfo>.Create;
  FCurrentPhase := 1;
end;

destructor TGrispPatternMatcher.Destroy;
begin
  FNodeVars.Free;
  FPatternVariables.Free;
  inherited Destroy;
end;

procedure TGrispPatternMatcher.SetCurrentRule(Rule: TGrispNode);
begin
  FCurrentRule := Rule;
end;

procedure TGrispPatternMatcher.SetPhase(Phase: Integer);
begin
  FCurrentPhase := Phase;
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

function TGrispPatternMatcher.GetAttributeKeys(Node: TGrispNode): TList<string>;
begin
  Result := TList<string>.Create;
  if Node.HasAttribute('value') then Result.Add('value');
  if Node.HasAttribute('next') then Result.Add('next');
  if Node.HasAttribute('name') then Result.Add('name');
  if Node.HasAttribute('mark') then Result.Add('mark');
  if Node.HasAttribute('phase') then Result.Add('phase');
  if Node.HasAttribute('temp') then Result.Add('temp');
  if Node.HasAttribute('where') then Result.Add('where');
  if Node.HasAttribute('match') then Result.Add('match');
  if Node.HasAttribute('rewrite') then Result.Add('rewrite');
  if Node.HasAttribute('minVal') then Result.Add('minVal');
  if Node.HasAttribute('minNode') then Result.Add('minNode');
  if Node.HasAttribute('scanPos') then Result.Add('scanPos');
  if Node.HasAttribute('pass') then Result.Add('pass');
  if Node.HasAttribute('currentMin') then Result.Add('currentMin');
  if Node.HasAttribute('isMin') then Result.Add('isMin');
  if Node.HasAttribute('X') then Result.Add('X');
  if Node.HasAttribute('Y') then Result.Add('Y');
  if Node.HasAttribute('Prev') then Result.Add('Prev');
  if Node.HasAttribute('Head') then Result.Add('Head');
  if Node.HasAttribute('State') then Result.Add('State');
end;

function TGrispPatternMatcher.ValuesEqual(Val1: TGrispValue; Val2: TGrispValue): Boolean;
var
  I: Integer;
  Id1, Id2: Integer;
  Name1, Name2: string;
begin
  if (Val1 = nil) or (Val2 = nil) then Exit((Val1 = nil) and (Val2 = nil));
  if Val1.Kind <> Val2.Kind then Exit(False);
  case Val1.Kind of
    gvkNumber: Result := Val1.NumberValue = Val2.NumberValue;
    gvkString: Result := Val1.StringValue = Val2.StringValue;
    gvkBoolean: Result := Val1.BoolValue = Val2.BoolValue;
    gvkIdentifier: Result := Val1.IdentifierValue = Val2.IdentifierValue;
    gvkArray:
      begin
        if Val1.ArrayValue.Count <> Val2.ArrayValue.Count then Exit(False);
        for I := 0 to Val1.ArrayValue.Count - 1 do
          if not ValuesEqual(Val1.ArrayValue[I], Val2.ArrayValue[I]) then Exit(False);
        Result := True;
      end;
    gvkNode:
      begin
        Val1.GetNodeReference(Id1, Name1);
        Val2.GetNodeReference(Id2, Name2);
        Result := (Id1 = Id2) and (Name1 = Name2);
      end;
  else
    Result := False;
  end;
end;

function TGrispPatternMatcher.GetNodeAttrOrEdge(TargetNode: TGrispNode; const Key: string; out OutVal: TGrispValue): Boolean;
var
  Edge: TGrispEdge;
begin
  OutVal := TargetNode.GetValueAttribute(Key);
  if OutVal <> nil then Exit(True);
  for Edge in TargetNode.Outgoing do
    if SameText(Edge.LabelName, Key) then
    begin
      OutVal := TGrispValue.Create(gvkIdentifier);
      OutVal.IdentifierValue := Edge.Target.Name;
      Exit(True);
    end;
  OutVal := nil;
  Result := False;
end;

function TGrispPatternMatcher.MatchNodeConstraints(PatternNode: TGrispNode; TargetNode: TGrispNode; Match: TGrispMatchResult): Boolean;
var
  Key: string;
  PatternVal, TargetVal: TGrispValue;
  NeedFree: Boolean;
  Edge: TGrispEdge;
  FoundEdge: Boolean;
  Keys: TList<string>;
begin
  if (PatternNode = nil) or (TargetNode = nil) then Exit(False);

  Keys := GetAttributeKeys(PatternNode);
  try
    for Key in Keys do
    begin
      PatternVal := PatternNode.GetValueAttribute(Key);
      NeedFree := False;

      if (Key = 'next') then
      begin
        FoundEdge := False;
        for Edge in TargetNode.Outgoing do
        begin
          if SameText(Edge.LabelName, 'next') then
          begin
            TargetVal := TGrispValue.Create(gvkIdentifier);
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
          if TargetVal <> TargetNode.GetValueAttribute(Key) then
            NeedFree := True;
        end;
      end
      else
      begin
        if not GetNodeAttrOrEdge(TargetNode, Key, TargetVal) then
          Exit(False);
        if TargetVal <> TargetNode.GetValueAttribute(Key) then
          NeedFree := True;
      end;

      if not MatchValue(PatternVal, TargetVal, Match) then
      begin
        if NeedFree then TargetVal.Free;
        Exit(False);
      end;

      if NeedFree then TargetVal.Free;
    end;
  finally
    Keys.Free;
  end;

  Result := True;
end;

function TGrispPatternMatcher.MatchValue(PatternValue: TGrispValue; TargetValue: TGrispValue; Match: TGrispMatchResult): Boolean;
var
  IdStr: string;
  BoundNode: TGrispNode;
  BoundValue: TGrispValue;
  TargetNodeRef: TGrispNode;
  I: Integer;
  Node: TGrispNode;
  PatNodeId, TarNodeId: Integer;
  PatNodeName, TarNodeName: string;
begin
  if (PatternValue = nil) or (TargetValue = nil) then
  begin
    Result := (PatternValue = nil) and (TargetValue = nil);
    Exit;
  end;

  if (PatternValue.Kind = gvkIdentifier) then
  begin
    IdStr := PatternValue.IdentifierValue;

    if (Length(IdStr) = 1) and CharInSet(IdStr[1], ['A'..'Z']) then
    begin
      if TargetValue.Kind = gvkIdentifier then
      begin
        TargetNodeRef := FGraph.FindNode(TargetValue.IdentifierValue);
        if TargetNodeRef = nil then
        begin
          Result := False;
          Exit;
        end;

        if Match.TryGetNode(IdStr, BoundNode) then
        begin
          Result := (BoundNode = TargetNodeRef);
          Exit;
        end;

        Match.AddNodeBinding(IdStr, TargetNodeRef);
        Result := True;
        Exit;
      end
      else if TargetValue.Kind = gvkNode then
      begin
        TargetValue.GetNodeReference(I, IdStr);
        TargetNodeRef := nil;
        for Node in FGraph.Nodes do
          if Node.Id = I then
          begin
            TargetNodeRef := Node;
            Break;
          end;
        if TargetNodeRef = nil then
        begin
          Result := False;
          Exit;
        end;

        if Match.TryGetNode(IdStr, BoundNode) then
        begin
          Result := (BoundNode = TargetNodeRef);
          Exit;
        end;

        Match.AddNodeBinding(IdStr, TargetNodeRef);
        Result := True;
        Exit;
      end
      else
      begin
        Result := False;
        Exit;
      end;
    end

    else if (Length(IdStr) >= 2) and (IdStr[1] = 'V') and CharInSet(IdStr[2], ['A'..'Z']) then
    begin
      if Match.TryGetValue(IdStr, BoundValue) then
      begin
        Result := ValuesEqual(BoundValue, TargetValue);
        Exit;
      end
      else
      begin
        if (TargetValue.Kind = gvkNumber) or (TargetValue.Kind = gvkBoolean) then
        begin
          Match.AddValueBinding(IdStr, TargetValue.Clone);
          Result := True;
          Exit;
        end
        else
        begin
          Result := False;
          Exit;
        end;
      end;
    end

    else
    begin
      if TargetValue.Kind = gvkIdentifier then
        Result := (IdStr = TargetValue.IdentifierValue)
      else
        Result := False;
      Exit;
    end;
  end

  else if PatternValue.Kind <> TargetValue.Kind then
  begin
    Result := False;
    Exit;
  end

  else
  begin
    case PatternValue.Kind of
      gvkNumber:
        Result := (PatternValue.NumberValue = TargetValue.NumberValue);

      gvkString:
        Result := (PatternValue.StringValue = TargetValue.StringValue);

      gvkBoolean:
        Result := (PatternValue.BoolValue = TargetValue.BoolValue);

      gvkIdentifier:
        Result := (PatternValue.IdentifierValue = TargetValue.IdentifierValue);

      gvkArray:
        begin
          if PatternValue.ArrayValue.Count <> TargetValue.ArrayValue.Count then
          begin
            Result := False;
            Exit;
          end;

          for I := 0 to PatternValue.ArrayValue.Count - 1 do
          begin
            if not MatchValue(PatternValue.ArrayValue[I], TargetValue.ArrayValue[I], Match) then
            begin
              Result := False;
              Exit;
            end;
          end;
          Result := True;
        end;

      gvkNode:
        begin
          PatternValue.GetNodeReference(PatNodeId, PatNodeName);
          TargetValue.GetNodeReference(TarNodeId, TarNodeName);

          // Find nodes by name
          var PatNode := FGraph.FindNode(PatNodeName);
          var TarNode := FGraph.FindNode(TarNodeName);

          if (PatNode = nil) or (TarNode = nil) then
            Result := False
          else
            Result := MatchNodeConstraints(PatNode, TarNode, Match);
        end;
    else
      Result := False;
    end;
  end;
end;

function TGrispPatternMatcher.CheckPatternEdges(PatternNode: TGrispNode; TargetNode: TGrispNode; const PartialMatch: TGrispMatchResult): Boolean;
var
  Key: string;
  PatVal: TGrispValue;
  TargetVar: string;
  TargetHN: TGrispNode;
  Edge: TGrispEdge;
  Found: Boolean;
  Keys: TList<string>;
begin
  Result := True;
  Keys := GetAttributeKeys(PatternNode);
  try
    for Key in Keys do
    begin
      PatVal := PatternNode.GetValueAttribute(Key);
      if (PatVal = nil) or (PatVal.Kind <> gvkIdentifier) then Continue;
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
  finally
    Keys.Free;
  end;
end;

function TGrispPatternMatcher.Search(VarIndex: Integer; Match: TGrispMatchResult): Boolean;
var
  VarInfo: TGrispNodeVarInfo;
  Candidate: TGrispNode;
  SavedNodeCount, SavedValueCount: Integer;
  AlreadyBound: TGrispNode;
  NodeBoundToOther: Boolean;
  B: TGrispNodeBinding;
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
begin
  Result := Assigned(FCurrentRule) and FCurrentRule.HasAttribute('where') and
            (FCurrentRule.GetValueAttribute('where').Kind = gvkExpression);
end;

function TGrispPatternMatcher.EvalWhere(Match: TGrispMatchResult): Boolean;
var
  V: TGrispValue;
  Expr: TGrispExpression;
  Bindings: TDictionary<string, TGrispValue>;
  Res: TGrispValue;
  B: TGrispValueBinding;
  BNode: TGrispNodeBinding;
  Pair: TPair<string, TGrispValue>;
begin
  Result := True;
  if not Assigned(FCurrentRule) then Exit;
  if not FCurrentRule.HasAttribute('where') then Exit;

  V := FCurrentRule.GetValueAttribute('where');
  if (V = nil) or (V.Kind <> gvkExpression) then Exit;

  // Cast ExpressionValue to TGrispExpression
  if not (V.ExpressionValue is TGrispExpression) then
    Exit(False);

  Expr := TGrispExpression(V.ExpressionValue);

  Bindings := TDictionary<string, TGrispValue>.Create;
  try
    for B in Match.ValueBindings do
      Bindings.Add(B.Name, B.Value.Clone);

    for BNode in Match.NodeBindings do
    begin
      if not Bindings.ContainsKey(BNode.Name) then
      begin
        var NodeVal := TGrispValue.Create(gvkIdentifier);
        NodeVal.IdentifierValue := BNode.Node.Name;
        Bindings.Add(BNode.Name, NodeVal);
      end;
    end;

    Res := TGrispExpressionEvaluator.Evaluate(Expr, Bindings);

    try
      Result := Assigned(Res) and (Res.Kind = gvkBoolean) and Res.BoolValue;
    finally
      Res.Free;
    end;
  finally
    for Pair in Bindings do
      Pair.Value.Free;
    Bindings.Free;
  end;
end;

procedure TGrispPatternMatcher.CollectVariables(Node: TGrispNode; IsTempPattern: Boolean);
var
  K: string;
  V: TGrispValue;
  VarInfo: TGrispNodeVarInfo;
  Keys: TList<string>;
  PatNodeId: Integer;
  PatNodeName: string;
  PatNode: TGrispNode;
begin
  if Node = nil then Exit;

  Keys := GetAttributeKeys(Node);
  try
    for K in Keys do
    begin
      V := Node.GetValueAttribute(K);
      if (V <> nil) and (V.Kind = gvkNode) then
      begin
        if IsVariable(K) then
        begin
          V.GetNodeReference(PatNodeId, PatNodeName);
          PatNode := FGraph.FindNode(PatNodeName);
          VarInfo.VarName := K;
          VarInfo.PatternNode := PatNode;
          FNodeVars.Add(VarInfo);
          if not IsTempPattern then
            FPatternVariables.Add(K);
        end;
        // Recursively collect - but need to get the actual node from the value
        if V.Kind = gvkNode then
        begin
          V.GetNodeReference(PatNodeId, PatNodeName);
          PatNode := FGraph.FindNode(PatNodeName);
          if PatNode <> nil then
            CollectVariables(PatNode, IsTempPattern);
        end;
      end
      else if (V <> nil) and (V.Kind = gvkIdentifier) then
      begin
        if IsVariable(V.IdentifierValue) then
        begin
          if not IsTempPattern then
            FPatternVariables.Add(V.IdentifierValue);
        end;
      end;
    end;
  finally
    Keys.Free;
  end;
end;

function TGrispPatternMatcher.MatchPattern(PatternRoot: TGrispNode): TGrispMatchResult;
var
  VarInfo: TGrispNodeVarInfo;
  TempPattern: TGrispNode;
  TempValue: TGrispValue;
  TempNodeId: Integer;
  TempNodeName: string;
begin
  Result := TGrispMatchResult.Create;
  FPatternVariables.Clear;
  FNodeVars.Clear;

  if PatternRoot = nil then
  begin
    Result.Success := False;
    Exit;
  end;

  TempPattern := nil;
  if (FCurrentRule <> nil) and FCurrentRule.HasAttribute('temp') then
  begin
    TempValue := FCurrentRule.GetValueAttribute('temp');
    if (TempValue <> nil) and (TempValue.Kind = gvkNode) then
    begin
      TempValue.GetNodeReference(TempNodeId, TempNodeName);
      TempPattern := FGraph.FindNode(TempNodeName);
    end;
  end;

  CollectVariables(PatternRoot, False);

  if TempPattern <> nil then
    CollectVariables(TempPattern, True);

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

function TGrispPatternMatcher.FindAllMatches(PatternRoot: TGrispNode): TList<TGrispMatchResult>;
var
  ResultList: TList<TGrispMatchResult>;
  TempMatch: TGrispMatchResult;
  VarInfo: TGrispNodeVarInfo;
  TempPattern: TGrispNode;
  TempValue: TGrispValue;
  TempNodeId: Integer;
  TempNodeName: string;

  procedure SearchAll(VarIndex: Integer; CurrentMatch: TGrispMatchResult);
  var
    VI: TGrispNodeVarInfo;
    Candidate: TGrispNode;
    SavedNodeCount, SavedValueCount: Integer;
    NodeBoundToOther: Boolean;
    BNode: TGrispNodeBinding;
    BValue: TGrispValueBinding;
    NewMatch: TGrispMatchResult;
  begin
    if VarIndex >= FNodeVars.Count then
    begin
      if HasWhere then
      begin
        if EvalWhere(CurrentMatch) then
        begin
          NewMatch := TGrispMatchResult.Create;
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
        NewMatch := TGrispMatchResult.Create;
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
  ResultList := TList<TGrispMatchResult>.Create;
  Result := ResultList;

  FPatternVariables.Clear;
  FNodeVars.Clear;

  if PatternRoot = nil then
    Exit;

  TempPattern := nil;
  if (FCurrentRule <> nil) and FCurrentRule.HasAttribute('temp') then
  begin
    TempValue := FCurrentRule.GetValueAttribute('temp');
    if (TempValue <> nil) and (TempValue.Kind = gvkNode) then
    begin
      TempValue.GetNodeReference(TempNodeId, TempNodeName);
      TempPattern := FGraph.FindNode(TempNodeName);
    end;
  end;

  CollectVariables(PatternRoot, False);

  if TempPattern <> nil then
    CollectVariables(TempPattern, True);

  if FNodeVars.Count = 0 then
  begin
    VarInfo.VarName := '';
    VarInfo.PatternNode := PatternRoot;
    FNodeVars.Add(VarInfo);
  end;

  TempMatch := TGrispMatchResult.Create;
  try
    SearchAll(0, TempMatch);
  finally
    TempMatch.Free;
  end;
end;

end.
