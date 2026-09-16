# GARP/1.24 Firefox Browser Gateway

This directory contains the Firefox-side implementation of the **GARP/1.24 Gateway AI Runtime Protocol**.

GARP is integrated directly into Firefox source code. It is **not** installed as a WebExtension, `.xpi`, or Firefox Add-on.

This README assumes you already have a working Firefox source checkout, Firefox build environment, bootstrap, and `mozconfig`.

## Install

Assume:

```text
Firefox source: R:\firefox
GARP source:    <path-to-this-repository>
```

Copy:

```text
browser\components\aistarter\
```

to:

```text
R:\firefox\browser\components\aistarter\
```

Do not flatten the directory structure.

The package uses **one** component build file:

```text
browser\components\aistarter\moz.build
```

There are no subordinate `moz.build` files under `actors`, `diagnostics`, `garp`, `providers`, `requests`, or `sessions`.

## Firefox build integration

The component follows the proven `EXTRA_JS_MODULES` packaging pattern:

```python
EXTRA_JS_MODULES.aistarter += [
    "AIAutomation.sys.mjs",
]

EXTRA_JS_MODULES.aistarter.garp += [
    "garp/GarpAuth.sys.mjs",
    "garp/GarpConnection.sys.mjs",
    # ...
]
```

This packages the modules into Firefox's module tree without a `FINAL_TARGET` override and without `FINAL_TARGET_FILES`.

The expected runtime module paths are:

```text
resource:///modules/aistarter/AIAutomation.sys.mjs
resource:///modules/aistarter/garp/...
resource:///modules/aistarter/providers/...
resource:///modules/aistarter/requests/...
resource:///modules/aistarter/sessions/...
resource:///modules/aistarter/diagnostics/...
resource:///modules/aistarter/actors/AIAutomationParent.sys.mjs
resource:///modules/aistarter/actors/AIAutomationChild.sys.mjs
```

### 1. Component directory

Open:

```text
R:\firefox\browser\components\moz.build
```

Ensure the existing `DIRS` list contains:

```python
"aistarter",
```

Keep Firefox's existing list intact and sorted.

### 2. JSWindowActor registration

Register the actor pair in the `JSWINDOWACTORS` table used by your Firefox checkout.

Use:

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

The actor name must be exactly:

```text
AIAutomation
```

Do not create a second `JSWINDOWACTORS` registry just for this component.

### 3. AIAutomation startup

Use:

```text
integration\BrowserGlue.integration.txt
```

for the required startup integration. The intended runtime model is one `AIAutomationService` instance per Firefox process.

## GARP secret

Set the deployment-provisioned `GARP_SECRET` before launching Firefox.

For local protocol testing only:

```bash
export GARP_SECRET="0123456789abcdef0123456789abcdef"
```

The implementation requires at least 32 UTF-8 bytes. Never commit a production secret.

## Build

```bash
cd /r/firefox
./mach build -j8
```

Use `-j4` or `-j2` when lower sustained CPU load is preferred.

## Verify packaging

Before starting Firefox, verify that the application output contains:

```text
R:\firefox-obj\dist\bin\modules\aistarter\AIAutomation.sys.mjs
R:\firefox-obj\dist\bin\modules\aistarter\garp\GarpConnection.sys.mjs
R:\firefox-obj\dist\bin\modules\aistarter\actors\AIAutomationChild.sys.mjs
R:\firefox-obj\dist\bin\modules\aistarter\actors\AIAutomationParent.sys.mjs
```

If `AIAutomation.sys.mjs` is missing from `dist\bin\modules\aistarter`, check `browser\components\aistarter\moz.build` before investigating BrowserGlue or actor registration.

## Run

```bash
export GARP_SECRET="0123456789abcdef0123456789abcdef"
./mach run
```

The default GARP listener is:

```text
127.0.0.1:9999
```

## Protocol test

From this repository:

```bash
node tests/Garp124Conformance.mjs
```

Expected:

```text
GARP/1.24 hybrid conformance vectors: PASS
```

This tests the protocol layer. Live Firefox actor and provider-page integration still require Firefox.

## Providers

Provider-specific browser automation is under:

```text
providers\
```

Current adapters are:

```text
chatgpt
claude
copilot
deepseek
gemini
grok
inception
perplexity
```

Provider website DOM changes can require adapter maintenance.

## Important

Do not install GARP through `about:addons`, the Firefox Add-ons Manager, an `.xpi`, or WebExtension APIs. The source is compiled into the custom Firefox build.
