# GARP/1.01 Delphi Test Application

This is a standalone Delphi console client for the GARP/1.01 Firefox gateway.
It deliberately does **not** use the old newline-delimited AI automation protocol and does not use Selenium.

## Purpose

The application is a GARP client and conformance smoke tester. It verifies the Firefox-side implementation over the real GARP/1.01 wire protocol:

- TCP localhost transport
- 48-byte GARP fixed header
- big-endian lengths and message types
- UTF-8 JSON payloads
- HELLO / HELLO_CHALLENGE / HELLO_AUTH / HELLO_ACK
- HMAC-SHA256 client authentication
- PING/PONG
- CAPABILITIES
- BROWSER_STATUS
- LIST_TABS
- CREATE_SESSION
- PROMPT / PROMPT_ACK
- asynchronous generation events
- GET-style completion observation through event stream
- CLOSE_SESSION
- local frame encode/decode self-test
- UTF-8 payload verification, including embedded newlines and Unicode

## Requirements

- Delphi with Indy (`IdTCPClient`), such as a normal VCL/FMX Delphi installation that includes Indy.
- A Firefox build containing the GARP/1.01 implementation.
- Firefox GARP server listening on `127.0.0.1:9999`.
- The same `GARP_SECRET` as the Firefox process.

## Firefox compatibility patch

The current Firefox GARP/1.01 draft needs one small registry correction before this client can authenticate: `HELLO_AUTH` needs a numeric message type. Apply `FIREFOX_REQUIRED_PATCH.txt` to `GarpRegistry.sys.mjs`. The recommended value in this test contract is `0x0007`; it does not change the already-implemented `handleHelloAuth()` logic.

## Build

Open `GARP101.Test.dpr` in Delphi and build a Console application.

The source intentionally uses standard RTL + Indy + `System.Hash` and does not depend on mORMot.

## Self-test

The self-test does not require Firefox:

```text
GARP101.Test.exe --self-test
```

It verifies the GARP magic/version, binary length framing, UUID placement and UTF-8 JSON round-trip including Unicode and an embedded newline.

## Live tests

Set the Firefox secret in the environment:

```text
set GARP_SECRET=your-firefox-secret
```

or supply it directly:

```text
GARP101.Test.exe --secret your-firefox-secret --conformance
```

Basic probes:

```text
GARP101.Test.exe --secret your-firefox-secret --ping
GARP101.Test.exe --secret your-firefox-secret --capabilities
GARP101.Test.exe --secret your-firefox-secret --browser-status
GARP101.Test.exe --secret your-firefox-secret --list-tabs
```

Create a session and prompt:

```text
GARP101.Test.exe --secret your-firefox-secret --session deepseek --prompt "Reply with exactly: hello from GARP"
```

Change the provider to one of the configured Firefox adapters, for example:

```text
gemini
grok
chatgpt
copilot
claude
perplexity
deepseek
inception
```

## Conformance smoke test

```text
GARP101.Test.exe --secret your-firefox-secret --conformance
```

By default the smoke test uses DeepSeek and sends a small deterministic prompt.

Use another provider with a provider argument only if the command line option is extended in your local copy, or use the source-level `Provider` field in `RunConformance`.

## Relationship to Firefox

The test application does not automate the AI website itself. Firefox remains responsible for:

```text
browser tabs
sessions
provider adapters
DOM interaction
prompt submission
response observation
streaming events
```

The Delphi client is only the GARP peer:

```text
Delphi GARP Test Client
        |
        | GARP/1.01
        v
Modified Firefox
        |
        v
Provider Adapter
        |
        v
AI website
```

## Important protocol detail

The current Firefox GARP implementation uses the 48-byte fixed header and version byte `$11` for GARP/1.01. The test client intentionally matches that wire contract exactly.
