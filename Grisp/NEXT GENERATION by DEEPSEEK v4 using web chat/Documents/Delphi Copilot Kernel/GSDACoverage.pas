unit GSDACoverage;

{

You can now wire this into your publication gate like:

uses
  GSDACoverage;

function TGSDAPublication.CheckCoverageThresholds: TPublicationPredicateResult;
var
  Engine: TGSDACoverageEngine;
  Task: TTask;
  Cov: TCoverageResult;
begin
  Result.Name := 'COVERAGE_THRESHOLDS';

  // For simplicity, assume one task; in reality you’d select the right one.
  Task := FKernel.State.FindTask('your-task-id-here');
  if Task = nil then
  begin
    Result.Passed := False;
    Result.Reason := 'No task found for coverage evaluation';
    Exit;
  end;

  Engine := TGSDACoverageEngine.Create(FKernel.State);
  try
    Cov := Engine.ComputeCoverage(Task);

    if Cov.CriticalCoverage < 1.0 then
    begin
      Result.Passed := False;
      Result.Reason := Format(
        'Critical coverage %.3f < 1.0; uncovered offsets: %s',
        [Cov.CriticalCoverage,
         string.Join(',', Cov.UncoveredOffsets)]
      );
    end
    else
    begin
      Result.Passed := True;
      Result.Reason := '';
    end;
  finally
    Engine.Free;
  end;
end;


}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  GSDAKernel; // for TTask, TAuthoritativeState, etc.

type
  // Intent element (simplified)
  TIntentElement = class
  public
    IntentID: string;
    Text: string;
    ByteStart: Integer;
    ByteEnd: Integer;
    Critical: Boolean;
    LinkedArtifactIDs: TArray<string>;
  end;

  // Coverage result
  TCoverageResult = record
    TotalIntentElements: Integer;
    LinkedIntentElements: Integer;
    CriticalIntentElements: Integer;
    LinkedCriticalIntentElements: Integer;
    CriticalCoverage: Double;
    UncoveredOffsets: TArray<Integer>;
  end;

  TGSDACoverageEngine = class
  private
    FState: TAuthoritativeState;

    function ExtractIntentElements(ATask: TTask): TArray<TIntentElement>;
    function LinkIntentToArtifacts(const Intents: TArray<TIntentElement>): TArray<TIntentElement>;
  public
    constructor Create(AState: TAuthoritativeState);

    function ComputeCoverage(ATask: TTask): TCoverageResult;
  end;

implementation

uses
  System.StrUtils;

{ TGSDACoverageEngine }

constructor TGSDACoverageEngine.Create(AState: TAuthoritativeState);
begin
  FState := AState;
end;

function TGSDACoverageEngine.ExtractIntentElements(ATask: TTask): TArray<TIntentElement>;
var
  List: TObjectList<TIntentElement>;
  Parts: TArray<string>;
  I, PosStart, PosEnd: Integer;
  Cursor: Integer;
  Elem: TIntentElement;
begin
  // Simplified segmentation: split user_intent on periods.
  List := TObjectList<TIntentElement>.Create(True);
  try
    Parts := ATask.UserIntent.Split(['.'], TStringSplitOptions.ExcludeEmpty);
    Cursor := 1;

    for I := 0 to High(Parts) do
    begin
      PosStart := Cursor;
      PosEnd := Cursor + Length(Parts[I]) - 1;

      Elem := TIntentElement.Create;
      Elem.IntentID := Format('intent:%d', [I + 1]);
      Elem.Text := Trim(Parts[I]);
      Elem.ByteStart := PosStart;
      Elem.ByteEnd := PosEnd;
      Elem.Critical := ContainsText(Elem.Text, '[CRITICAL]');
      Elem.LinkedArtifactIDs := [];

      List.Add(Elem);

      Cursor := PosEnd + 2; // skip ". "
    end;

    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function TGSDACoverageEngine.LinkIntentToArtifacts(
  const Intents: TArray<TIntentElement>): TArray<TIntentElement>;
var
  I: Integer;
begin
  // Stub: in a real system, you would:
  // - walk artifacts in FState
  // - match intent text to requirement text, artifact text, etc.
  // - populate LinkedArtifactIDs for each intent element.
  //
  // For now, we simulate that every non-empty intent is linked.

  Result := Copy(Intents);
  for I := 0 to High(Result) do
  begin
    if Result[I].Text <> '' then
      Result[I].LinkedArtifactIDs := ['artifact:dummy'];
  end;
end;

function TGSDACoverageEngine.ComputeCoverage(ATask: TTask): TCoverageResult;
var
  Intents, LinkedIntents: TArray<TIntentElement>;
  I: Integer;
  Uncovered: TList<Integer>;
begin
  Intents := ExtractIntentElements(ATask);
  LinkedIntents := LinkIntentToArtifacts(Intents);

  Result.TotalIntentElements := Length(Intents);
  Result.LinkedIntentElements := 0;
  Result.CriticalIntentElements := 0;
  Result.LinkedCriticalIntentElements := 0;

  Uncovered := TList<Integer>.Create;
  try
    for I := 0 to High(LinkedIntents) do
    begin
      if LinkedIntents[I].Critical then
        Inc(Result.CriticalIntentElements);

      if Length(LinkedIntents[I].LinkedArtifactIDs) > 0 then
      begin
        Inc(Result.LinkedIntentElements);
        if LinkedIntents[I].Critical then
          Inc(Result.LinkedCriticalIntentElements);
      end
      else
      begin
        // record uncovered byte_start for reporting
        Uncovered.Add(LinkedIntents[I].ByteStart);
      end;
    end;

    if Result.CriticalIntentElements > 0 then
      Result.CriticalCoverage :=
        Result.LinkedCriticalIntentElements / Result.CriticalIntentElements
    else
      Result.CriticalCoverage := 1.0;

    Result.UncoveredOffsets := Uncovered.ToArray;
  finally
    Uncovered.Free;
  end;
end;

end.
