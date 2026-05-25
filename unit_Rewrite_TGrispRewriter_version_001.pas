unit unit_Rewrite_TGrispRewriter_version_001;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  unit_Graph_TGrispGraph_version_001,
  unit_Graph_TGrispEdge_TGrispNode_version_001,
  unit_Core_TGrispValueBase_version_001,
  unit_Pattern_TGrispMatchResult_version_001,
  unit_Pattern_TGrispPatternMatcher_version_001,
  unit_Pattern_TGrispNodeBinding_version_001,
  unit_Rewrite_TGrispRewriteOperation_version_001;

type
  TGrispRewriter = class
  private
    FGraph: TGrispGraph;
    FOperations: TList<TGrispRewriteOperation>;
    FTrace: TStrings;

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
    function SelectNonOverlappingMatches(Matches: TList<TGrispMatchResult>): TList<TGrispMatchResult>;

  public
    constructor Create(AGraph: TGrispGraph);
    destructor Destroy; override;

    function ApplyAllMatches(ARule: TGrispNode; Matcher: TGrispPatternMatcher; Trace: TStrings = nil): Integer;
    function ApplyAllMatchesWithLimit(ARule: TGrispNode; Matcher: TGrispPatternMatcher;
                                      MaxMatches: Integer; Trace: TStrings = nil): Integer;

    property Trace: TStrings read FTrace write FTrace;
  end;

implementation

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
  NodeId: Integer;
  NodeName: string;
begin
  Result := nil;
  V := ARule.GetValueAttribute('match');
  if (V <> nil) and (V.Kind = gvkNode) then
  begin
    V.GetNodeReference(NodeId, NodeName);
    Result := FGraph.FindNode(NodeName);
  end;
end;

function TGrispRewriter.GetRewriteRoot(ARule: TGrispNode): TGrispNode;
var
  V: TGrispValue;
  NodeId: Integer;
  NodeName: string;
begin
  Result := nil;
  V := ARule.GetValueAttribute('rewrite');
  if (V <> nil) and (V.Kind = gvkNode) then
  begin
    V.GetNodeReference(NodeId, NodeName);
    Result := FGraph.FindNode(NodeName);
  end;
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
      begin
        var Id: Integer;
        var Name: string;
        AValue.GetNodeReference(Id, Name);
        Result.SetNodeReference(Id, Name);
      end;
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
  NodeId: Integer;
  NodeName: string;
  SourceNode: TGrispNode;
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

        // Get the source node from the template value
        TemplateVal.GetNodeReference(NodeId, NodeName);
        SourceNode := FGraph.FindNode(NodeName);

        if SourceNode <> nil then
        begin
          Keys := SourceNode.GetAttributeKeys;
          try
            for AttrKey in Keys do
              NewInlineNode.SetValueAttribute(
                AttrKey,
                EvaluateValue(SourceNode.GetValueAttribute(AttrKey), Match, NodeVarMap, NewNodes)
              );
          finally
            Keys.Free;
          end;
        end;

        Result := TGrispValue.Create(gvkNode);
        // Store the node reference using SetNodeReference instead of NodeValue
        Result.SetNodeReference(NewInlineNode.Id, NewInlineNode.Name);
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
var
  Edge: TGrispEdge;
begin
  if Node = nil then Exit;

  while Node.Outgoing.Count > 0 do
  begin
    Edge := Node.Outgoing[0];
    RemoveEdge(Edge.Source, Edge.LabelName, Edge.Target);
  end;

  while Node.Incoming.Count > 0 do
  begin
    Edge := Node.Incoming[0];
    RemoveEdge(Edge.Source, Edge.LabelName, Edge.Target);
  end;

  if Node.Name <> '' then
    FGraph.NodeIndex.Remove(Node.Name);

  FGraph.Nodes.Remove(Node);
  Node.Free;
end;

function TGrispRewriter.SelectNonOverlappingMatches(Matches: TList<TGrispMatchResult>): TList<TGrispMatchResult>;
var
  M: TGrispMatchResult;
  BNode: TGrispNodeBinding;
  UsedNodes: THashSet<TGrispNode>;
  HasOverlap: Boolean;
  i: Integer;
begin
  Result := TList<TGrispMatchResult>.Create;
  UsedNodes := THashSet<TGrispNode>.Create;

  try
    for i := 0 to Matches.Count - 1 do
    begin
      M := Matches[i];
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
        Result.Add(M);
        for BNode in M.NodeBindings do
          UsedNodes.Add(BNode.Node);
      end;
    end;
  finally
    UsedNodes.Free;
  end;
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
  NodeId: Integer;
  NodeName: string;
begin
  NodeVarMap := TDictionary<string, TGrispNode>.Create;
  try
    RewriteKeys := RewriteRoot.GetAttributeKeys;
    try
      for AttrKey in RewriteKeys do
      begin
        AttrVal := RewriteRoot.GetValueAttribute(AttrKey);
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
      AttrVal := RewriteRoot.GetValueAttribute(AttrKey);
      if (AttrVal <> nil) and (AttrVal.Kind = gvkNode) then
      begin
        AttrVal.GetNodeReference(NodeId, NodeName);
        InlineTemplate := FGraph.FindNode(NodeName);

        Op.Init;
        Op.TargetNode := BoundNode;

        if Assigned(InlineTemplate) then
        begin
          InlineKeys := InlineTemplate.GetAttributeKeys;
          try
            for Key in InlineKeys do
            begin
              IsDeletion := IsEdgeDeletionAttribute(Key, EdgeLabel);

              if IsDeletion then
              begin
                EvaluatedVal := EvaluateValue(InlineTemplate.GetValueAttribute(Key), Match, NodeVarMap, NewNodes);
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

              EvaluatedVal := EvaluateValue(InlineTemplate.GetValueAttribute(Key), Match, NodeVarMap, NewNodes);

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
                    EvaluatedVal.GetNodeReference(NodeId, NodeName);
                    TargetNode := FGraph.FindNode(NodeName);
                    if Assigned(TargetNode) then
                    begin
                      EdgePair.Key := Key;
                      EdgePair.Value := TargetNode;
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

        if Op.HasChanges then
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
        Op.TargetNode.SetValueAttribute(AttrKey, AttrVal);
      end;
    end;

    for Pair in Op.EdgesToAdd do
      FGraph.AddEdge(Op.TargetNode, Pair.Value, Pair.Key);

    for NodeToRemove in Op.NodesToRemove do
      RemoveNode(NodeToRemove);
  end;
end;

function TGrispRewriter.ApplyAllMatches(ARule: TGrispNode; Matcher: TGrispPatternMatcher; Trace: TStrings): Integer;
begin
  Result := ApplyAllMatchesWithLimit(ARule, Matcher, MaxInt, Trace);
end;

function TGrispRewriter.ApplyAllMatchesWithLimit(ARule: TGrispNode; Matcher: TGrispPatternMatcher;
                                                MaxMatches: Integer; Trace: TStrings): Integer;
var
  MatchRoot, RewriteRoot: TGrispNode;
  MatchResults: TList<TGrispMatchResult>;
  NewNodes: TList<TGrispNode>;
  AllOperations: TList<TGrispRewriteOperation>;
  Op: TGrispRewriteOperation;
  TotalApplied: Integer;
  SelectedMatches: TList<TGrispMatchResult>;
  M: TGrispMatchResult;
  i: Integer;
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

      SelectedMatches := SelectNonOverlappingMatches(MatchResults);
      try
        if SelectedMatches.Count = 0 then
          Break;

        if Assigned(Trace) then
          Trace.Add(Format('Selected %d non-overlapping matches', [SelectedMatches.Count]));

        NewNodes := TList<TGrispNode>.Create;
        AllOperations := TList<TGrispRewriteOperation>.Create;
        try
          for i := 0 to SelectedMatches.Count - 1 do
          begin
            if TotalApplied >= MaxMatches then Break;
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
      end;
    finally
      MatchResults.Free;
    end;
  until (TotalApplied >= MaxMatches);

  Result := TotalApplied;
end;

end.
