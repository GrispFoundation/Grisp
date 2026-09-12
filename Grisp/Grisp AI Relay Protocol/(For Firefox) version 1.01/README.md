# Firefox AI Automation + GARP/1.01

This repository contains the Firefox-side implementation of the **GRISP AI Relay Protocol GARP/1.01**.

It is deliberately **Selenium-free**. Firefox itself is the browser automation substrate. The implementation uses Firefox chrome/parent code, JSWindowActors, and provider-specific adapters.

## Architecture

```text
GRISP / GARP client
        |
        | GARP/1.01 over localhost TCP
        v
Firefox AIAutomationService
        |
        +-- GarpConnection
        +-- AIAutomationSessionManager
        +-- GarpRequestManager
        +-- ProviderRegistry
        |
        v
AIAutomationParent
        |
        v
AIAutomationChild
        |
        +-- DeepSeekAdapter
        +-- GeminiAdapter
        +-- ChatGPTAdapter
        +-- ClaudeAdapter
        +-- GrokAdapter
        +-- CopilotAdapter
        +-- PerplexityAdapter
        +-- InceptionAdapter
        |
        v
AI provider website DOM
```

Firefox owns provider interaction and observation. GARP carries the browser/session/request state. GRISP remains responsible for interpreting and verifying AI output.

## Supported providers

| Key | Site |
|---|---|
| `gemini` | https://gemini.google.com/app |
| `grok` | https://grok.com/ |
| `chatgpt` | https://chatgpt.com/ |
| `copilot` | https://copilot.microsoft.com/ |
| `claude` | https://claude.ai/ |
| `perplexity` | https://www.perplexity.ai/ |
| `deepseek` | https://chat.deepseek.com/ |
| `inception` | https://chat.inceptionlabs.ai/ |

Provider adapters are isolated. A provider DOM change should normally require a change only to that provider adapter.

# 1. Requirements

This implementation is intended for a **source build of Firefox**.

On Windows, Mozilla's current build documentation recommends MozillaBuild and a supported Windows installation. The current guide lists 4 GB RAM minimum, 8 GB+ recommended, and at least 40 GB free disk space. The MozillaBuild shell is the supported traditional build environment. 

Official documentation:

- Firefox Windows build guide: https://firefox-source-docs.mozilla.org/setup/windows_build.html
- Firefox contributor quick reference: https://firefox-source-docs.mozilla.org/contributing/contribution_quickref.html
- MozillaBuild / Windows Mach notes: https://firefox-source-docs.mozilla.org/mach/windows-usage-outside-mozillabuild.html

# 2. Fresh Firefox checkout

Use a completely fresh clone for the first GARP/1.01 build.

From the **MozillaBuild shell**:

```bash
git clone https://github.com/mozilla-firefox/firefox L:/Firefox
cd L:/Firefox
```

Do not copy the old `ai_automation_logic` implementation into the tree. This GARP/1.01 package is intended to replace that architecture with the structured directory layout below.

# 3. Bootstrap Firefox

Run the Firefox bootstrap process from the Firefox tree:

```bash
./mach bootstrap
```

Follow the interactive choices. For this project, a normal desktop source build is the safest choice because the browser source is being modified.

The official Firefox documentation also supports the bootstrap.py workflow when starting from a new source directory.

# 4. Install GARP/1.01 into Firefox

The source package contains:

```text
browser/components/aistarter/
    AIAutomation.sys.mjs

    actors/
        AIAutomationChild.sys.mjs
        AIAutomationParent.sys.mjs

    garp/
        GarpConnection.sys.mjs
        GarpErrors.sys.mjs
        GarpFrame.sys.mjs
        GarpRegistry.sys.mjs

    sessions/
        AIAutomationSession.sys.mjs
        AIAutomationSessionManager.sys.mjs

    requests/
        GarpRequest.sys.mjs
        GarpRequestManager.sys.mjs

    providers/
        ProviderAdapter.sys.mjs
        ProviderRegistry.sys.mjs
        DeepSeekAdapter.sys.mjs
        GeminiAdapter.sys.mjs
        ChatGPTAdapter.sys.mjs
        ClaudeAdapter.sys.mjs
        GrokAdapter.sys.mjs
        CopilotAdapter.sys.mjs
        PerplexityAdapter.sys.mjs
        InceptionAdapter.sys.mjs

    diagnostics/
        AIAutomationDiagnostics.sys.mjs
```

Copy the supplied `browser/components/aistarter` directory into the Firefox source tree.

Example:

```text
xcopy /E /I /Y F:\GARP101_Firefox\browser\components\aistarter L:\Firefox\browser\components\aistarter
```

# 5. Register the component

Edit:

```text
L:\Firefox\browser\components\moz.build
```

Add `aistarter` to the `DIRS` list:

```python
DIRS += [
    "aistarter",
]
```

The supplied `browser/components/aistarter/moz.build` exports the GARP, session, request, provider, diagnostic, and actor modules to Firefox's module tree.

# 6. Start AIAutomationService during Firefox startup

Edit:

```text
L:\Firefox\browser\components\BrowserGlue.sys.mjs
```

Add the module getter in the existing `ChromeUtils.defineESModuleGetters(lazy, {...})` block:

```javascript
AIAutomationService: "resource:///modules/aistarter/AIAutomation.sys.mjs",
```

During `BrowserGlue.prototype._init`, instantiate the service:

```javascript
try {
  this.aiAutomationService = new lazy.AIAutomationService();
  this.aiAutomationService.init();
} catch (ex) {
  Cu.reportError("AIAutomationService init failed: " + ex);
}
```

Place this after the core browser state exists.

# 7. Register the JSWindowActors

Edit:

```text
L:\Firefox\browser\components\DesktopActorRegistry.sys.mjs
```

Inside the `JSWINDOWACTORS` registry add:

```javascript
AIAutomation: {
  parent: {
    esModuleURI: "resource:///modules/aistarter/actors/AIAutomationParent.sys.mjs",
  },
  child: {
    esModuleURI: "resource:///modules/aistarter/actors/AIAutomationChild.sys.mjs",
  },
  allFrames: true,
},
```

The actor name **must** remain `AIAutomation`, because the parent service requests:

```javascript
getActor("AIAutomation")
```

# 8. Optional authentication secret

GARP/1.01 requires authenticated localhost access by default.

The Firefox process looks for:

```text
GARP_SECRET
```

in its environment.

For development, if it is not present, Firefox creates a random startup secret. The current development implementation reports that secret through `dump()` so a local test client can retrieve it from the launched Firefox process.

For normal use, prefer setting an explicit secret in the Firefox launch environment rather than relying on the generated development secret.

Example in the MozillaBuild shell:

```bash
export GARP_SECRET="replace-with-a-random-high-entropy-secret"
```

Then launch Firefox from that same shell.

The secret is never exposed to page JavaScript or provider pages.

# 9. Build Firefox

From the Firefox root:

```bash
./mach build
```

Then run:

```bash
./mach run
```

For subsequent incremental changes, rerun `./mach build` and restart the local Firefox instance.

Mozilla's current documentation recommends `./mach build` for source builds. 

# 10. GARP port

The default listener is:

```text
127.0.0.1:9999
```

This is intentionally different from the future standalone Delphi GARP test application: Firefox is the GARP server and the Delphi test application will be a GARP client.

# 11. Wire protocol

GARP/1.01 uses a binary length-framed TCP protocol.

Fixed header:

```text
magic[4]          = GARP
version[1]        = 0x11 for GARP/1.01
flags[1]
header_length[2]
payload_length[4]
message_type[2]
reserved[2]       = 0
request_id[16]    = binary RFC 4122 UUID
session_id[16]    = binary RFC 4122 UUID
```

The fixed header is **48 bytes**.

The payload is UTF-8 JSON.

All integer fields are big-endian.

The JSON `protocol` value is:

```text
GARP/1.01
```

Newline characters are ordinary payload data and are not framing characters.

# 12. Handshake

The first logical message is `hello`.

Example:

```json
{
  "protocol": "GARP/1.01",
  "type": "hello",
  "payload": {
    "client_id": "GRISP-Agent-001",
    "client_version": "1.0.0",
    "nonce": "client-random-nonce"
  }
}
```

Firefox replies with `hello_challenge`, followed by an authenticated `hello_auth`, then the final `hello_ack`.

The authentication proof is HMAC-SHA256 over:

```text
GARP/1.01|client_id|client_nonce|server_nonce
```

The shared secret is never sent in the protocol.

# 13. First functional test

After starting the modified Firefox, confirm that the Firefox console contains something similar to:

```text
GARP/1.01: listening on 127.0.0.1:9999
```

Then sign in manually to one supported AI provider in the local Firefox profile.

The first external test client should perform this sequence:

```text
HELLO
HELLO_CHALLENGE
HELLO_AUTH
HELLO_ACK
CAPABILITIES
LIST_TABS
CREATE_SESSION
PROMPT
PROMPT_ACK
GENERATION_STARTED
INPUT_SUBMITTED
GENERATION_DELTA ...
GENERATION_COMPLETED
```

The separate Delphi GARP test application will implement this sequence in the next task.

# 14. Session behavior

A session has a stable `session_id`.

A tab has a stable `tab_id`.

Changing tab indexes does not change `tab_id`.

A JSWindowActor replacement does not change `session_id` or `tab_id`.

A significant navigation or actor replacement increments `page_generation`.

Only one active prompt is permitted per session by default.

A second simultaneous prompt receives:

```text
SESSION_BUSY
```

# 15. Provider adapter behavior

Provider-specific selectors live exclusively in `providers/`.

The generic child actor does not contain one giant provider selector table.

Each adapter is responsible for:

```text
discover input
inspect readiness
submit prompt
inspect generation
identify responses
detect continuation
continue generation
detect authentication
detect rate limits
detect provider errors
cancel generation
reset session
```

The initial adapter implementation preserves the selector strategies from the existing Firefox AI automation project.

# 16. Existing automation migration

The previous project had:

```text
AIAutomationService
AIAutomationConnection
AIAutomationUtils
AIAutomationChild
```

The GARP/1.01 implementation replaces the internal organization with:

```text
AIAutomationService
    |
    +-- GarpConnection
    +-- AIAutomationSessionManager
    +-- GarpRequestManager
    +-- ProviderRegistry
```

The two-phase navigation-safe design is preserved:

```text
parent
  |
  +-- acquire actor
  +-- child operation
  +-- actor disappears during SPA navigation
  +-- reacquire actor
  +-- continue session/request state
```

The old newline JSON commands are deliberately not used by the GARP path.

# 17. Important implementation boundary

The Firefox side does **not** decide whether AI output is a valid GRISP artifact.

The flow is:

```text
provider response
    |
    v
GARP/1.01
    |
    v
GAI/1.0
    |
    v
GRISP validation
    |
    v
artifact/evidence/state
```

Firefox must never silently change the semantic AI response while transporting it.

# 18. Troubleshooting

### Port 9999 already in use

Stop the previous local Firefox instance or identify the process holding the port.

### No GARP listener

Check that `BrowserGlue.sys.mjs` actually initializes `AIAutomationService` and that the module path resolves to:

```text
resource:///modules/aistarter/AIAutomation.sys.mjs
```

### Child actor unavailable

Verify the `AIAutomation` entry in `DesktopActorRegistry.sys.mjs` and verify the two actor modules were exported by `aistarter/moz.build`.

### Provider says AUTH_REQUIRED

Open that provider manually in the local Firefox profile and sign in. GARP does not automate credential entry.

### Provider DOM unsupported

The affected provider adapter needs an update. Do not add the selector to the generic child actor unless the selector is truly provider-independent.

### Build problems

Start with a clean Firefox source checkout and rerun the official bootstrap process. Mozilla notes that the source/build tree can consume substantial disk space and recommends antivirus exclusions for MozillaBuild, the Firefox source tree, and `.mozbuild` on Windows because security scanning can slow or interfere with builds.

# 19. Source-build references

Use Mozilla's current documentation rather than copying old toolchain versions from historical project instructions:

- https://firefox-source-docs.mozilla.org/setup/windows_build.html
- https://firefox-source-docs.mozilla.org/contributing/contribution_quickref.html
- https://firefox-source-docs.mozilla.org/mach/windows-usage-outside-mozillabuild.html

# 20. Status

This package is the **Firefox-side GARP/1.01 implementation task**.

It intentionally contains no Selenium dependency and no Delphi client.

The next separate task is the Delphi GARP conformance/test application that connects to `127.0.0.1:9999` and exercises the normative handshake, session lifecycle, prompt lifecycle, streaming, cancellation, duplicate suppression, sequence handling, and reconnection behavior.
