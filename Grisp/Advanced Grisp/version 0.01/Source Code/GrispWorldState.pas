unit GrispWorldState;

interface

uses
  SysUtils, Classes, Generics.Collections;

type
  TWorldState = class
  private
    FVersion: Integer;
    FVariables: TDictionary<string, string>;
    FFacts: TList<string>;
    FToolOutputs: TDictionary<string, string>;
    FGraphNodes: TList<string>;
    FBundles: TList<string>;
    FPlanHistory: TList<string>;
    function Serialize: string;
    procedure Deserialize(const JSON: string);
  public
    constructor Create;
    destructor Destroy; override;
    procedure IncrementVersion;
    procedure SetVariable(const Name, Value: string);
    function GetVariable(const Name: string): string;
    procedure AddFact(const Fact: string);
    procedure AddToolOutput(const ID, Output: string);
    procedure AddBundle(const BundleID: string);
    procedure AddPlanOutcome(const Outcome: string);
    procedure SaveToFile(const Filename: string);
    procedure LoadFromFile(const Filename: string);
    property Version: Integer read FVersion;
  end;

implementation

uses
  System.JSON;

{ TWorldState }

constructor TWorldState.Create;
begin
  FVersion := 0;
  FVariables := TDictionary<string, string>.Create;
  FFacts := TList<string>.Create;
  FToolOutputs := TDictionary<string, string>.Create;
  FGraphNodes := TList<string>.Create;
  FBundles := TList<string>.Create;
  FPlanHistory := TList<string>.Create;
end;

destructor TWorldState.Destroy;
begin
  FVariables.Free;
  FFacts.Free;
  FToolOutputs.Free;
  FGraphNodes.Free;
  FBundles.Free;
  FPlanHistory.Free;
  inherited;
end;

procedure TWorldState.IncrementVersion;
begin
  Inc(FVersion);
end;

procedure TWorldState.SetVariable(const Name, Value: string);
begin
  if FVariables.ContainsKey(Name) then
    FVariables[Name] := Value
  else
    FVariables.Add(Name, Value);
end;

function TWorldState.GetVariable(const Name: string): string;
begin
  if FVariables.TryGetValue(Name, Result) then Exit;
  Result := '';
end;

procedure TWorldState.AddFact(const Fact: string);
begin
  FFacts.Add(Fact);
end;

procedure TWorldState.AddToolOutput(const ID, Output: string);
begin
  if FToolOutputs.ContainsKey(ID) then
    FToolOutputs[ID] := Output
  else
    FToolOutputs.Add(ID, Output);
end;

procedure TWorldState.AddBundle(const BundleID: string);
begin
  FBundles.Add(BundleID);
end;

procedure TWorldState.AddPlanOutcome(const Outcome: string);
begin
  FPlanHistory.Add(Outcome);
end;

function TWorldState.Serialize: string;
var
  obj: TJSONObject;
  vars: TJSONObject;
  facts: TJSONArray;
  outputs: TJSONObject;
  nodes: TJSONArray;
  bundles: TJSONArray;
  history: TJSONArray;
  pair: TPair<string, string>;
  s: string;
begin
  obj := TJSONObject.Create;
  try
    obj.AddPair('version', TJSONNumber.Create(FVersion));
    vars := TJSONObject.Create;
    for pair in FVariables do
      vars.AddPair(pair.Key, pair.Value);
    obj.AddPair('variables', vars);
    facts := TJSONArray.Create;
    for s in FFacts do facts.Add(s);
    obj.AddPair('facts', facts);
    outputs := TJSONObject.Create;
    for pair in FToolOutputs do
      outputs.AddPair(pair.Key, pair.Value);
    obj.AddPair('tool_outputs', outputs);
    nodes := TJSONArray.Create;
    for s in FGraphNodes do nodes.Add(s);
    obj.AddPair('graph_nodes', nodes);
    bundles := TJSONArray.Create;
    for s in FBundles do bundles.Add(s);
    obj.AddPair('bundles', bundles);
    history := TJSONArray.Create;
    for s in FPlanHistory do history.Add(s);
    obj.AddPair('plan_history', history);
    Result := obj.ToJSON;
  finally
    obj.Free;
  end;
end;

procedure TWorldState.Deserialize(const JSON: string);
var
  obj: TJSONObject;
  vars: TJSONObject;
  arr: TJSONArray;
  pair: TJSONPair;
  i: Integer;
begin
  obj := TJSONObject.ParseJSONValue(JSON) as TJSONObject;
  if not Assigned(obj) then Exit;
  try
    FVersion := (obj.GetValue('version') as TJSONNumber).AsInt;
    vars := obj.GetValue('variables') as TJSONObject;
    FVariables.Clear;
    for pair in vars do
      FVariables.Add(pair.JsonString.Value, pair.JsonValue.Value);
    arr := obj.GetValue('facts') as TJSONArray;
    FFacts.Clear;
    for i := 0 to arr.Count - 1 do FFacts.Add(arr.Items[i].Value);
    vars := obj.GetValue('tool_outputs') as TJSONObject;
    FToolOutputs.Clear;
    for pair in vars do
      FToolOutputs.Add(pair.JsonString.Value, pair.JsonValue.Value);
    arr := obj.GetValue('graph_nodes') as TJSONArray;
    FGraphNodes.Clear;
    for i := 0 to arr.Count - 1 do FGraphNodes.Add(arr.Items[i].Value);
    arr := obj.GetValue('bundles') as TJSONArray;
    FBundles.Clear;
    for i := 0 to arr.Count - 1 do FBundles.Add(arr.Items[i].Value);
    arr := obj.GetValue('plan_history') as TJSONArray;
    FPlanHistory.Clear;
    for i := 0 to arr.Count - 1 do FPlanHistory.Add(arr.Items[i].Value);
  finally
    obj.Free;
  end;
end;

procedure TWorldState.SaveToFile(const Filename: string);
var
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.Text := Serialize;
    sl.SaveToFile(Filename);
  finally
    sl.Free;
  end;
end;

procedure TWorldState.LoadFromFile(const Filename: string);
var
  sl: TStringList;
begin
  if not FileExists(Filename) then Exit;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(Filename);
    Deserialize(sl.Text);
  finally
    sl.Free;
  end;
end;

end.