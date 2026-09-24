program GrispGUI;

uses
  Vcl.Forms,
  Main in 'Main.pas' {MainForm};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'GRISP OS';
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.