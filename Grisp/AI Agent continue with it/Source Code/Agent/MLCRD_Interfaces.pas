unit MLCRD_Interfaces;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  MLCRD_Types;

type
  // Interface for web-based or local LLM peer
  IWebLLMPeer = interface
    ['{A1B2C3D4-0000-0000-0000-000000000001}']
    function GetName: string;
    function GenerateCandidate(const UserPrompt: string): TCandidate;
    function CritiqueCandidate(const UserPrompt: string; const Candidate: TCandidate): TCritique;
    function RepairCandidate(const UserPrompt: string; const Candidate: TCandidate; const Critiques: TArray<TCritique>): TRepair;
    function RequestCapabilities(const UserPrompt: string; const Repairs: TArray<TRepair>): TArray<TCapabilityRequest>;
    function ProposeTestProgram(const UserPrompt: string; const Repair: TRepair): TTestProgram;
    function ScoreRepairs(const UserPrompt: string; const Candidates: TArray<TCandidate>;
      const Repairs: TArray<TRepair>; const Debugs: TArray<TDebugFeedback>): TArray<TScore>;
  end;

  // GRISP Virtual File System interface
  IGrispVfs = interface
    ['{A1B2C3D4-0000-0000-0000-000000000002}']
    function WriteFile(const VirtualPath, Content, Mime: string): Boolean;
    function ReadFile(const VirtualPath: string): string;
    function Resolve(const VirtualPath: string): string;
    function DeleteFile(const VirtualPath: string): Boolean;
    function FileExists(const VirtualPath: string): Boolean;
  end;

  // Test compilation and execution adapter behind GRISP
  IGrispTestAdapter = interface
    ['{A1B2C3D4-0000-0000-0000-000000000003}']
    function CompileAndRunTest(const RealPath, Language: string; out Feedback: TDebugFeedback): Boolean;
    function RunQuickCheck(const RealPath, Language: string; out Feedback: TDebugFeedback): Boolean;
  end;

  // Debug adapter for syntax, semantic/LSP diagnostics, and runtime traces
  IGrispDebugAdapter = interface
    ['{A1B2C3D4-0000-0000-0000-000000000005}']
    function CheckSyntax(const Code, Language: string; out Feedback: TDebugFeedback): Boolean;
    function CheckSemantic(const Code, Language: string; out Feedback: TDebugFeedback): Boolean;
    function RunWithDebug(const RealPath: string; const Args: TArray<string>; out Feedback: TDebugFeedback): Boolean;
  end;

  // GRISP plan validation and execution harness
  IGrispHarnessAdapter = interface
    ['{A1B2C3D4-0000-0000-0000-000000000004}']
    function ValidatePlan(const Plan: string; out Diagnostics: string): Boolean;
    function ExecutePlan(const Plan: string; out ExecOutput: string; out ExecDebug: TDebugFeedback): Boolean;
  end;

implementation

end.
