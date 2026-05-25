unit unit_GrispRewrite_version_001;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  unit_GrispGraph_version_001,
  unit_GrispPattern_version_001;

type
  TGrispRewriteOperation = record
    TargetNode: TGrispNode;
    Attributes: TDictionary<string, TGrispValue>;
    EdgesToAdd: TList<TPair<string, TGrispNode>>;
    EdgesToRemove: TList<TPair<string, TGrispNode>>;
    NodesToRemove: TList<TGrispNode>;
    procedure Init;
    procedure Free;
  end;

  TGrispRewriter = class
  private
    FGraph: TGrispGraph;
    FOperations: TList<TGrispRewriteOperation>;

    function GetMatchRoot(ARule: TGrispNode): TGrispNode;
    function GetRewriteRoot(ARule: TGrispNode): TGrispNode;
    function CloneValue(AValue: TGrispValue): TGrispValue;
    function IsEdgeDeletionAttribute(const Key: string; out EdgeLabel: string): Boolean;
    function EvaluateValue(
      TemplateVal: TGrispValue;
      Match: TGrispMatchResult;
      NodeVarMap: TDictionary<string, TGrispNode>;
      NewNodes: TList<TGrispNode>): TGrispValue;
    procedure CollectRewriteOperations(
      RewriteRoot: TGrispNode;
      Match: TGrispMatchResult;
      NewNodes: TList<TGrispNode>;
      Operations: TList<TGrispRewriteOperation>);
    procedure ApplyOperations(Operations: TList<TGrispRewriteOperation>);
    procedure RemoveEdge(Source: TGrispNode; const LabelName: string; Target: TGrispNode);
    procedure RemoveNode(Node: TGrispNode);
  public
    constructor Create(AGraph: TGrispGraph);
    destructor Destroy; override;
    function ApplyAllMatches(ARule: TGrispNode; Matcher: TGrispPatternMatcher; Trace: TStrings = nil): Integer;
  end;

implementation

{ TGrispRewriteOperation }

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

{ TGrispRewriter }

constructor TGrispRewriter.Create(AGraph: TGrispGraph);
begin
  inherited Create;
  FGraph := AGraph;
  FOperations := TList<TGrispRewriteOperation>.Create;
end;

destructor TGrispRewriter.Destroy;
var
  Op: TGrispRewriteOperation;
begin
  for Op in FOperations do
    Op.Free;
  FOperations.Free;
  inherited Destroy;
end;

function TGrispRewriter.GetMatchRoot(ARule: TGrispNode): TGrispNode;
var
  V: TGrispValue;
begin
  Result := nil;
  V := ARule.GetAttribute('match');
  if (V <> nil) and (V.Kind = gvkNode) then
    Result := V.NodeValue;
end;

function TGrispRewriter.GetRewriteRoot(ARule: TGrispNode): TGrispNode;
var
  V: TGrispValue;
begin
  Result := nil;
  V := ARule.GetAttribute('rewrite');
  if (V <> nil) and (V.Kind = gvkNode) then
    Result := V.NodeValue;
end;

function TGrispRewriter.CloneValue(AValue: TGrispValue): TGrispValue;
var
  Elem: TGrispValue;
begin
  if AValue = nil then Exit(nil);
  Result := TGrispValue.Create(AValue.Kind);
  case AValue.Kind of
    gvkNumber:  Result.NumberValue := AValue.NumberValue;
    gvkString:  Result.StringValue := AValue.StringValue;
    gvkBoolean: Result.BoolValue := AValue.BoolValue;
    gvkIdentifier: Result.IdentifierValue := AValue.IdentifierValue;
    gvkArray:
      for Elem in AValue.ArrayValue do
        Result.ArrayValue.Add(CloneValue(Elem));
    gvkNode:
      Result.NodeValue := AValue.NodeValue;
	gvkExpression:
      Result.ExpressionValue := AValue.ExpressionValue;
  end;
end;

function TGrispRewriter.IsEdgeDeletionAttribute(const Key: string; out EdgeLabel: string): Boolean;
begin
  if (Length(Key) > 7) and (Copy(Key, 1, 7) = 'remove_') then
  begin
    EdgeLabel := Copy(Key, 8, Length(Key) - 7);
    Result := True;
  end
  else
  begin
    EdgeLabel := '';
    Result := False;
  end;
end;

function TGrispRewriter.EvaluateValue(
  TemplateVal: TGrispValue;
  Match: TGrispMatchResult;
  NodeVarMap: TDictionary<string, TGrispNode>;
  NewNodes: TList<TGrispNode>): TGrispValue;
var
  BoundNode: TGrispNode;
  BoundVal: TGrispValue;
  Elem: TGrispValue;
  NewInlineNode: TGrispNode;
  AttrKey: string;
  Keys: TList<string>;
begin
  if TemplateVal = nil then Exit(nil);

  case TemplateVal.Kind of
    gvkNumber:
      begin
        Result := TGrispValue.Create(gvkNumber);
        Result.NumberValue := TemplateVal.NumberValue;
      end;
    gvkString:
      begin
        Result := TGrispValue.Create(gvkString);
        Result.StringValue := TemplateVal.StringValue;
      end;
    gvkBoolean:
      begin
        Result := TGrispValue.Create(gvkBoolean);
        Result.BoolValue := TemplateVal.BoolValue;
      end;
    gvkIdentifier:
      begin
        if Match.TryGetNode(TemplateVal.IdentifierValue, BoundNode) then
        begin
          Result := TGrispValue.Create(gvkIdentifier);
          Result.IdentifierValue := BoundNode.Name;
        end
        else if NodeVarMap.TryGetValue(TemplateVal.IdentifierValue, BoundNode) then
        begin
          Result := TGrispValue.Create(gvkIdentifier);
          Result.IdentifierValue := BoundNode.Name;
        end
        else if Match.TryGetValue(TemplateVal.IdentifierValue, BoundVal) then
        begin
          Result := CloneValue(BoundVal);
        end
		else
        begin
          Result := TGrispValue.Create(gvkIdentifier);
          Result.IdentifierValue := TemplateVal.IdentifierValue;
        end;
      end;
    gvkArray:
      begin
        Result := TGrispValue.Create(gvkArray);
        for Elem in TemplateVal.ArrayValue do
          Result.ArrayValue.Add(EvaluateValue(Elem, Match, NodeVarMap, NewNodes));
      end;
    gvkNode:
      begin
        NewInlineNode := FGraph.AddNode('', 'node');
        NewNodes.Add(NewInlineNode);
        if Assigned(TemplateVal.NodeValue) then
        begin
          Keys := TList<string>.Create;
          try
            // Get attribute keys - this is a limitation
            if TemplateVal.NodeValue.HasAttribute('value') then Keys.Add('value');
            if TemplateVal.NodeValue.HasAttribute('next') then Keys.Add('next');
            if TemplateVal.NodeValue.HasAttribute('name') then Keys.Add('name');
            if TemplateVal.NodeValue.HasAttribute('mark') then Keys.Add('mark');
            if TemplateVal.NodeValue.HasAttribute('phase') then Keys.Add('phase');

            for AttrKey in Keys do
              NewInlineNode.SetAttribute(
                AttrKey,
                EvaluateValue(TemplateVal.NodeValue.GetAttribute(AttrKey), Match, NodeVarMap, NewNodes)
              );
          finally
            Keys.Free;
          end;
        end;
        Result := TGrispValue.Create(gvkNode);
        Result.NodeValue := NewInlineNode;
      end;
  else
    Result := nil;
  end;
end;

procedure TGrispRewriter.RemoveEdge(Source: TGrispNode; const LabelName: string; Target: TGrispNode);
var
  i: Integer;
  Edge: TGrispEdge;
begin
  if (Source = nil) or (Target = nil) then Exit;

  for i := Source.Outgoing.Count - 1 downto 0 do
  begin
    Edge := Source.Outgoing[i];
    if (Edge.LabelName = LabelName) and (Edge.Target = Target) then
    begin
      Source.Outgoing.Delete(i);
      Break;
    end;
  end;

  for i := Target.Incoming.Count - 1 downto 0 do
  begin
    Edge := Target.Incoming[i];
    if (Edge.LabelName = LabelName) and (Edge.Source = Source) then
    begin
	  Target.Incoming.Delete(i);
      Break;
    end;
  end;

  for i := FGraph.Edges.Count - 1 downto 0 do
  begin
    Edge := FGraph.Edges[i];
    if (Edge.Source = Source) and (Edge.LabelName = LabelName) and (Edge.Target = Target) then
    begin
      FGraph.Edges.Delete(i);
      Edge.Free;
      Break;
    end;
  end;
end;

procedure TGrispRewriter.RemoveNode(Node: TGrispNode);
begin
  if Node = nil then Exit;

  while Node.Outgoing.Count > 0 do
    RemoveEdge(Node.Outgoing[0], Node.Outgoing[0].LabelName, Node.Outgoing[0].Target);

  while Node.Incoming.Count > 0 do
    RemoveEdge(Node.Incoming[0], Node.Incoming[0].LabelName, Node.Incoming[0].Source);

  if Node.Name <> '' then
    FGraph.NodeIndex.Remove(Node.Name);

  FGraph.Nodes.Remove(Node);
  Node.Free;
end;

procedure TGrispRewriter.CollectRewriteOperations(
  RewriteRoot: TGrispNode;
  Match: TGrispMatchResult;
  NewNodes: TList<TGrispNode>;
  Operations: TList<TGrispRewriteOperation>);
var
  NodeVarMap: TDictionary<string, TGrispNode>;
  AttrKey, Key, EdgeLabel: string;
  AttrVal: TGrispValue;
  BoundNode, NewNode, TargetNode: TGrispNode;
  InlineTemplate: TGrispNode;
  EvaluatedVal: TGrispValue;
  Op: TGrispRewriteOperation;
  EdgePair: TPair<string, TGrispNode>;
  IsDeletion: Boolean;
  RewriteKeys: TList<string>;
  InlineKeys: TList<string>;
begin
  NodeVarMap := TDictionary<string, TGrispNode>.Create;
  try
    // Get rewrite root attribute keys
    RewriteKeys := TList<string>.Create;
    try
      if RewriteRoot.HasAttribute('X') then RewriteKeys.Add('X');
      if RewriteRoot.HasAttribute('Y') then RewriteKeys.Add('Y');
      if RewriteRoot.HasAttribute('Prev') then RewriteKeys.Add('Prev');
      if RewriteRoot.HasAttribute('Head') then RewriteKeys.Add('Head');
      if RewriteRoot.HasAttribute('State') then RewriteKeys.Add('State');
      if RewriteRoot.HasAttribute('MinNode') then RewriteKeys.Add('MinNode');

      for AttrKey in RewriteKeys do
      begin
		AttrVal := RewriteRoot.GetAttribute(AttrKey);
        if (AttrVal <> nil) and (AttrVal.Kind = gvkNode) then
        begin
          if Match.TryGetNode(AttrKey, BoundNode) then
            NodeVarMap.Add(AttrKey, BoundNode)
          else
          begin
            NewNode := FGraph.AddNode('', 'node');
            NewNodes.Add(NewNode);
            NodeVarMap.Add(AttrKey, NewNode);
          end;
        end;
      end;
    finally
      RewriteKeys.Free;
    end;

    for AttrKey in NodeVarMap.Keys do
    begin
      BoundNode := NodeVarMap[AttrKey];
      AttrVal := RewriteRoot.GetAttribute(AttrKey);
      if (AttrVal <> nil) and (AttrVal.Kind = gvkNode) then
      begin
        InlineTemplate := AttrVal.NodeValue;

        Op.Init;
        Op.TargetNode := BoundNode;

        if Assigned(InlineTemplate) then
        begin
          InlineKeys := TList<string>.Create;
          try
            if InlineTemplate.HasAttribute('value') then InlineKeys.Add('value');
            if InlineTemplate.HasAttribute('next') then InlineKeys.Add('next');
            if InlineTemplate.HasAttribute('name') then InlineKeys.Add('name');
            if InlineTemplate.HasAttribute('isMin') then InlineKeys.Add('isMin');
            if InlineTemplate.HasAttribute('minVal') then InlineKeys.Add('minVal');
            if InlineTemplate.HasAttribute('minNode') then InlineKeys.Add('minNode');
            if InlineTemplate.HasAttribute('scanPos') then InlineKeys.Add('scanPos');
            if InlineTemplate.HasAttribute('pass') then InlineKeys.Add('pass');

            for Key in InlineKeys do
            begin
              IsDeletion := IsEdgeDeletionAttribute(Key, EdgeLabel);

              if IsDeletion then
              begin
                EvaluatedVal := EvaluateValue(InlineTemplate.GetAttribute(Key), Match, NodeVarMap, NewNodes);
                if (EvaluatedVal <> nil) and (EvaluatedVal.Kind = gvkIdentifier) then
                begin
                  TargetNode := FGraph.FindNode(EvaluatedVal.IdentifierValue);
                  if Assigned(TargetNode) then
                  begin
                    EdgePair.Key := EdgeLabel;
                    EdgePair.Value := TargetNode;
                    Op.EdgesToRemove.Add(EdgePair);
                  end;
                end;
                EvaluatedVal.Free;
                Continue;
              end;

              EvaluatedVal := EvaluateValue(InlineTemplate.GetAttribute(Key), Match, NodeVarMap, NewNodes);

              if (Key = 'delete') and (EvaluatedVal <> nil) and (EvaluatedVal.Kind = gvkBoolean) and EvaluatedVal.BoolValue then
              begin
				Op.NodesToRemove.Add(BoundNode);
                EvaluatedVal.Free;
                Continue;
              end;

              if (Key = 'next') and (EvaluatedVal <> nil) and (EvaluatedVal.Kind = gvkIdentifier) then
              begin
                NewNode := FGraph.FindNode(EvaluatedVal.IdentifierValue);
                if Assigned(NewNode) and (NewNode = BoundNode) then
                begin
                  EvaluatedVal.Free;
                  Continue;
                end;
              end;

              if SameText(Key, 'name') and (EvaluatedVal <> nil) and (EvaluatedVal.Kind = gvkIdentifier) then
              begin
                Op.Attributes.AddOrSetValue(Key, EvaluatedVal);
              end
              else
              begin
                Op.Attributes.AddOrSetValue(Key, EvaluatedVal);

                if Assigned(EvaluatedVal) then
                begin
                  if EvaluatedVal.Kind = gvkNode then
                  begin
                    if Assigned(EvaluatedVal.NodeValue) then
                    begin
                      EdgePair.Key := Key;
                      EdgePair.Value := EvaluatedVal.NodeValue;
                      Op.EdgesToAdd.Add(EdgePair);
                    end;
                  end
                  else if EvaluatedVal.Kind = gvkIdentifier then
                  begin
                    NewNode := FGraph.FindNode(EvaluatedVal.IdentifierValue);
                    if Assigned(NewNode) then
                    begin
                      EdgePair.Key := Key;
                      EdgePair.Value := NewNode;
                      Op.EdgesToAdd.Add(EdgePair);
                    end;
                  end;
                end;
              end;
            end;
          finally
            InlineKeys.Free;
          end;
        end;

        if (Op.Attributes.Count > 0) or (Op.EdgesToAdd.Count > 0) or
           (Op.EdgesToRemove.Count > 0) or (Op.NodesToRemove.Count > 0) then
          Operations.Add(Op)
        else
          Op.Free;
      end;
    end;
  finally
    NodeVarMap.Free;
  end;
end;

procedure TGrispRewriter.ApplyOperations(Operations: TList<TGrispRewriteOperation>);
var
  Op: TGrispRewriteOperation;
  Pair: TPair<string, TGrispNode>;
  AttrKey: string;
  AttrVal: TGrispValue;
  NodeToRemove: TGrispNode;
begin
  for Op in Operations do
  begin
    for Pair in Op.EdgesToRemove do
      RemoveEdge(Op.TargetNode, Pair.Key, Pair.Value);

    for AttrKey in Op.Attributes.Keys do
    begin
      AttrVal := Op.Attributes[AttrKey];

      if SameText(AttrKey, 'name') and (AttrVal <> nil) and (AttrVal.Kind = gvkIdentifier) then
      begin
        if Op.TargetNode.Name <> '' then
          FGraph.NodeIndex.Remove(Op.TargetNode.Name);
        Op.TargetNode.Name := AttrVal.IdentifierValue;
        if Op.TargetNode.Name <> '' then
          FGraph.NodeIndex.AddOrSetValue(Op.TargetNode.Name, Op.TargetNode);
      end
      else
      begin
        Op.TargetNode.SetAttribute(AttrKey, AttrVal);
      end;
    end;

    for Pair in Op.EdgesToAdd do
      FGraph.AddEdge(Op.TargetNode, Pair.Value, Pair.Key);

    for NodeToRemove in Op.NodesToRemove do
      RemoveNode(NodeToRemove);
  end;
end;

function TGrispRewriter.ApplyAllMatches(ARule: TGrispNode; Matcher: TGrispPatternMatcher; Trace: TStrings): Integer;
var
  MatchRoot, RewriteRoot: TGrispNode;
  MatchResults: TList<TGrispMatchResult>;
  NewNodes: TList<TGrispNode>;
  AllOperations: TList<TGrispRewriteOperation>;
  Op: TGrispRewriteOperation;
  TotalApplied: Integer;
  i: Integer;
  M: TGrispMatchResult;
  HasOverlap: Boolean;
  UsedNodes: THashSet<TGrispNode>;
  SelectedMatches: TList<TGrispMatchResult>;
  BNode: TGrispNodeBinding;
begin
  Result := 0;
  TotalApplied := 0;

  MatchRoot := GetMatchRoot(ARule);
  RewriteRoot := GetRewriteRoot(ARule);
  if (MatchRoot = nil) or (RewriteRoot = nil) then
    Exit;

  repeat
    MatchResults := Matcher.FindAllMatches(MatchRoot);
    try
      if MatchResults.Count = 0 then
        Break;

	  if Assigned(Trace) then
        Trace.Add(Format('Found %d matches for rule %s', [MatchResults.Count, ARule.Name]));

      UsedNodes := THashSet<TGrispNode>.Create;
      SelectedMatches := TList<TGrispMatchResult>.Create;
      try
        for M in MatchResults do
        begin
          HasOverlap := False;
          for BNode in M.NodeBindings do
          begin
            if UsedNodes.Contains(BNode.Node) then
            begin
              HasOverlap := True;
              Break;
            end;
          end;

          if not HasOverlap then
          begin
            SelectedMatches.Add(M);
            for BNode in M.NodeBindings do
              UsedNodes.Add(BNode.Node);
          end;
        end;

        if SelectedMatches.Count = 0 then
          Break;

        if Assigned(Trace) then
          Trace.Add(Format('Selected %d non-overlapping matches', [SelectedMatches.Count]));

        NewNodes := TList<TGrispNode>.Create;
        AllOperations := TList<TGrispRewriteOperation>.Create;
        try
          for i := 0 to SelectedMatches.Count - 1 do
          begin
            M := SelectedMatches[i];
            CollectRewriteOperations(RewriteRoot, M, NewNodes, AllOperations);
          end;

          if AllOperations.Count > 0 then
          begin
            ApplyOperations(AllOperations);
            Inc(TotalApplied, AllOperations.Count);
            if Assigned(Trace) then
              Trace.Add(Format('Applied %d rewrites (total: %d)', [AllOperations.Count, TotalApplied]));
          end;
        finally
          for Op in AllOperations do
            Op.Free;
          AllOperations.Free;
          NewNodes.Free;
        end;
      finally
        SelectedMatches.Free;
        UsedNodes.Free;
      end;
    finally
      MatchResults.Free;
    end;
  until False;

  Result := TotalApplied;
end;

end.
