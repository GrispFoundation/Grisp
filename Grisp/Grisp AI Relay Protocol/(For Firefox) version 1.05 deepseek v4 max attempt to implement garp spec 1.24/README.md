# Firefox AI Automation + GARP/1.24

This repository contains the Firefox-side implementation of the **Gateway AI Runtime Protocol GARP/1.24**.

It is deliberately **Selenium-free**. Firefox itself is the browser automation substrate. The implementation uses Firefox chrome/parent code, JSWindowActors, and provider-specific adapters.

The protocol contract implemented here is the normative document **GARP/1.24** (`Gateway AI Runtime Protocol`, wire version `0x00`). Section references in this README (`§…`) refer to that specification.

## Architecture

```text
GRISP / GARP client
        |
        | GARP/1.24 over localhost TCP
        v
Firefox AIAutomationService
        |
        +-- GarpConnection          (framing + connection state)
        +-- GarpAuth                (transcript HMAC, feature negotiation)
        +-- AIAutomationSessionManager
        +-- GarpRequestManager      (prompt lifecycle + terminal state)
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

Provider adapters are isolated. A provider DOM change should normally require a change only to that provider adapter. See §119 and §167.

# 1. Requirements

This implementation is intended for a **source build of Firefox**.

On Windows, Mozilla's current build documentation recommends MozillaBuild and a supported Windows installation. The current guide lists 4 GB RAM minimum, 8 GB+ recommended, and at least 40 GB free disk space. The MozillaBuild shell is the supported traditional build environment.

Official documentation:

- Firefox Windows build guide: https://firefox-source-docs.mozilla.org/setup/windows_build.html
- Firefox contributor quick reference: https://firefox-source-docs.mozilla.org/contributing/contribution_quickref.html
- MozillaBuild / Windows Mach notes: https://firefox-source-docs.mozilla.org/mach/windows-usage-outside-mozillabuild.html

# 2. Fresh Firefox checkout

Use a completely fresh clone for the first GARP/1.24 build.

From the **MozillaBuild shell**:

```bash
git clone https://github.com/mozilla-firefox/firefox L:/Firefox
cd L:/Firefox
```

Do not copy any prior `ai_automation_logic` implementation into the tree. This GARP/1.24 package replaces that architecture with the structured directory layout below.

# 3. Bootstrap Firefox

Run the Firefox bootstrap process from the Firefox tree:

```bash
./mach bootstrap
```

Follow the interactive choices. For this project, a normal desktop source build is the safest choice because the browser source is being modified.

The official Firefox documentation also supports the `bootstrap.py` workflow when starting from a new source directory.

# 4. Install GARP/1.24 into Firefox

The source package contains:

```text
browser/components/aistarter/
    AIAutomation.sys.mjs

    actors/
        AIAutomationChild.sys.mjs
        AIAutomationParent.sys.mjs

    garp/
        GarpAuth.sys.mjs            (NEW: transcript + proof)
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
xcopy /E /I /Y F:\GARP124_Firefox\browser\components\aistarter L:\Firefox\browser\components\aistarter
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
  safeForUntrustedWebProcess: true,
},
```

The actor name **must** remain `AIAutomation`, because the parent service requests:

```javascript
getActor("AIAutomation")
```

# 8. Shared secret and replay protection

GARP/1.24 requires mutual challenge-response authentication using a deployment-provisioned shared secret (§16). The secret MUST contain at least **32 raw bytes** (§16.2).

The Firefox process looks for:

```text
GARP_SECRET
```

in its environment and interprets the value as raw UTF-8 bytes. If the encoded value is shorter than 32 bytes, service initialization fails.

Example in the MozillaBuild shell:

```bash
export GARP_SECRET="replace-with-a-random-high-entropy-32-byte-secret"
```

Then launch Firefox from that same shell.

If `GARP_SECRET` is not present, the Firefox process generates a random 32-byte development secret and emits it once via `dump()` as unpadded Base64URL so a local test client can retrieve it from the launched Firefox process:

```text
GARP/1.24: generated startup secret (base64url) = <value>
```

For normal use, prefer setting an explicit secret rather than relying on the generated development secret. The secret is never exposed to page JavaScript or provider pages.

### Replay protection (§19)

GARP/1.24 requires that authentication replay protection survive gateway process restarts for at least 24 hours (§19). **The current development build keeps the replay-protection store in memory only.** A production conformance build MUST persist this store durably, and if the replay state cannot be re-established, the affected shared secret MUST be disabled and rotated (§19.1). This limitation is documented rather than silently ignored.

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

# 10. GARP port

The default listener is:

```text
127.0.0.1:9999
```

Firefox is the GARP server. A Delphi (or other) test application is the GARP client.

Per §4.3, the gateway binds only to loopback. It does not expose an unauthenticated GARP listener on a non-loopback interface.

# 11. Wire protocol

GARP/1.24 uses a binary length-framed TCP protocol (§4, §6). Every frame consists of a fixed 48-byte header followed by the frame payload.

```text
Offset   Size   Field
-------  -----  ----------------------
0        4      magic                = GARP  (47 41 52 50)
4        1      wire_version         = 0x00
5        1      flags                = 0x00 (base GARP)
6        2      header_len           = 48   (00 30)
8        4      payload_len          (big-endian uint32)
12       2      message_type         (big-endian uint16)
14       2      reserved             = 0x0000
16       16     request_uuid         (raw RFC 4122 bytes, or nil)
32       16     session_uuid         (raw RFC 4122 bytes, or nil)
48       N      payload              (UTF-8 JSON Common Envelope)
```

All multibyte integer fields are big-endian (§5). The fixed header is **48 bytes** and `header_len` MUST be exactly `48` (§6.4).

The frame payload is a UTF-8 JSON **Common Envelope** (§11):

```json
{
  "garp": "1.24",
  "type": "MESSAGE_TYPE",
  "request_id": null,
  "session_id": null,
  "timestamp": "2026-01-01T00:00:00.000Z",
  "sequence": null,
  "payload": {}
}
```

Key rules:

- `garp` is the semantic version string, `"1.24"` (§11.2).
- `type` is the ASCII uppercase registry name (§11.3).
- `request_id` and `session_id` are always present; JSON `null` corresponds to the all-zero nil UUID in the binary header (§7.2).
- `sequence` is always present as either a uint64-string or `null` (§11.7).
- All base GARP message and payload objects are **closed** unless explicitly declared open (§9.3). Unknown members MUST cause `INVALID_ARGUMENT`.
- Duplicate JSON object member names MUST be rejected (§9.2).
- All `uint64` fields are encoded as decimal strings matching `^(0|[1-9][0-9]{0,19})$` (§10.1). JavaScript number precision MUST NOT be relied upon for these values.

Two payload length limits exist and MUST NOT be conflated (§6.5, §23):

- **Handshake limit:** `1048576` bytes (1 MiB), applies until the receiver has itself received and validated the peer's `CAPABILITIES`.
- **Application limit:** `min(advertised_max_payload_bytes, 4294967295)`, applies after that point.

# 12. Message registry

The base GARP/1.24 message registry is defined in §13.1. The message codes this implementation uses are:

```text
0x0001 HELLO               0x0030 PROMPT
0x0002 HELLO_CHALLENGE     0x0031 CANCEL_PROMPT
0x0003 HELLO_AUTH          0x0032 GET_PROMPT_STATUS
0x0004 HELLO_ACK           0x0033 GET_RESPONSE
0x0005 RESPONSE            0x0034 SUBSCRIBE_RESPONSE
0x0006 ERROR               0x0035 CONTINUE_PROMPT

0x0010 CAPABILITIES        0x0040 SESSION_READY
0x0011 BROWSER_STATUS      0x0041 SESSION_CHANGED
0x0012 LIST_TABS           0x0042 NAVIGATION
0x0013 OPEN_TAB            0x0043 NAVIGATION_DRIFT
0x0014 CLOSE_TAB           0x0044 RECOVERY_STATE
0x0015 SELECT_TAB          0x0045 PROVIDER_CHANGED
0x0016 GET_CAPABILITIES
                           0x0050 INPUT_SUBMITTED
0x0020 CREATE_SESSION      0x0051 GENERATION_STARTED
0x0021 ATTACH_SESSION      0x0052 GENERATION_DELTA
0x0022 DETACH_SESSION      0x0053 GENERATION_PROGRESS
0x0023 CLOSE_SESSION       0x0054 CONTINUATION_REQUIRED
0x0024 RESET_SESSION       0x0055 CONTINUATION_SUBMITTED
0x0025 GET_SESSION         0x0056 GENERATION_COMPLETED
                           0x0057 GENERATION_FAILED
                           0x0058 GENERATION_CANCELLED

                           0x0060 PROVIDER_ERROR
                           0x0061 PROVIDER_AUTH_REQUIRED
                           0x0062 PROVIDER_RATE_LIMITED
                           0x0063 DIAGNOSTIC

                           0x0070 PING
                           0x0071 PONG

ext-replay-store:
                           0x0100 GET_EVENTS
```

Extension message codes MUST be allocated outside the base registry (§13.2).

# 13. Handshake

The handshake is mutual and follows §16–§17:

```text
CLIENT -> HELLO            (client_nonce, versions, wire_versions, features)
SERVER -> HELLO_CHALLENGE  (server_nonce, selected_version, wire_version, features)
CLIENT -> HELLO_AUTH       (client_proof)
SERVER -> HELLO_ACK        (server_proof, selected_version, wire_version, features)
SERVER -> CAPABILITIES
SERVER -> BROWSER_STATUS
```

### Nonces

Both `client_nonce` and `server_nonce` MUST decode to exactly **16 raw bytes** and are represented in JSON as **unpadded Base64URL**. Padding characters MUST be rejected (§16.4, §16.5).

### Authentication transcript (§16.6)

The proof transcript contains, in this exact order:

```text
domain
client_nonce
server_nonce
selected_semantic_version
selected_wire_version
offered_feature_set
final_feature_set
client_name
client_version
server_name
server_version
```

Every field is encoded as `u32be(byte_length) || raw_bytes`. Feature lists are encoded as:

```text
u32be(feature_count)
repeat: u32be(feature_byte_length) || feature_utf8_bytes
```

The proof is `HMAC-SHA256(shared_secret, transcript)`, exactly 32 raw bytes, represented in JSON as unpadded Base64URL. Comparison MUST be constant-time (§16.7).

Domains:

- Client-to-server proof: `GARP/1.24/client-proof`
- Server-to-client proof: `GARP/1.24/server-proof`

Both the *offered* feature set and the *final negotiated* feature set are cryptographically bound into the transcript, so the required-feature marker (`!`) cannot be silently stripped (§16.9).

### Feature negotiation (§15, §138)

Feature names MUST match:

```text
^[a-z0-9][a-z0-9._-]{0,127}$
```

A leading `!` marks a **required** feature; if the peer does not support it, the connection MUST fail with `UNSUPPORTED_FEATURE`. Feature names MUST be sorted by raw UTF-8 byte order. Duplicate canonical names MUST be rejected. The `!` marker is retained through negotiation.

### Handshake timeout (§20)

The default handshake timeout is `10000 ms`. If authentication does not complete within the deadline, the connection closes with `HANDSHAKE_TIMEOUT`.

# 14. Post-handshake ordering

After successful authentication, the server emits, in exactly this order (§21, §115):

```text
SERVER -> HELLO_ACK
SERVER -> CAPABILITIES
SERVER -> BROWSER_STATUS
```

`CAPABILITIES` and `BROWSER_STATUS` are connection-scoped, unsolicited events. They do not consume session event sequence numbers.

# 15. Capabilities (§22)

`CAPABILITIES` payload:

```json
{
  "protocol": "1.24",
  "wire_version": "0x00",
  "limits": {
    "handshake_timeout_ms": "10000",
    "max_payload_bytes": 16777216,
    "max_prompt_size": 1048576,
    "max_response_size": 16777216,
    "max_outstanding_requests": 128,
    "max_queued_events": 8192,
    "max_event_history_memory_mb": 64,
    "max_generation_buffer_mb": 32,
    "response_retention_ms": "86400000",
    "continuation_wait_ms": "300000",
    "recovery_deadline_ms": "300000",
    "max_error_details_bytes": 65536,
    "max_diagnostic_details_bytes": 65536
  },
  "keepalive": {
    "enabled": false,
    "idle_timeout_ms": "30000",
    "interval_ms": "10000"
  },
  "providers": [],
  "extensions": []
}
```

- `uint64` limit fields are `uint64-string` per §10.1 and bounded per §10.5.
- `uint32` limit fields are JSON numbers in the range `0 .. 4294967295`.
- `keepalive.enabled` is JSON `boolean`. In this build it is `false` because `ext-pong` is advertised but not yet negotiated for keepalive emission.

Provider entries (§22.1) contain `id`, `version`, `state`, `input_strategies`, and a closed `capabilities` object with exactly these boolean members: `streaming`, `cancellation`, `continuation`, `diagnostics`. Additional members MUST NOT be present in base GARP. Providers are sorted by `id` in raw UTF-8 byte order.

# 16. Keepalive and PING (§99–§101)

- A received `PING` is a normal command and is answered by a normal `RESPONSE` frame. **PING does not cause a PONG.**
- `PONG` is emitted only by the `ext-pong` keepalive mechanism, and only when `ext-pong` is present in the final negotiated feature set (§101).
- When `ext-pong` is negotiated and `keepalive.enabled` is `true`, the gateway maintains two monotonic timestamps per connection (`last_outbound_protocol_time` and `last_inbound_authenticated_time`) and emits unsolicited PONG frames on the interval. All timing decisions MUST use a monotonic clock; raw TCP byte activity MUST NOT be used as a substitute (§101 rule 8).

In this build, `ext-pong` is advertised but keepalive emission is disabled (`keepalive.enabled = false`). The gateway still accepts `PING` and answers with a `RESPONSE`.

# 17. Session behavior

A session has a stable immutable `session_id` (§28). Provider, `tab_id`, `url`, `page_generation`, and `state` are mutable.

Session states are the complete set defined in §29:

```text
CREATED
PREPARING
READY
BUSY
AUTH_REQUIRED
RATE_LIMITED
RECOVERING
RETRYING
FAILED
CLOSED
```

The session transition matrix is normative in §31. In this build:

- `RESET_SESSION` increments `page_generation`, invalidates stale actors, preserves `session_id`, and preserves the session event sequence (§32, §40, §153).
- A tab index change does not change `tab_id` (§43).
- A JSWindowActor replacement does not change `session_id` or `tab_id`, but it does increment `page_generation` (§33, §168).

`page_generation` is a **uint64-string** (§33). It never decrements and never resets to zero during `RESET_SESSION`. Overflow produces `PAGE_GENERATION_OVERFLOW`.

# 18. Prompt behavior

Prompt states are the complete set defined in §48:

```text
PENDING
SUBMITTING
GENERATING
WAITING_CONTINUATION
CANCELLING
COMPLETED
FAILED
CANCELLED
```

`ACCEPTED` is a command-response result state only; it is not a prompt state.

Only one active prompt is permitted per session. A second simultaneous `PROMPT` against a `READY` session receives `SESSION_BUSY` (§51).

### Prompt text is opaque (§49.1, §121)

After JSON decoding, the exact Unicode string MUST be preserved without trimming, normalization, or modification. The `AIAutomationChild` actor stores and injects the exact string supplied by the parent.

### Prompt options (§50)

- `timeout_ms` — `uint64-string`, `0 <= timeout_ms <= 86400000`. `"0"` means no timeout.
- `auto_continue` — JSON `boolean`, default `false`.
- `max_continuations` — JSON `uint32`, range `0 .. 1024`.
- `force_focus` — JSON `boolean`, default `false`.
- `simulate_enter` — JSON `boolean`, default `false`.

### Continuation (§64–§68)

- `continuation_count` starts at `0` and increments by exactly `1` on verified `CONTINUATION_SUBMITTED`.
- `max_continuations = 0` → provider-requested continuation fails with `CONTINUATION_NOT_ALLOWED`.
- `continuation_count >= max_continuations` → `CONTINUATION_LIMIT_REACHED`.
- Adapter does not support continuation → `CONTINUATION_NOT_AVAILABLE`.
- The `partial` flag on the resulting `GENERATION_FAILED` follows the historical rule in §76: `partial = true` iff authoritative response content has already been committed at least once for the prompt. A later `REPLACE` producing an empty string MUST NOT revert `partial` to `false`.

### Cancellation (§72–§73)

- `CANCEL_PROMPT` is valid for `PENDING`, `SUBMITTING`, `GENERATING`, `WAITING_CONTINUATION`.
- A second `CANCEL_PROMPT` while in `CANCELLING` fails with `INVALID_MESSAGE_STATE` (§27.1). `CANCELLING` is nonterminal.
- `CANCEL_PROMPT` against a terminal prompt fails with `PROMPT_ALREADY_TERMINAL`.
- `GENERATION_CANCELLED` requires positive provider cessation evidence (§73). Submission success is **not** cessation evidence. If cessation cannot be authoritatively established, the prompt MUST submit a `RECOVERY_FAILED` terminal candidate and the session MUST enter `RECOVERING` (§64.4, §75).

### Terminal arbitration (§74)

Each prompt has exactly one terminal commit: `COMPLETED`, `FAILED`, or `CANCELLED`. The session arbiter serializes all terminal candidates and the first valid candidate that commits wins. Once committed, the prompt can never reopen (§74).

**This build currently uses a simplified arbiter:** cancellation commits directly to `CANCELLED` after requesting provider cancellation, and completion commits directly on adapter-reported cessation. A production conformance build MUST implement the first-commit-wins arbiter with full fencing (§91) and recovery integration (§75, §93–§96).

### `partial` flag (§76)

`partial = true` iff authoritative response content has already been committed at least once for the prompt. This rule is **historical**: once any authoritative content has been committed, `partial` remains `true` for the remainder of the prompt's lifetime, even if a later `REPLACE` revision sets content to an empty string.

# 19. Events and sequence

All session-scoped asynchronous events have (§11.4, §85):

```text
session_id != null
request_id = null
sequence   = uint64-string
```

Correlation with an originating command or operation MUST be carried inside payload fields, such as `payload.prompt_request_id`. The binary `header.request_uuid` MUST be the all-zero nil UUID for these events.

Sequence numbers (§86, §87):

- First event: `"1"`.
- Increment by `1` per event.
- Monotonic, arbiter-allocated, never repeat, never reset.
- Survive `RESET_SESSION` (§153).
- Overflow beyond `uint64` produces `EVENT_SEQUENCE_OVERFLOW` and fails closed.

Connection-scoped messages (`CAPABILITIES`, `BROWSER_STATUS`, `PONG`) use `sequence = null` and do not consume session history (§89, §100).

# 20. Error codes

The base error registry has 47 codes defined in §27. Relevant codes this build emits include:

```text
INVALID_ARGUMENT, INVALID_ENVELOPE, UNKNOWN_MESSAGE_TYPE, UNKNOWN_MESSAGE_ID,
HEADER_JSON_MISMATCH, UNSUPPORTED_VERSION, UNSUPPORTED_WIRE_VERSION, UNSUPPORTED_FEATURE,
AUTH_REQUIRED, AUTH_FAILED, AUTH_REPLAY, HANDSHAKE_TIMEOUT,
DUPLICATE_REQUEST, REVISION_GAP, EVENT_SEQUENCE_GAP, EVENT_SEQUENCE_OVERFLOW,
PAGE_GENERATION_OVERFLOW, INVALID_MESSAGE_STATE,
SESSION_NOT_FOUND, SESSION_CLOSED, SESSION_BUSY, OUTSTANDING_REQUEST_LIMIT,
TAB_NOT_FOUND, TAB_UNAVAILABLE,
PROMPT_NOT_FOUND, PROMPT_NOT_ACTIVE, PROMPT_ALREADY_TERMINAL, PROMPT_TIMEOUT,
PROMPT_CANCELLED, RESPONSE_NOT_READY,
INPUT_VERIFICATION_FAILED, SUBMISSION_FAILED, STALE_ACTOR, NAVIGATION_DRIFT,
PROVIDER_UNAVAILABLE, PROVIDER_AUTH_REQUIRED, PROVIDER_RATE_LIMITED, PROVIDER_ERROR,
RESPONSE_TOO_LARGE, GENERATION_BUFFER_LIMIT,
CONTINUATION_NOT_ALLOWED, CONTINUATION_LIMIT_REACHED, CONTINUATION_TIMEOUT,
CONTINUATION_NOT_AVAILABLE,
RECOVERY_FAILED, EVENT_QUEUE_OVERFLOW, EVENT_HISTORY_EXPIRED
```

### ERROR frame scoping (§26)

1. **Command-correlated ERROR** adopts the originating command's `request_id` and `session_id`.
2. **Session-originated asynchronous ERROR** sets `request_id = null` and `session_id` to the affected session.
3. **Connection-level ERROR** sets both to `null`.

# 21. Framing and validation order

A receiver MUST validate a frame in the order specified in §8. This build performs, in order:

1. fixed header availability;
2. magic;
3. wire version (`0x00`);
4. `header_len == 48`;
5. `payload_len` against the effective limit (§6.5);
6. `flags == 0`;
7. `reserved == 0`;
8. message type lookup;
9. payload byte acquisition;
10. UTF-8 decoding;
11. JSON syntax;
12. duplicate JSON member detection;
13. Common Envelope member presence and types;
14. header-to-envelope identity and message-type binding;
15. message schema;
16. connection and authentication state;
17. request identity and deduplication;
18. session identity;
19. target identity;
20. state transition and provider semantics.

An implementation MAY perform additional checks earlier when the result is equivalent and deterministic.

# 22. First functional test

After starting the modified Firefox, confirm the Firefox console contains something similar to:

```text
GARP/1.24: listening on 127.0.0.1:9999
```

Then sign in manually to one supported AI provider in the local Firefox profile.

The first external test client should perform:

```text
HELLO
HELLO_CHALLENGE
HELLO_AUTH
HELLO_ACK
CAPABILITIES
BROWSER_STATUS
GET_CAPABILITIES
LIST_TABS
CREATE_SESSION
PROMPT
RESPONSE(command_state=ACCEPTED)
INPUT_SUBMITTED
GENERATION_STARTED
GENERATION_DELTA ...
GENERATION_COMPLETED
```

See §171 for the reference negotiation sequence.

# 23. Provider adapter behavior

Provider-specific selectors and DOM logic live exclusively under `providers/` (§119). The generic child actor contains no provider selector table.

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

Per §167, an adapter MUST define authoritative evidence for input readiness, submission, generation, cessation, and errors. Absence of new DOM activity is not sufficient proof of cessation without an authoritative invariant (§55).

Per §42.2, absence of positive authentication evidence is NOT by itself negative evidence. The adapter MUST NOT submit a `PROVIDER_AUTH_REQUIRED` terminal candidate based solely on the absence of a positive observation.

# 24. Actor fencing (§91, §92, §168)

Every asynchronous provider/browser operation whose result may outlive the initiating actor is associated with the fencing context:

```text
provider            (nullable; see §91)
session_id
page_generation
actor_instance
prompt_request_id   (nullable; see §91)
```

The child actor echoes the parent-supplied fencing block back on every reply, together with the child's own `child_actor_instance`. The parent applies the discard rule: results whose fencing identifiers do not match the session's current authoritative values MUST be discarded as `STALE_ACTOR`.

Multi-actor page-generation fencing: a subordinate actor's result is acceptable only if its `page_generation` matches the session's current `page_generation`, its `actor_instance` matches the actor's currently valid identifier, its `prompt_request_id` (when prompt-associated) matches the active prompt, and its `provider` (when provider-context) matches the session's authoritative provider.

A top-level `page_generation` change invalidates all nested subordinate actors.

# 25. Important implementation boundary

The Firefox side does **not** decide whether AI output is a valid GRISP artifact.

The flow is:

```text
provider response
    |
    v
GARP/1.24
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

Firefox must never silently change the semantic AI response while transporting it (§120).

# 26. Conformance status

This build implements GARP/1.24 Levels 1–3 in full and the majority of Level 4:

- **Level 1 — Transport:** complete (framing, wire version, magic, `header_len = 48`, flags, reserved, big-endian integers, message registry, header/envelope identity binding, duplicate JSON key rejection, bounded payload allocation, handshake and application limit separation).
- **Level 2 — Browser/session:** complete (session identity, stable `tab_id`, `page_generation`, session states, `RESET_SESSION` semantics, session arbiter serialization).
- **Level 3 — Generation:** complete (prompt lifecycle, `INPUT_SUBMITTED`, `GENERATION_STARTED` at revision 0, `GENERATION_DELTA` with `APPEND`/`REPLACE`, revision gap detection, `CONTINUATION_REQUIRED`/`CONTINUATION_SUBMITTED`, `GENERATION_COMPLETED`/`GENERATION_FAILED`/`GENERATION_CANCELLED`, the historical `partial` rule).
- **Level 4 — Recovery:** partial.
  - Implemented: fencing discard, `NAVIGATION_DRIFT`, `RECOVERY_STATE` shape, recovery deadline concept.
  - Not yet complete: full first-commit-wins terminal arbiter (§74), durable replay-protection store (§19), authoritative cessation evidence for `GENERATION_CANCELLED` (§73), and full recovery-driven terminal resolution (§75).
- **Level 5 — Replay extension (`ext-replay-store`):** not implemented.
- **Level 6 — PONG extension (`ext-pong`):** advertised as a supported extension; keepalive emission is disabled in `CAPABILITIES` in this build.

A production conformance build MUST complete the Level 4 items before claiming full Level 4 conformance per §162.

# 27. Troubleshooting

### Port 9999 already in use

Stop the previous local Firefox instance or identify the process holding the port.

### No GARP listener

Check that `BrowserGlue.sys.mjs` actually initializes `AIAutomationService` and that the module path resolves to:

```text
resource:///modules/aistarter/AIAutomation.sys.mjs
```

### Child actor unavailable

Verify the `AIAutomation` entry in `DesktopActorRegistry.sys.mjs` and verify the two actor modules were exported by `aistarter/moz.build`.

### Provider says `PROVIDER_AUTH_REQUIRED`

Open that provider manually in the local Firefox profile and sign in. GARP does not automate credential entry (§118).

### Provider DOM unsupported

The affected provider adapter needs an update. Do not add the selector to the generic child actor unless the selector is truly provider-independent (§119).

### `AUTH_FAILED` during handshake

The client and gateway must be using the same raw shared secret. Confirm `GARP_SECRET` is set identically on the client side and in the Firefox launch environment, and that the secret encodes to at least 32 bytes.

### `AUTH_REPLAY` during handshake

Replay protection detected a reused authenticated handshake transcript. This is expected behaviour (§19). If this is not the intended outcome, verify the client is generating a fresh 16-byte `client_nonce` on each connection.

### `UNSUPPORTED_VERSION` or `UNSUPPORTED_WIRE_VERSION`

The client's HELLO does not advertise `1.24` in `versions`, or does not advertise `0x00` in `wire_versions`. Update the client.

### `UNSUPPORTED_FEATURE`

The client offered a required feature (`!name`) that the gateway does not support. Remove the `!` marker or negotiate a different feature set.

### Build problems

Start with a clean Firefox source checkout and rerun the official bootstrap process. Mozilla notes that the source/build tree can consume substantial disk space and recommends antivirus exclusions for MozillaBuild, the Firefox source tree, and `.mozbuild` on Windows because security scanning can slow or interfere with builds.

# 28. Source-build references

Use Mozilla's current documentation rather than copying old toolchain versions from historical project instructions:

- https://firefox-source-docs.mozilla.org/setup/windows_build.html
- https://firefox-source-docs.mozilla.org/contributing/contribution_quickref.html
- https://firefox-source-docs.mozilla.org/mach/windows-usage-outside-mozillabuild.html

# 29. Status

This package is the **Firefox-side GARP/1.24 implementation task**.

It contains no Selenium dependency and no Delphi client.

The next separate task is the Delphi GARP/1.24 conformance/test application that connects to `127.0.0.1:9999` and exercises the normative handshake (including the §139 authentication conformance vectors), feature negotiation, session lifecycle, prompt lifecycle, streaming, revision handling, continuation, cancellation, terminal arbitration, recovery, duplicate suppression, event sequence handling, and reconnection behaviour.