unit unit_GrispRewrite_version_001;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  unit_GrispGraph_version_001,
  unit_GrispPattern_version_001;

type
  TRewriteOperation = record
    TargetNode: TGNode;
    Attributes: TDictionary<string, TGValue>;
    EdgesToAdd: TList<TPair<string, TGNode>>;
  end;

  TGrispRewriter = class
  private
    FGraph: TGGraph;
    FOperations: TList<TRewriteOperation>;

    function GetMatchRoot(ARule: TGNode): TGNode;
    function GetRewriteRoot(ARule: TGNode): TGNode;
    function CloneValue(AValue: TGValue): TGValue;
    function EvaluateValue(
      TemplateVal: TGValue;
      Match: TMatchResult;
      NodeVarMap: TDictionary<string, TGNode>;
      NewNodes: TList<TGNode>): TGValue;
	procedure CollectRewriteOperations(
      RewriteRoot: TGNode;
      Match: TMatchResult;
      NewNodes: TList<TGNode>;
      Operations: TList<TRewriteOperation>);
    procedure ApplyOperations(Operations: TList<TRewriteOperation>);
  public
    constructor Create(AGraph: TGGraph);
    destructor Destroy; override;
    function ApplyAllMatches(ARule: TGNode; Matcher: TGrispPatternMatcher; Trace: TStrings = nil): Integer;
  end;

implementation

{ TGrispRewriter }

constructor TGrispRewriter.Create(AGraph: TGGraph);
begin
  inherited Create;
  FGraph := AGraph;
  FOperations := TList<TRewriteOperation>.Create;
end;

destructor TGrispRewriter.Destroy;
var
  Op: TRewriteOperation;
begin
  for Op in FOperations do
  begin
    Op.Attributes.Free;
    Op.EdgesToAdd.Free;
  end;
  FOperations.Free;
  inherited Destroy;
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
  if AValue = nil then Exit(nil);
  Result := TGValue.Create(AValue.Kind);
  case AValue.Kind of
    vkNumber:  Result.NumberValue := AValue.NumberValue;
    vkString:  Result.StringValue := AValue.StringValue;
    vkBoolean: Result.BoolValue := AValue.BoolValue;
    vkIdentifier: Result.IdentifierValue := AValue.IdentifierValue;
    vkArray:
      for Elem in AValue.ArrayValue do
        Result.ArrayValue.Add(CloneValue(Elem));
    vkNode:
      Result.NodeValue := AValue.NodeValue;
    vkExpression:
      Result.ExpressionValue := AValue.ExpressionValue;
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
  if TemplateVal = nil then Exit(nil);

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
        else if Match.TryGetValue(TemplateVal.IdentifierValue, BoundVal) then
        begin
          Result := CloneValue(BoundVal);
        end
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
          Result.ArrayValue.Add(EvaluateValue(Elem, Match, NodeVarMap, NewNodes));
      end;
    vkNode:
      begin
        NewInlineNode := FGraph.AddNode('', 'node');
        NewNodes.Add(NewInlineNode);
        if Assigned(TemplateVal.NodeValue) then
          for AttrKey in TemplateVal.NodeValue.Attributes.Keys do
            NewInlineNode.SetAttribute(
              AttrKey,
              EvaluateValue(TemplateVal.NodeValue.GetAttribute(AttrKey), Match, NodeVarMap, NewNodes)
            );
		Result := TGValue.Create(vkNode);
        Result.NodeValue := NewInlineNode;
      end;
  else
    Result := nil;
  end;
end;

procedure TGrispRewriter.CollectRewriteOperations(
  RewriteRoot: TGNode;
  Match: TMatchResult;
  NewNodes: TList<TGNode>;
  Operations: TList<TRewriteOperation>);
var
  NodeVarMap: TDictionary<string, TGNode>;
  AttrKey, Key: string;
  AttrVal: TGValue;
  BoundNode, NewNode: TGNode;
  InlineTemplate: TGNode;
  EvaluatedVal: TGValue;
  Op: TRewriteOperation;
  EdgePair: TPair<string, TGNode>;
begin
  NodeVarMap := TDictionary<string, TGNode>.Create;
  try
    // Phase 1: bind or create node variables
    for AttrKey in RewriteRoot.Attributes.Keys do
    begin
      AttrVal := RewriteRoot.GetAttribute(AttrKey);
      if (AttrVal <> nil) and (AttrVal.Kind = vkNode) then
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

    // Phase 2: collect operations
    for AttrKey in RewriteRoot.Attributes.Keys do
    begin
      AttrVal := RewriteRoot.GetAttribute(AttrKey);
      if (AttrVal <> nil) and (AttrVal.Kind = vkNode) then
      begin
        BoundNode := NodeVarMap[AttrKey];
        InlineTemplate := AttrVal.NodeValue;

        if Assigned(InlineTemplate) then
        begin
          Op.TargetNode := BoundNode;
          Op.Attributes := TDictionary<string, TGValue>.Create;
          Op.EdgesToAdd := TList<TPair<string, TGNode>>.Create;

          for Key in InlineTemplate.Attributes.Keys do
          begin
            EvaluatedVal := EvaluateValue(InlineTemplate.GetAttribute(Key), Match, NodeVarMap, NewNodes);

            // Skip 'next' attribute if it would create a self-reference or cycle
            if (Key = 'next') and (EvaluatedVal <> nil) and (EvaluatedVal.Kind = vkIdentifier) then
            begin
              var TargetNode := FGraph.FindNode(EvaluatedVal.IdentifierValue);
              if Assigned(TargetNode) and (TargetNode = BoundNode) then
                Continue; // Skip self-reference
            end;

            if SameText(Key, 'name') and (EvaluatedVal <> nil) and (EvaluatedVal.Kind = vkIdentifier) then
            begin
              // Handle name change
              Op.Attributes.AddOrSetValue(Key, EvaluatedVal);
            end
            else
            begin
              Op.Attributes.AddOrSetValue(Key, EvaluatedVal);

              // Collect edge info
              if Assigned(EvaluatedVal) then
              begin
                if EvaluatedVal.Kind = vkNode then
                begin
                  if Assigned(EvaluatedVal.NodeValue) then
                  begin
                    EdgePair.Key := Key;
                    EdgePair.Value := EvaluatedVal.NodeValue;
                    Op.EdgesToAdd.Add(EdgePair);
                  end;
                end
                else if EvaluatedVal.Kind = vkIdentifier then
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

          // Only add operation if it has meaningful changes
          if (Op.Attributes.Count > 0) or (Op.EdgesToAdd.Count > 0) then
            Operations.Add(Op)
          else
          begin
            Op.Attributes.Free;
            Op.EdgesToAdd.Free;
          end;
        end;
      end;
    end;
  finally
    NodeVarMap.Free;
  end;
end;

procedure TGrispRewriter.ApplyOperations(Operations: TList<TRewriteOperation>);
var
  Op: TRewriteOperation;
  Pair: TPair<string, TGNode>;
  AttrKey: string;
  AttrVal: TGValue;
begin
  for Op in Operations do
  begin
	// Apply attribute changes
	for AttrKey in Op.Attributes.Keys do
	begin
	  AttrVal := Op.Attributes[AttrKey];

	  // Handle name change
	  if SameText(AttrKey, 'name') and (AttrVal <> nil) and (AttrVal.Kind = vkIdentifier) then
	  begin
		if Op.TargetNode.Name <> '' then
		  FGraph.NodeIndex.Remove(Op.TargetNode.Name);
		Op.TargetNode.Name := AttrVal.IdentifierValue;
		if Op.TargetNode.Name <> '' then
		  FGraph.NodeIndex.AddOrSetValue(Op.TargetNode.Name, Op.TargetNode);
	  end;

	  Op.TargetNode.SetAttribute(AttrKey, AttrVal);
	end;

	// Remove old edges and add new ones
	for Pair in Op.EdgesToAdd do
	begin
	  // Note: Edge removal would need to be handled here
	  FGraph.AddEdge(Op.TargetNode, Pair.Value, Pair.Key);
	end;
  end;
end;

function TGrispRewriter.ApplyAllMatches(ARule: TGNode; Matcher: TGrispPatternMatcher; Trace: TStrings): Integer;
var
  MatchRoot, RewriteRoot: TGNode;
  MatchResults: TList<TMatchResult>;
  NewNodes: TList<TGNode>;
  AllOperations: TList<TRewriteOperation>;
  Op: TRewriteOperation;
  TotalApplied: Integer;
  i: Integer;
  M: TMatchResult;
  HasOverlap: Boolean;
  UsedNodes: THashSet<TGNode>;
  SelectedMatches: TList<TMatchResult>;
  BNode: TNodeBinding;
begin
  Result := 0;
  TotalApplied := 0;

  MatchRoot := GetMatchRoot(ARule);
  RewriteRoot := GetRewriteRoot(ARule);
  if (MatchRoot = nil) or (RewriteRoot = nil) then
    Exit;

  // Keep finding and applying matches until no more
  repeat
    MatchResults := Matcher.FindAllMatches(MatchRoot);
    try
      if MatchResults.Count = 0 then
        Break;

      if Assigned(Trace) then
        Trace.Add(Format('Found %d matches for rule %s', [MatchResults.Count, ARule.Name]));

      // Select non-overlapping matches
      UsedNodes := THashSet<TGNode>.Create;
      SelectedMatches := TList<TMatchResult>.Create;
      try
        for M in MatchResults do
        begin
          // Check if this match overlaps with already selected ones
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

        // Build operations for selected matches
        NewNodes := TList<TGNode>.Create;
        AllOperations := TList<TRewriteOperation>.Create;
        try
          for i := 0 to SelectedMatches.Count - 1 do
          begin
            M := SelectedMatches[i];
            CollectRewriteOperations(RewriteRoot, M, NewNodes, AllOperations);
          end;

          // Apply all operations
          if AllOperations.Count > 0 then
          begin
            ApplyOperations(AllOperations);
            Inc(TotalApplied, AllOperations.Count);
            if Assigned(Trace) then
              Trace.Add(Format('Applied %d rewrites (total: %d)', [AllOperations.Count, TotalApplied]));
          end;
        finally
          for Op in AllOperations do
          begin
            Op.Attributes.Free;
            Op.EdgesToAdd.Free;
          end;
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
  until False;  // Continue until no matches found

  Result := TotalApplied;
end;

end.
