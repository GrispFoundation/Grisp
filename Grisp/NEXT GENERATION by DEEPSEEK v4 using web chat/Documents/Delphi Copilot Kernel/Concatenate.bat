@echo off
setlocal enabledelayedexpansion

REM === CONFIGURATION ===
set OUTFILE=GSDA_AllCombined.txt
set BASEDIR=K:\Delphi\Technology\Grisp\github version 0.18 cleanup\Grisp\NEXT GENERATION by DEEPSEEK v4 using web chat\Documents\Delphi Copilot Kernel

REM === CLEAR OUTPUT FILE ===
echo Creating structured GSDA concatenation...
echo. > "%OUTFILE%"

REM === FUNCTION TO APPEND A FILE WITH HEADER ===
for %%F in (
    "GSDACanonicalJson.pas"
    "GSDACoordinatorV2.pas"
    "GSDACoverage.pas"
    "GSDACoverageV2.pas"
    "GSDADemo.dpr"
    "GSDAEngineV2.pas"
    "GSDAEngineV2_TestHarness.dpr"
    "GSDAIdentity.pas"
    "GSDAIdentityFactory.pas"
    "GSDAIdentityProvenance.pas"
    "GSDAIdentityRegistry.pas"
    "GSDAIdentityTraceGraph.pas"
    "GSDAIdentityValidation.pas"
    "GSDAKernel.pas"
    "GSDAKernelV2.pas"
    "GSDAPeerAdapterV2.pas"
    "GSDAPeerConsolidationV2.pas"
    "GSDAPeerScoringV2.pas"
    "GSDAPublication.pas"
    "GSDAPublicationBundleV2.pas"
    "GSDAPublicationLineageIntegrationV2.pas"
    "GSDAPublicationV2.pas"
    "GSDARevisionLineageV2.pas"
    "GSDARoundOrchestrationV2.pas"
    "GSDASpecContentIDV2.pas"
    "GSDASpecDiffV2.pas"
    "GSDASystemOrchestrationV2.pas"
    "GSDATaskOrchestrationV2.pas"
    "GSDATraceability.pas"
    "GSDATraceabilityV2.pas"
    "GSDAVizV2.pas"
) do (
    echo ===== BEGIN FILE: %%F ===== >> "%OUTFILE%"
    type "%BASEDIR%\%%F" >> "%OUTFILE%"
    echo. >> "%OUTFILE%"
    echo ===== END FILE: %%F ===== >> "%OUTFILE%"
    echo. >> "%OUTFILE%"
)

echo Done.
echo Output written to %OUTFILE%

endlocal
