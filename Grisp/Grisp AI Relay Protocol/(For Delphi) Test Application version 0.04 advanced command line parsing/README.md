# GARP/1.24 Delphi Test Client

Standalone Delphi console client and live smoke tester for the Firefox-side **GARP/1.24** gateway.

The client uses TCP + Indy and speaks the GARP/1.24 binary framing and Common Envelope directly. It does not use Selenium or the old GARP/1.01 protocol.

## Requirements

- Delphi with Indy (`IdTCPClient`).
- A Firefox build containing the GARP/1.24 gateway.
- Firefox GARP listener available at `127.0.0.1:9999` unless another host/port is configured.
- The same deployment-provisioned `GARP_SECRET` as the Firefox process.

The protocol unit does not require the Delphi `Winapi.BCrypt` unit. It calls `BCryptGenRandom` directly from `bcrypt.dll`.

## Build

Open:

```text
src\GARP124.Test.dpr
```

Build it as a Delphi console application with the Indy packages available to the project.

The client uses standard Delphi RTL, JSON, hashing, encoding, Windows, and Indy APIs.

## What was fixed

The previous Delphi client had a parser-breaking use of `TTimeZone` in `GARP124.Protocol.pas`. That caused the compiler to misparse the remainder of the implementation and report many false forward-declaration errors.

The timestamp now uses Delphi's `System.DateUtils.DateToISO8601`:

```pascal
DateToISO8601(Now, False)
```

The client was also corrected for Delphi dynamic-array feature membership. A dynamic `TArray<string>` cannot be used directly with the `in` operator, so negotiated-feature checks now use an explicit helper.

`WaitForCompletion` was corrected to wait specifically for `GENERATION_COMPLETED`, `GENERATION_FAILED`, or `GENERATION_CANCELLED`; it no longer returns on the first intermediate generation event.

`CreateSession` now waits for the asynchronous `SESSION_READY` event when Firefox reports the new session as `PREPARING`.

## Local self-test

```text
GARP124.Test.exe --self-test
```

The self-test verifies:

- GARP/1.24 envelope construction.
- 48-byte fixed header.
- Big-endian header fields.
- UUID placement and header/envelope identity.
- UTF-8 JSON round-trip.
- 16-byte nonce generation.
- Base64URL encoding.
- GARP/1.24 client-proof and server-proof transcript vectors.

Expected proof vectors:

```text
client proof:
4RiTq2SUP15gOp1alqIRdMBUM7Qv4CMZqREMXX4efQs

server proof:
iFaTVoYbn_pb5yCCHOTpAUyfzFaCkXXKgLAbpMX6cfI
```

## Environment

Set the same secret used by Firefox in the shell from which the Delphi client is launched:

```cmd
set GARP_SECRET=your-development-secret
```

or pass it explicitly with `--secret`.

The secret must provide at least 32 UTF-8 bytes.

For a 32-byte ASCII development secret:

```text
0123456789abcdef0123456789abcdef
```

For a longer secret, use a high-entropy random value.

## Basic tests

```text
GARP124.Test.exe --secret your-development-secret --ping
GARP124.Test.exe --secret your-development-secret --capabilities
GARP124.Test.exe --secret your-development-secret --browser-status
GARP124.Test.exe --secret your-development-secret --list-tabs
```

The connection uses:

```text
HELLO
HELLO_CHALLENGE
HELLO_AUTH
HELLO_ACK
CAPABILITIES
BROWSER_STATUS
```

The client verifies the server proof in `HELLO_ACK` before treating the connection as authenticated.

## Session and prompt test

Create a session:

```text
GARP124.Test.exe --secret your-development-secret --session deepseek
```

Run a prompt:

```text
GARP124.Test.exe --secret your-development-secret --session deepseek --prompt "Reply with exactly: GARP/1.24 TEST OK"
```

`CREATE_SESSION` may initially return the session in `PREPARING`. The client now waits for Firefox's asynchronous `SESSION_READY` event before returning from `CreateSession` when appropriate.

## Conformance smoke test

```text
GARP124.Test.exe --secret your-development-secret --conformance
```

The test performs:

```text
HELLO / authentication
PING / RESPONSE
GET_CAPABILITIES
BROWSER_STATUS
LIST_TABS
CREATE_SESSION
PROMPT
terminal generation event
CLOSE_SESSION
```

The default provider is `deepseek`. Use `--session <provider>` together with `--conformance` to select another adapter.

## GARP/1.24 wire details

```text
Protocol:           GARP/1.24
Semantic version:   1.24
Wire version:       0x00
Header:             48 bytes
Byte order:         big-endian
Nonce:              16 raw bytes
Nonce encoding:     unpadded Base64URL
Authentication:     HMAC-SHA256
```

The handshake transcript binds:

```text
protocol/domain
client nonce
server nonce
selected semantic version
selected wire version
offered feature set
final feature set
client name/version
server name/version
```

Feature lists are UTF-8 byte sorted. The current Firefox gateway offers:

```text
ext-pong
ext-replay-store
```

## Prompt lifecycle

GARP/1.24 does not use the old 1.01 `PROMPT_ACK` or `CANCEL_ACK` message types.

`PROMPT` receives a normal correlated `RESPONSE` indicating command acceptance.

Generation then arrives asynchronously using events such as:

```text
INPUT_SUBMITTED
GENERATION_STARTED
GENERATION_DELTA
GENERATION_PROGRESS
CONTINUATION_REQUIRED
CONTINUATION_SUBMITTED
GENERATION_COMPLETED
GENERATION_FAILED
GENERATION_CANCELLED
```

Generation events have a null Common Envelope `request_id`; the prompt is correlated through:

```text
payload.prompt_request_id
```

The client therefore uses the frame request ID for command responses and the payload prompt request ID for generation events.

## Files

```text
src\
    GARP124.Protocol.pas
    GARP124.Client.pas
    GARP124.Test.dpr
```

No installer is required. Copy/build the Delphi project normally.

## Firefox relationship

```text
Delphi GARP/1.24 Test Client
            |
            | TCP 127.0.0.1:9999
            v
Custom Firefox
            |
            +-- AIAutomationService
            +-- GarpConnection
            +-- sessions / requests
            +-- JSWindowActor bridge
            +-- provider adapter
            v
AI provider website
```

The Delphi application is the GARP peer and test client. It does not directly manipulate provider website DOMs.
