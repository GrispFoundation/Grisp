unit GrispExecutor;

interface

uses
  SysUtils, Classes,
  GrispEIR, GrispToolManifest, GrispWorldState, GrispLSBP, GrispMarkerParser;

type
  TExecutor = class
  private
    FWorldState: TWorldState;
    FManifests: TToolManifestRegistry;
    FEventLog: TStringList;
    FLSBPBundle: TLSBPBundle;
    procedure EmitEvent(const EventName, Payload: string);
    procedure ExecuteAssignment(const AssignText: string);
    procedure ExecuteToolCall(const CallText: string);
    procedure ExecuteLoop(const LoopBlock: string);
    procedure ExecuteDecision(const DecisionBlock: string);
    procedure ExecuteBlock(const BlockName, Content: string);
    procedure ProcessBlock(const Block: TBlock);
  public
    constructor Create(AWorldState: TWorldState; AManifests: TToolManifestRegistry);
    destructor Destroy; override;
    procedure ExecuteCanonicalEIR(const EIRText: string);
    procedure PrintEvents;
  end;

implementation

{ TExecutor }

constructor TExecutor.Create(AWorldState: TWorldState; AManifests: TToolManifestRegistry);
begin
  FWorldState := AWorldState;
  FManifests := AManifests;
  FEventLog := TStringList.Create;
  FLSBPBundle := TLSBPBundle.Create(dtBundle);
end;

destructor TExecutor.Destroy;
begin
  FEventLog.Free;
  FLSBPBundle.Free;
  inherited;
end;

procedure TExecutor.EmitEvent(const EventName, Payload: string);
begin
  FEventLog.Add(Format('{"event":"%s","payload":"%s"}', [EventName, Payload]));
end;

procedure TExecutor.ExecuteAssignment(const AssignText: string);
var
  eqPos: Integer;
  varName, value: string;
begin
  eqPos := Pos('=', AssignText);
  if eqPos > 0 then
  begin
    varName := Trim(Copy(AssignText, 1, eqPos - 1));
    value := Trim(Copy(AssignText, eqPos + 1, MaxInt));
    FWorldState.SetVariable(varName, value);
    EmitEvent('assignment', varName + ' = ' + value);
  end;
end;

procedure TExecutor.ExecuteToolCall(const CallText: string);
var
  target, action, args: string;
  dotPos, parenPos: Integer;
  Manifest: TToolManifest;
  Act: TActionDefinition;
  Pre: string;
begin
  dotPos := Pos('.', CallText);
  if dotPos > 0 then
  begin
    target := Trim(Copy(CallText, 1, dotPos - 1));
    parenPos := Pos('(', CallText);
    if parenPos > 0 then
    begin
      action := Trim(Copy(CallText, dotPos + 1, parenPos - dotPos - 1));
      args := Trim(Copy(CallText, parenPos + 1, Length(CallText) - parenPos - 1));
      if not FManifests.HasTool(target) then
        EmitEvent('tool_call_error', 'Unknown target: ' + target)
      else
      begin
        Manifest := FManifests.GetManifest(target);
        Act := Manifest.FindAction(action);
        if Act.ActionName = '' then
          EmitEvent('tool_call_error', 'Unknown action: ' + action)
        else
        begin
          // Check preconditions
          for Pre in Act.Preconditions do
          begin
            if FWorldState.GetVariable(Pre) = '' then
            begin
              EmitEvent('precondition_failed', Pre);
              Exit;
            end;
          end;
          // Simulate tool call
          EmitEvent('tool_call', target + '.' + action + '(' + args + ')');
          // Handle bundle strategy
          if Act.SideEffects.IndexOf('filesystem') >= 0 then
          begin
            if SameText(Act.BundleStrategy, 'immediate') then
            begin
              var BundleText := FLSBPBundle.GenerateBundle;
              EmitEvent('lsbp_bundle_immediate', BundleText);
              FWorldState.AddBundle('immediate_bundle');
            end
            else if SameText(Act.BundleStrategy, 'lazy') then
            begin
              // Accumulate in bundle
              FLSBPBundle.AddFile('lazy.txt', 'Lazy content');
            end;
            // else 'never': do nothing
          end;
        end;
      end;
    end;
  end;
end;

procedure TExecutor.ExecuteLoop(const LoopBlock: string);
var
  i: Integer;
begin
  EmitEvent('loop_start', '');
  for i := 1 to 3 do
  begin
    EmitEvent('loop_iteration', IntToStr(i));
  end;
  EmitEvent('loop_end', '');
end;

procedure TExecutor.ExecuteDecision(const DecisionBlock: string);
begin
  EmitEvent('decision', 'branch_taken');
end;

procedure TExecutor.ExecuteBlock(const BlockName, Content: string);
begin
  if SameText(BlockName, 'ASSIGNMENT') then
    ExecuteAssignment(Content)
  else if SameText(BlockName, 'TOOL CALL') then
    ExecuteToolCall(Content)
  else if SameText(BlockName, 'LOOP') then
    ExecuteLoop(Content)
  else if SameText(BlockName, 'DECISION') then
    ExecuteDecision(Content)
  else
    EmitEvent('block', BlockName + ':' + Content);
end;

procedure TExecutor.ProcessBlock(const Block: TBlock);
var
  Child: TBlock;
begin
  if SameText(Block.Name, 'PROGRAM') then
  begin
    for Child in Block.Children do
      ProcessBlock(Child);
  end
  else
  begin
    ExecuteBlock(Block.Name, Block.Content);
  end;
end;

procedure TExecutor.ExecuteCanonicalEIR(const EIRText: string);
var
  Doc: TDocument;
  Prog: TBlock;
begin
  Doc := TDocument.Create;
  try
    Doc.Parse(EIRText);
    Prog := Doc.Root.FindChild('PROGRAM');
    if Assigned(Prog) then
      ProcessBlock(Prog);
    // After execution, if lazy bundle has content, emit it.
    if FLSBPBundle.GenerateBundle <> '' then
      EmitEvent('lsbp_bundle_lazy', FLSBPBundle.GenerateBundle);
  finally
    Doc.Free;
  end;
end;

procedure TExecutor.PrintEvents;
var
  s: string;
begin
  for s in FEventLog do
    WriteLn(s);
end;

end.
