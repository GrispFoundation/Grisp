# GARP/1.24 Firefox Browser Gateway — Fixed Packaging

This package is a Firefox source-tree integration. It is **not** a WebExtension, XPI, or Add-on Manager installation.

## The startup fix

Firefox's `browser/moz.build` exports `DIST_SUBDIR = "browser"`. The previous GARP packaging inherited that destination, so modules could be copied under `dist/bin/browser/modules/...` while the code imported `resource:///modules/aistarter/...` from the main application target.

This version deliberately uses **one `browser/components/aistarter/moz.build` file** and pins:

```python
FINAL_TARGET = 'dist/bin'
```

All GARP modules are then installed under:

```text
dist/bin/modules/aistarter/
dist/bin/modules/aistarter/garp/
dist/bin/modules/aistarter/providers/
dist/bin/modules/aistarter/requests/
dist/bin/modules/aistarter/sessions/
dist/bin/modules/aistarter/diagnostics/
dist/bin/actors/
```

which matches the runtime URLs:

```text
resource:///modules/aistarter/AIAutomation.sys.mjs
resource:///modules/aistarter/garp/...
resource:///modules/aistarter/providers/...
resource:///modules/aistarter/requests/...
resource:///modules/aistarter/sessions/...
resource:///modules/aistarter/diagnostics/...
resource:///actors/AIAutomationParent.sys.mjs
resource:///actors/AIAutomationChild.sys.mjs
```

Mozilla documents `FINAL_TARGET` and `FINAL_TARGET_FILES` as controlling installation into the application target; `browser/moz.build` currently exports `DIST_SUBDIR = "browser"`, which is why the explicit target is necessary here. See the official Firefox build-system documentation.

## Install overlay

Copy this package's:

```text
browser/components/aistarter/
```

to:

```text
R:irefoxrowser\componentsistarter```

Then edit the existing:

```text
R:irefoxrowser\components\moz.build
```

and add `"aistarter"` to its existing `DIRS` list. Do not replace the existing list.

Register the actor in the checkout's existing `JSWINDOWACTORS` table using `integration/DesktopActorRegistry.integration.txt`.

Integrate startup using `integration/BrowserGlue.integration.txt`.

## Verify packaging before starting Firefox

After:

```bash
cd /r/firefox
./mach build -j8
```

run:

```bash
ls -l /r/firefox-obj/dist/bin/modules/aistarter/AIAutomation.sys.mjs
ls -l /r/firefox-obj/dist/bin/modules/aistarter/garp/GarpConnection.sys.mjs
ls -l /r/firefox-obj/dist/bin/actors/AIAutomationChild.sys.mjs
ls -l /r/firefox-obj/dist/bin/actors/AIAutomationParent.sys.mjs
```

These four files must exist before `./mach run` is expected to succeed.

Also check that this does **not** contain the main module:

```text
R:irefox-obj\distinrowser\modulesistarter\AIAutomation.sys.mjs
```

The intended location is `dist/bin/modules/aistarter`, not `dist/bin/browser/modules/aistarter`.

## Run

```bash
export GARP_SECRET="0123456789abcdef0123456789abcdef"
./mach run
```

Default listener:

```text
127.0.0.1:9999
```

## Protocol test

```bash
node tests/Garp124Conformance.mjs
```
