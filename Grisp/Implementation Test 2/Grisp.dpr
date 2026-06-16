program Grisp;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  Grisp.Core.Types in 'Grisp.Core.Types.pas',
  Grisp.Core.Ordering in 'Grisp.Core.Ordering.pas',
  Grisp.Core.Counters in 'Grisp.Core.Counters.pas',
  Grisp.Runtime.Engine in 'Grisp.Runtime.Engine.pas',
  Grisp.Core.Expr in 'Grisp.Core.Expr.pas',
  Grisp.Core.Graph in 'Grisp.Core.Graph.pas',
  Grisp.IR.AST in 'Grisp.IR.AST.pas';

begin
  try
    { TODO -oUser -cConsole Main : Insert code here }
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
