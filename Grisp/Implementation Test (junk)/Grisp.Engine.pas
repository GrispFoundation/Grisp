unit Grisp.Engine;

interface

uses
  System.SysUtils, System.Generics.Collections, System.Generics.Defaults, Grisp.Core, Grisp.AST, Grisp.Evaluator, Grisp.JSON;

type
  TPrimitiveActionType = (patCreateNode, patCreateEdge, patUpdateField, patDeleteEdge, patDeleteNode, patEmitEvent);

  TFieldValEntry = record
    Name: string;
    Value: TValue;
  end;

  TPrimitiveAction = record
    ActType: TPrimitiveActionType;
    ElementId: TIdentifier;
    TypeName: string;
    SrcId: TIdentifier;
    TgtId: TIdentifier;
    FieldName: string;
    Value: TValue;
    Fields: TArray<TFieldValEntry>;
    Payloads: TArray<TValue>;
  end;

  TCommittedChange = record
    ActType: string;
    ElementId: TIdentifier;
    FieldName: string;
    Value: TValue;
  end;

  TEventRecord = record
    RuleId: string;
    EventType: string;
    Payload: TValue;
  end;

  TTickResult = record
    TickNumber: Int64;
    SelectedMatchKey: TValue;
    CommittedChanges: TArray<TValue>;
    Events: TArray<TValue>;
    Success: Boolean;
    FatalError: Boolean;
    ErrorCode: string;
    ErrorMsg: string;
  end;

  TEngine = class
  private
    FRules: TObjectList<TRule>;
    FState: TState;
    FMaxTicks: Int64;
    FTypeHash: string;
    FCurrentRule: TRule;
    FMatches: TList<TMatch>;
    FCurrentReadTrace: TList<TReadEffect>;
    FCurrentEnv: TDictionary<string, TValue>;
    procedure DiscoverMatches;
    procedure MatchPatterns(APatIdx: Integer);
    procedure EvaluateLetAndConstraints;
    function SelectMatch(const AMatches: TList<TMatch>; out AMatchOut: TMatch): Boolean;
    procedure CompileActions(const AMatch: TMatch; out ATrace: TArray<TPrimitiveAction>; out AActionReads: TList<TReadEffect>);
    function CommitMatch(const AMatch: TMatch; const ATrace: TArray<TPrimitiveAction>; const AReads: TList<TReadEffect>;
                         out AChangesOut: TArray<TCommittedChange>; out AEventsOut: TArray<TEventRecord>): Boolean;
    procedure RunTick(out AResult: TTickResult);
  public
    constructor Create(ARules: TObjectList<TRule>; AState: TState; AMaxTicks: Int64; const ATypeHash: string);
	destructor Destroy; override;
    function ExecuteSimulation: TValue;
  end;

implementation

{ TEngine }

constructor TEngine.Create(ARules: TObjectList<TRule>; AState: TState; AMaxTicks: Int64; const ATypeHash: string);
begin
  FRules := ARules;
  FState := AState;
  FMaxTicks := AMaxTicks;
  FTypeHash := ATypeHash;
  FMatches := TList<TMatch>.Create;
  FCurrentReadTrace := TList<TReadEffect>.Create;
  FCurrentEnv := TDictionary<string, TValue>.Create;
end;

destructor TEngine.Destroy;
begin
  FRules.Free;
  FState.Free;
  FMatches.Free;
  FCurrentReadTrace.Free;
  FCurrentEnv.Free;
  inherited;
end;

procedure TEngine.DiscoverMatches;
var
  R: TRule;
begin
  FMatches.Clear;
  for R in FRules do
  begin
    FCurrentRule := R;
    FCurrentEnv.Clear;
    FCurrentReadTrace.Clear;
    MatchPatterns(0);
  end;
end;

procedure TEngine.MatchPatterns(APatIdx: Integer);
var
  Pat: TPattern;
  Node: TNode;
  Edge: TEdge;
  IdVal: TValue;
  SrcVal, TgtVal: TValue;
  SrcId, TgtId: TIdentifier;
  i: Integer;
begin
  if APatIdx = FCurrentRule.Patterns.Count then
  begin
    EvaluateLetAndConstraints;
    Exit;
  end;

  Pat := FCurrentRule.Patterns[APatIdx];
  if Pat.PatternType = ptNode then
  begin
    FCurrentReadTrace.Add(TReadEffect.Extent(Pat.TypeName, FState.Counters.GetExtentVersion(Pat.TypeName)));
    for i := 0 to FState.Graph.Nodes.Count - 1 do
    begin
      Node := FState.Graph.Nodes[i];
      if Node.TypeName = Pat.TypeName then
      begin
        IdVal := TValue.CreateIdentifier(Node.Id.TypeName, Node.Id.SequenceNumber);
        FCurrentReadTrace.Add(TReadEffect.NodeExistence(Node.Id, FState.Counters.GetExistenceVersion(Node.Id)));
        FCurrentEnv.Add(Pat.VarName, IdVal);
        MatchPatterns(APatIdx + 1);
        FCurrentEnv.Remove(Pat.VarName);
      end;
    end;
  end
  else if Pat.PatternType = ptEdge then
  begin
    if not FCurrentEnv.TryGetValue(Pat.SrcVar, SrcVal) or (SrcVal.ValType <> vtIdentifier) then
      raise Exception.Create('Source variable not bound or not an identifier: ' + Pat.SrcVar);
    SrcId := SrcVal.IdValue;
    if not FCurrentEnv.TryGetValue(Pat.TgtVar, TgtVal) or (TgtVal.ValType <> vtIdentifier) then
      raise Exception.Create('Target variable not bound or not an identifier: ' + Pat.TgtVar);
    TgtId := TgtVal.IdValue;
    FCurrentReadTrace.Add(TReadEffect.ReadEdgeType(Pat.TypeName, FState.Counters.GetEdgeTypeVersion(Pat.TypeName)));
    for i := 0 to FState.Graph.Edges.Count - 1 do
    begin
      Edge := FState.Graph.Edges[i];
      if (Edge.TypeName = Pat.TypeName) and
         (CompareIdentifiers(Edge.Src, SrcId) = 0) and
         (CompareIdentifiers(Edge.Tgt, TgtId) = 0) then
      begin
        IdVal := TValue.CreateIdentifier(Edge.Id.TypeName, Edge.Id.SequenceNumber);
        FCurrentReadTrace.Add(TReadEffect.EdgeExistence(Edge.Id, FState.Counters.GetExistenceVersion(Edge.Id)));
        FCurrentReadTrace.Add(TReadEffect.Adjacency(Edge.Src, Edge.TypeName, 'out', FState.Counters.GetAdjacencyVersion(Edge.Src, Edge.TypeName, 'out')));
        FCurrentReadTrace.Add(TReadEffect.Adjacency(Edge.Tgt, Edge.TypeName, 'in', FState.Counters.GetAdjacencyVersion(Edge.Tgt, Edge.TypeName, 'in')));
        FCurrentEnv.Add(Pat.VarName, IdVal);
        MatchPatterns(APatIdx + 1);
        FCurrentEnv.Remove(Pat.VarName);
      end;
    end;
  end;
end;

procedure TEngine.EvaluateLetAndConstraints;
var
  LetBind: TLetBinding;
  ConstExpr: TExpr;
  EvalVal: TValue;
  EnvCopy: TDictionary<string, TValue>;
  Match: TMatch;
  K: string;
  PList: TList<TPair<string, TValue>>;
  i: Integer;
begin
  EnvCopy := TDictionary<string, TValue>.Create;
  try
    for K in FCurrentEnv.Keys do
      EnvCopy.Add(K, FCurrentEnv[K]);

    for LetBind in FCurrentRule.LetBindings do
    begin
      EvalVal := EvaluateExpr(LetBind.Expr, EnvCopy, FState.Graph, FState.Counters, FCurrentReadTrace);
      EnvCopy.AddOrSetValue(LetBind.VarName, EvalVal);
    end;

    for ConstExpr in FCurrentRule.Constraints do
    begin
      EvalVal := EvaluateExpr(ConstExpr, EnvCopy, FState.Graph, FState.Counters, FCurrentReadTrace);
      if (EvalVal.ValType <> vtBoolean) or (not EvalVal.BoolValue) then
        Exit;
    end;

    Match.MatchKey.RuleId := FCurrentRule.RuleId;
    PList := TList<TPair<string, TValue>>.Create;
    try
      for K in FCurrentEnv.Keys do
        PList.Add(TPair<string, TValue>.Create(K, FCurrentEnv[K]));
      PList.Sort(TComparer<TPair<string, TValue>>.Construct(
        function(const Left, Right: TPair<string, TValue>): Integer
        begin
          Result := CompareUTF8(Left.Key, Right.Key);
        end
      ));
      Match.MatchKey.Bindings := PList.ToArray;
      Match.Bindings := Match.MatchKey.Bindings;
    finally
      PList.Free;
    end;

    SetLength(Match.ReadTrace, FCurrentReadTrace.Count);
    for i := 0 to FCurrentReadTrace.Count - 1 do
      Match.ReadTrace[i] := FCurrentReadTrace[i];

    K := Match.MatchKey.ToString;
    if FState.PrevMatches.TryGetValue(K, Match.Age) then
      Match.Age := SafeAdd(Match.Age, 1)
    else
      Match.Age := 0;

    Match.Score := SafeAdd(SafeMul(FCurrentRule.BasePriority, FCurrentRule.PriorityScale),
                           SafeMul(Match.Age, FCurrentRule.FairnessScale));
    FMatches.Add(Match);
  finally
    EnvCopy.Free;
  end;
end;

function CompareMatches(const Left, Right: TMatch): Integer;
begin
  if Left.Score > Right.Score then Exit(-1);
  if Left.Score < Right.Score then Exit(1);
  Result := CompareUTF8(Left.MatchKey.ToString, Right.MatchKey.ToString);
end;

function TEngine.SelectMatch(const AMatches: TList<TMatch>; out AMatchOut: TMatch): Boolean;
begin
  if AMatches.Count = 0 then Exit(False);
  AMatches.Sort(TComparer<TMatch>.Construct(CompareMatches));
  AMatchOut := AMatches[0];
  Result := True;
end;

procedure TEngine.CompileActions(const AMatch: TMatch; out ATrace: TArray<TPrimitiveAction>; out AActionReads: TList<TReadEffect>);
var
  TempEnv: TDictionary<string, TValue>;
  TempCounters: TCounters;
  TraceList: TList<TPrimitiveAction>;
  Rule: TRule;
  Act: TAction;
  Pair: TPair<string, TValue>;
  CN: TActionCreateNode;
  CNSeq, i, j: Int64;
  CNId: TIdentifier;
  CNFields: TArray<TFieldValEntry>;
  CE: TActionCreateEdge;
  CESrcVal, CETgtVal: TValue;
  CESrcId, CETgtId: TIdentifier;
  CESeq: Int64;
  CEId: TIdentifier;
  CEFields: TArray<TFieldValEntry>;
  UF: TActionUpdateField;
  UFTargetVal, UFVal: TValue;
  UFTargetId: TIdentifier;
  UFIsNode: Boolean;
  UFNode: TNode;
  UFEdge: TEdge;
  DE: TActionDeleteEdge;
  DEVal: TValue;
  DEId: TIdentifier;
  DEEdge: TEdge;
  DN: TActionDeleteNode;
  DNVal: TValue;
  DNId: TIdentifier;
  DNEdge: TEdge;
  IncidentEdges: TList<TEdge>;
  EE: TActionEmitEvent;
  EEPayloads: TArray<TValue>;
begin
  ATrace := nil;
  AActionReads := TList<TReadEffect>.Create;
  TraceList := TList<TPrimitiveAction>.Create;
  TempEnv := TDictionary<string, TValue>.Create;
  TempCounters := FState.Counters.Clone;
  try
    for Pair in AMatch.Bindings do
      TempEnv.Add(Pair.Key, Pair.Value);

    Rule := nil;
    for Rule in FRules do
      if Rule.RuleId = AMatch.MatchKey.RuleId then Break;
    if Rule = nil then raise Exception.Create('Rule not found: ' + AMatch.MatchKey.RuleId);

    for i := 0 to Rule.LetBindings.Count - 1 do
    begin
      UFVal := EvaluateExpr(Rule.LetBindings[i].Expr, TempEnv, FState.Graph, TempCounters, AActionReads);
      TempEnv.AddOrSetValue(Rule.LetBindings[i].VarName, UFVal);
    end;

    for i := 0 to Rule.Actions.Count - 1 do
    begin
      Act := Rule.Actions[i];
      if Act is TActionCreateNode then
      begin
        CN := TActionCreateNode(Act);
        CNSeq := TempCounters.NextSequenceCounter(CN.TypeName);
        CNId := TIdentifier.Create(CN.TypeName, CNSeq);
        TempEnv.AddOrSetValue(CN.VarName, TValue.CreateIdentifier(CNId.TypeName, CNId.SequenceNumber));
        TempCounters.SetExistenceVersion(CNId, 1);
        SetLength(CNFields, Length(CN.Fields));
        for j := 0 to High(CN.Fields) do
        begin
          CNFields[j].Name := CN.Fields[j].Name;
          CNFields[j].Value := EvaluateExpr(CN.Fields[j].Expr, TempEnv, FState.Graph, TempCounters, AActionReads);
          TempCounters.SetFieldVersion(CNId, CN.Fields[j].Name, 1);
        end;
        var PAct: TPrimitiveAction;
		PAct.ActType := patCreateNode;
        PAct.ElementId := CNId;
        PAct.TypeName := CN.TypeName;
        PAct.Fields := CNFields;
        TraceList.Add(PAct);
      end
      else if Act is TActionCreateEdge then
      begin
        CE := TActionCreateEdge(Act);
        CESrcVal := EvaluateExpr(CE.SrcExpr, TempEnv, FState.Graph, TempCounters, AActionReads);
        CETgtVal := EvaluateExpr(CE.TgtExpr, TempEnv, FState.Graph, TempCounters, AActionReads);
        if (CESrcVal.ValType <> vtIdentifier) or (CETgtVal.ValType <> vtIdentifier) then
          raise Exception.Create('Edge src/tgt must evaluate to Identifier');
        CESrcId := CESrcVal.IdValue;
        CETgtId := CETgtVal.IdValue;
        AActionReads.Add(TReadEffect.NodeExistence(CESrcId, TempCounters.GetExistenceVersion(CESrcId)));
        AActionReads.Add(TReadEffect.NodeExistence(CETgtId, TempCounters.GetExistenceVersion(CETgtId)));
        CESeq := TempCounters.NextSequenceCounter(CE.TypeName);
        CEId := TIdentifier.Create(CE.TypeName, CESeq);
        TempEnv.AddOrSetValue(CE.VarName, TValue.CreateIdentifier(CEId.TypeName, CEId.SequenceNumber));
        TempCounters.SetExistenceVersion(CEId, 1);
        SetLength(CEFields, Length(CE.Fields));
        for j := 0 to High(CE.Fields) do
        begin
          CEFields[j].Name := CE.Fields[j].Name;
          CEFields[j].Value := EvaluateExpr(CE.Fields[j].Expr, TempEnv, FState.Graph, TempCounters, AActionReads);
          TempCounters.SetFieldVersion(CEId, CE.Fields[j].Name, 1);
        end;
        var PAct: TPrimitiveAction;
        PAct.ActType := patCreateEdge;
        PAct.ElementId := CEId;
        PAct.TypeName := CE.TypeName;
        PAct.SrcId := CESrcId;
        PAct.TgtId := CETgtId;
        PAct.Fields := CEFields;
        TraceList.Add(PAct);
      end
      else if Act is TActionUpdateField then
      begin
        UF := TActionUpdateField(Act);
        UFTargetVal := EvaluateExpr(UF.TargetExpr, TempEnv, FState.Graph, TempCounters, AActionReads);
        if UFTargetVal.ValType <> vtIdentifier then
          raise Exception.Create('UpdateField target must evaluate to Identifier');
        UFTargetId := UFTargetVal.IdValue;
        UFIsNode := FState.Graph.FindNode(UFTargetId, UFNode);
        if not UFIsNode and not FState.Graph.FindEdge(UFTargetId, UFEdge) then
          if TempCounters.GetExistenceVersion(UFTargetId) = 0 then
            raise Exception.Create('UpdateField target does not exist: ' + UFTargetId.ToString);
        if UFIsNode then
        begin
          AActionReads.Add(TReadEffect.NodeExistence(UFTargetId, TempCounters.GetExistenceVersion(UFTargetId)));
          AActionReads.Add(TReadEffect.FieldRead(UFTargetId, UF.FieldName, TempCounters.GetFieldVersion(UFTargetId, UF.FieldName)));
        end
        else
        begin
          AActionReads.Add(TReadEffect.EdgeExistence(UFTargetId, TempCounters.GetExistenceVersion(UFTargetId)));
          AActionReads.Add(TReadEffect.FieldRead(UFTargetId, UF.FieldName, TempCounters.GetFieldVersion(UFTargetId, UF.FieldName)));
        end;
        UFVal := EvaluateExpr(UF.Expr, TempEnv, FState.Graph, TempCounters, AActionReads);
        var PAct: TPrimitiveAction;
        PAct.ActType := patUpdateField;
        PAct.ElementId := UFTargetId;
        PAct.FieldName := UF.FieldName;
        PAct.Value := UFVal;
        TraceList.Add(PAct);
      end
      else if Act is TActionDeleteEdge then
      begin
        DE := TActionDeleteEdge(Act);
        DEVal := EvaluateExpr(DE.Expr, TempEnv, FState.Graph, TempCounters, AActionReads);
        if DEVal.ValType <> vtIdentifier then
          raise Exception.Create('DeleteEdge must evaluate to Identifier');
		DEId := DEVal.IdValue;
        if not FState.Graph.FindEdge(DEId, DEEdge) then
          raise Exception.Create('DeleteEdge target edge does not exist: ' + DEId.ToString);
        AActionReads.Add(TReadEffect.EdgeExistence(DEId, TempCounters.GetExistenceVersion(DEId)));
        AActionReads.Add(TReadEffect.Adjacency(DEEdge.Src, DEEdge.TypeName, 'out', TempCounters.GetAdjacencyVersion(DEEdge.Src, DEEdge.TypeName, 'out')));
        AActionReads.Add(TReadEffect.Adjacency(DEEdge.Tgt, DEEdge.TypeName, 'in', TempCounters.GetAdjacencyVersion(DEEdge.Tgt, DEEdge.TypeName, 'in')));
        var PAct: TPrimitiveAction;
        PAct.ActType := patDeleteEdge;
        PAct.ElementId := DEId;
        TraceList.Add(PAct);
      end
      else if Act is TActionDeleteNode then
      begin
        DN := TActionDeleteNode(Act);
        if not TempEnv.TryGetValue(DN.VarName, DNVal) or (DNVal.ValType <> vtIdentifier) then
          raise Exception.Create('DeleteNode variable not bound or not an identifier: ' + DN.VarName);
        DNId := DNVal.IdValue;
        if not FState.Graph.FindNode(DNId, UFNode) then
          raise Exception.Create('DeleteNode target node does not exist: ' + DNId.ToString);
        AActionReads.Add(TReadEffect.NodeExistence(DNId, TempCounters.GetExistenceVersion(DNId)));
        IncidentEdges := TList<TEdge>.Create;
        try
          for j := 0 to FState.Graph.Edges.Count - 1 do
          begin
            DNEdge := FState.Graph.Edges[j];
            if (CompareIdentifiers(DNEdge.Src, DNId) = 0) or (CompareIdentifiers(DNEdge.Tgt, DNId) = 0) then
              IncidentEdges.Add(DNEdge);
          end;
          IncidentEdges.Sort(TComparer<TEdge>.Construct(
            function(const Left, Right: TEdge): Integer
            begin
              Result := CompareIdentifiers(Left.Id, Right.Id);
            end
          ));
          for j := 0 to IncidentEdges.Count - 1 do
          begin
            DNEdge := IncidentEdges[j];
            if CompareIdentifiers(DNEdge.Src, DNId) = 0 then
              AActionReads.Add(TReadEffect.Adjacency(DNId, DNEdge.TypeName, 'out', TempCounters.GetAdjacencyVersion(DNId, DNEdge.TypeName, 'out')))
            else
              AActionReads.Add(TReadEffect.Adjacency(DNId, DNEdge.TypeName, 'in', TempCounters.GetAdjacencyVersion(DNId, DNEdge.TypeName, 'in')));
            AActionReads.Add(TReadEffect.EdgeExistence(DNEdge.Id, TempCounters.GetExistenceVersion(DNEdge.Id)));
            var PAct: TPrimitiveAction;
            PAct.ActType := patDeleteEdge;
            PAct.ElementId := DNEdge.Id;
            TraceList.Add(PAct);
          end;
        finally
          IncidentEdges.Free;
        end;
        var PActNode: TPrimitiveAction;
        PActNode.ActType := patDeleteNode;
        PActNode.ElementId := DNId;
        TraceList.Add(PActNode);
      end;
    end;

    for i := 0 to Rule.Actions.Count - 1 do
    begin
      Act := Rule.Actions[i];
      if Act is TActionEmitEvent then
      begin
        EE := TActionEmitEvent(Act);
        SetLength(EEPayloads, Length(EE.Payloads));
        for j := 0 to High(EE.Payloads) do
          EEPayloads[j] := EvaluateExpr(EE.Payloads[j], TempEnv, FState.Graph, TempCounters, AActionReads);
        var PAct: TPrimitiveAction;
        PAct.ActType := patEmitEvent;
        PAct.TypeName := EE.EventType;
        PAct.Payloads := EEPayloads;
        TraceList.Add(PAct);
      end;
	end;

    ATrace := TraceList.ToArray;
  finally
    TempEnv.Free;
    TempCounters.Free;
    TraceList.Free;
  end;
end;

function TEngine.CommitMatch(const AMatch: TMatch; const ATrace: TArray<TPrimitiveAction>; const AReads: TList<TReadEffect>;
                             out AChangesOut: TArray<TCommittedChange>; out AEventsOut: TArray<TEventRecord>): Boolean;
var
  i, j: Integer;
  ReadEff: TReadEffect;
  CurrentVer: Int64;
  PAct: TPrimitiveAction;
  CreatedElements: THashSet<string>;
  UpdateFieldsSet: THashSet<string>;
  UFKey: string;
  NodeObj: TNode;
  EdgeObj: TEdge;
  TargetId: TIdentifier;
  SimCounters: TCounters;
  ChangeList: TList<TCommittedChange>;
  EventList: TList<TEventRecord>;
  AdjacencyIncs: THashSet<string>;
  AdjKey: string;
begin
  AChangesOut := nil;
  AEventsOut := nil;
  Result := False;

  for i := 0 to AReads.Count - 1 do
  begin
    ReadEff := AReads[i];
    case ReadEff.ReadType of
      rtNodeExistence, rtEdgeExistence: CurrentVer := FState.Counters.GetExistenceVersion(ReadEff.ElementId);
      rtFieldRead: CurrentVer := FState.Counters.GetFieldVersion(ReadEff.ElementId, ReadEff.FieldName);
      rtExtent: CurrentVer := FState.Counters.GetExtentVersion(ReadEff.TypeName);
      rtPredicate: CurrentVer := FState.Counters.GetPredicateVersion(ReadEff.TypeName, ReadEff.FieldName);
      rtOrderingDependency: CurrentVer := FState.Counters.GetOrderingDependencyVersion(ReadEff.TypeName, ReadEff.FieldName);
      rtEdgeType: CurrentVer := FState.Counters.GetEdgeTypeVersion(ReadEff.TypeName);
      rtEdgePredicate: CurrentVer := FState.Counters.GetEdgePredicateVersion(ReadEff.TypeName, ReadEff.FieldName);
      rtEdgeOrderingDependency: CurrentVer := FState.Counters.GetEdgeOrderingDependencyVersion(ReadEff.TypeName, ReadEff.FieldName);
      rtAdjacency: CurrentVer := FState.Counters.GetAdjacencyVersion(ReadEff.NodeId, ReadEff.AdjEdgeType, ReadEff.Direction);
    else
      CurrentVer := 0;
    end;
    if CurrentVer <> ReadEff.VersionValue then
      Exit;
  end;

  UpdateFieldsSet := THashSet<string>.Create;
  CreatedElements := THashSet<string>.Create;
  try
    for i := 0 to High(ATrace) do
    begin
      PAct := ATrace[i];
      case PAct.ActType of
        patCreateNode, patCreateEdge:
          CreatedElements.Add(PAct.ElementId.ToString);
        patUpdateField:
          begin
            UFKey := PAct.ElementId.ToString + '.' + PAct.FieldName;
            if UpdateFieldsSet.Contains(UFKey) then Exit;
            UpdateFieldsSet.Add(UFKey);
            TargetId := PAct.ElementId;
            if not FState.Graph.FindNode(TargetId, NodeObj) and
               not FState.Graph.FindEdge(TargetId, EdgeObj) and
               not CreatedElements.Contains(TargetId.ToString) then
              Exit;
		  end;
        patDeleteEdge, patDeleteNode:
          begin
            TargetId := PAct.ElementId;
            if (PAct.ActType = patDeleteNode) and not FState.Graph.FindNode(TargetId, NodeObj) then Exit;
            if (PAct.ActType = patDeleteEdge) and not FState.Graph.FindEdge(TargetId, EdgeObj) then Exit;
          end;
      end;
    end;
  finally
    UpdateFieldsSet.Free;
    CreatedElements.Free;
  end;

  SimCounters := FState.Counters.Clone;
  try
    if SimCounters.TickCounter = Int64.MaxValue then raise Exception.Create('COUNTER_OVERFLOW');
    SimCounters.TickCounter := SimCounters.TickCounter + 1;
    for i := 0 to High(ATrace) do
    begin
      PAct := ATrace[i];
      case PAct.ActType of
        patCreateNode:
          begin
            SimCounters.IncExtentVersion(PAct.TypeName);
            for j := 0 to High(PAct.Fields) do
            begin
              SimCounters.IncPredicateVersion(PAct.TypeName, PAct.Fields[j].Name);
              SimCounters.IncOrderingDependencyVersion(PAct.TypeName, PAct.Fields[j].Name);
            end;
          end;
        patDeleteNode:
          SimCounters.IncExtentVersion(PAct.ElementId.TypeName);
        patCreateEdge:
          begin
            SimCounters.IncEdgeTypeVersion(PAct.TypeName);
            SimCounters.IncAdjacencyVersion(PAct.SrcId, PAct.TypeName, 'out');
            SimCounters.IncAdjacencyVersion(PAct.TgtId, PAct.TypeName, 'in');
            for j := 0 to High(PAct.Fields) do
            begin
              SimCounters.IncEdgePredicateVersion(PAct.TypeName, PAct.Fields[j].Name);
              SimCounters.IncEdgeOrderingDependencyVersion(PAct.TypeName, PAct.Fields[j].Name);
            end;
          end;
        patDeleteEdge:
          if FState.Graph.FindEdge(PAct.ElementId, EdgeObj) then
          begin
            SimCounters.IncEdgeTypeVersion(EdgeObj.TypeName);
            SimCounters.IncAdjacencyVersion(EdgeObj.Src, EdgeObj.TypeName, 'out');
            SimCounters.IncAdjacencyVersion(EdgeObj.Tgt, EdgeObj.TypeName, 'in');
          end;
        patUpdateField:
          begin
            TargetId := PAct.ElementId;
            if FState.Graph.FindNode(TargetId, NodeObj) then
            begin
              SimCounters.IncPredicateVersion(NodeObj.TypeName, PAct.FieldName);
              SimCounters.IncOrderingDependencyVersion(NodeObj.TypeName, PAct.FieldName);
              SimCounters.IncFieldVersion(TargetId, PAct.FieldName);
            end
            else if FState.Graph.FindEdge(TargetId, EdgeObj) then
            begin
              SimCounters.IncEdgePredicateVersion(EdgeObj.TypeName, PAct.FieldName);
              SimCounters.IncEdgeOrderingDependencyVersion(EdgeObj.TypeName, PAct.FieldName);
              SimCounters.IncFieldVersion(TargetId, PAct.FieldName);
            end;
          end;
      end;
    end;
  finally
    SimCounters.Free;
  end;

  ChangeList := TList<TCommittedChange>.Create;
  EventList := TList<TEventRecord>.Create;
  AdjacencyIncs := THashSet<string>.Create;
  try
    FState.Counters.TickCounter := FState.Counters.TickCounter + 1;
    FState.TickNumber := FState.TickNumber + 1;
    for i := 0 to High(ATrace) do
    begin
      PAct := ATrace[i];
      case PAct.ActType of
        patCreateNode:
          begin
            NodeObj := TNode.Create(PAct.ElementId, PAct.TypeName);
            for j := 0 to High(PAct.Fields) do
              NodeObj.SetField(PAct.Fields[j].Name, PAct.Fields[j].Value);
            FState.Graph.AddNode(NodeObj);
            var Chg: TCommittedChange;
            Chg.ActType := 'create_node';
            Chg.ElementId := PAct.ElementId;
            ChangeList.Add(Chg);
            FState.Counters.IncExtentVersion(PAct.TypeName);
            FState.Counters.SetExistenceVersion(PAct.ElementId, 1);
            for j := 0 to High(PAct.Fields) do
            begin
              FState.Counters.IncPredicateVersion(PAct.TypeName, PAct.Fields[j].Name);
              FState.Counters.IncOrderingDependencyVersion(PAct.TypeName, PAct.Fields[j].Name);
              FState.Counters.SetFieldVersion(PAct.ElementId, PAct.Fields[j].Name, 1);
            end;
          end;
        patCreateEdge:
          begin
            EdgeObj := TEdge.Create(PAct.ElementId, PAct.TypeName, PAct.SrcId, PAct.TgtId);
            for j := 0 to High(PAct.Fields) do
              EdgeObj.SetField(PAct.Fields[j].Name, PAct.Fields[j].Value);
            FState.Graph.AddEdge(EdgeObj);
            var Chg: TCommittedChange;
            Chg.ActType := 'create_edge';
            Chg.ElementId := PAct.ElementId;
            ChangeList.Add(Chg);
            FState.Counters.IncEdgeTypeVersion(PAct.TypeName);
            FState.Counters.SetExistenceVersion(PAct.ElementId, 1);
            AdjKey := PAct.SrcId.ToString + ':' + PAct.TypeName + ':out';
            if not AdjacencyIncs.Contains(AdjKey) then
            begin
              FState.Counters.IncAdjacencyVersion(PAct.SrcId, PAct.TypeName, 'out');
              AdjacencyIncs.Add(AdjKey);
            end;
            AdjKey := PAct.TgtId.ToString + ':' + PAct.TypeName + ':in';
            if not AdjacencyIncs.Contains(AdjKey) then
            begin
              FState.Counters.IncAdjacencyVersion(PAct.TgtId, PAct.TypeName, 'in');
              AdjacencyIncs.Add(AdjKey);
            end;
            for j := 0 to High(PAct.Fields) do
            begin
              FState.Counters.IncEdgePredicateVersion(PAct.TypeName, PAct.Fields[j].Name);
              FState.Counters.IncEdgeOrderingDependencyVersion(PAct.TypeName, PAct.Fields[j].Name);
              FState.Counters.SetFieldVersion(PAct.ElementId, PAct.Fields[j].Name, 1);
            end;
          end;
        patUpdateField:
          begin
            TargetId := PAct.ElementId;
            if FState.Graph.FindNode(TargetId, NodeObj) then
            begin
              NodeObj.SetField(PAct.FieldName, PAct.Value);
              FState.Counters.IncPredicateVersion(NodeObj.TypeName, PAct.FieldName);
              FState.Counters.IncOrderingDependencyVersion(NodeObj.TypeName, PAct.FieldName);
              FState.Counters.IncFieldVersion(TargetId, PAct.FieldName);
            end
            else if FState.Graph.FindEdge(TargetId, EdgeObj) then
			begin
              EdgeObj.SetField(PAct.FieldName, PAct.Value);
              FState.Counters.IncEdgePredicateVersion(EdgeObj.TypeName, PAct.FieldName);
              FState.Counters.IncEdgeOrderingDependencyVersion(EdgeObj.TypeName, PAct.FieldName);
              FState.Counters.IncFieldVersion(TargetId, PAct.FieldName);
            end;
            var Chg: TCommittedChange;
            Chg.ActType := 'update_field';
            Chg.ElementId := TargetId;
            Chg.FieldName := PAct.FieldName;
            Chg.Value := PAct.Value;
            ChangeList.Add(Chg);
          end;
        patDeleteEdge:
          begin
            TargetId := PAct.ElementId;
            if FState.Graph.FindEdge(TargetId, EdgeObj) then
            begin
              AdjKey := EdgeObj.Src.ToString + ':' + EdgeObj.TypeName + ':out';
              if not AdjacencyIncs.Contains(AdjKey) then
              begin
                FState.Counters.IncAdjacencyVersion(EdgeObj.Src, EdgeObj.TypeName, 'out');
                AdjacencyIncs.Add(AdjKey);
              end;
              AdjKey := EdgeObj.Tgt.ToString + ':' + EdgeObj.TypeName + ':in';
              if not AdjacencyIncs.Contains(AdjKey) then
              begin
                FState.Counters.IncAdjacencyVersion(EdgeObj.Tgt, EdgeObj.TypeName, 'in');
                AdjacencyIncs.Add(AdjKey);
              end;
              FState.Counters.IncEdgeTypeVersion(EdgeObj.TypeName);
              FState.Counters.RemoveExistenceVersion(TargetId);
              FState.Counters.RemoveFieldVersions(TargetId);
              FState.Graph.DeleteEdge(TargetId);
              var Chg: TCommittedChange;
              Chg.ActType := 'delete_edge';
              Chg.ElementId := TargetId;
              ChangeList.Add(Chg);
            end;
          end;
        patDeleteNode:
          begin
            TargetId := PAct.ElementId;
            if FState.Graph.FindNode(TargetId, NodeObj) then
            begin
              FState.Counters.IncExtentVersion(NodeObj.TypeName);
              FState.Counters.RemoveExistenceVersion(TargetId);
              FState.Counters.RemoveFieldVersions(TargetId);
              FState.Graph.DeleteNode(TargetId);
              var Chg: TCommittedChange;
              Chg.ActType := 'delete_node';
              Chg.ElementId := TargetId;
              ChangeList.Add(Chg);
            end;
          end;
        patEmitEvent:
          begin
            var Evt: TEventRecord;
            Evt.RuleId := AMatch.MatchKey.RuleId;
            Evt.EventType := PAct.TypeName;
            Evt.Payload := TValue.CreateList(PAct.Payloads);
            EventList.Add(Evt);
          end;
      end;
    end;
    AChangesOut := ChangeList.ToArray;
    AEventsOut := EventList.ToArray;
    Result := True;
  finally
    ChangeList.Free;
    EventList.Free;
    AdjacencyIncs.Free;
  end;
end;

procedure TEngine.RunTick(out AResult: TTickResult);
var
  Match: TMatch;
  Trace: TArray<TPrimitiveAction>;
  ActionReads: TList<TReadEffect>;
  Changes: TArray<TCommittedChange>;
  Events: TArray<TEventRecord>;
  i: Integer;
  BindingsMap, KeyMap, ChgMap, EvtMap: TList<TPair<string, TValue>>;
  ChgJSON: TList<TValue>;
begin
  AResult.TickNumber := FState.TickNumber;
  AResult.SelectedMatchKey := TValue.CreateNull;
  AResult.CommittedChanges := nil;
  AResult.Events := nil;
  AResult.Success := False;
  AResult.FatalError := False;

  DiscoverMatches;

  while FMatches.Count > 0 do
  begin
    if not SelectMatch(FMatches, Match) then
      Break;

    BindingsMap := TList<TPair<string, TValue>>.Create;
    KeyMap := TList<TPair<string, TValue>>.Create;
    try
      for i := 0 to High(Match.MatchKey.Bindings) do
        BindingsMap.Add(TPair<string, TValue>.Create(Match.MatchKey.Bindings[i].Key, Match.MatchKey.Bindings[i].Value));
      KeyMap.Add(TPair<string, TValue>.Create('rule_id', TValue.CreateString(Match.MatchKey.RuleId)));
      KeyMap.Add(TPair<string, TValue>.Create('bindings', TValue.CreateMap(BindingsMap.ToArray)));
      AResult.SelectedMatchKey := TValue.CreateMap(KeyMap.ToArray);
    finally
      BindingsMap.Free;
      KeyMap.Free;
    end;

    Trace := nil;
    ActionReads := nil;
    try
      CompileActions(Match, Trace, ActionReads);
    except
      on E: Exception do
      begin
        FMatches.Remove(Match);
        Continue;
      end;
    end;

    Changes := nil;
    Events := nil;
    try
      if CommitMatch(Match, Trace, ActionReads, Changes, Events) then
      begin
        AResult.Success := True;
        FState.PrevMatches.Clear;
        for i := 0 to FMatches.Count - 1 do
          FState.PrevMatches.Add(FMatches[i].MatchKey.ToString, FMatches[i].Age);
        ActionReads.Free;

        ChgJSON := TList<TValue>.Create;
        try
          for i := 0 to High(Changes) do
          begin
            ChgMap := TList<TPair<string, TValue>>.Create;
            ChgMap.Add(TPair<string, TValue>.Create('action', TValue.CreateString(Changes[i].ActType)));
            ChgMap.Add(TPair<string, TValue>.Create('id', TValue.CreateString(Changes[i].ElementId.ToString)));
			if Changes[i].FieldName <> '' then
            begin
              ChgMap.Add(TPair<string, TValue>.Create('field', TValue.CreateString(Changes[i].FieldName)));
              ChgMap.Add(TPair<string, TValue>.Create('value', Changes[i].Value));
            end;
            ChgJSON.Add(TValue.CreateMap(ChgMap.ToArray));
            ChgMap.Free;
          end;
          AResult.CommittedChanges := ChgJSON.ToArray;
        finally
          ChgJSON.Free;
        end;

        ChgJSON := TList<TValue>.Create;
        try
          for i := 0 to High(Events) do
          begin
            EvtMap := TList<TPair<string, TValue>>.Create;
            EvtMap.Add(TPair<string, TValue>.Create('rule_id', TValue.CreateString(Events[i].RuleId)));
            EvtMap.Add(TPair<string, TValue>.Create('event_type', TValue.CreateString(Events[i].EventType)));
            EvtMap.Add(TPair<string, TValue>.Create('payload', Events[i].Payload));
            ChgJSON.Add(TValue.CreateMap(EvtMap.ToArray));
            EvtMap.Free;
          end;
          AResult.Events := ChgJSON.ToArray;
        finally
          ChgJSON.Free;
        end;
        Exit;
      end
      else
      begin
        ActionReads.Free;
        FMatches.Remove(Match);
        Continue;
      end;
    except
      on E: Exception do
      begin
        ActionReads.Free;
        AResult.FatalError := True;
        AResult.ErrorCode := E.Message;
        AResult.ErrorMsg := E.Message;
        Exit;
      end;
    end;
  end;

  try
    if FState.Counters.TickCounter = Int64.MaxValue then raise Exception.Create('COUNTER_OVERFLOW');
    FState.Counters.TickCounter := FState.Counters.TickCounter + 1;
    FState.TickNumber := FState.TickNumber + 1;
    AResult.Success := False;
  except
    on E: Exception do
    begin
      AResult.FatalError := True;
      AResult.ErrorCode := E.Message;
      AResult.ErrorMsg := E.Message;
    end;
  end;
end;

function SerializeGraph(AGraph: TGraph): TValue;
var
  NodesList, EdgesList: TList<TValue>;
  NodeMap, EdgeMap, FieldMap: TList<TPair<string, TValue>>;
  N: TNode;
  E: TEdge;
  i: Integer;
begin
  NodesList := TList<TValue>.Create;
  EdgesList := TList<TValue>.Create;
  try
    for N in AGraph.Nodes do
    begin
      NodeMap := TList<TPair<string, TValue>>.Create;
      NodeMap.Add(TPair<string, TValue>.Create('id', TValue.CreateString(N.Id.ToString)));
      NodeMap.Add(TPair<string, TValue>.Create('type', TValue.CreateString(N.TypeName)));
      FieldMap := TList<TPair<string, TValue>>.Create;
      for i := 0 to High(N.Fields) do
        FieldMap.Add(TPair<string, TValue>.Create(N.Fields[i].Name, N.Fields[i].Value));
      NodeMap.Add(TPair<string, TValue>.Create('fields', TValue.CreateMap(FieldMap.ToArray)));
      NodesList.Add(TValue.CreateMap(NodeMap.ToArray));
      FieldMap.Free;
      NodeMap.Free;
    end;

    for E in AGraph.Edges do
    begin
      EdgeMap := TList<TPair<string, TValue>>.Create;
      EdgeMap.Add(TPair<string, TValue>.Create('id', TValue.CreateString(E.Id.ToString)));
      EdgeMap.Add(TPair<string, TValue>.Create('type', TValue.CreateString(E.TypeName)));
      EdgeMap.Add(TPair<string, TValue>.Create('src', TValue.CreateString(E.Src.ToString)));
      EdgeMap.Add(TPair<string, TValue>.Create('tgt', TValue.CreateString(E.Tgt.ToString)));
      FieldMap := TList<TPair<string, TValue>>.Create;
      for i := 0 to High(E.Fields) do
        FieldMap.Add(TPair<string, TValue>.Create(E.Fields[i].Name, E.Fields[i].Value));
      EdgeMap.Add(TPair<string, TValue>.Create('fields', TValue.CreateMap(FieldMap.ToArray)));
      EdgesList.Add(TValue.CreateMap(EdgeMap.ToArray));
      FieldMap.Free;
      EdgeMap.Free;
    end;

    var GraphMap := TList<TPair<string, TValue>>.Create;
    try
      GraphMap.Add(TPair<string, TValue>.Create('nodes', TValue.CreateList(NodesList.ToArray)));
      GraphMap.Add(TPair<string, TValue>.Create('edges', TValue.CreateList(EdgesList.ToArray)));
      Result := TValue.CreateMap(GraphMap.ToArray);
    finally
      GraphMap.Free;
    end;
  finally
    NodesList.Free;
    EdgesList.Free;
  end;
end;

function SerializeState(AState: TState): TValue;
var
  StateMap, PrevMap: TList<TPair<string, TValue>>;
  K: string;
begin
  StateMap := TList<TPair<string, TValue>>.Create;
  PrevMap := TList<TPair<string, TValue>>.Create;
  try
    StateMap.Add(TPair<string, TValue>.Create('tick_number', TValue.CreateInteger(AState.TickNumber)));
    StateMap.Add(TPair<string, TValue>.Create('graph', SerializeGraph(AState.Graph)));
    for K in AState.PrevMatches.Keys do
      PrevMap.Add(TPair<string, TValue>.Create(K, TValue.CreateInteger(AState.PrevMatches[K])));
    StateMap.Add(TPair<string, TValue>.Create('prev_matches', TValue.CreateMap(PrevMap.ToArray)));
    Result := TValue.CreateMap(StateMap.ToArray);
  finally
    StateMap.Free;
    PrevMap.Free;
  end;
end;

function TEngine.ExecuteSimulation: TValue;
var
  TicksJSON: TList<TValue>;
  TickRecMap: TList<TPair<string, TValue>>;
  TickRec: TTickResult;
  RootMap: TList<TPair<string, TValue>>;
  InitialStateJSON, FinalStateJSON: TValue;
  CurrentTick: Int64;
  FatalErr: Boolean;
  ErrMap: TList<TPair<string, TValue>>;
  ErrVal: TValue;
begin
  TicksJSON := TList<TValue>.Create;
  RootMap := TList<TPair<string, TValue>>.Create;
  FatalErr := False;
  try
    InitialStateJSON := SerializeState(FState);
    CurrentTick := 0;
    while CurrentTick < FMaxTicks do
    begin
      RunTick(TickRec);
      if TickRec.FatalError then
      begin
        FatalErr := True;
        ErrMap := TList<TPair<string, TValue>>.Create;
        try
          ErrMap.Add(TPair<string, TValue>.Create('code', TValue.CreateString(TickRec.ErrorCode)));
          var CtxMap := TList<TPair<string, TValue>>.Create;
          CtxMap.Add(TPair<string, TValue>.Create('location', TValue.CreateInteger(0)));
          CtxMap.Add(TPair<string, TValue>.Create('location_str', TValue.CreateString('commit_engine')));
          ErrMap.Add(TPair<string, TValue>.Create('context', TValue.CreateMap(CtxMap.ToArray)));
          CtxMap.Free;
          ErrMap.Add(TPair<string, TValue>.Create('state', SerializeState(FState)));
          ErrMap.Add(TPair<string, TValue>.Create('tick', TValue.CreateInteger(TickRec.TickNumber)));
          ErrVal := TValue.CreateMap(ErrMap.ToArray);
        finally
          ErrMap.Free;
        end;
        Break;
      end;

      TickRecMap := TList<TPair<string, TValue>>.Create;
      TickRecMap.Add(TPair<string, TValue>.Create('tick_number', TValue.CreateInteger(TickRec.TickNumber)));
      TickRecMap.Add(TPair<string, TValue>.Create('selected_match_key', TickRec.SelectedMatchKey));
      if TickRec.Success then
        TickRecMap.Add(TPair<string, TValue>.Create('committed_changes', TValue.CreateList(TickRec.CommittedChanges)))
      else
        TickRecMap.Add(TPair<string, TValue>.Create('committed_changes', TValue.CreateList(nil)));
      if TickRec.Success then
        TickRecMap.Add(TPair<string, TValue>.Create('events', TValue.CreateList(TickRec.Events)))
      else
        TickRecMap.Add(TPair<string, TValue>.Create('events', TValue.CreateList(nil)));
      TicksJSON.Add(TValue.CreateMap(TickRecMap.ToArray));
      TickRecMap.Free;

      if not TickRec.Success then Break;
      Inc(CurrentTick);
    end;

    FinalStateJSON := SerializeState(FState);
    RootMap.Add(TPair<string, TValue>.Create('ir_schema_version', TValue.CreateString('1.0')));
    RootMap.Add(TPair<string, TValue>.Create('type_definitions_hash', TValue.CreateString(FTypeHash)));
    RootMap.Add(TPair<string, TValue>.Create('initial_state', InitialStateJSON));
    if FatalErr then
      RootMap.Add(TPair<string, TValue>.Create('ticks', ErrVal))
    else
      RootMap.Add(TPair<string, TValue>.Create('ticks', TValue.CreateList(TicksJSON.ToArray)));
    RootMap.Add(TPair<string, TValue>.Create('final_state', FinalStateJSON));
    Result := TValue.CreateMap(RootMap.ToArray);
  finally
    TicksJSON.Free;
    RootMap.Free;
  end;
end;

end.
