# GARP/1.24 Delphi Test Client v0.05

Standalone Delphi console client and live smoke tester for the Firefox-side **GARP/1.24 Gateway AI Runtime Protocol**.

## Purpose

This release keeps the existing GARP/1.24 client/protocol implementation and extends the live conformance smoke test to verify **same-session prompt reuse after `GENERATION_COMPLETED`**.

The conformance test now:

1. authenticates to Firefox;
2. creates one DeepSeek session by default;
3. sends prompt #1 and waits for `GENERATION_COMPLETED`;
4. queries the session and verifies it returned to `READY`;
5. sends prompt #2 on the **same session**, with the **same prompt text** as prompt #1;
6. waits for a second `GENERATION_COMPLETED`;
7. verifies the second response is identical to the first and the session remains `READY`;
8. closes the session cleanly.

The identical second response deliberately exercises the parent request manager's message-count baseline: after the first response, `last_message_count` is 1, so the second response must be identified by the message count increasing to 2 even though the response text is unchanged.

## Source files

```text
src/
    GARP124.Protocol.pas
    GARP124.Client.pas
    GARP124.Test.dpr
```

`GARP124.Protocol.pas` contains the GARP/1.24 wire constants, envelope construction, fixed 48-byte frame encoding/decoding, Base64URL helpers, nonce handling, and authentication transcript.

`GARP124.Client.pas` contains the TCP client, handshake, feature negotiation, request/response handling, session commands, and prompt lifecycle helpers.

`GARP124.Test.dpr` is the console smoke-test executable.

## Build

Open:

```text
src\GARP124.Test.dpr
```

in Delphi and build it as a Console application. Indy must be available to the project.

## Self-test

```text
GARP124.Test.exe --self-test
```

The self-test validates GARP/1.24 envelope construction, 48-byte framing, UUID round-trip, UTF-8/newline preservation, and the published authentication proof vectors.

## Firefox environment

Start Firefox with the same GARP secret. The gateway defaults to:

```text
127.0.0.1:9999
```

For example from MozillaBuild:

```bash
export GARP_SECRET="0123456789abcdef0123456789abcdef"
./mach run
```

The provider used by the live conformance test defaults to `deepseek`; the provider must be authenticated in the Firefox profile.

## Live conformance test v0.05

```text
GARP124.Test.exe --secret your-firefox-secret --conformance
```

Optionally add `--session <provider>` to select another advertised provider.

Expected lifecycle for the new regression test:

```text
CREATE_SESSION
    ↓
PROMPT #1
    ↓
GENERATION_COMPLETED
    ↓
GET_SESSION → READY
    ↓
PROMPT #2 (same text)
    ↓
GENERATION_COMPLETED
    ↓
GET_SESSION → READY
    ↓
CLOSE_SESSION
```

With `--debug`, the underlying asynchronous generation events and their session sequence values are printed by the client.
