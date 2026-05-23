unit unit_GrispRewrite_version_001;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  unit_GrispGraph_version_001,
  unit_GrispPattern_version_001;

type
  TGrispRewriter = class
  private
    FGraph: TGGraph;

    function GetMatchRoot(ARule: TGNode): TGNode;
    function GetRewriteRoot(ARule: TGNode): TGNode;

    function CloneValue(AValue: TGValue): TGValue;
    procedure SafeRemoveEdgesForAttribute(ANode: TGNode; const AttrKey: string);

    function EvaluateValue(
      TemplateVal: TGValue;
      Match: TMatchResult;
      NodeVarMap: TDictionary<string, TGNode>;
      NewNodes: TList<TGNode>): TGValue;

    function BuildRewriteSubgraph(RewriteRoot: TGNode; Match: TMatchResult;
      out NewNodes: TList<TGNode>; out NewEdges: TList<TGEdge>): Boolean;

    procedure ApplyRewriteToGraph(ARule: TGNode; Match: TMatchResult;
      NewNodes: TList<TGNode>; NewEdges: TList<TGEdge>);
  public
    constructor Create(AGraph: TGGraph);

    // Try to apply a single rule once.
    // Returns True if the graph was modified.
    function ApplyRuleOnce(ARule: TGNode; Matcher: TGrispPatternMatcher): Boolean;
  end;

implementation

{ TGrispRewriter }

constructor TGrispRewriter.Create(AGraph: TGGraph);
begin
  inherited Create;
  FGraph := AGraph;
end;

function TGrispRewriter.GetMatchRoot(ARule: TGNode): TGNode;
var
  V: TGValue;
begin
  Result := nil;
  V := ARule.GetAttribute('match');
  if (V <> nil) and (V.Kind = vkNode) then
    Result := V.NodeValue;
end;

function TGrispRewriter.GetRewriteRoot(ARule: TGNode): TGNode;
var
  V: TGValue;
begin
  Result := nil;
  V := ARule.GetAttribute('rewrite');
  if (V <> nil) and (V.Kind = vkNode) then
    Result := V.NodeValue;
end;

function TGrispRewriter.CloneValue(AValue: TGValue): TGValue;
var
  Elem: TGValue;
begin
  if AValue = nil then
    Exit(nil);

  Result := TGValue.Create(AValue.Kind);
  case AValue.Kind of
    vkNumber:
      Result.NumberValue := AValue.NumberValue;
    vkString:
      Result.StringValue := AValue.StringValue;
    vkBoolean:
      Result.BoolValue := AValue.BoolValue;
    vkIdentifier:
      Result.IdentifierValue := AValue.IdentifierValue;
    vkArray:
      for Elem in AValue.ArrayValue do
        Result.ArrayValue.Add(CloneValue(Elem));
    vkNode:
      Result.NodeValue := AValue.NodeValue;
  end;
end;

procedure TGrispRewriter.SafeRemoveEdgesForAttribute(ANode: TGNode; const AttrKey: string);
var
  Edge: TGEdge;
  ToRemove: TList<TGEdge>;
begin
  if ANode = nil then
    Exit;

  ToRemove := TList<TGEdge>.Create;
  try
    // Find matching edges in the node's outgoing list
    for Edge in ANode.Outgoing do
    begin
      if SameText(Edge.LabelName, AttrKey) then
        ToRemove.Add(Edge);
    end;

    // Find matching edges in the graph's list to be thorough
    for Edge in FGraph.Edges do
    begin
      if (Edge.Source = ANode) and SameText(Edge.LabelName, AttrKey) then
      begin
        if ToRemove.IndexOf(Edge) < 0 then
          ToRemove.Add(Edge);
      end;
    end;

    // Safe extraction and deletion to avoid double-freeing
    for Edge in ToRemove do
    begin
      if Assigned(Edge.Source) then
        Edge.Source.Outgoing.Extract(Edge);
      FGraph.Edges.Remove(Edge); // This frees the TGEdge object
    end;
  finally
    ToRemove.Free;
  end;
end;

function TGrispRewriter.EvaluateValue(
  TemplateVal: TGValue;
  Match: TMatchResult;
  NodeVarMap: TDictionary<string, TGNode>;
  NewNodes: TList<TGNode>): TGValue;
var
  BoundNode: TGNode;
  BoundVal: TGValue;
  Elem: TGValue;
  NewInlineNode: TGNode;
  AttrKey: string;
begin
  if TemplateVal = nil then
    Exit(nil);

  case TemplateVal.Kind of
    vkNumber:
      begin
        Result := TGValue.Create(vkNumber);
        Result.NumberValue := TemplateVal.NumberValue;
      end;
    vkString:
      begin
        Result := TGValue.Create(vkString);
        Result.StringValue := TemplateVal.StringValue;
      end;
    vkBoolean:
      begin
        Result := TGValue.Create(vkBoolean);
        Result.BoolValue := TemplateVal.BoolValue;
      end;
    vkIdentifier:
      begin
        // 1. Is it a node variable?
        if Match.TryGetNode(TemplateVal.IdentifierValue, BoundNode) then
        begin
          Result := TGValue.Create(vkIdentifier);
          Result.IdentifierValue := BoundNode.Name;
        end
        else if NodeVarMap.TryGetValue(TemplateVal.IdentifierValue, BoundNode) then
        begin
          Result := TGValue.Create(vkIdentifier);
          Result.IdentifierValue := BoundNode.Name;
        end
        // 2. Is it a value variable?
        else if Match.TryGetValue(TemplateVal.IdentifierValue, BoundVal) then
        begin
          Result := CloneValue(BoundVal);
        end
        // 3. Otherwise literal
        else
        begin
          Result := TGValue.Create(vkIdentifier);
          Result.IdentifierValue := TemplateVal.IdentifierValue;
        end;
      end;
    vkArray:
      begin
        Result := TGValue.Create(vkArray);
        for Elem in TemplateVal.ArrayValue do
        begin
          Result.ArrayValue.Add(EvaluateValue(Elem, Match, NodeVarMap, NewNodes));
        end;
      end;
    vkNode:
      begin
        NewInlineNode := FGraph.AddNode('', 'node');
        NewNodes.Add(NewInlineNode);

        if Assigned(TemplateVal.NodeValue) then
        begin
          for AttrKey in TemplateVal.NodeValue.Attributes.Keys do
          begin
            NewInlineNode.SetAttribute(
              AttrKey,
              EvaluateValue(TemplateVal.NodeValue.GetAttribute(AttrKey), Match, NodeVarMap, NewNodes)
            );
          end;
        end;

        Result := TGValue.Create(vkNode);
        Result.NodeValue := NewInlineNode;
      end;
  else
    Result := nil;
  end;
end;

function TGrispRewriter.BuildRewriteSubgraph(
  RewriteRoot: TGNode; Match: TMatchResult;
  out NewNodes: TList<TGNode>; out NewEdges: TList<TGEdge>): Boolean;
var
  NodeVarMap: TDictionary<string, TGNode>;
  AttrKey, Key: string;
  AttrVal: TGValue;
  BoundNode, NewNode: TGNode;
  InlineTemplate: TGNode;
  EvaluatedVal: TGValue;
begin
  Result := False;
  NewNodes := TList<TGNode>.Create;
  NewEdges := TList<TGEdge>.Create;

  NodeVarMap := TDictionary<string, TGNode>.Create;
  try
    // Phase 1: Match or create node variables from the RewriteRoot template attributes
    for AttrKey in RewriteRoot.Attributes.Keys do
    begin
      AttrVal := RewriteRoot.GetAttribute(AttrKey);
      if (AttrVal <> nil) and (AttrVal.Kind = vkNode) then
      begin
        if Match.TryGetNode(AttrKey, BoundNode) then
        begin
          NodeVarMap.Add(AttrKey, BoundNode);
        end
        else
        begin
          // Create new node for previously unbound node variables
          NewNode := FGraph.AddNode('', 'node');
          NewNodes.Add(NewNode);
          NodeVarMap.Add(AttrKey, NewNode);
        end;
      end;
    end;

    // Phase 2: For each node variable, evaluate and update attributes and edges
    for AttrKey in RewriteRoot.Attributes.Keys do
    begin
      AttrVal := RewriteRoot.GetAttribute(AttrKey);
      if (AttrVal <> nil) and (AttrVal.Kind = vkNode) then
      begin
        BoundNode := NodeVarMap[AttrKey];
        InlineTemplate := AttrVal.NodeValue;

        if Assigned(InlineTemplate) then
        begin
          for Key in InlineTemplate.Attributes.Keys do
          begin
            EvaluatedVal := EvaluateValue(InlineTemplate.GetAttribute(Key), Match, NodeVarMap, NewNodes);

            // If updating 'name', keep NodeIndex updated explicitly
            if SameText(Key, 'name') and (EvaluatedVal <> nil) and (EvaluatedVal.Kind = vkIdentifier) then
            begin
              if BoundNode.Name <> '' then
                FGraph.NodeIndex.Remove(BoundNode.Name);
              BoundNode.Name := EvaluatedVal.IdentifierValue;
              if BoundNode.Name <> '' then
                FGraph.NodeIndex.AddOrSetValue(BoundNode.Name, BoundNode);
            end;

            // Update attribute directly
            BoundNode.SetAttribute(Key, EvaluatedVal);

            // Splicing: remove old edges for this attribute key
            SafeRemoveEdgesForAttribute(BoundNode, Key);

            // Splicing: add new edge if the attribute value represents a node Target
            if Assigned(EvaluatedVal) then
            begin
              if EvaluatedVal.Kind = vkNode then
              begin
                if Assigned(EvaluatedVal.NodeValue) then
                  NewEdges.Add(FGraph.AddEdge(BoundNode, EvaluatedVal.NodeValue, Key));
              end
              else if EvaluatedVal.Kind = vkIdentifier then
              begin
                NewNode := FGraph.FindNode(EvaluatedVal.IdentifierValue);
                if Assigned(NewNode) then
                  NewEdges.Add(FGraph.AddEdge(BoundNode, NewNode, Key));
              end;
            end;
          end;
        end;
      end;
    end;

    Result := True;
  finally
    NodeVarMap.Free;
  end;
end;

procedure TGrispRewriter.ApplyRewriteToGraph(
  ARule: TGNode; Match: TMatchResult;
  NewNodes: TList<TGNode>; NewEdges: TList<TGEdge>);
begin
  // Splice / updates were completed during the build phase in a transactional manner.
end;

function TGrispRewriter.ApplyRuleOnce(ARule: TGNode; Matcher: TGrispPatternMatcher): Boolean;
var
  MatchRoot, RewriteRoot: TGNode;
  Match: TMatchResult;
  NewNodes: TList<TGNode>;
  NewEdges: TList<TGEdge>;
begin
  Result := False;

  MatchRoot := GetMatchRoot(ARule);
  RewriteRoot := GetRewriteRoot(ARule);
  if (MatchRoot = nil) or (RewriteRoot = nil) then
    Exit;

  Match := Matcher.MatchPattern(MatchRoot);
  try
    if not Match.Success then
      Exit;

    NewNodes := TList<TGNode>.Create;
    NewEdges := TList<TGEdge>.Create;
    try
      if not BuildRewriteSubgraph(RewriteRoot, Match, NewNodes, NewEdges) then
        Exit;

      ApplyRewriteToGraph(ARule, Match, NewNodes, NewEdges);
      Result := True;
    finally
      NewEdges.Free;
      NewNodes.Free;
    end;
  finally
    Match.Free;
  end;
end;

end.
