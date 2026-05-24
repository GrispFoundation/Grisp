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
begin
  Result := 0;
  if Graph = nil then
  begin
    Exit;
  end;
  Matcher := TGrispPatternMatcher.Create(Graph);
  Rewriter := TGrispRewriter.Create(Graph);
  try
    Step := 0;
    repeat
      Changed := False;
      for Rule in Graph.Rules do
      begin
        if Rewriter.ApplyRuleOnce(Rule, Matcher, Trace) then
        begin
          Inc(Step);
          Changed := True;
          if Assigned(Trace) then
          begin
            Trace.Add(Format('Step %d: applied %s', [Step, Rule.Name]));
          end;
          if Step >= MaxSteps then
          begin
            Break;
          end;
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
