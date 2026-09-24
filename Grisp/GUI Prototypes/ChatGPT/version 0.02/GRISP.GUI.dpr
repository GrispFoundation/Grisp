program GRISP.GUI;

uses
    Vcl.Forms,
    GRISP.GUI.Main in 'GRISP.GUI.Main.pas';

{$R *.res}

begin
    Application.Initialize;
    Application.MainFormOnTaskbar := True;
    Application.Title := 'GRISP OS';
    Application.CreateForm(TGrispMainForm, GrispMainForm);
    Application.Run;
end.
