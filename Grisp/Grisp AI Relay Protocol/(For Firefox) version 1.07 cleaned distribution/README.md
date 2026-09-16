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

## Firefox build integration

### 1. Component directory

Open:

```text
R:\firefox\browser\components\moz.build
```

Ensure the existing `DIRS` list contains:

```python
'aistarter',
```

Keep Firefox's existing list intact and sorted.

### 2. JSWindowActor registration

Register the actor pair in the `JSWINDOWACTORS` table used by your Firefox checkout. In the current project layout this is expected in:

```text
browser/components/DesktopActorRegistry.sys.mjs
```

Use:

```javascript
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

The actor name must be exactly:

```text
AIAutomation
```

The exact registry file is source-tree dependent. Do not create a second `JSWINDOWACTORS` registry just for this component.

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

This tests the protocol layer only; live Firefox actor and provider-page integration still require Firefox.

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
