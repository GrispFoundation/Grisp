program GRISP_TUI;

{$APPTYPE CONSOLE}

uses
    System.SysUtils,
    GRISP.TUI.App in 'GRISP.TUI.App.pas';

begin
    try
        TGrispTUIApplication.Run;
    except
        on E: Exception do
        begin
            Writeln;
            Writeln('GRISP TUI fatal error: ', E.ClassName, ': ', E.Message);
            Writeln('Press ENTER to exit.');
            Readln;
            ExitCode := 1;
        end;
    end;
end.
