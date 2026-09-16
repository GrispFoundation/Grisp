@echo off
setlocal

set OUT=combined.txt

REM --- Start fresh ---
if exist "%OUT%" del "%OUT%"

REM --- Helper to write header + file ---
REM Usage: call :addfile "full\path\to\file"
:addfile
echo ================================================================ >> "%OUT%"
echo FILE: %~1 >> "%OUT%"
echo ================================================================ >> "%OUT%"
type "%~1" >> "%OUT%"
echo. >> "%OUT%"
goto :eof

REM --- Concatenate all files with headers ---

call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\IMPLEMENTATION_NOTES.md"
call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\install-component.ps1"
call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\README.md"
call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\README_INSTALLATION.md"

call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\browser\components\aistarter\AIAutomation.sys.mjs"
call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\browser\components\aistarter\actors\AIAutomationChild.sys.mjs"
call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\browser\components\aistarter\actors\AIAutomationParent.sys.mjs"
call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\browser\components\aistarter\diagnostics\AIAutomationDiagnostics.sys.mjs"

call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\browser\components\aistarter\garp\GarpConnection.sys.mjs"
call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\browser\components\aistarter\garp\GarpErrors.sys.mjs"
call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\browser\components\aistarter\garp\GarpFrame.sys.mjs"
call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\browser\components\aistarter\garp\GarpRegistry.sys.mjs"

call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\browser\components\aistarter\providers\ChatGPTAdapter.sys.mjs"
call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\browser\components\aistarter\providers\ClaudeAdapter.sys.mjs"
call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\browser\components\aistarter\providers\CopilotAdapter.sys.mjs"
call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\browser\components\aistarter\providers\DeepSeekAdapter.sys.mjs"
call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\browser\components\aistarter\providers\GeminiAdapter.sys.mjs"
call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\browser\components\aistarter\providers\GrokAdapter.sys.mjs"
call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\browser\components\aistarter\providers\InceptionAdapter.sys.mjs"
call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\browser\components\aistarter\providers\PerplexityAdapter.sys.mjs"
call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\browser\components\aistarter\providers\ProviderAdapter.sys.mjs"
call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\browser\components\aistarter\providers\ProviderRegistry.sys.mjs"

call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\browser\components\aistarter\requests\GarpRequest.sys.mjs"
call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\browser\components\aistarter\requests\GarpRequestManager.sys.mjs"

call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\browser\components\aistarter\sessions\AIAutomationSession.sys.mjs"
call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\browser\components\aistarter\sessions\AIAutomationSessionManager.sys.mjs"

call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\integration\BrowserGlue.integration.txt"
call :addfile "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\Grisp AI Relay Protocol\(For Firefox) version 1.04 fix race conditions and bugs\integration\DesktopActorRegistry.integration.txt"

echo Done.
endlocal
