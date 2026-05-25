unit unit_GrispRuntime_version_001;

interface

uses
  System.SysUtils,
  System.Classes,
  unit_GrispGraph_version_001,
  unit_GrispPattern_version_001,
  unit_GrispRewrite_version_001;

type
  TGrispRuntime = class
  public
    class function Run(Graph: TGGraph; MaxSteps: Integer = 1000; Trace: TStrings = nil): Integer;
  end;

implementation

class function TGrispRuntime.Run(Graph: TGGraph; MaxSteps: Integer; Trace: TStrings): Integer;
var
  Matcher: TGrispPatternMatcher;
  Rewriter: TGrispRewriter;
  Step: Integer;
  Changed: Boolean;
  Rule: TGNode;
  Applied: Integer;
begin
  Result := 0;
  if Graph = nil then
    Exit;

  Matcher := TGrispPatternMatcher.Create(Graph);
  Rewriter := TGrispRewriter.Create(Graph);
  try
    Step := 0;
    repeat
      Changed := False;

      for Rule in Graph.Rules do
      begin
        Matcher.SetCurrentRule(Rule);
        Applied := Rewriter.ApplyAllMatches(Rule, Matcher, Trace);

        if Applied > 0 then
        begin
          Inc(Step, Applied);
          Changed := True;

          if Assigned(Trace) then
            Trace.Add(Format('Step %d: applied %s (%d matches)', [Step, Rule.Name, Applied]));

          if Step >= MaxSteps then
            Break;
        end;
      end;

    until (not Changed) or (Step >= MaxSteps);

    Result := Step;
  finally
    Rewriter.Free;
    Matcher.Free;
  end;
end;

end.
