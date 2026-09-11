program GrispTestRunner;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  Grisp.Types in '..\Core\Grisp.Types.pas',
  Grisp.Canonical in '..\Core\Grisp.Canonical.pas',
  Grisp.Parser in '..\Core\Grisp.Parser.pas',
  Grisp.GARP in '..\Core\Grisp.GARP.pas',
  Grisp.StateMachine in '..\Core\Grisp.StateMachine.pas',
  Grisp.MockCompiler in '..\Mock\Grisp.MockCompiler.pas',
  Grisp.MockTestRunner in '..\Mock\Grisp.MockTestRunner.pas',
  Grisp.Tests in '..\Tests\Grisp.Tests.pas';

begin
  try
    Writeln('====================================================');
    Writeln(' GRISP v1.0 Verification Engine & Test Harness ');
    Writeln('====================================================');
    Writeln;

    TGrispTests.RunAllTests;

    Writeln;
    Writeln('Execution completed successfully. Press ENTER to exit.');
    Readln;
  except
    on E: Exception do
    begin
      Writeln(Format('Fatal Error: %s: %s', [E.ClassName, E.Message]));
      ExitCode := 1;
      Readln;
    end;
  end;
end.