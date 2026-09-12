unit GSDAVizV2;

{

You’d use it like this in your test harness:
delphi

uses
  GSDAEngineV2, GSDAVizV2;

var
  Engine: TGSDAEngineV2;
  Res: TGSDAEngineResultV2;
begin
  Engine := TGSDAEngineV2.Create;
  Res := Engine.ExecuteSystem(Prompts, RawMsgs, PeerIDs, MsgTypes, Confidences);

  TGSDAVisualizerV2.PrintSystemSummary(Res.SystemJson);
  TGSDAVisualizerV2.PrintTaskDetails(Res.SystemJson);
  TGSDAVisualizerV2.PrintRevisionLineage(Res.SystemJson);
end;

This gives you a clear, human‑readable view of how your GSDA system behaves end‑to‑end.

}

interface

uses
  System.SysUtils,
  System.JSON;

type
  TGSDAVisualizerV2 = class
  public
    class procedure PrintSystemSummary(const SystemJson: TJSONObject);
    class procedure PrintRevisionLineage(const SystemJson: TJSONObject);
    class procedure PrintTaskDetails(const SystemJson: TJSONObject);
  end;

implementation

class procedure TGSDAVisualizerV2.PrintSystemSummary(
  const SystemJson: TJSONObject);
var
  TasksArr: TJSONArray;
begin
  Writeln('=== GSDA SYSTEM SUMMARY ===');

  TasksArr := SystemJson.GetValue('tasks') as TJSONArray;
  Writeln('Tasks count: ', TasksArr.Count);

  if SystemJson.GetValue('revision_lineage') <> nil then
    Writeln('Revision lineage present.')
  else
    Writeln('No revision lineage.');
end;

class procedure TGSDAVisualizerV2.PrintRevisionLineage(
  const SystemJson: TJSONObject);
var
  LineageObj, EntriesArrItem: TJSONValue;
  EntriesArr: TJSONArray;
  I: Integer;
begin
  Writeln;
  Writeln('=== REVISION LINEAGE ===');

  LineageObj := SystemJson.GetValue('revision_lineage');
  if (LineageObj = nil) or not (LineageObj is TJSONObject) then
  begin
    Writeln('No lineage data.');
    Exit;
  end;

  EntriesArr := (LineageObj as TJSONObject).GetValue('entries') as TJSONArray;
  if EntriesArr = nil then
  begin
    Writeln('No entries array in lineage.');
    Exit;
  end;

  for I := 0 to EntriesArr.Count - 1 do
  begin
    EntriesArrItem := EntriesArr.Items[I];
    if EntriesArrItem is TJSONObject then
    begin
      Writeln('--- Entry ', I, ' ---');
      Writeln('SpecContentID: ',
        (EntriesArrItem as TJSONObject).GetValue('spec_content_id').Value);
      Writeln('PreviousSpecContentID: ',
        (EntriesArrItem as TJSONObject).GetValue('previous_spec_content_id').Value);
      Writeln('HumanAccepted: ',
        (EntriesArrItem as TJSONObject).GetValue('human_accepted').Value);
      Writeln('Signature: ',
        (EntriesArrItem as TJSONObject).GetValue('signature').Value);
    end;
  end;
end;

class procedure TGSDAVisualizerV2.PrintTaskDetails(
  const SystemJson: TJSONObject);
var
  TasksArr: TJSONArray;
  TaskVal: TJSONValue;
  TaskObj, BundleObj, CoverageObj, DiffObj: TJSONObject;
  I: Integer;
begin
  Writeln;
  Writeln('=== TASK DETAILS ===');

  TasksArr := SystemJson.GetValue('tasks') as TJSONArray;
  if TasksArr = nil then
  begin
    Writeln('No tasks array.');
    Exit;
  end;

  for I := 0 to TasksArr.Count - 1 do
  begin
    TaskVal := TasksArr.Items[I];
    if not (TaskVal is TJSONObject) then
      Continue;

    TaskObj := TaskVal as TJSONObject;

    Writeln('--- Task ', I, ' ---');
    Writeln('TaskID: ', TaskObj.GetValue('task_id').Value);
    Writeln('RunID: ', TaskObj.GetValue('run_id').Value);
    Writeln('FinalRoundIndex: ', TaskObj.GetValue('final_round_index').Value);
    Writeln('FinalExecutionIdentity: ',
      TaskObj.GetValue('final_execution_identity').Value);
    Writeln('Converged: ', TaskObj.GetValue('converged').Value);

    BundleObj := TaskObj.GetValue('publication_bundle') as TJSONObject;
    if BundleObj <> nil then
    begin
      Writeln('SpecContentID: ',
        BundleObj.GetValue('spec_content_id').Value);

      CoverageObj := BundleObj.GetValue('coverage') as TJSONObject;
      if CoverageObj <> nil then
      begin        Writeln('Coverage: ',
          'Req=', CoverageObj.GetValue('total_requirements').Value,
          ' Covered=', CoverageObj.GetValue('covered_requirements').Value);
      end;

      DiffObj := BundleObj.GetValue('diff_summary') as TJSONObject;
      if DiffObj <> nil then
        Writeln('DiffSummary: ', DiffObj.ToJSON);
    end;
  end;
end;

end.
