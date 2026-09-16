# Firefox AI Automation + GARP/1.24

This package is the Firefox-side implementation of the **GARP/1.24 Gateway AI Runtime Protocol** freeze candidate supplied with the implementation task.

It replaces the earlier GARP/1.01 wire contract. Firefox remains the browser automation substrate and provider-specific DOM logic remains isolated in provider adapters.

## Architecture

```text
GRISP / AI Runtime
        |
        | GARP/1.24 over localhost TCP
        v
Firefox AIAutomationService
        |
        +-- GarpConnection
        +-- AIAutomationSessionManager
        +-- GarpRequestManager
        +-- ProviderRegistry
        +-- GarpReplayStore
        |
        v
AIAutomationParent / AIAutomationChild
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

GARP is the transport and browser/session boundary. It does not decide GRISP artifact validity or semantic AI quality.

## Providers

The supplied provider adapters are retained from the input implementation and wrapped in the GARP/1.24 fencing/evidence model:

`gemini`, `grok`, `chatgpt`, `copilot`, `claude`, `perplexity`, `deepseek`, `inception`.

Provider DOM selectors are inherently maintenance-sensitive; no claim is made that the current provider websites still expose exactly these selectors.

## GARP/1.24 changes implemented

* Protocol identifier is `GARP/1.24` and semantic envelope version is `1.24`.
* Wire version is exactly `0x00`.
* Fixed binary header is exactly 48 bytes and all integers are big-endian.
* JSON envelope is the 1.24 Common Envelope with mandatory `garp`, `type`, `request_id`, `session_id`, `timestamp`, `sequence`, and `payload`.
* Envelope/header identities are cross-checked.
* Duplicate JSON object members are rejected before JSON parsing semantics can choose first/last values.
* Base objects are closed; `_extensions` is only permitted in `PROMPT.options`.
* `uint64` JSON values use decimal strings and are represented internally with `BigInt`.
* Handshake receive limits are 1 MiB until the receiver has validated peer CAPABILITIES; application receive/send limits then follow the peer's advertised `max_payload_bytes`.
* Base message registry is replaced with the exact GARP/1.24 registry, plus optional `GET_EVENTS` extension code `0x0100`.
* HELLO authentication uses 16-byte raw nonces, unpadded Base64URL, and the exact transcript construction from §16.6.
* Authentication supports the required-feature `!` modifier and binds both offered and final feature sets into the HMAC transcript.
* `GARP_SECRET` is deployment-provisioned and must provide at least 32 raw UTF-8 bytes; no startup fallback secret is generated.
* Authentication replay state is persisted in the Firefox profile for at least 24 hours. Loss/corruption/persistence failure disables the configured credential context until secret rotation.
* Handshake timeout is 10 seconds using a monotonic clock.
* CAPABILITIES is emitted after HELLO_ACK, followed by the initial BROWSER_STATUS event.
* PING receives a normal correlated RESPONSE. Unsolicited PONG is emitted only when `ext-pong` is negotiated.
* BROWSER_STATUS tracks `active_tab_id` and is emitted only when its committed status changes, plus the required initial handshake emission.
* Stable tab IDs are used; tab indexes are not identity.
* Sessions have serialized per-session arbiter queues, stable session IDs, monotonic `page_generation`, and monotonic session event sequences.
* Prompt states match the 1.24 lifecycle, including `CANCELLING` and `WAITING_CONTINUATION`.
* Prompt admission reserves at most one active prompt per session.
* Prompt timeout starts at acceptance commit and uses monotonic time.
* INPUT_SUBMITTED is emitted only after positive provider submission verification.
* GENERATION_STARTED establishes message identity at revision 0; accepted generation deltas use explicit APPEND/REPLACE revisions starting at 1.
* Partial-result state is historical: once authoritative response content has been committed, later empty REPLACE snapshots cannot clear `partial`.
* Completion, failure, cancellation, timeout, navigation drift, provider invalidation, continuation limit failures, and recovery failures converge through one terminal arbitration path; the first valid terminal candidate committed by the session arbiter wins.
* Cancellation is fenced and requires positive provider cessation evidence.
* In-flight continuation work is fenced by a continuation epoch and is discarded after accepted cancellation.
* Page-generation and actor-instance fencing rejects stale browser results.
* Provider-context results are additionally fenced by authoritative provider identity.
* Recovery has a finite deadline and an explicit `RECOVERING -> FAILED` terminal transition on deadline expiry.
* Event history is retained in complete committed Common Envelopes and supports atomic `GET_EVENTS` snapshots when `ext-replay-store` is negotiated.
* Replay returns a contiguous sequence only and reports `EVENT_HISTORY_EXPIRED` rather than skipping unavailable history.

## Firefox integration

1. Copy `browser/components/aistarter` into the Firefox tree.
2. Add `aistarter` to `browser/components/moz.build`.
3. Add the module getter and single `AIAutomationService` startup call described in `integration/BrowserGlue.integration.txt`.
4. Add the `AIAutomation` JSWindowActor entry from `integration/DesktopActorRegistry.integration.txt`.
5. Launch Firefox with a deployment-provisioned `GARP_SECRET` containing at least 32 UTF-8 bytes.
6. Build and run Firefox using the normal source-build flow.

The supplied package intentionally does not modify a real Firefox checkout automatically because the integration locations are source-tree dependent.

## Authentication test vector

The package's test suite verifies the published GARP/1.20, 1.22 and 1.23 transcript anchors indirectly through the transcript construction used by the implementation, and verifies the computed GARP/1.24 proof values:

```text
client hex:
e11893ab64943f5e603a9d5a96a21174c05433b42fe02319a9110c5d7e1e7d0b

client Base64URL:
4RiTq2SUP15gOp1alqIRdMBUM7Qv4CMZqREMXX4efQs

server hex:
88569356861b9ffa5be720821ce4e9014c9fcc56829175ca80b01ba4c5fa71f2

server Base64URL:
iFaTVoYbn_pb5yCCHOTpAUyfzFaCkXXKgLAbpMX6cfI
```

## PING vector

The conformance test verifies the exact 167-byte JSON payload from §102 and the first 16 bytes of its binary header:

```text
47 41 52 50 00 00 00 30 00 00 00 A7 00 70 00 00
```

## Test

The protocol-level tests require a Node.js runtime only; they do not require Firefox:

```bash
node tests/Garp124Conformance.mjs
```

Expected result:

```text
GARP/1.24 conformance unit vectors: PASS
```

## Validation status

The package has been syntax-checked with `node --check` for every `.mjs` file and the protocol-level conformance test passes.

A complete `./mach build` has **not** been run here because that requires a full Firefox source checkout and Mozilla build environment. Firefox integration should therefore be treated as source-level prepared but not as a completed full-browser build verification.
