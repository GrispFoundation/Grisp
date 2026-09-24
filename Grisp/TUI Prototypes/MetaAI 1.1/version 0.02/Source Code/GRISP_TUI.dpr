program GRISP_TUI;

{$APPTYPE CONSOLE}

uses
  Winapi.Windows,
  System.SysUtils,
  GRISP.TUI.Data in 'GRISP.TUI.Data.pas',
  GRISP.TUI.Core in 'GRISP.TUI.Core.pas',
  GRISP.TUI.App in 'GRISP.TUI.App.pas';

var
  App: TGRISPTUIApp;

begin
  try
    App := TGRISPTUIApp.Create;
    try
      App.Run;
    finally
      App.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Readln;
    end;
  end;
end.
