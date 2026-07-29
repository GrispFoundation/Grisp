program GrispCLI;

(*

===============================================================================
GRISP SYSTEM V3.1 – USER MANUAL
===============================================================================

Welcome to the Grisp system – a deterministic, layered execution environment
for AI‑assisted software engineering and autonomous agents. This manual
explains how to install, configure, and use the Grisp CLI tool.

1. SYSTEM OVERVIEW
------------------
Grisp transforms high‑level intent (SIR) into executable plans (EIR) through
a pipeline:

  SIR (Intent)  →  Planner (heuristic)  →  Evaluator (cost ranking)
  →  Validator (checks & CEIR expansion)  →  GRISP Executor (deterministic)
  →  LSBP bundles (persistent state)

The system supports two operation modes:
  • AUTO mode – the built‑in heuristic planner generates candidate plans.
  • MANUAL mode – the agent produces a prompt for an external LLM (e.g.,
    ChatGPT) and you paste the response back.

2. INSTALLATION
---------------
After extracting the source files, compile the project with Delphi or Free
Pascal. The main executable is GrispCLI.exe.

No additional libraries are required – all units are self‑contained.

3. COMMAND‑LINE USAGE
---------------------
  GrispCLI <SIR file> <Manifest directory> <WorldState file>

  • <SIR file>        – path to a text file containing the intent description
                        in marker‑based SIR format (see Section 4).
  • <Manifest directory> – folder containing tool manifest files (*.manifest).
  • <WorldState file> – JSON file that holds the persistent state; will be
                        created if it does not exist.

Example:
  GrispCLI my_goal.sir manifests\ worldstate.json

4. SIR FILE FORMAT (Semantic Intent Representation)
---------------------------------------------------
The SIR file uses marker‑based syntax with blocks. A minimal SIR document:

  ⟦BEGIN PROGRAM⟧
    ⟦BEGIN METADATA⟧
      author = "User"
      version = "1.0"
    ⟦END METADATA⟧

    ⟦BEGIN SEMANTIC MAP⟧
      ⟦BEGIN MAPPING⟧entity = "server room" : WorldState.zone_1_temp⟦END MAPPING⟧
      ⟦BEGIN MAPPING⟧action = "cool down" : CoolingSystem.set_speed⟦END MAPPING⟧
      ⟦BEGIN MAPPING⟧constraint = "max power" : 2000⟦END MAPPING⟧
    ⟦END SEMANTIC MAP⟧

    ⟦BEGIN GOAL⟧
      cool down the server room to 38 degrees within 5 minutes
    ⟦END GOAL⟧

    ⟦BEGIN CONSTRAINT⟧
      max power must not be exceeded
    ⟦END CONSTRAINT⟧
  ⟦END PROGRAM⟧

The SEMANTIC MAP is crucial: it tells the Planner how to ground natural
language phrases to actual system identifiers (WorldState variables, tool
actions, and numeric constants). If a term is missing, the Planner fails
with error P004.

5. TOOL MANIFESTS
-----------------
Each external tool must be described by a manifest file (extension .manifest)
placed in the Manifest directory. The manifest defines capabilities,
arguments, costs, side effects, and policies.

Example: CoolingSystem.manifest

  ⟦BEGIN TOOL MANIFEST⟧
    ⟦BEGIN NAME⟧CoolingSystem⟦END NAME⟧
    ⟦BEGIN VERSION⟧1.0⟦END VERSION⟧
    ⟦BEGIN DESCRIPTION⟧Industrial cooling fan controller⟦END DESCRIPTION⟧
    ⟦BEGIN CAPABILITIES⟧
      ⟦BEGIN CAPABILITY⟧set_speed⟦END CAPABILITY⟧
    ⟦END CAPABILITIES⟧
    ⟦BEGIN ACTIONS⟧
      ⟦BEGIN ACTION⟧
        ⟦BEGIN ACTION NAME⟧set_speed⟦END ACTION NAME⟧
        ⟦BEGIN ARGUMENTS⟧
          ⟦BEGIN ARGUMENT⟧
            ⟦BEGIN NAME⟧speed⟦END NAME⟧
            ⟦BEGIN TYPE⟧integer⟦END TYPE⟧
            ⟦BEGIN MIN⟧0⟦END MIN⟧
            ⟦BEGIN MAX⟧100⟦END MAX⟧
            ⟦BEGIN REQUIRED⟧true⟦END REQUIRED⟧
          ⟦END ARGUMENT⟧
        ⟦END ARGUMENTS⟧
        ⟦BEGIN RETURNS⟧
          ⟦BEGIN TYPE⟧string⟦END TYPE⟧
        ⟦END RETURNS⟧
        ⟦BEGIN SIDE EFFECTS⟧
          ⟦BEGIN EFFECT⟧state_change⟦END EFFECT⟧
        ⟦END SIDE EFFECTS⟧
        ⟦BEGIN IDEMPOTENT⟧false⟦END IDEMPOTENT⟧
        ⟦BEGIN COST EXPRESSION⟧50 + (speed / 10)⟦END COST EXPRESSION⟧
        ⟦BEGIN TIMEOUT MS⟧1000⟦END TIMEOUT MS⟧
        ⟦BEGIN RETRY POLICY⟧
          ⟦BEGIN MAX ATTEMPTS⟧3⟦END MAX ATTEMPTS⟧
          ⟦BEGIN DELAY MS⟧200⟦END DELAY MS⟧
        ⟦END RETRY POLICY⟧
        ⟦BEGIN PERMISSIONS⟧
          ⟦BEGIN PERMISSION⟧cooling_control⟦END PERMISSION⟧
        ⟦END PERMISSIONS⟧
        ⟦BEGIN PRECONDITIONS⟧
          ⟦BEGIN PRECONDITION⟧power_available⟦END PRECONDITION⟧
        ⟦END PRECONDITIONS⟧
        ⟦BEGIN POSTCONDITIONS⟧
          ⟦BEGIN POSTCONDITION⟧fan_speed == speed⟦END POSTCONDITION⟧
        ⟦END POSTCONDITIONS⟧
        ⟦BEGIN BUNDLE STRATEGY⟧lazy⟦END BUNDLE STRATEGY⟧
      ⟦END ACTION⟧
    ⟦END ACTIONS⟧
  ⟦END TOOL MANIFEST⟧

Notes:
  • COST EXPRESSION is evaluated dynamically against the WorldState.
  • BUNDLE STRATEGY can be "immediate", "lazy", or "never".
  • PRECONDITIONS are checked during validation and again at runtime.

6. WORLDSTATE FILE
------------------
The WorldState is a JSON file that persists variable bindings, facts, tool
outputs, graph snapshots, and history. Initially it can be empty or contain
initial values:

  {
    "version": 0,
    "variables": {
      "power_available": "true",
      "current_temp": "42"
    },
    "facts": [],
    "tool_outputs": {},
    "graph_nodes": [],
    "bundles": [],
    "plan_history": []
  }

The system updates this file after each execution.

7. RUNNING THE AGENT
--------------------
When you launch GrispCLI, you will be prompted:

  Run in auto mode? (y/n):

  • AUTO mode (y) – the built‑in Planner generates three candidate plans,
    the Evaluator ranks them by dynamic cost (primary), confidence, and
    risk, and the best plan is executed automatically.

  • MANUAL mode (n) – the agent prints a prompt that you can copy and paste
    into an external LLM. The prompt includes the SIR, current WorldState,
    and available tools. You then paste the LLM's CEIR response back into
    the terminal (ending with a line containing "END"). The agent then
    validates and executes that plan.

This manual mode allows you to use state‑of‑the‑art language models even
without direct API integration.

8. UNDERSTANDING THE OUTPUT
---------------------------
During execution, the system emits deterministic JSON events, such as:

  {"event":"assignment","payload":"current_temp = 42"}
  {"event":"tool_call","payload":"CoolingSystem.set_speed(speed=70)"}
  {"event":"lsbp_bundle_lazy","payload":"... bundle text ..."}

These events allow you to trace every operation and verify determinism.

9. CEIR (Compact EIR)
---------------------
The Planner and the external LLM output a compact form of EIR that uses
shorthand macros like ⟦SET⟧, ⟦WHILE⟧, ⟦IF⟧, ⟦CALL⟧. The Validator expands
these into the full canonical 32‑block EIR before execution. This saves
tokens and makes it easier for the LLM to generate valid plans.

10. ERROR HANDLING
------------------
If validation fails, the system prints an error code (V001‑V015) and a
message, then halts. Common errors:

  V001 – Syntax error in EIR (check marker balance).
  V002 – Undefined variable (declare all variables in VARIABLE blocks).
  V004 – Missing tool argument (check required arguments).
  V010 – Precondition failed (ensure WorldState has the required values).
  P004 – Unmapped semantic term (add a mapping in SEMANTIC MAP).

11. BEST PRACTICES
------------------
• Always include a SEMANTIC MAP with clear mappings for all entities and
  actions used in your GOAL and CONSTRAINT blocks.
• Keep tool manifests up‑to‑date – they are the contract between the system
  and the external environment.
• Use "lazy" BUNDLE STRATEGY for most filesystem operations to reduce I/O.
• Test your SIR with auto mode first; if the built‑in Planner produces a
  satisfactory plan, you can rely on it.
• For complex goals, use manual mode and an advanced LLM to generate the
  CEIR plan, then let Grisp validate and execute it deterministically.

12. EXAMPLE SESSION
-------------------
  > GrispCLI cool.sir manifests\ worldstate.json
  Run in auto mode? (y/n): n

  Copy the following prompt and paste it into your LLM:
  ----------------------------------------
  You are an AI planner. Given ... (long prompt)
  ----------------------------------------
  Paste the LLM response (CEIR) below (end with "END"):
  ⟦BEGIN PROGRAM⟧
    ⟦SET current_temp = 0⟧
    ⟦WHILE current_temp > 38 DO⟧
      ⟦CALL Hardware.read_sensor(sensor_id = "sensor_01") INTO current_temp⟧
      ⟦IF current_temp > 42 THEN⟧
        ⟦SET fan_speed = 100⟧
      ⟦ELSE IF current_temp > 40 THEN⟧
        ⟦SET fan_speed = 70⟧
      ⟦ELSE⟧
        ⟦SET fan_speed = 40⟧
      ⟦END IF⟧
      ⟦CALL CoolingSystem.set_speed(speed = fan_speed)⟧
      ⟦CALL Clock.sleep(duration = 30)⟧
    ⟦END WHILE⟧
  ⟦END PROGRAM⟧
  END

  Validation passed. Canonical EIR generated.
  {"event":"assignment","payload":"current_temp = 0"}
  {"event":"loop_start","payload":""}
  {"event":"loop_iteration","payload":"1"}
  ...

  WorldState saved.

13. FURTHER READING
-------------------
Refer to the full specification document (Specification_v3.1.txt) for the
complete formal definitions, normative invariants, and API details.

===============================================================================
End of manual
===============================================================================


*)


{$APPTYPE CONSOLE}

uses
  SysUtils,
  GrispAgent in '..\Source Code\GrispAgent.pas',
  GrispCEIRExpander in '..\Source Code\GrispCEIRExpander.pas',
  GrispEIR in '..\Source Code\GrispEIR.pas',
  GrispEvaluator in '..\Source Code\GrispEvaluator.pas',
  GrispExecutor in '..\Source Code\GrispExecutor.pas',
  GrispLSBP in '..\Source Code\GrispLSBP.pas',
  GrispMarkerLexer in '..\Source Code\GrispMarkerLexer.pas',
  GrispMarkerParser in '..\Source Code\GrispMarkerParser.pas',
  GrispPlanner in '..\Source Code\GrispPlanner.pas',
  GrispSIR in '..\Source Code\GrispSIR.pas',
  GrispToolManifest in '..\Source Code\GrispToolManifest.pas',
  GrispValidator in '..\Source Code\GrispValidator.pas',
  GrispWorldState in '..\Source Code\GrispWorldState.pas';

var
  Agent: TGrispAgent;
  SIRFile, ManifestDir, WorldFile: string;
begin
  if ParamCount < 3 then
  begin
    Writeln('Usage: GrispCLI <SIR file> <Manifest directory> <WorldState file>');
    Halt(1);
  end;
  SIRFile := ParamStr(1);
  ManifestDir := ParamStr(2);
  WorldFile := ParamStr(3);
  Agent := TGrispAgent.Create;
  try
    Agent.Run(SIRFile, ManifestDir, WorldFile);
  finally
    Agent.Free;
  end;
end.