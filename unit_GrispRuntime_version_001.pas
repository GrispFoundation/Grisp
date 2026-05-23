unit unit_GrispRuntime_version_001;

interface

uses
  unit_GrispGraph_version_001,
  unit_GrispPattern_version_001,
  unit_GrispRewrite_version_001;

type
  TGrispRuntime = class
  public
    // Run all rules on the graph until no more changes or MaxSteps reached.
    // Returns the number of successful rewrite steps.
    class function Run(Graph: TGGraph; MaxSteps: Integer = 1000): Integer;
  end;

implementation

class function TGrispRuntime.Run(Graph: TGGraph; MaxSteps: Integer): Integer;
var
  Matcher: TGrispPatternMatcher;
  Rewriter: TGrispRewriter;
  Step: Integer;
  Changed: Boolean;
  Rule: TGNode;
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
        if Rewriter.ApplyRuleOnce(Rule, Matcher) then
        begin
          Inc(Step);
          Changed := True;
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
