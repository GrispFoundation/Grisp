program GrispAgentTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  GrispCapabilities in '..\..\Source Code\Core\GrispCapabilities.pas',
  GrispVfs in '..\..\Source Code\Core\GrispVfs.pas',
  GrispGraph in '..\..\Source Code\Core\GrispGraph.pas',
  GrispCore in '..\..\Source Code\Core\GrispCore.pas',
  MLCRD_Types in '..\..\Source Code\Agent\MLCRD_Types.pas',
  MLCRD_Interfaces in '..\..\Source Code\Agent\MLCRD_Interfaces.pas',
  MLCRD_Utils in '..\..\Source Code\Agent\MLCRD_Utils.pas',
  MLCRD_Algorithms in '..\..\Source Code\Agent\MLCRD_Algorithms.pas',
  MLCRD_Adapters in '..\..\Source Code\Agent\MLCRD_Adapters.pas',
  MLCRD_Peers in '..\..\Source Code\Agent\MLCRD_Peers.pas',
  MLCRD_Coordinator in '..\..\Source Code\Agent\MLCRD_Coordinator.pas',
  TestGrispCore in '..\..\Source Code\Tests\TestGrispCore.pas',
  TestMLCRD in '..\..\Source Code\Tests\TestMLCRD.pas';

var
  CoreRunner: TTestGrispCoreRunner;
  MLCRDRunner: TTestMLCRDRunner;
  TotalPassed, TotalFailed: Integer;
begin
  try
    Writeln('****************************************************************');
    Writeln('    GRISP ADVANCED AGENT & KERNEL AUTOMATED TEST SUITE          ');
    Writeln('****************************************************************');
    Writeln;

    CoreRunner := TTestGrispCoreRunner.Create;
    try
      CoreRunner.RunAllTests;
    finally
      TotalPassed := CoreRunner.Passed;
      TotalFailed := CoreRunner.Failed;
      CoreRunner.Free;
    end;

    Writeln;

    MLCRDRunner := TTestMLCRDRunner.Create;
    try
      MLCRDRunner.RunAllTests;
      TotalPassed := TotalPassed + MLCRDRunner.Passed;
      TotalFailed := TotalFailed + MLCRDRunner.Failed;
    finally
      MLCRDRunner.Free;
    end;

    Writeln;
    Writeln('****************************************************************');
    Writeln(Format('GRAND TOTAL: %d Tests Passed, %d Tests Failed', [TotalPassed, TotalFailed]));
    Writeln('****************************************************************');

    if TotalFailed > 0 then
      ExitCode := 1
    else
      ExitCode := 0;

  except
    on E: Exception do
    begin
      Writeln('FATAL TEST EXCEPTION: ' + E.ClassName + ': ' + E.Message);
      ExitCode := 2;
    end;
  end;
end.
