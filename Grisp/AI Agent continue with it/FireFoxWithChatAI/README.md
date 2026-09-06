# Firefox AI Automation

This repository provides a modified version of Firefox with a built-in AI automation service. It enables programmatic interaction with top AI chat services through a simple TCP-based Python console tool.

## Supported Sites

| Key | Site |
|-----|------|
| `gemini` | https://gemini.google.com/app |
| `grok` | https://grok.com/ |
| `chatgpt` | https://chatgpt.com/ |
| `copilot` | https://copilot.microsoft.com/ |
| `claude` | https://claude.ai/ |
| `perplexity` | https://www.perplexity.ai/ |
| `deepseek` | https://chat.deepseek.com/ |
| `inception` | https://chat.inceptionlabs.ai/ |

---

## 🚀 Setup & Installation

### 1. Clone the Firefox Source

Clone the official Firefox source repository (a sibling directory is recommended):

```bash
git clone --depth 1 https://github.com/mozilla-firefox/firefox L:\Firefox
```

### 2. Integrate AI Automation Logic

Copy the `ai_automation_logic` folder from this repository into the Firefox source tree:

```bash
mkdir L:\Firefox\browser\components\aistarter
xcopy /E /I L:\FireFoxWithChatAi\ai_automation_logic\* L:\Firefox\browser\components\aistarter\
```

### 3. Register the Component

You must register the new component in the Firefox build system.

Add the following entries to `L:\Firefox\browser\components\moz.build`:

```python
DIRS += [
    "aistarter",
]
```

And ensure `L:\Firefox\browser\components\aistarter\moz.build` (copied in Step 2) correctly exports the modules:

```python
# browser/components/aistarter/moz.build
EXTRA_JS_MODULES += [
    "AIAutomation.sys.mjs",
]

EXTRA_JS_MODULES.actors += [
    "actors/AIAutomationChild.sys.mjs",
    "actors/AIAutomationParent.sys.mjs",
]
```

### 4. Initialize the Service

The AI automation service must be initialized during Firefox startup.

In `L:\Firefox\browser\components\BrowserGlue.sys.mjs`, add the `AIAutomationService` getter and initialize it in the `_init()` method:

```javascript
// Near the top of the file, in defineESModuleGetters:
ChromeUtils.defineESModuleGetters(lazy, {
  // ... existing getters ...
  AIAutomationService: "resource:///modules/aistarter/AIAutomation.sys.mjs",
});

// Inside BrowserGlue.prototype._init:
_init: function BG__init() {
  // ... existing code ...
  this.aiAutomationService = new lazy.AIAutomationService();
  this.aiAutomationService.init();
},
```

### 5. Register the Actors

Register the JS actors so they can interact with the AI website content.

In `L:\Firefox\browser\components\DesktopActorRegistry.sys.mjs`, add the `AIAutomation` entry to the `JSWINDOWACTORS` object:

```javascript
let JSWINDOWACTORS = {
  // ... existing actors ...

  AIAutomation: {
    parent: {
      esModuleURI: "resource:///modules/aistarter/actors/AIAutomationParent.sys.mjs",
    },
    child: {
      esModuleURI: "resource:///modules/aistarter/actors/AIAutomationChild.sys.mjs",
    },
    allFrames: true,
  },
};
```

### 6. Build Firefox

Use the Mozilla build environment:

```bash
./mach build faster
./mach run
```

---

## ⚡ Quick Start

### AI Chat Prompting

Use the Python console to send prompts to specific AI sites:

```bash
python ai_console.py --site gemini --prompt "Hello Gemini!"
python ai_console.py --site grok --prompt "What is Rust?"
```

### Tab Management

The API allows you to manage browser tabs and re-use them for continuing chat sessions:

```bash
# List all open tabs with their indices and titles
python ai_console.py --list-tabs

# Open a new tab
python ai_console.py --open-url "https://google.com"

# Re-use an existing tab for a chat session (by index, title, or URL)
python ai_console.py --tab 0 --site gemini --prompt "Continue our chat"
python ai_console.py --tab "Gemini" --site gemini --prompt "Another message"

# Duplicate a tab
python ai_console.py --duplicate --tab 0

# Close a tab
python ai_console.py --close --tab "Google"
```

### Batch Scripts

Or use the pre-made test scripts:

```
TestGemini.bat
TestGrok.bat
TestChatGPT.bat
TestCopilot.bat
TestClaude.bat
TestDeepSeek.bat
TestInception.bat
TestPerplexity.bat
```

---

## 🏗️ Core Architecture

| Layer | File | Role |
|-------|------|------|
| **TCP Service** | `AIAutomation.sys.mjs` | Listens on port `9999`, receives JSON commands, opens tabs, polls for responses |
| **Content Actor** | `AIAutomationChild.sys.mjs` | Handles DOM injection and response scraping using site-specific CSS selectors |
| **Parent Actor** | `AIAutomationParent.sys.mjs` | Thin IPC bridge (queries resolved by the service) |

### Two-Phase Response Flow

1. **Ready-wait** — Parent polls `CheckReady` until the AI site's input box is visible
2. **Inject** — Child actor types the prompt and clicks Send, then returns immediately
3. **Response poll** — Parent re-polls `FetchResponse` on the new page (survives SPA navigation)

This design prevents the `Actor destroyed before query resolved` crash that occurs when AI sites (e.g. Gemini) navigate to a new conversation URL after submission.

---

## 🔧 Development

All automation logic lives in `ai_automation_logic/`. To apply changes:

1. Edit files in `ai_automation_logic/`
2. Copy them back to the Firefox source tree:
   ```bash
   xcopy /E /Y L:\FireFoxWithChatAi\ai_automation_logic\* L:\Firefox\browser\components\aistarter\
   ```
3. Run `./mach build faster` and restart Firefox

The `ai_automation_logic/` folder is kept in sync with `L:\Firefox\browser\components\aistarter\` after every change.



ADVANCED/UPDATED README:

# Firefox AI Automation + OpenAI Proxy

This repository contains related components that together enable programmatic interaction with web AI chat services using a modified Firefox build and optional proxy/console tools.

**There are four distinct components in this project:**
  1) **Firefox AI Automation** — a small Firefox integration (actors + parent service) that exposes an in‑browser TCP automation agent to programmatically drive AI chat sites (type, click, scrape, poll responses).
  2) **OpenAI Proxy Server** — an external HTTP REST server (Delphi) that accepts OpenAI‑style chat requests and forwards them as JSON commands to the Firefox automation agent, returning OpenAI‑compatible responses.
  3) **Delphi AI Console** — a native Delphi console tool for quick manual tests against the TCP agent or the proxy.
  4) **Python AI Console** — a Python TCP client and helper scripts used to send commands directly to the Firefox automation agent and to manage tabs/sessions.

--------------------------------------------------------------------------------
SUPPORTED SITES (keys)

  gemini     -> https://gemini.google.com/app
  grok       -> https://grok.com/
  chatgpt    -> https://chatgpt.com/
  copilot    -> https://copilot.microsoft.com/
  claude     -> https://claude.ai/
  perplexity -> https://www.perplexity.ai/
  deepseek   -> https://chat.deepseek.com/
  inception  -> https://chat.inceptionlabs.ai/

--------------------------------------------------------------------------------
QUICK ARCHITECTURE SUMMARY

Primary components (files inside Firefox tree)
  - `AIAutomation.sys.mjs`       : TCP service (default port 9999) that receives JSON commands and orchestrates tab actions.
  - `AIAutomationParent.sys.mjs` : Parent actor bridging the service and content actors.
  - `AIAutomationChild.sys.mjs`  : Content actor injected into pages to type, click, and scrape responses.

  - OpenAI Proxy               : REST server (default 127.0.0.1:8080) that translates OpenAI requests into agent commands.
  - Delphi AI Console          : native test client for Windows.
  - Python AI Console          : cross-platform test client and helper scripts.

Two-phase response flow:
  1) Parent polls CheckReady until the AI site's input box is visible.
  2) Child injects text and triggers send; returns immediately.
  3) Parent polls FetchResponse until the response completes or times out.

This prevents the "Actor destroyed before query resolved" crash when sites navigate after submission.

--------------------------------------------------------------------------------
SECTION 1 — FIREFOX INTEGRATION (what to change inside Firefox)

These steps modify Firefox itself. The proxy and consoles are external programs that talk to the agent over TCP.

1) Clone the Firefox source (example)
   - Recommended: keep Firefox source as a sibling directory to this repo.
   - Example:
     git clone --depth 1 https://github.com/mozilla-firefox/firefox L:\Firefox

2) Copy the automation logic into the Firefox tree
   - Copy the ai_automation_logic folder into the Firefox source tree under:
     browser/components/aistarter/
   - Example (Windows):
     mkdir L:\Firefox\browser\components\aistarter
     xcopy /E /I L:\FireFoxWithChatAi\ai_automation_logic\* L:\Firefox\browser\components\aistarter\

3) Register the component in the build
   - Edit L:\Firefox\browser\components\moz.build and add:
     DIRS += [
         "aistarter",
     ]
   - Ensure browser/components/aistarter/moz.build exports the modules:
     EXTRA_JS_MODULES += [
         "AIAutomation.sys.mjs",
     ]
     EXTRA_JS_MODULES.actors += [
         "actors/AIAutomationChild.sys.mjs",
         "actors/AIAutomationParent.sys.mjs",
     ]

4) Initialize the AIAutomation service at startup
   - Edit L:\Firefox\browser\components\BrowserGlue.sys.mjs.
   - Add the ES module getter inside defineESModuleGetters:
     AIAutomationService: "resource:///modules/aistarter/AIAutomation.sys.mjs",
   - Initialize in BrowserGlue.prototype._init:
     _init: function BG__init() {
       // ... existing code ...
       try {
         this.aiAutomationService = new lazy.AIAutomationService();
         this.aiAutomationService.init();
       } catch (ex) {
         Cu.reportError("AIAutomationService init failed: " + ex);
       }
       // ... existing code ...
     },
   - Notes:
     * Ensure the resource URI matches where you placed the module files.
     * Wrap init() in try/catch and log failures so startup errors are visible.
     * Call init() after BrowserGlue has created its core state.

5) Register the window actors
   - Edit L:\Firefox\browser\components\DesktopActorRegistry.sys.mjs.
   - Add the AIAutomation entry to JSWINDOWACTORS:
     AIAutomation: {
       parent: {
         esModuleURI: "resource:///modules/aistarter/actors/AIAutomationParent.sys.mjs",
       },
       child: {
         esModuleURI: "resource:///modules/aistarter/actors/AIAutomationChild.sys.mjs",
       },
       allFrames: true,
     },
   - Notes:
     * Confirm the actor files exist at the specified resource paths.
     * allFrames: true makes the child actor available in every frame (useful for SPA sites).
     * Keep the actor key name consistent with the service code that calls it.

6) Build and run Firefox
   - From the Firefox repo root:
     ./mach build faster
     ./mach run
   - On Windows PowerShell:
     .\mach build faster
     .\mach run

Verification checklist (Firefox integration)
  - Browser Console: search for AIAutomation logs or the Cu.reportError message.
  - TCP port listening: netstat -an | findstr 9999 (Windows) or ss -ltnp | grep 9999 (Linux).
  - Use ai_console.py or AIConsoleTool to send a ping or CheckReady command and confirm a JSON reply.

--------------------------------------------------------------------------------
SECTION 2 — OPENAI PROXY SERVER (Delphi, external program)

The OpenAI Proxy Server is a separate Delphi executable that accepts OpenAI‑style HTTP requests and forwards commands to the Firefox automation agent on TCP port 9999.

Default addresses
  - HTTP API (proxy):  http://127.0.0.1:8080
  - Automation agent: 127.0.0.1:9999 (TCP)

Main endpoints
  - POST /api/V1ChatCompletions
      Accepts OpenAI-style JSON:
        { "model":"deepseek-chat", "messages":[{"role":"user","content":"..."}] }
      Returns OpenAI-style completion JSON or structured error JSON.
  - GET /api/V1Models
      Returns supported model -> site mappings.
  - GET /api/V1Debug
      Returns current debug settings:
        { "enabled": <bool>, "level": <int>, "logfile": "<path>" }

Automation agent command format (TCP)
  - Example command sent to the agent:
      {"command":"prompt","site":"deepseek","text":"Hello","tab":-1}
  - Agent replies with JSON containing either "text" or "error". The proxy converts that into OpenAI-style "choices" or an error object.

Quick test commands (Windows-friendly)
  - PowerShell (recommended):
    $body = @{ model="deepseek-chat"; messages=@(@{ role="user"; content="Hello from PowerShell test" }) } | ConvertTo-Json
    Invoke-RestMethod -Uri "http://127.0.0.1:8080/api/V1ChatCompletions" -Method Post -ContentType "application/json" -Body $body

  - curl (single-line, cmd.exe):
    curl -s -X POST "http://127.0.0.1:8080/api/V1ChatCompletions" -H "Content-Type: application/json" -d "{\"model\":\"deepseek-chat\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello from curl test\"}]}"

  - curl using file (avoids escaping/BOM issues):
    1) Create request.json (UTF-8 without BOM):
       {"model":"deepseek-chat","messages":[{"role":"user","content":"Hello from file"}]}
    2) Send:
       curl -s -X POST "http://127.0.0.1:8080/api/V1ChatCompletions" -H "Content-Type: application/json" --data-binary @request.json

--------------------------------------------------------------------------------
SECTION 3 — DELPHI AI CONSOLE (component 3)

Purpose
  - A small Delphi console application that can connect directly to the Firefox automation agent (TCP) or to the OpenAI Proxy (HTTP) for quick manual tests and scripted checks.

Location (example)
  - F:\FireFoxWithChatAI\Delphi\AI Console\version 0.01\AIConsoleTool.dpr

Usage examples
  - Connect directly to agent:
    AIConsoleTool.exe --host 127.0.0.1 --port 9999 --prompt "Hello"
  - Connect via proxy:
    AIConsoleTool.exe --proxy http://127.0.0.1:8080 --model deepseek-chat --prompt "Hello"

Notes
  - Useful for Windows users who prefer a compiled native test tool.
  - Inspect the .dpr for command-line flags and example prompts.

--------------------------------------------------------------------------------
SECTION 4 — PYTHON AI CONSOLE (component 4)

Purpose
  - Python-based TCP client and helper scripts that send JSON commands directly to the Firefox automation agent. Also used for tab management and batch scripts.

Location (example)
  - ai_console.py at the repo root or tools/ folder.

Common commands
  - Send a prompt:
    python ai_console.py --site gemini --prompt "Hello Gemini!"
  - List tabs:
    python ai_console.py --list-tabs
  - Open URL:
    python ai_console.py --open-url "https://google.com"
  - Reuse tab:
    python ai_console.py --tab 0 --site gemini --prompt "Continue our chat"

Batch scripts (examples)
  - TestGemini.bat
  - TestGrok.bat
  - TestChatGPT.bat
  - TestCopilot.bat
  - TestClaude.bat
  - TestDeepSeek.bat
  - TestInception.bat
  - TestPerplexity.bat

--------------------------------------------------------------------------------
DELPHI FOLDER (OpenAI Proxy Server and AI Console) — quick reference

Paths (examples from the repo):
  F:\FireFoxWithChatAI\Delphi\AI Console\version 0.01\AIConsoleTool.dpr
  F:\FireFoxWithChatAI\Delphi\OpenAI Proxy Server\version 0.01\Unit_ProxyService.pas
  F:\FireFoxWithChatAI\Delphi\OpenAI Proxy Server\version 0.01\Unit_ProxyServiceImpl.pas
  F:\FireFoxWithChatAI\Delphi\OpenAI Proxy Server\version 0.01\OpenAIProxyServer.dpr
  ... (v0.02, v0.03, v0.04, v0.05 folders with updated units)

Which files and what they do (high level)
  - AIConsoleTool.dpr
      Delphi console test tool that connects to the TCP agent or proxy and sends prompts.

  - OpenAIProxyServer.dpr / OpenAIFirefoxProxyServer.dpr
      Application startup: reads settings, creates logger, instantiates REST server and proxy,
      and starts listening on the configured HTTP port. Contains graceful shutdown wiring.

  - Unit_ProxyService.pas
      REST interface declarations: V1ChatCompletions, V1Models, V1Debug endpoints.

  - Unit_ProxyServiceImpl.pas
      Implementation of REST endpoints. Reads raw request bytes (Ctxt.Call.InBody), validates JSON,
      calls proxy logic, and formats OpenAI-style responses. Good place to add diagnostic logging.

  - unit_OpenAIProxy.pas
      Core proxy logic: model→site mapping, message extraction, tab selection and caching,
      BuildFirefoxCommand(...) and error mapping from agent replies to OpenAI-style errors.

  - unit_OpenAIServer.pas
      REST server glue and HTTP handling (mORMot integration).

  - Unit_OpenAISettings.pas (v0.04+)
      Centralized runtime settings: HTTPPort, AgentHost, AgentPort, LogFile, DebugEnabled, DebugLevel, timeouts.

Which version to use
  - Prefer the latest stable folder (v0.04 or v0.05) because they include debugging improvements and shutdown fixes.

Build and run (Delphi)
  - Open the desired .dpr in Delphi (use the latest stable version folder).
  - Ensure required libraries are available (mORMot2, JSON, logging libs).
  - Build and run the proxy executable. The proxy will start the HTTP listener and forward commands to the automation agent.

Runtime configuration and edits
  - Change ports/hosts in Unit_OpenAISettings.pas or via command-line parsing in the .dpr.
  - Adjust LogFile, DebugEnabled, DebugLevel in Unit_OpenAISettings.pas.
  - Modify model→site mapping in unit_OpenAIProxy.pas to add or change supported sites.
  - Tune timeouts and retry logic in settings.

--------------------------------------------------------------------------------
mORMot2 COMPATIBILITY NOTE (exact commit)

The Delphi OpenAI Proxy Server and AI Console (versions v0.01 through v0.05) were developed and tested against the following exact mORMot2 repository state:

  https://github.com/synopse/mORMot2

  commit aef05e96dcd947c2dd0a82818c47a449f2ba99bd
  Author: Arnaud Bouchez <ab@synopse.info>
  Date:   Tue Sep 1 18:57:22 2026 +0200
  Message: net: some Tunnel logic fixes - especially for less used methods

Notes:
  - Pin mORMot2 to that exact commit when building the Delphi projects to reproduce the environment used during development and testing.
  - The proxy and console rely on mORMot2 networking/tunnel behavior and fixes present in that commit; using a different mORMot2 tip may introduce subtle differences in TCP/agent behavior or error handling.

--------------------------------------------------------------------------------
EXACT FIREFOX CHECKOUT USED DURING DEVELOPMENT

Include this snippet in the README so collaborators can verify they are building from the same tree.

  Microsoft Windows [Version 10.0.22631.6199]
  (c) Microsoft Corporation. All rights reserved.

  F:\Firefox>git log --graph --all
  * commit c100d1817308120604dd2d8fa8337a4714515a76 (HEAD -> Branch/ChatWithAI)
  | Author: Skybuck Flying <skybuck2000@hotmail.com>
  | Date:   Thu Apr 9 19:19:35 2026 +0200
  |
  |     Modifications for ChatWithAI
  |
  * commit 6c91f883b4a59faa6145f9bcf82e2b2acdad82d7 (grafted, origin/main, origin/HEAD, main)
    Author: Timothy Nikkel <tnikkel@gmail.com>
    Date:   Tue Apr 7 23:58:13 2026 +0000

        Bug 2029291. r=gfx-reviewers,lsalzman

        Differential Revision: https://phabricator.services.mozilla.com/D292370

  F:\Firefox>git remote
  origin

  F:\Firefox>git remote get-url origin
  https://github.com/mozilla-firefox/firefox

How to fetch and build this exact Firefox version
  - If you want to reproduce the exact Firefox tree used during development, run these steps
    from a shell with Git available. Replace paths with your local layout (example uses L:\Firefox or F:\Firefox).

  1) Clone the official Firefox repository (if you don't already have it)
     git clone https://github.com/mozilla-firefox/firefox L:\Firefox
     cd L:\Firefox

  2) Fetch all remote refs and tags
     git fetch --all --prune

  3) Create a pinned branch at the exact commit (safe, non-destructive)
     # create a named branch so you are not left in detached HEAD
     git fetch origin
     git checkout -b pinned-ChatWithAI-c100d18 c100d1817308120604dd2d8fa8337a4714515a76

     If the commit is not present locally after fetch, fetch it explicitly:
     git fetch origin c100d1817308120604dd2d8fa8337a4714515a76
     git checkout -b pinned-ChatWithAI-c100d18 FETCH_HEAD

  4) Confirm you are on the pinned branch and at the expected commit
     git rev-parse --short HEAD   # should print: c100d18
     git show -s --format="%H %an %ad %s" HEAD

  5) Build and run Firefox from this checkout
     ./mach build faster
     ./mach run
     (PowerShell: .\mach build faster ; .\mach run)

Notes and safety tips
  - Creating a pinned branch is recommended so you can switch back to other branches easily.
  - Do not use git reset --hard on shared branches unless you understand the consequences.
  - If you only want to inspect the tree without creating a branch, you can git checkout <commit> but that leaves you in a detached HEAD.

--------------------------------------------------------------------------------
DEBUGGING & RUNTIME CONTROLS

Log file
  - Default: openai_proxy.log (next to the proxy executable). Changeable at runtime.

Debug settings
  - DebugEnabled (bool) — toggle logging on/off.
  - DebugLevel (int) — 0=off, 1=error, 2=info, 3=verbose.
  - SetLogFile(path) — change log file path.
  - GET /api/V1Debug — read current debug settings.

Common errors and fixes
  - 400 "Request body is empty"
      * Client sent no body. On Windows prefer PowerShell or use --data-binary @file.
  - 400 "Invalid JSON request body"
      * Escaping issues or UTF-8 BOM. Use PowerShell ConvertTo-Json or file-based --data-binary.
  - "Firefox automation server returned an empty response"
      * Ensure the TCP agent is running on port 9999 and reachable; check firewall.
  - "firefox_automation_error"
      * Agent returned an error (sign-in required, selector mismatch). Inspect error.message and update selectors or sign-in state.

Temporary diagnostic logging to add
  - Log raw request length and first bytes in V1ChatCompletions to detect BOM or stray characters.
  - Log "Built Firefox command: <json>" before sending to the agent.
  - Log lifecycle events: "TOpenAIProxy.Shutdown start", "TOpenAIProxy.Destroy start", "TOpenAIRestServer.Destroy start".

Shutdown best practice
  - Stop HTTP server, call proxy Shutdown to terminate workers, wait for threads to exit, then free objects
    in the correct order to avoid double-free or destructor-time exceptions.

--------------------------------------------------------------------------------
BEST PRACTICES & TIPS

  - Keep the controlled Firefox profile signed in for long runs; re-auth flows break automation.
  - When site DOMs change, update site-specific CSS selectors in ai_automation_logic.
  - Use unique test tokens (e.g., TESTID-<timestamp>) in prompts to correlate proxy logs and agent logs.
  - Rotate logs for long-running servers and monitor disk usage.
  - Prefer PowerShell or file-based requests on Windows to avoid escaping and BOM issues.
  - Add small delays and retries in client harnesses for transient errors (exponential backoff).

--------------------------------------------------------------------------------

END
