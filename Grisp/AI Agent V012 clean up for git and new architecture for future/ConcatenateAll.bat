@echo off
setlocal

REM --- Output file ---
set OUT=combined.txt

REM --- Start fresh every run ---
if exist "%OUT%" del "%OUT%"

REM --- Concatenate all files in fixed order ---
type "Projects\GrispAgent\GrispAgentCLI.dpr" >> "%OUT%"
type "Source Code\Agent\MLCRD_Adapters.pas" >> "%OUT%"
type "Source Code\Agent\MLCRD_Algorithms.pas" >> "%OUT%"
type "Source Code\Agent\MLCRD_Coordinator.pas" >> "%OUT%"
type "Source Code\Agent\MLCRD_FirefoxPeer.pas" >> "%OUT%"
type "Source Code\Agent\MLCRD_Interfaces.pas" >> "%OUT%"
type "Source Code\Agent\MLCRD_Peers.pas" >> "%OUT%"
type "Source Code\Agent\MLCRD_Types.pas" >> "%OUT%"
type "Source Code\Agent\MLCRD_Utils.pas" >> "%OUT%"
type "Source Code\Core\GrispCapabilities.pas" >> "%OUT%"
type "Source Code\Core\GrispCore.pas" >> "%OUT%"
type "Source Code\Core\GrispGraph.pas" >> "%OUT%"
type "Source Code\Core\GrispVfs.pas" >> "%OUT%"

echo Combined file created: %OUT%
endlocal


pause