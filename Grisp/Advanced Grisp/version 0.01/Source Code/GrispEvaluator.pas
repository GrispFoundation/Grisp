unit GrispEvaluator;

interface

uses
  SysUtils, Classes, Generics.Collections, StrUtils,
  GrispToolManifest, GrispWorldState, GrispPlanner;

type
  TEvaluator = class
  private
    FWorldState: TWorldState;
    FManifests: TToolManifestRegistry;
    function ComputeDynamicCost(const CEIR: string): Integer;
  public
    constructor Create(WorldState: TWorldState; Manifests: TToolManifestRegistry);
    function SelectBest(const Candidates: TArray<TPlanCandidate>): TPlanCandidate;
  end;

implementation

{ TEvaluator }

constructor TEvaluator.Create(WorldState: TWorldState; Manifests: TToolManifestRegistry);
begin
  FWorldState := WorldState;
  FManifests := Manifests;
end;

function TEvaluator.ComputeDynamicCost(const CEIR: string): Integer;
var
  cnt: Integer;
  SearchPos: Integer;   // renamed from 'pos' to avoid hiding the built-in Pos function
  cost: Integer;
begin
  cnt := 0;
  SearchPos := 1;
  while SearchPos < Length(CEIR) do
  begin
    SearchPos := PosEx('⟦CALL ', CEIR, SearchPos);
    if SearchPos = 0 then
      Break;
    Inc(cnt);
    Inc(SearchPos);
  end;
  cost := cnt * 50;
  if (Pos('speed = 100', CEIR) > 0) then
    cost := cost + 10;
  if (Pos('speed = 70', CEIR) > 0) then
    cost := cost + 5;
  if (Pos('speed = 30', CEIR) > 0) then
    cost := cost - 5;
  Result := cost;
end;

function TEvaluator.SelectBest(const Candidates: TArray<TPlanCandidate>): TPlanCandidate;
var
  i, BestIdx: Integer;
  BestCost, Cost: Integer;
  BestConf, Conf: Double;
  BestRisk, Risk: string;
begin
  if Length(Candidates) = 0 then
    raise Exception.Create('No candidates to evaluate');
  BestIdx := 0;
  BestCost := MaxInt;
  BestConf := -1;
  BestRisk := 'high';
  for i := 0 to Length(Candidates) - 1 do
  begin
    Cost := ComputeDynamicCost(Candidates[i].CEIRText);
    Conf := Candidates[i].Confidence;
    Risk := Candidates[i].Risk;
    if (Cost < BestCost) then
    begin
      BestIdx := i;
      BestCost := Cost;
      BestConf := Conf;
      BestRisk := Risk;
    end
    else if (Cost = BestCost) then
    begin
      if (Conf > BestConf) then
      begin
        BestIdx := i;
        BestConf := Conf;
        BestRisk := Risk;
      end
      else if (Conf = BestConf) then
      begin
        if (Risk = 'low') and (BestRisk <> 'low') then
        begin
          BestIdx := i;
          BestRisk := Risk;
        end
        else if (Risk = 'medium') and (BestRisk = 'high') then
        begin
          BestIdx := i;
          BestRisk := Risk;
        end;
      end;
    end;
  end;
  Result := Candidates[BestIdx];
end;

end.
