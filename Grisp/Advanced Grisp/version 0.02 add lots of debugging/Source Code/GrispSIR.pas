unit GrispSIR;

interface

uses
  SysUtils, Classes, Generics.Collections, GrispMarkerParser;

type
  TSIRSemanticMapping = record
    MapType: string;
    Phrase: string;
    Target: string;
  end;

  TSIRDocument = class
  public
    Metadata: string;
    SemanticMaps: TList<TSIRSemanticMapping>;
    Goals: TStringList;
    Subgoals: TStringList;
    Questions: TStringList;
    Observations: TStringList;
    Facts: TStringList;
    Assumptions: TStringList;
    Constraints: TStringList;
    Hypotheses: TStringList;
    Evidences: TStringList;
    CounterEvidences: TStringList;
    Alternatives: TStringList;
    Risks: TStringList;
    Confidences: TStringList;
    Dependencies: TStringList;
    Unknowns: TStringList;
    Policies: TStringList;
    Intentions: TStringList;
    constructor Create;
    destructor Destroy; override;
    function LoadFromBlock(Block: TBlock): Boolean;
  end;

implementation

{ TSIRDocument }

constructor TSIRDocument.Create;
begin
  SemanticMaps := TList<TSIRSemanticMapping>.Create;
  Goals := TStringList.Create;
  Subgoals := TStringList.Create;
  Questions := TStringList.Create;
  Observations := TStringList.Create;
  Facts := TStringList.Create;
  Assumptions := TStringList.Create;
  Constraints := TStringList.Create;
  Hypotheses := TStringList.Create;
  Evidences := TStringList.Create;
  CounterEvidences := TStringList.Create;
  Alternatives := TStringList.Create;
  Risks := TStringList.Create;
  Confidences := TStringList.Create;
  Dependencies := TStringList.Create;
  Unknowns := TStringList.Create;
  Policies := TStringList.Create;
  Intentions := TStringList.Create;
end;

destructor TSIRDocument.Destroy;
begin
  SemanticMaps.Free;
  Goals.Free;
  Subgoals.Free;
  Questions.Free;
  Observations.Free;
  Facts.Free;
  Assumptions.Free;
  Constraints.Free;
  Hypotheses.Free;
  Evidences.Free;
  CounterEvidences.Free;
  Alternatives.Free;
  Risks.Free;
  Confidences.Free;
  Dependencies.Free;
  Unknowns.Free;
  Policies.Free;
  Intentions.Free;
  inherited;
end;

function TSIRDocument.LoadFromBlock(Block: TBlock): Boolean;
var
  i: Integer;
  Child, MapBlock: TBlock;
  Map: TSIRSemanticMapping;
begin
  Result := False;
  if not Assigned(Block) then Exit;
  Metadata := Block.GetContent('METADATA');
  Child := Block.FindChild('SEMANTIC MAP');
  if Assigned(Child) then
  begin
    for i := 0 to Child.Children.Count - 1 do
    begin
      MapBlock := Child.Children[i];
      if SameText(MapBlock.Name, 'MAPPING') then
      begin
        // Parse: "entity = "server room" : WorldState.zone_1_temp"
        // We'll split on ':' to get left and target.
        var colonPos := Pos(':', MapBlock.Content);
        if colonPos > 0 then
        begin
          Map.Target := Trim(Copy(MapBlock.Content, colonPos+1, MaxInt));
          var Left := Trim(Copy(MapBlock.Content, 1, colonPos-1));
          // Extract type and phrase from left: "entity = "server room""
          var eqPos := Pos('=', Left);
          if eqPos > 0 then
          begin
            Map.MapType := Trim(Copy(Left, 1, eqPos-1));
            Map.Phrase := Trim(Copy(Left, eqPos+1, MaxInt));
            // Remove surrounding quotes if any
            if (Length(Map.Phrase) >= 2) and (Map.Phrase[1] = '"') and (Map.Phrase[Length(Map.Phrase)] = '"') then
              Map.Phrase := Copy(Map.Phrase, 2, Length(Map.Phrase)-2);
            SemanticMaps.Add(Map);
          end;
        end;
      end;
    end;
  end;
  for i := 0 to Block.Children.Count - 1 do
  begin
    Child := Block.Children[i];
    if SameText(Child.Name, 'GOAL') then Goals.Add(Child.Content)
    else if SameText(Child.Name, 'SUBGOAL') then Subgoals.Add(Child.Content)
    else if SameText(Child.Name, 'QUESTION') then Questions.Add(Child.Content)
    else if SameText(Child.Name, 'OBSERVATION') then Observations.Add(Child.Content)
    else if SameText(Child.Name, 'FACT') then Facts.Add(Child.Content)
    else if SameText(Child.Name, 'ASSUMPTION') then Assumptions.Add(Child.Content)
    else if SameText(Child.Name, 'CONSTRAINT') then Constraints.Add(Child.Content)
    else if SameText(Child.Name, 'HYPOTHESIS') then Hypotheses.Add(Child.Content)
    else if SameText(Child.Name, 'EVIDENCE') then Evidences.Add(Child.Content)
    else if SameText(Child.Name, 'COUNTER EVIDENCE') then CounterEvidences.Add(Child.Content)
    else if SameText(Child.Name, 'ALTERNATIVE') then Alternatives.Add(Child.Content)
    else if SameText(Child.Name, 'RISK') then Risks.Add(Child.Content)
    else if SameText(Child.Name, 'CONFIDENCE') then Confidences.Add(Child.Content)
    else if SameText(Child.Name, 'DEPENDENCY') then Dependencies.Add(Child.Content)
    else if SameText(Child.Name, 'UNKNOWN') then Unknowns.Add(Child.Content)
    else if SameText(Child.Name, 'POLICY') then Policies.Add(Child.Content)
    else if SameText(Child.Name, 'INTENTION') then Intentions.Add(Child.Content);
  end;
  Result := True;
end;

end.