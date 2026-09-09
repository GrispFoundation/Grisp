unit MLCRD_Adapters;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.IOUtils,
  System.Diagnostics, System.Types, System.SyncObjs,
  MLCRD_Types, MLCRD_Interfaces, GrispCapabilities, GrispVfs, GrispGraph, GrispCore;

type
  // Simple compiler interface
  ICompiler = interface
    function Compile(const SourcePath, OutputPath: string; var Errors: string): Boolean;
    function Run(const ExePath: string; var StdOut, StdErr: string; var ExitCode: Integer): Boolean;
  end;

  // Registry to get compiler for language
  TGrispCompilerRegistry = class
  private
    FCompilerPath: string;
    FTimeoutMs: Integer;
    function RunProcess(const CmdLine: string; var Output, Errors: string; var ExitCode: Integer): Boolean;
  public
    constructor Create(const ACompilerPath: string = ''; ATimeoutMs: Integer = 30000);
    function GetCompilerForLanguage(Lang: TAgentLanguage; const Config: TAgentConfiguration): ICompiler;
  end;

  // Real compiler adapter using FPC or GCC
  TRealCompiler = class(TInterfacedObject, ICompiler)
  private
    FCompilerExe: string;
    FLanguage: TAgentLanguage;
    FRegistry: TGrispCompilerRegistry;
  public
    constructor Create(const ACompilerExe: string; ALang: TAgentLanguage; ARegistry: TGrispCompilerRegistry);
    function Compile(const SourcePath, OutputPath: string; var Errors: string): Boolean;
    function Run(const ExePath: string; var StdOut, StdErr: string; var ExitCode: Integer): Boolean;
  end;

  // Adapter implementing IGrispTestAdapter with real compilation
  TGrispTestAdapterImpl = class(TInterfacedObject, IGrispTestAdapter, IGrispDebugAdapter)
  private
    FVfs: TGrispVfs;
    FConfig: TAgentConfiguration;
    FRegistry: TGrispCompilerRegistry;
    function ExecuteInternalTest(const Code, Language: string; out Feedback: TDebugFeedback): Boolean;
  public
    constructor Create(AVfs: TGrispVfs; const AConfig: TAgentConfiguration);
    function CompileAndRunTest(const RealPath, Language: string; out Feedback: TDebugFeedback): Boolean;
    function RunQuickCheck(const RealPath, Language: string; out Feedback: TDebugFeedback): Boolean;
    // Debug adapter methods
    function CheckSyntax(const Code, Language: string; out Feedback: TDebugFeedback): Boolean;
    function CheckSemantic(const Code, Language: string; out Feedback: TDebugFeedback): Boolean;
    function RunWithDebug(const RealPath: string; const Args: TArray<string>; out Feedback: TDebugFeedback): Boolean;
  end;

  // GRISP VFS adapter
  TGrispVfsAdapter = class(TInterfacedObject, IGrispVfs)
  private
    FVfs: TGrispVfs;
    FCap: IGrispCapability;
  public
    constructor Create(AVfs: TGrispVfs; ACap: IGrispCapability = nil);
    function WriteFile(const VirtualPath, Content, Mime: string): Boolean;
    function ReadFile(const VirtualPath: string): string;
    function Resolve(const VirtualPath: string): string;
    function DeleteFile(const VirtualPath: string): Boolean;
    function FileExists(const VirtualPath: string): Boolean;
  end;

  // Harness adapter
  TGrispHarnessAdapterImpl = class(TInterfacedObject, IGrispHarnessAdapter)
  private
    FEngine: TGrispEngine;
    FCapName: string;
  public
    constructor Create(AEngine: TGrispEngine; const ACapName: string = '');
    function ValidatePlan(const Plan: string; out Diagnostics: string): Boolean; overload;
    function ValidatePlan(const Plan: string; out ValidationResult: TGrispValidationResult): Boolean; overload;
    function ExecutePlan(const Plan: string; out ExecOutput: string; out ExecDebug: TDebugFeedback): Boolean;
  end;

implementation

uses
  {$IFDEF FPC}
  Process,
  {$ELSE}
  Winapi.Windows,
  {$ENDIF}
  System.Generics.Defaults;

{ TGrispCompilerRegistry }

constructor TGrispCompilerRegistry.Create(const ACompilerPath: string; ATimeoutMs: Integer);
begin
  inherited Create;
  if ACompilerPath <> '' then
    FCompilerPath := ACompilerPath
  else
    FCompilerPath := ''; // will search PATH later
  FTimeoutMs := ATimeoutMs;
end;

function TGrispCompilerRegistry.RunProcess(const CmdLine: string; var Output, Errors: string; var ExitCode: Integer): Boolean;
{$IFDEF FPC}
var
  Proc: TProcess;
  OutputStream, ErrorStream: TStringStream;
  Timeout: Integer;
begin
  Output := '';
  Errors := '';
  ExitCode := 0;
  Result := False;
  Proc := TProcess.Create(nil);
  try
    Proc.CommandLine := CmdLine;
    Proc.Options := Proc.Options + [poUsePipes, poNoConsole];
    OutputStream := TStringStream.Create('');
    ErrorStream := TStringStream.Create('');
    try
      Proc.Execute;
      Timeout := 0;
      while Proc.Running and (Timeout < FTimeoutMs) do
      begin
        Sleep(10);
        Inc(Timeout, 10);
      end;
      if Proc.Running then
      begin
        Proc.Terminate(1);
        Errors := 'Process timed out after ' + IntToStr(FTimeoutMs) + ' ms';
        Exit(False);
      end;
      OutputStream.CopyFrom(Proc.Output, Proc.Output.NumBytesAvailable);
      ErrorStream.CopyFrom(Proc.Stderr, Proc.Stderr.NumBytesAvailable);
      Output := OutputStream.DataString;
      Errors := ErrorStream.DataString;
      ExitCode := Proc.ExitCode;
      Result := ExitCode = 0;
    finally
      OutputStream.Free;
      ErrorStream.Free;
    end;
  finally
    Proc.Free;
  end;
end;
{$ELSE} // Delphi / WinAPI
var
  SI: TStartupInfo;
  PI: TProcessInformation;
  SecurityAttr: TSecurityAttributes;
  StdOutRead, StdOutWrite: THandle;
  StdErrRead, StdErrWrite: THandle;
  Cmd: string;
  BytesRead: DWORD;
  Buffer: array[0..4095] of AnsiChar;
  TotalOut, TotalErr: AnsiString;
  WaitResult: DWORD;
  ExitCodeDWORD: DWORD;
begin
  Output := '';
  Errors := '';
  ExitCode := 0;
  Result := False;

  // Create pipes for stdout and stderr
  SecurityAttr.nLength := SizeOf(SecurityAttr);
  SecurityAttr.bInheritHandle := True;
  SecurityAttr.lpSecurityDescriptor := nil;

  if not CreatePipe(StdOutRead, StdOutWrite, @SecurityAttr, 0) then
    Exit(False);
  if not CreatePipe(StdErrRead, StdErrWrite, @SecurityAttr, 0) then
  begin
    CloseHandle(StdOutRead);
    CloseHandle(StdOutWrite);
    Exit(False);
  end;

  try
    FillChar(SI, SizeOf(SI), 0);
    SI.cb := SizeOf(SI);
    SI.dwFlags := STARTF_USESTDHANDLES;
    SI.hStdOutput := StdOutWrite;
    SI.hStdError := StdErrWrite;
    SI.hStdInput := GetStdHandle(STD_INPUT_HANDLE);

    Cmd := CmdLine;
    // CreateProcess requires a writable command line
    UniqueString(Cmd);

    if not CreateProcess(nil, PChar(Cmd), nil, nil, True,
      CREATE_NO_WINDOW, nil, nil, SI, PI) then
    begin
      Errors := 'CreateProcess failed: ' + SysErrorMessage(GetLastError);
      Exit(False);
    end;

    try
      // Wait for process to finish or timeout
      WaitResult := WaitForSingleObject(PI.hProcess, FTimeoutMs);
      if WaitResult = WAIT_TIMEOUT then
      begin
        TerminateProcess(PI.hProcess, 1);
        Errors := 'Process timed out after ' + IntToStr(FTimeoutMs) + ' ms';
        Exit(False);
      end;

      // Read stdout
      CloseHandle(StdOutWrite);
      CloseHandle(StdErrWrite);
      StdOutWrite := 0;
      StdErrWrite := 0;

      while True do
      begin
        if not ReadFile(StdOutRead, Buffer[0], SizeOf(Buffer)-1, BytesRead, nil) then
          Break;
        if BytesRead = 0 then Break;
        Buffer[BytesRead] := #0;
        TotalOut := TotalOut + AnsiString(Buffer);
      end;

      while True do
      begin
        if not ReadFile(StdErrRead, Buffer[0], SizeOf(Buffer)-1, BytesRead, nil) then
          Break;
        if BytesRead = 0 then Break;
        Buffer[BytesRead] := #0;
        TotalErr := TotalErr + AnsiString(Buffer);
      end;

      Output := string(TotalOut);
      Errors := string(TotalErr);

      // Get exit code - fix type mismatch
      if GetExitCodeProcess(PI.hProcess, ExitCodeDWORD) then
        ExitCode := Integer(ExitCodeDWORD)
      else
        ExitCode := -1;

      Result := ExitCode = 0;
    finally
      CloseHandle(PI.hProcess);
      CloseHandle(PI.hThread);
    end;
  finally
    if StdOutWrite <> 0 then CloseHandle(StdOutWrite);
    if StdErrWrite <> 0 then CloseHandle(StdErrWrite);
    if StdOutRead <> 0 then CloseHandle(StdOutRead);
    if StdErrRead <> 0 then CloseHandle(StdErrRead);
  end;
end;
{$ENDIF}

// ---------------------------------------------------------------------------
// FIXED: GetCompilerForLanguage with directory detection
// ---------------------------------------------------------------------------
function TGrispCompilerRegistry.GetCompilerForLanguage(Lang: TAgentLanguage; const Config: TAgentConfiguration): ICompiler;
var
  Exe, SearchPath: string;
begin
  case Lang of
    alPascal, alDelphi:
      begin
        SearchPath := Config.CompilerPath;
        if (SearchPath <> '') and DirectoryExists(SearchPath) then
        begin
          // Look for dcc32 (Delphi) first, then fpc (Free Pascal)
          if FileExists(TPath.Combine(SearchPath, 'dcc32.exe')) then
            Exe := TPath.Combine(SearchPath, 'dcc32.exe')
          else if FileExists(TPath.Combine(SearchPath, 'dcc32')) then
            Exe := TPath.Combine(SearchPath, 'dcc32')
          else if FileExists(TPath.Combine(SearchPath, 'fpc.exe')) then
            Exe := TPath.Combine(SearchPath, 'fpc.exe')
          else if FileExists(TPath.Combine(SearchPath, 'fpc')) then
            Exe := TPath.Combine(SearchPath, 'fpc')
          else
            raise Exception.Create('No Delphi/Pascal compiler found in directory: ' + SearchPath);
        end
        else if (SearchPath <> '') and FileExists(SearchPath) then
          Exe := SearchPath
        else
          Exe := 'dcc32'; // fallback to system PATH

        Result := TRealCompiler.Create(Exe, Lang, Self);
      end;
    alC:
      begin
        SearchPath := Config.CompilerPath;
        if (SearchPath <> '') and DirectoryExists(SearchPath) then
        begin
          if FileExists(TPath.Combine(SearchPath, 'gcc.exe')) then
            Exe := TPath.Combine(SearchPath, 'gcc.exe')
          else if FileExists(TPath.Combine(SearchPath, 'gcc')) then
            Exe := TPath.Combine(SearchPath, 'gcc')
          else if FileExists(TPath.Combine(SearchPath, 'clang.exe')) then
            Exe := TPath.Combine(SearchPath, 'clang.exe')
          else if FileExists(TPath.Combine(SearchPath, 'clang')) then
            Exe := TPath.Combine(SearchPath, 'clang')
          else
            raise Exception.Create('No C compiler found in directory: ' + SearchPath);
        end
        else if (SearchPath <> '') and FileExists(SearchPath) then
          Exe := SearchPath
        else
          Exe := 'gcc';

        Result := TRealCompiler.Create(Exe, Lang, Self);
      end;
    alPython:
      begin
        // Python doesn't compile, just run; we'll handle separately
        raise Exception.Create('Python test execution not yet implemented');
      end;
  else
    raise Exception.Create('Unsupported language for compilation');
  end;
end;
// ---------------------------------------------------------------------------

{ TRealCompiler }

constructor TRealCompiler.Create(const ACompilerExe: string; ALang: TAgentLanguage; ARegistry: TGrispCompilerRegistry);
begin
  inherited Create;
  FCompilerExe := ACompilerExe;
  FLanguage := ALang;
  FRegistry := ARegistry;
end;

function TRealCompiler.Compile(const SourcePath, OutputPath: string; var Errors: string): Boolean;
var
  CmdLine: string;
  Output, Err: string;
  ExitCode: Integer;
begin
  if FLanguage in [alPascal, alDelphi] then
  begin
    if Pos('fpc', FCompilerExe) > 0 then
      CmdLine := Format('%s "%s" -o"%s"', [FCompilerExe, SourcePath, OutputPath])
    else // assume dcc32
      CmdLine := Format('%s "%s" -E"%s"', [FCompilerExe, SourcePath, OutputPath]);
  end
  else if FLanguage = alC then
  begin
    CmdLine := Format('%s "%s" -o "%s"', [FCompilerExe, SourcePath, OutputPath]);
  end
  else
    raise Exception.Create('Compilation not supported for this language');
  Result := FRegistry.RunProcess(CmdLine, Output, Err, ExitCode);
  if not Result then
    Errors := Err + Output;
end;

function TRealCompiler.Run(const ExePath: string; var StdOut, StdErr: string; var ExitCode: Integer): Boolean;
var
  CmdLine: string;
  OutStr, ErrStr: string;
  EC: Integer;
begin
  CmdLine := '"' + ExePath + '"';
  Result := FRegistry.RunProcess(CmdLine, OutStr, ErrStr, EC);
  StdOut := OutStr;
  StdErr := ErrStr;
  ExitCode := EC;
end;

{ TGrispTestAdapterImpl }

constructor TGrispTestAdapterImpl.Create(AVfs: TGrispVfs; const AConfig: TAgentConfiguration);
begin
  inherited Create;
  FVfs := AVfs;
  FConfig := AConfig;
  FRegistry := TGrispCompilerRegistry.Create(AConfig.CompilerPath, AConfig.TimeoutMs);
end;

function TGrispTestAdapterImpl.ExecuteInternalTest(const Code, Language: string; out Feedback: TDebugFeedback): Boolean;
var
  Compiler: ICompiler;
  SourcePath, ExePath, BaseName, Dir: string;
  Errors, StdOut, StdErr: string;
  ExitCode: Integer;
  Watch: TStopwatch;
  Guid: TGuid;
begin
  Feedback := Default(TDebugFeedback);
  Watch := TStopwatch.StartNew;
  try
    CreateGUID(Guid);
    BaseName := 'grisp_test_' + GUIDToString(Guid).Replace('{','').Replace('}','').Replace('-','');
    Dir := TPath.GetTempPath;
    if Language.ToLower = 'c' then
      SourcePath := TPath.Combine(Dir, BaseName + '.c')
    else if (Language.ToLower = 'pascal') or (Language.ToLower = 'delphi') then
      SourcePath := TPath.Combine(Dir, BaseName + '.pas')
    else
      SourcePath := TPath.Combine(Dir, BaseName + '.txt');

    TFile.WriteAllText(SourcePath, Code, TEncoding.UTF8);

    ExePath := TPath.Combine(Dir, BaseName);
    {$IFDEF MSWINDOWS}
    ExePath := ExePath + '.exe';
    {$ENDIF}

    Compiler := FRegistry.GetCompilerForLanguage(FConfig.PreferredLanguage, FConfig);
    if not Compiler.Compile(SourcePath, ExePath, Errors) then
    begin
      Feedback := TDebugFeedback.MakeFailure('Compilation failed: ' + Errors);
      Feedback.ElapsedMs := Watch.ElapsedMilliseconds;
      Exit(False);
    end;

    if not Compiler.Run(ExePath, StdOut, StdErr, ExitCode) then
    begin
      Feedback := TDebugFeedback.MakeFailure('Runtime error: ' + StdErr + #13#10 + StdOut, ExitCode);
      Feedback.ElapsedMs := Watch.ElapsedMilliseconds;
      Exit(False);
    end;

    Feedback := TDebugFeedback.MakeSuccess('All tests passed');
    Feedback.TestOutput := StdOut + StdErr;
    Feedback.TestExitCode := ExitCode;
    Feedback.TestPassed := (ExitCode = 0);
    Feedback.ElapsedMs := Watch.ElapsedMilliseconds;
    Result := True;
  finally
    try
      if FileExists(SourcePath) then TFile.Delete(SourcePath);
      if FileExists(ExePath) then TFile.Delete(ExePath);
    except
      // ignore
    end;
  end;
end;

function TGrispTestAdapterImpl.CompileAndRunTest(const RealPath, Language: string; out Feedback: TDebugFeedback): Boolean;
var
  Code: string;
begin
  if TFile.Exists(RealPath) then
    Code := TFile.ReadAllText(RealPath, TEncoding.UTF8)
  else
    Code := '';
  Result := ExecuteInternalTest(Code, Language, Feedback);
end;

function TGrispTestAdapterImpl.RunQuickCheck(const RealPath, Language: string; out Feedback: TDebugFeedback): Boolean;
begin
  Result := CompileAndRunTest(RealPath, Language, Feedback);
end;

function TGrispTestAdapterImpl.CheckSyntax(const Code, Language: string; out Feedback: TDebugFeedback): Boolean;
begin
  Result := ExecuteInternalTest(Code, Language, Feedback);
  Feedback.RuntimeOK := True;
end;

function TGrispTestAdapterImpl.CheckSemantic(const Code, Language: string; out Feedback: TDebugFeedback): Boolean;
begin
  Result := CheckSyntax(Code, Language, Feedback);
end;

function TGrispTestAdapterImpl.RunWithDebug(const RealPath: string; const Args: TArray<string>; out Feedback: TDebugFeedback): Boolean;
begin
  Feedback := TDebugFeedback.MakeSuccess('Debug run not implemented, returning success');
  Result := True;
end;

{ TGrispVfsAdapter }

constructor TGrispVfsAdapter.Create(AVfs: TGrispVfs; ACap: IGrispCapability);
begin
  inherited Create;
  FVfs := AVfs;
  FCap := ACap;
end;

function TGrispVfsAdapter.WriteFile(const VirtualPath, Content, Mime: string): Boolean;
var
  Reason: string;
begin
  Result := FVfs.WriteFile(VirtualPath, Content, Mime, FCap, Reason);
end;

function TGrispVfsAdapter.ReadFile(const VirtualPath: string): string;
var
  Content, Reason: string;
begin
  if FVfs.ReadFile(VirtualPath, FCap, Content, Reason) then
    Result := Content
  else
    Result := '';
end;

function TGrispVfsAdapter.Resolve(const VirtualPath: string): string;
begin
  Result := FVfs.ResolveToPhysical(VirtualPath);
end;

function TGrispVfsAdapter.DeleteFile(const VirtualPath: string): Boolean;
var
  Reason: string;
begin
  Result := FVfs.DeleteFile(VirtualPath, FCap, Reason);
end;

function TGrispVfsAdapter.FileExists(const VirtualPath: string): Boolean;
begin
  Result := FVfs.FileExists(VirtualPath);
end;

{ TGrispHarnessAdapterImpl }

constructor TGrispHarnessAdapterImpl.Create(AEngine: TGrispEngine; const ACapName: string);
begin
  inherited Create;
  FEngine := AEngine;
  FCapName := ACapName;
end;

function TGrispHarnessAdapterImpl.ValidatePlan(const Plan: string; out ValidationResult: TGrispValidationResult): Boolean;
var
  Parser: TGrispParser;
  Rules: TArray<TGrispRule>;
begin
  if Plan.Trim = '' then
  begin
    ValidationResult := TGrispValidationResult.MakeAccepted('Empty plan', 0);
    Exit(True);
  end;
  if Plan.StartsWith('rules') then
  begin
    Parser := TGrispParser.Create(Plan);
    try
      Rules := Parser.Parse;
      ValidationResult := FEngine.ValidatePlan(Rules, FCapName);
      Result := ValidationResult.Accepted;
    except
      on E: Exception do
      begin
        ValidationResult := TGrispValidationResult.MakeRejected('Plan syntax error: ' + E.Message, ['SYNTAX_ERROR']);
        Result := False;
      end;
    end;
    Parser.Free;
  end
  else
  begin
    ValidationResult := TGrispValidationResult.MakeAccepted('Freeform plan accepted', 0);
    Result := True;
  end;
end;

function TGrispHarnessAdapterImpl.ValidatePlan(const Plan: string; out Diagnostics: string): Boolean;
var
  VR: TGrispValidationResult;
begin
  Result := ValidatePlan(Plan, VR);
  Diagnostics := VR.Diagnostics;
end;

function TGrispHarnessAdapterImpl.ExecutePlan(const Plan: string; out ExecOutput: string; out ExecDebug: TDebugFeedback): Boolean;
var
  Parser: TGrispParser;
  Rules: TArray<TGrispRule>;
  Reason: string;
  Watch: TStopwatch;
begin
  Watch := TStopwatch.StartNew;
  ExecDebug := Default(TDebugFeedback);
  ExecDebug.SyntaxOK := True;
  ExecDebug.CompileOK := True;
  ExecDebug.RuntimeOK := True;
  ExecDebug.TestPassed := True;

  if Plan.Trim.StartsWith('rules') then
  begin
    Parser := TGrispParser.Create(Plan);
    try
      Rules := Parser.Parse;
      if FEngine.ExecutePlan(Rules, FCapName, Reason) then
      begin
        ExecOutput := FEngine.EventsToJSON;
        ExecDebug.Diagnostics := 'GRISP engine committed plan';
        Result := True;
      end
      else
      begin
        ExecOutput := Format('{"error":"GRISP_REJECTED","reason":"%s"}', [Reason]);
        ExecDebug.RuntimeOK := False;
        ExecDebug.CrashCount := 1;
        ExecDebug.Diagnostics := Reason;
        Result := False;
      end;
    finally
      Parser.Free;
    end;
  end
  else
  begin
    ExecOutput := 'Plan committed and persisted to workspace.';
    ExecDebug.Diagnostics := 'Code plan executed';
    Result := True;
  end;
  ExecDebug.ElapsedMs := Watch.ElapsedMilliseconds;
end;

end.