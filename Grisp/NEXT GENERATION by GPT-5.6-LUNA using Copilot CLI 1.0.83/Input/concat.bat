@echo off
setlocal

rem Output file next to this batch file
set OUT="%~dp0Combined.txt"

rem Start fresh
del %OUT% 2>nul

type "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\NEXT GENERATION by GPT-5.6-LUNA using Copilot CLI 1.0.83\Input\Delphi Source Code\Core\Grisp.Artifact.pas" >> %OUT%
type "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\NEXT GENERATION by GPT-5.6-LUNA using Copilot CLI 1.0.83\Input\Delphi Source Code\Core\Grisp.ArtifactParser.pas" >> %OUT%
type "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\NEXT GENERATION by GPT-5.6-LUNA using Copilot CLI 1.0.83\Input\Delphi Source Code\Core\Grisp.Canonical.pas" >> %OUT%
type "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\NEXT GENERATION by GPT-5.6-LUNA using Copilot CLI 1.0.83\Input\Delphi Source Code\Core\Grisp.Commit.pas" >> %OUT%
type "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\NEXT GENERATION by GPT-5.6-LUNA using Copilot CLI 1.0.83\Input\Delphi Source Code\Core\Grisp.Evidence.pas" >> %OUT%
type "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\NEXT GENERATION by GPT-5.6-LUNA using Copilot CLI 1.0.83\Input\Delphi Source Code\Core\Grisp.Hash.pas" >> %OUT%
type "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\NEXT GENERATION by GPT-5.6-LUNA using Copilot CLI 1.0.83\Input\Delphi Source Code\Core\Grisp.Policy.pas" >> %OUT%
type "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\NEXT GENERATION by GPT-5.6-LUNA using Copilot CLI 1.0.83\Input\Delphi Source Code\Core\Grisp.StateMachine.pas" >> %OUT%
type "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\NEXT GENERATION by GPT-5.6-LUNA using Copilot CLI 1.0.83\Input\Delphi Source Code\Core\Grisp.Types.pas" >> %OUT%
type "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\NEXT GENERATION by GPT-5.6-LUNA using Copilot CLI 1.0.83\Input\Delphi Source Code\Projects\GrispConformance.dpr" >> %OUT%
type "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\NEXT GENERATION by GPT-5.6-LUNA using Copilot CLI 1.0.83\Input\Delphi Source Code\Tests\Grisp.Core.Tests.pas" >> %OUT%
type "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\NEXT GENERATION by GPT-5.6-LUNA using Copilot CLI 1.0.83\Input\Firefox Source Code\garp\GarpProtocol.sys.mjs" >> %OUT%
type "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\NEXT GENERATION by GPT-5.6-LUNA using Copilot CLI 1.0.83\Input\Firefox Source Code\garp\GarpSessionManager.sys.mjs" >> %OUT%
type "K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\NEXT GENERATION by GPT-5.6-LUNA using Copilot CLI 1.0.83\Input\Firefox Source Code\providers\ProviderAdapter.sys.mjs" >> %OUT%

echo Done.
