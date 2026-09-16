# GARP/1.24 Firefox Browser Gateway Integration

This directory contains the GARP/1.24 browser gateway implementation for Firefox.

## 1. What is included

Runtime modules are split by responsibility:

- `AIAutomation.sys.mjs` — connection listener and gateway service.
- `garp/` — framing, envelope/schema validation, authentication, replay protection, errors, and protocol registry.
- `sessions/` — session identity, state, tab binding, event sequencing, and arbitration.
- `requests/` — prompt lifecycle, generation revisions, cancellation, continuation, terminal arbitration, and replay/subscription handling.
- `providers/` — provider-independent adapter base plus provider-specific browser adapters.
- `actors/` — JSWindowActor parent/child bridge between Firefox chrome code and provider pages.
- `diagnostics/` — diagnostic payload helpers.

The conformance test is in `tests/Garp124Conformance.mjs`.

## 2. Build integration

The JavaScript modules must be installed by `moz.build` files. Mozilla's build documentation requires a `moz.build` to live in the same directory as the files it installs; do not list files from a subdirectory in a parent directory. The supplied package therefore uses one root `moz.build` plus one `moz.build` in each module subdirectory.

The runtime actor modules are installed from `actors/`, and the test module is installed with `TESTING_JS_MODULES` from `tests/`.

## 3. JSWindowActor registration — REQUIRED

Adding the actor files to `moz.build` is not sufficient. `AIAutomationParent.sys.mjs` and `AIAutomationChild.sys.mjs` must also be registered as a `JSWindowActor` pair.

The service calls:

```js
const actor = windowGlobal.getActor("AIAutomation");
```

Therefore the registration name MUST be exactly `AIAutomation`.

Firefox's JSWindowActor registration is normally placed in the Firefox Desktop `BrowserGlue.sys.mjs` `JSWINDOWACTORS` table, or in `ActorManagerParent.sys.mjs` when the actor belongs there. Use the registration location appropriate for the Firefox tree being built.

Add an entry equivalent to:

```js
AIAutomation: {
  parent: {
    esModuleURI: "resource:///actors/AIAutomationParent.sys.mjs",
  },
  child: {
    esModuleURI: "resource:///actors/AIAutomationChild.sys.mjs",
  },
  allFrames: false,
},
```

`allFrames: false` is intentional: GARP sessions are bound to the top-level browser tab/document and the gateway does not need a separate actor instance for arbitrary subframes.

Do not add `messages` entries for this JSWindowActor. The implementation uses `sendQuery()` / `receiveMessage()` directly through the actor pair.

After registration, the parent side can obtain the actor with:

```js
const windowGlobal = browser?.browsingContext?.currentWindowGlobal;
const actor = windowGlobal?.getActor("AIAutomation");
```

and the child side receives operations such as:

```text
GARP:PrepareSession
GARP:InspectReady
GARP:CaptureSnapshot
GARP:InjectPrompt
GARP:ObserveGeneration
GARP:ContinueGeneration
GARP:CancelGeneration
GARP:InspectProviderState
```

## 4. Resource paths

When the actor is registered with the paths above, Firefox resolves the modules as:

```text
resource:///actors/AIAutomationParent.sys.mjs
resource:///actors/AIAutomationChild.sys.mjs
```

This depends on the `actors/moz.build` installation mapping. Do not change the registration URI to the source-tree path `browser/components/aistarter/actors/...`.

## 5. Authentication configuration

Set the deployment-provisioned `GARP_SECRET` environment variable before starting Firefox.

The implementation interprets the configured value as raw UTF-8 bytes and requires at least 32 bytes. It does not generate a fallback deployment secret.

The authentication replay state is persisted in the Firefox profile. If the replay store cannot be trusted or durably updated, the configured secret is disabled and must be rotated before authentication is resumed.

## 6. Runtime startup

The gateway listens on loopback TCP port `9999` by default.

Expected startup sequence:

```text
HELLO
HELLO_CHALLENGE
HELLO_AUTH
HELLO_ACK
CAPABILITIES
BROWSER_STATUS
```

Only after authentication has completed are application commands accepted.

## 7. Provider adapters

Provider-specific selectors and DOM behavior belong only in `providers/*.sys.mjs`.

The provider registry advertises actual adapter capabilities through GARP `CAPABILITIES`. The provider-independent protocol layer must not contain provider-specific CSS selectors or DOM assumptions.

## 8. Conformance test

Run the JavaScript conformance test using the Node/test environment appropriate for the Firefox tree. The test covers the published GARP/1.24 authentication transcript and PING vectors, strict duplicate-key rejection, header checks, prompt opacity, and selected schema rules.

The live Firefox integration still needs to be exercised separately because JSWindowActor registration, provider pages, and browser-process behavior cannot be fully validated by the standalone protocol vectors.

## 9. Registration verification

A successful build is not enough to prove actor registration is correct. Verify all of the following in a live Firefox run:

1. Firefox starts without a JS module registration error.
2. `windowGlobal.getActor("AIAutomation")` returns an actor.
3. `PrepareSession` reaches `AIAutomationChild.sys.mjs`.
4. A provider adapter can inspect the current document.
5. A GARP client can complete the HELLO/HELLO_AUTH/HELLO_ACK exchange.
6. `CAPABILITIES` and `BROWSER_STATUS` are emitted after `HELLO_ACK`.

If `getActor("AIAutomation")` fails, check the `JSWINDOWACTORS` registration first, then the `actors/moz.build` installation.

## 10. Security boundary

GARP is a transport/browser-session protocol. It does not automate provider credential entry, approve generated artifacts, or define AI-quality or policy decisions.

The browser gateway must remain fail-closed on malformed protocol input, stale actors, stale provider observations, ambiguous cancellation, and lost authentication replay state.
