program GRISP_OS_D13;

uses
  Vcl.Forms,
  Vcl.Skia, // Skia4Delphi 7.3 ingebouwd in Delphi 13 Florence
  MainForm in 'MainForm.pas' {FrmGRISP},
  GRISP.Data in 'GRISP.Data.pas',
  GRISP.Terminal in 'GRISP.Terminal.pas';

{$R *.res}

begin
  // Delphi 13 Florence heeft Skia4Delphi 7.3 geintegreerd
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'GRISP OS - Delphi 13 Prototype';
  // Optioneel: Mica materiaal voor Windows 11
  // Application.StyleServices.Enabled := True;
  Application.CreateForm(TFrmGRISP, FrmGRISP);
  Application.Run;
end.
