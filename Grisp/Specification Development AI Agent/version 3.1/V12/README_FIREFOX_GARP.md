# GSDA/3.1 Firefox + GARP layer

This adds the first real browser boundary around the deterministic GSDA core.

## Architecture

```text
Firefox AI provider
       |
       | Selenium WebDriver
       v
firefox-garp-bridge.js
       |
       | GARP/1.0 TCP, 4-byte big-endian length prefix
       v
GSDA31.GARP.pas
       |
       v
GSDA31.Gateway.pas
       |
       v
TGSDASpecAgent31
       |
       v
TGSDAKernel31
```

The browser is not trusted with the GSDA kernel state. The deterministic kernel remains the authority for IDs, HMAC verification, state mutation, candidate selection, and freezing.

The browser bridge is an adapter. Its CSS selectors are configuration and are deliberately outside the kernel.

## Delphi server

Build and run `GSDA31.GARPHost.dpr`.

It listens on `127.0.0.1:9911` and registers the development peer:

- peer:alpha
- fingerprint: `local|adapter:firefox|endpoint:firefox`
- secret: `development-secret`

Do not use that secret in production.

Indy is required (`IdContext`, `IdTCPServer`, `IdGlobal`, etc.).

## Node bridge

Install Selenium:

```text
npm install selenium-webdriver
```

Selenium Manager can locate/install the browser driver in current Selenium releases. `GECKODRIVER_PATH` may also be set explicitly when a fixed geckodriver executable is required. Firefox is driven through WebDriver rather than a browser-specific scraping framework.

Set at minimum:

```text
GSDA_PROMPT=Develop a deterministic specification for browser-mediated specification development.
GSDA_PROVIDER_URL=https://example.invalid/
GSDA_PROMPT_SELECTOR=textarea
GSDA_RESPONSE_SELECTOR=.assistant-message
```

Optional send button:

```text
GSDA_SEND_SELECTOR=button[type="submit"]
```

Run:

```text
node firefox-garp-bridge.js
```

The script intentionally does not automate credentials. Use an existing Firefox profile or log in interactively before submitting the task.

## GARP framing

Every message is:

```text
4-byte unsigned big-endian payload length
UTF-8 JSON payload
```

Request schema:

```json
{
  "schema": "garp/1.0",
  "message_type": "command",
  "request_id": "UUID",
  "session_id": "session:...",
  "tab_id": "tab:...",
  "sequence": 1,
  "payload": { "command": "..." }
}
```

Response schema:

```json
{
  "schema": "garp/1.0",
  "message_type": "command_response",
  "request_id": "UUID",
  "session_id": "session:...",
  "tab_id": "tab:...",
  "sequence": 1,
  "payload": { ... }
}
```

## Current scope

This is the first transport/automation integration, not the final provider-specific production adapter. The next hardening work is:

1. provider-specific Firefox profiles/selectors for the actual AI sites;
2. generation event capture instead of response polling where practical;
3. exact GARP sequence/session/tab replay rules;
4. persistent peer configuration instead of development hard-coding;
5. full GSDA reliability/scoring/finding/repair/consolidation pipeline;
6. a GARP conformance test client that attacks malformed frames, replay, wrong tab, wrong sequence, and wrong HMAC.
