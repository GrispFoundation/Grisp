program GSDADemo;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.JSON,
  GSDAKernel in 'GSDAKernel.pas',
  GSDACanonicalJson in 'GSDACanonicalJson.pas',
  GSDAPublication in 'GSDAPublication.pas',
  GSDACoverage in 'GSDACoverage.pas',
  GSDATraceability in 'GSDATraceability.pas';

procedure RunDemo;
var
  Kernel: TGSDAKernel;
  Task: TTask;
  Run: TRun;
  Requirements, Glossary, Assumptions, OpenQuestions, TraceabilityJson: TJSONObject;
  Pub: TGSDAPublication;
  TraceEngine: TGSDATraceabilityEngine;
  Trace: TTraceability;
begin
  Kernel := TGSDAKernel.Create;
  try
    Writeln('GSDA Demo starting...');

    // 1. Create a task
    Task := Kernel.CreateTask(
      'User wants a deterministic spec system.',
      'Define a deterministic kernel. [CRITICAL] Ensure identity is stable.',
      'specification',
      'gsda',
      'Delphi',
      ['engineers'],
      ['deterministic', 'traceable'],
      ['spec', 'code'],
      'default'
    );

    Writeln('TaskID: ' + Task.TaskID);
    Writeln('TargetContextID: ' + Task.TargetContextID);

    // 2. Start a run
    Run := Kernel.StartRun(Task);
    Writeln('RunID: ' + Run.RunID);

    // 3. Build dummy spec components
    Requirements := TJSONObject.Create;
    Glossary := TJSONObject.Create;
    Assumptions := TJSONObject.Create;
    OpenQuestions := TJSONObject.Create;

    Requirements.AddPair('schema', 'requirements/3.1');
    Requirements.AddPair('items', TJSONArray.Create);

    Glossary.AddPair('schema', 'glossary/3.1');
    Glossary.AddPair('terms', TJSONArray.Create);

    Assumptions.AddPair('schema', 'assumptions/3.1');
    Assumptions.AddPair('items', TJSONArray.Create);

    OpenQuestions.AddPair('schema', 'open_questions/3.1');
    OpenQuestions.AddPair('items', TJSONArray.Create);

    // 4. Compute traceability (dummy)
    TraceEngine := TGSDATraceabilityEngine.Create(Kernel.State);
    try
      Trace := TraceEngine.ComputeTraceability;
      TraceabilityJson := TraceEngine.ToJson(Trace);
    finally
      TraceEngine.Free;
    end;

    // 5. Publication attempt
    Pub := TGSDAPublication.Create(Kernel);
    try
      Writeln('Evaluating publication predicates...');
      Pub.Publish(Requirements, Glossary, Assumptions, OpenQuestions, TraceabilityJson);
      Writeln('Publication succeeded.');
    except
      on E: Exception do
      begin
        Writeln('Publication failed: ' + E.Message);
      end;
    end;

    // Cleanup
    Requirements.Free;
    Glossary.Free;
    Assumptions.Free;
    OpenQuestions.Free;
    TraceabilityJson.Free;

    Writeln('GSDA Demo finished.');
  finally
    Kernel.Free;
  end;
end;

begin
  try
    RunDemo;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
  Readln;
end.
