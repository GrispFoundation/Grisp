@echo off
setlocal

rem Output file in the batch file's own directory
set OUT="%~dp0Combined.txt"

rem Start fresh
del %OUT% 2>nul

rem Concatenate all files in order
type "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\NEXT GENERATION by GEMINI 3.6\Input\Delphi Source Code\Core\Grisp.Canonical.pas" >> %OUT%
type "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\NEXT GENERATION by GEMINI 3.6\Input\Delphi Source Code\Core\Grisp.GARP.pas" >> %OUT%
type "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\NEXT GENERATION by GEMINI 3.6\Input\Delphi Source Code\Core\Grisp.Parser.pas" >> %OUT%
type "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\NEXT GENERATION by GEMINI 3.6\Input\Delphi Source Code\Core\Grisp.StateMachine.pas" >> %OUT%
type "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\NEXT GENERATION by GEMINI 3.6\Input\Delphi Source Code\Core\Grisp.Types.pas" >> %OUT%
type "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\NEXT GENERATION by GEMINI 3.6\Input\Delphi Source Code\Mock\Grisp.MockCompiler.pas" >> %OUT%
type "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\NEXT GENERATION by GEMINI 3.6\Input\Delphi Source Code\Mock\Grisp.MockTestRunner.pas" >> %OUT%
type "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\NEXT GENERATION by GEMINI 3.6\Input\Delphi Source Code\Projects\GrispTestRunner.dpr" >> %OUT%
type "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\NEXT GENERATION by GEMINI 3.6\Input\Delphi Source Code\Tests\Grisp.Tests.pas" >> %OUT%

echo Done.
