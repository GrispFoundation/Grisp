unit Grisp.Parser;

interface

uses
  System.SysUtils, System.Generics.Collections, Grisp.Core, Grisp.AST, Grisp.JSON;

function TryGetMapValue(const AVal: TValue; const AKey: string; out AValueOut: TValue): Boolean;
function TryGetMapString(const AVal: TValue; const AKey: string; out AStrOut: string): Boolean;
function TryGetMapInt(const AVal: TValue; const AKey: string; out AIntOut: Int64): Boolean;

function ParseExpr(const AVal: TValue): TExpr;
function ParsePattern(const AVal: TValue): TPattern;
function ParseLetBinding(const AVal: TValue): TLetBinding;
function ParseAction(const AVal: TValue): TAction;
function ParseRule(const AVal: TValue): TRule;

procedure ParseInput(const AInputJSON: string; out AIRRules: TObjectList<TRule>; out AState: TState; out AMaxTicks: Int64; out ATypeHash: string);

implementation

function TryGetMapValue(const AVal: TValue; const AKey: string; out AValueOut: TValue): Boolean;
var
  i: Integer;
begin
  if AVal.ValType = vtMap then
  begin
    for i := 0 to High(AVal.MapValue) do
      if AVal.MapValue[i].Key = AKey then
      begin
        AValueOut := AVal.MapValue[i].Value;
        Exit(True);
      end;
  end;
  Result := False;
end;

function TryGetMapString(const AVal: TValue; const AKey: string; out AStrOut: string): Boolean;
var
  V: TValue;
begin
  if TryGetMapValue(AVal, AKey, V) and (V.ValType = vtString) then
  begin
    AStrOut := V.StrValue;
    Exit(True);
  end;
  Result := False;
end;

function TryGetMapInt(const AVal: TValue; const AKey: string; out AIntOut: Int64): Boolean;
var
  V: TValue;
begin
  if TryGetMapValue(AVal, AKey, V) and (V.ValType = vtInteger) then
  begin
    AIntOut := V.IntValue;
    Exit(True);
  end;
  Result := False;
end;

function ParseExpr(const AVal: TValue): TExpr;
var
  Tag, Op, VarName, FieldName: string;
  ScaleVal: Byte;
  LeftVal, RightVal, SubExprVal, ValueVal: TValue;
  IntVal: Int64;
begin
  if AVal.ValType <> vtMap then
    Exit(TExprLiteral.Create(AVal));

  if not TryGetMapString(AVal, 'tag', Tag) then
    if not TryGetMapString(AVal, 'type', Tag) then
      raise Exception.Create('Expression object missing "tag" or "type": ' + AVal.ToString);

  if (Tag = 'Literal') or (Tag = 'literal') then
  begin
    if not TryGetMapValue(AVal, 'value', ValueVal) then
      raise Exception.Create('Literal expression missing "value"');
	Exit(TExprLiteral.Create(ValueVal));
  end;

  if (Tag = 'Var') or (Tag = 'Variable') or (Tag = 'var') or (Tag = 'variable') then
  begin
    if not TryGetMapString(AVal, 'name', VarName) then
      if not TryGetMapString(AVal, 'var_name', VarName) then
        if not TryGetMapString(AVal, 'variable', VarName) then
          raise Exception.Create('Variable expression missing "name"');
    Exit(TExprVar.Create(VarName));
  end;

  if (Tag = 'Field') or (Tag = 'FieldAccess') or (Tag = 'field') or (Tag = 'field_access') then
  begin
    if not TryGetMapString(AVal, 'variable', VarName) then
      if not TryGetMapString(AVal, 'var_name', VarName) then
        raise Exception.Create('FieldAccess expression missing "variable"');
    if not TryGetMapString(AVal, 'field', FieldName) then
      if not TryGetMapString(AVal, 'field_name', FieldName) then
        raise Exception.Create('FieldAccess expression missing "field"');
    Exit(TExprField.Create(VarName, FieldName));
  end;

  if (Tag = 'Binary') or (Tag = 'BinaryOp') or (Tag = 'binary') or (Tag = 'binary_op') then
  begin
    if not TryGetMapString(AVal, 'op', Op) then
      if not TryGetMapString(AVal, 'operator', Op) then
        raise Exception.Create('Binary expression missing "op"');
    if not TryGetMapValue(AVal, 'left', LeftVal) then
      raise Exception.Create('Binary expression missing "left"');
    if not TryGetMapValue(AVal, 'right', RightVal) then
      raise Exception.Create('Binary expression missing "right"');
    Exit(TExprBinary.Create(Op, ParseExpr(LeftVal), ParseExpr(RightVal)));
  end;

  if (Tag = 'Len') or (Tag = 'len') or (Tag = 'Length') or (Tag = 'length') then
  begin
    if not TryGetMapValue(AVal, 'expr', SubExprVal) then
      if not TryGetMapValue(AVal, 'expression', SubExprVal) then
        raise Exception.Create('Len expression missing "expr"');
    Exit(TExprLen.Create(ParseExpr(SubExprVal)));
  end;

  if (Tag = 'ToFixed') or (Tag = 'to_fixed') or (Tag = 'ToFixedPoint') then
  begin
    if not TryGetMapValue(AVal, 'expr', SubExprVal) then
      if not TryGetMapValue(AVal, 'expression', SubExprVal) then
        raise Exception.Create('ToFixed expression missing "expr"');
    if not TryGetMapInt(AVal, 'scale', IntVal) then
      raise Exception.Create('ToFixed expression missing "scale"');
    ScaleVal := Byte(IntVal);
    Exit(TExprToFixed.Create(ParseExpr(SubExprVal), ScaleVal));
  end;

  if (Tag = 'ToInteger') or (Tag = 'to_integer') or (Tag = 'ToInt') then
  begin
    if not TryGetMapValue(AVal, 'expr', SubExprVal) then
      if not TryGetMapValue(AVal, 'expression', SubExprVal) then
        raise Exception.Create('ToInteger expression missing "expr"');
    Exit(TExprToInteger.Create(ParseExpr(SubExprVal)));
  end;

  raise Exception.Create('Unknown expression tag: ' + Tag);
end;

function ParsePattern(const AVal: TValue): TPattern;
var
  Tag, VarName, TypeName, SrcVar, TgtVar: string;
begin
  if AVal.ValType <> vtMap then
    raise Exception.Create('Pattern must be a JSON object');

  if not TryGetMapString(AVal, 'tag', Tag) then
    if not TryGetMapString(AVal, 'type', Tag) then
      raise Exception.Create('Pattern missing "tag" or "type"');

  if not TryGetMapString(AVal, 'variable', VarName) then
    if not TryGetMapString(AVal, 'var_name', VarName) then
      if not TryGetMapString(AVal, 'name', VarName) then
        raise Exception.Create('Pattern missing "variable"');

  if not TryGetMapString(AVal, 'type_name', TypeName) then
    if not TryGetMapString(AVal, 'type', TypeName) then
      raise Exception.Create('Pattern missing "type_name"');

  if (Tag = 'MatchNode') or (Tag = 'match_node') then
    Exit(TPattern.CreateNode(VarName, TypeName));

  if (Tag = 'MatchEdge') or (Tag = 'match_edge') then
  begin
    if not TryGetMapString(AVal, 'src', SrcVar) then
      if not TryGetMapString(AVal, 'source', SrcVar) then
        raise Exception.Create('MatchEdge missing "src"');
    if not TryGetMapString(AVal, 'tgt', TgtVar) then
      if not TryGetMapString(AVal, 'target', TgtVar) then
        raise Exception.Create('MatchEdge missing "tgt"');
    Exit(TPattern.CreateEdge(VarName, TypeName, SrcVar, TgtVar));
  end;

  raise Exception.Create('Unknown pattern tag: ' + Tag);
end;

function ParseLetBinding(const AVal: TValue): TLetBinding;
var
  VarName: string;
  ExprVal: TValue;
begin
  if AVal.ValType <> vtMap then
    raise Exception.Create('LetBinding must be a JSON object');

  if not TryGetMapString(AVal, 'variable', VarName) then
    if not TryGetMapString(AVal, 'var_name', VarName) then
      raise Exception.Create('LetBinding missing "variable"');

  if not TryGetMapValue(AVal, 'expr', ExprVal) then
    if not TryGetMapValue(AVal, 'expression', ExprVal) then
      raise Exception.Create('LetBinding missing "expr"');

  Result := TLetBinding.Create(VarName, ParseExpr(ExprVal));
end;

function ParseAction(const AVal: TValue): TAction;
var
  Tag, VarName, TypeName, FieldName, EventType: string;
  FieldsVal, SrcVal, TgtVal, ExprVal, TargetVal, PayloadVal: TValue;
  FieldsArray: TArray<TFieldExprEntry>;
  PayloadsArray: TArray<TExpr>;
  i: Integer;
begin
  if AVal.ValType <> vtMap then
    raise Exception.Create('Action must be a JSON object');

  if not TryGetMapString(AVal, 'tag', Tag) then
    if not TryGetMapString(AVal, 'type', Tag) then
      raise Exception.Create('Action missing "tag" or "type"');

  if (Tag = 'CreateNode') or (Tag = 'create_node') then
  begin
    if not TryGetMapString(AVal, 'variable', VarName) then
      if not TryGetMapString(AVal, 'var_name', VarName) then
        raise Exception.Create('CreateNode missing "variable"');
    if not TryGetMapString(AVal, 'type_name', TypeName) then
      raise Exception.Create('CreateNode missing "type_name"');
    FieldsArray := nil;
	if TryGetMapValue(AVal, 'fields', FieldsVal) and (FieldsVal.ValType = vtMap) then
    begin
      SetLength(FieldsArray, Length(FieldsVal.MapValue));
      for i := 0 to High(FieldsVal.MapValue) do
      begin
        FieldsArray[i].Name := FieldsVal.MapValue[i].Key;
        FieldsArray[i].Expr := ParseExpr(FieldsVal.MapValue[i].Value);
      end;
    end;
    Exit(TActionCreateNode.Create(VarName, TypeName, FieldsArray));
  end;

  if (Tag = 'CreateEdge') or (Tag = 'create_edge') then
  begin
    if not TryGetMapString(AVal, 'variable', VarName) then
      if not TryGetMapString(AVal, 'var_name', VarName) then
        raise Exception.Create('CreateEdge missing "variable"');
    if not TryGetMapString(AVal, 'type_name', TypeName) then
      raise Exception.Create('CreateEdge missing "type_name"');
    if not TryGetMapValue(AVal, 'src', SrcVal) then
      if not TryGetMapValue(AVal, 'source', SrcVal) then
        raise Exception.Create('CreateEdge missing "src"');
    if not TryGetMapValue(AVal, 'tgt', TgtVal) then
      if not TryGetMapValue(AVal, 'target', TgtVal) then
        raise Exception.Create('CreateEdge missing "tgt"');
    FieldsArray := nil;
    if TryGetMapValue(AVal, 'fields', FieldsVal) and (FieldsVal.ValType = vtMap) then
    begin
      SetLength(FieldsArray, Length(FieldsVal.MapValue));
      for i := 0 to High(FieldsVal.MapValue) do
      begin
        FieldsArray[i].Name := FieldsVal.MapValue[i].Key;
        FieldsArray[i].Expr := ParseExpr(FieldsVal.MapValue[i].Value);
      end;
    end;
    Exit(TActionCreateEdge.Create(VarName, TypeName, ParseExpr(SrcVal), ParseExpr(TgtVal), FieldsArray));
  end;

  if (Tag = 'UpdateField') or (Tag = 'update_field') then
  begin
    if not TryGetMapValue(AVal, 'target', TargetVal) then
      raise Exception.Create('UpdateField missing "target"');
    if not TryGetMapString(AVal, 'field', FieldName) then
      if not TryGetMapString(AVal, 'field_name', FieldName) then
        raise Exception.Create('UpdateField missing "field"');
    if not TryGetMapValue(AVal, 'expr', ExprVal) then
      if not TryGetMapValue(AVal, 'expression', ExprVal) then
        raise Exception.Create('UpdateField missing "expr"');
    Exit(TActionUpdateField.Create(ParseExpr(TargetVal), FieldName, ParseExpr(ExprVal)));
  end;

  if (Tag = 'DeleteEdge') or (Tag = 'delete_edge') then
  begin
    if not TryGetMapValue(AVal, 'expr', ExprVal) then
      if not TryGetMapValue(AVal, 'expression', ExprVal) then
        raise Exception.Create('DeleteEdge missing "expr"');
    Exit(TActionDeleteEdge.Create(ParseExpr(ExprVal)));
  end;

  if (Tag = 'DeleteNode') or (Tag = 'delete_node') then
  begin
    if not TryGetMapString(AVal, 'variable', VarName) then
      if not TryGetMapString(AVal, 'var_name', VarName) then
        raise Exception.Create('DeleteNode missing "variable"');
    Exit(TActionDeleteNode.Create(VarName));
  end;

  if (Tag = 'EmitEvent') or (Tag = 'emit_event') then
  begin
    if not TryGetMapString(AVal, 'event_type', EventType) then
      raise Exception.Create('EmitEvent missing "event_type"');
    PayloadsArray := nil;
	if TryGetMapValue(AVal, 'payload', PayloadVal) or TryGetMapValue(AVal, 'payloads', PayloadVal) then
    begin
      if PayloadVal.ValType = vtList then
      begin
        SetLength(PayloadsArray, Length(PayloadVal.ListValue));
        for i := 0 to High(PayloadVal.ListValue) do
          PayloadsArray[i] := ParseExpr(PayloadVal.ListValue[i]);
      end;
    end;
    Exit(TActionEmitEvent.Create(EventType, PayloadsArray));
  end;

  raise Exception.Create('Unknown action tag: ' + Tag);
end;

function ParseRule(const AVal: TValue): TRule;
var
  RuleId: string;
  BasePri, PriScale, FairScale: Int64;
  PatsVal, ConstsVal, LetsVal, ActsVal: TValue;
  i: Integer;
begin
  if AVal.ValType <> vtMap then
    raise Exception.Create('Rule must be a JSON object');

  if not TryGetMapString(AVal, 'rule_id', RuleId) then
    raise Exception.Create('Rule missing "rule_id"');

  if not TryGetMapInt(AVal, 'base_priority', BasePri) then BasePri := 0;
  if not TryGetMapInt(AVal, 'priority_scale', PriScale) then PriScale := 1;
  if not TryGetMapInt(AVal, 'fairness_scale', FairScale) then FairScale := 1;

  Result := TRule.Create(RuleId, BasePri, PriScale, FairScale);
  try
    if TryGetMapValue(AVal, 'patterns', PatsVal) and (PatsVal.ValType = vtList) then
      for i := 0 to High(PatsVal.ListValue) do
        Result.Patterns.Add(ParsePattern(PatsVal.ListValue[i]));

    if TryGetMapValue(AVal, 'constraints', ConstsVal) and (ConstsVal.ValType = vtList) then
      for i := 0 to High(ConstsVal.ListValue) do
        Result.Constraints.Add(ParseExpr(ConstsVal.ListValue[i]));

    if TryGetMapValue(AVal, 'let_bindings', LetsVal) and (LetsVal.ValType = vtList) then
      for i := 0 to High(LetsVal.ListValue) do
        Result.LetBindings.Add(ParseLetBinding(LetsVal.ListValue[i]));

    if TryGetMapValue(AVal, 'actions', ActsVal) and (ActsVal.ValType = vtList) then
      for i := 0 to High(ActsVal.ListValue) do
        Result.Actions.Add(ParseAction(ActsVal.ListValue[i]));
  except
    Result.Free;
    raise;
  end;
end;

procedure ParseGraph(const AGraphVal: TValue; AGraph: TGraph);
var
  NodesVal, EdgesVal, NodeVal, EdgeVal, FieldsVal, FVal: TValue;
  i, j: Integer;
  NodeId, EdgeId, SrcId, TgtId: TIdentifier;
  NodeTypeName, EdgeTypeName: string;
  NodeObj: TNode;
  EdgeObj: TEdge;
begin
  if AGraphVal.ValType <> vtMap then Exit;

  if TryGetMapValue(AGraphVal, 'nodes', NodesVal) then
  begin
    if NodesVal.ValType = vtList then
    begin
      for i := 0 to High(NodesVal.ListValue) do
      begin
		NodeVal := NodesVal.ListValue[i];
        if not TryGetMapValue(NodeVal, 'id', FVal) then raise Exception.Create('Node missing "id"');
        NodeId := ValueToIdent(FVal);
        if not TryGetMapString(NodeVal, 'type', NodeTypeName) then
          NodeTypeName := NodeId.TypeName;
        NodeObj := TNode.Create(NodeId, NodeTypeName);
        if TryGetMapValue(NodeVal, 'fields', FieldsVal) and (FieldsVal.ValType = vtMap) then
          for j := 0 to High(FieldsVal.MapValue) do
            NodeObj.SetField(FieldsVal.MapValue[j].Key, FieldsVal.MapValue[j].Value);
        AGraph.AddNode(NodeObj);
      end;
    end
    else if NodesVal.ValType = vtMap then
    begin
      for i := 0 to High(NodesVal.MapValue) do
      begin
        NodeId := ValueToIdent(TValue.CreateString(NodesVal.MapValue[i].Key));
        NodeVal := NodesVal.MapValue[i].Value;
        NodeTypeName := NodeId.TypeName;
        NodeObj := TNode.Create(NodeId, NodeTypeName);
        if NodeVal.ValType = vtMap then
          for j := 0 to High(NodeVal.MapValue) do
            NodeObj.SetField(NodeVal.MapValue[j].Key, NodeVal.MapValue[j].Value);
        AGraph.AddNode(NodeObj);
      end;
    end;
  end;

  if TryGetMapValue(AGraphVal, 'edges', EdgesVal) then
  begin
    if EdgesVal.ValType = vtList then
    begin
      for i := 0 to High(EdgesVal.ListValue) do
      begin
        EdgeVal := EdgesVal.ListValue[i];
        if not TryGetMapValue(EdgeVal, 'id', FVal) then raise Exception.Create('Edge missing "id"');
        EdgeId := ValueToIdent(FVal);
        if not TryGetMapString(EdgeVal, 'type', EdgeTypeName) then
          EdgeTypeName := EdgeId.TypeName;
        if not TryGetMapValue(EdgeVal, 'src', FVal) and not TryGetMapValue(EdgeVal, 'source', FVal) then
          raise Exception.Create('Edge missing "src"');
        SrcId := ValueToIdent(FVal);
        if not TryGetMapValue(EdgeVal, 'tgt', FVal) and not TryGetMapValue(EdgeVal, 'target', FVal) then
          raise Exception.Create('Edge missing "tgt"');
        TgtId := ValueToIdent(FVal);
        EdgeObj := TEdge.Create(EdgeId, EdgeTypeName, SrcId, TgtId);
        if TryGetMapValue(EdgeVal, 'fields', FieldsVal) and (FieldsVal.ValType = vtMap) then
          for j := 0 to High(FieldsVal.MapValue) do
            EdgeObj.SetField(FieldsVal.MapValue[j].Key, FieldsVal.MapValue[j].Value);
        AGraph.AddEdge(EdgeObj);
      end;
    end
    else if EdgesVal.ValType = vtMap then
    begin
      for i := 0 to High(EdgesVal.MapValue) do
      begin
        EdgeId := ValueToIdent(TValue.CreateString(EdgesVal.MapValue[i].Key));
        EdgeVal := EdgesVal.MapValue[i].Value;
        EdgeTypeName := EdgeId.TypeName;
        if not TryGetMapValue(EdgeVal, 'src', FVal) and not TryGetMapValue(EdgeVal, 'source', FVal) then
          raise Exception.Create('Edge missing "src"');
        SrcId := ValueToIdent(FVal);
        if not TryGetMapValue(EdgeVal, 'tgt', FVal) and not TryGetMapValue(EdgeVal, 'target', FVal) then
          raise Exception.Create('Edge missing "tgt"');
        TgtId := ValueToIdent(FVal);
        EdgeObj := TEdge.Create(EdgeId, EdgeTypeName, SrcId, TgtId);
        if EdgeVal.ValType = vtMap then
          for j := 0 to High(EdgeVal.MapValue) do
            EdgeObj.SetField(EdgeVal.MapValue[j].Key, EdgeVal.MapValue[j].Value);
        AGraph.AddEdge(EdgeObj);
      end;
    end;
  end;
end;

procedure ParseInput(const AInputJSON: string; out AIRRules: TObjectList<TRule>; out AState: TState; out AMaxTicks: Int64; out ATypeHash: string);
var
  RootVal, RulesVal, InitStateVal, GraphVal, PrevMatchesVal, TickVal: TValue;
  i: Integer;
  Node: TNode;
  Edge: TEdge;
begin
  AIRRules := TObjectList<TRule>.Create(True);
  AState := TState.Create;
  AMaxTicks := 1000;
  ATypeHash := '';

  RootVal := ParseJSON(AInputJSON);
  if RootVal.ValType <> vtMap then
    raise Exception.Create('Root of input must be a JSON object');

  TryGetMapString(RootVal, 'type_definitions_hash', ATypeHash);
  TryGetMapInt(RootVal, 'max_ticks', AMaxTicks);

  if TryGetMapValue(RootVal, 'rules', RulesVal) and (RulesVal.ValType = vtList) then
    for i := 0 to High(RulesVal.ListValue) do
      AIRRules.Add(ParseRule(RulesVal.ListValue[i]));

  if TryGetMapValue(RootVal, 'initial_state', InitStateVal) and (InitStateVal.ValType = vtMap) then
  begin
    if TryGetMapInt(InitStateVal, 'tick_number', TickVal.IntValue) then
      AState.TickNumber := TickVal.IntValue
    else if TryGetMapInt(InitStateVal, 'tick', TickVal.IntValue) then
      AState.TickNumber := TickVal.IntValue;

    if TryGetMapValue(InitStateVal, 'graph', GraphVal) then
      ParseGraph(GraphVal, AState.Graph);

    if TryGetMapValue(InitStateVal, 'prev_matches', PrevMatchesVal) and (PrevMatchesVal.ValType = vtMap) then
      for i := 0 to High(PrevMatchesVal.MapValue) do
        if PrevMatchesVal.MapValue[i].Value.ValType = vtInteger then
          AState.PrevMatches.Add(PrevMatchesVal.MapValue[i].Key, PrevMatchesVal.MapValue[i].Value.IntValue);
  end;

  // Initialize counters from graph
  AState.Counters.TickCounter := AState.TickNumber;
  for Node in AState.Graph.Nodes do
    if Node.Id.SequenceNumber >= AState.Counters.GetSequenceCounter(Node.TypeName) then
      AState.Counters.SetSequenceCounter(Node.TypeName, Node.Id.SequenceNumber + 1);
  for Edge in AState.Graph.Edges do
    if Edge.Id.SequenceNumber >= AState.Counters.GetSequenceCounter(Edge.TypeName) then
      AState.Counters.SetSequenceCounter(Edge.TypeName, Edge.Id.SequenceNumber + 1);

  for Node in AState.Graph.Nodes do
  begin
    AState.Counters.SetExistenceVersion(Node.Id, 1);
    for i := 0 to High(Node.Fields) do
      AState.Counters.SetFieldVersion(Node.Id, Node.Fields[i].Name, 1);
  end;
  for Edge in AState.Graph.Edges do
  begin
    AState.Counters.SetExistenceVersion(Edge.Id, 1);
    for i := 0 to High(Edge.Fields) do
      AState.Counters.SetFieldVersion(Edge.Id, Edge.Fields[i].Name, 1);
  end;

  for Node in AState.Graph.Nodes do
    if AState.Counters.GetExtentVersion(Node.TypeName) = 0 then
      AState.Counters.ExtentVersions.AddOrSetValue(Node.TypeName, 1);
  for Edge in AState.Graph.Edges do
    if AState.Counters.GetEdgeTypeVersion(Edge.TypeName) = 0 then
      AState.Counters.EdgeTypeVersions.AddOrSetValue(Edge.TypeName, 1);
end;

end.
