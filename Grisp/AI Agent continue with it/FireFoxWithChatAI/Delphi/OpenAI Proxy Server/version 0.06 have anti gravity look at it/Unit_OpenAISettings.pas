unit Unit_OpenAISettings;

interface

uses
  System.SysUtils;

var
  // Set these values as you like before creating the server.
  // DebugEnabled: True to enable logging at startup.
  // DebugLevel: 0=off, 1=errors, 2=info, 3=verbose.
  DebugEnabled: Boolean = True;
  DebugLevel: Integer = 3;
  // LogFile: if empty, the DPR will set a default next-to-exe path.
  LogFile: string = '';

implementation

end.

