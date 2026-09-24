program GRISP_OS_D13;

uses
  Vcl.Forms,
  MainForm in 'MainForm.pas' {FrmGRISP},
  GRISP.Data in 'GRISP.Data.pas',
  GRISP.Terminal in 'GRISP.Terminal.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'GRISP OS - Delphi 13 Florence v0.02';
  Application.CreateForm(TFrmGRISP, FrmGRISP);
  Application.Run;
end.
