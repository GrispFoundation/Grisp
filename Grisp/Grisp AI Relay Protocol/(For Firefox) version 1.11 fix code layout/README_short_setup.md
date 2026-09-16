# Firefox + GARP/1.24 Developer Setup

This document is for a new Windows developer who does not yet have a working Firefox source-build environment.

For a developer who already has a working Firefox checkout and build environment, use `README.md`.

## 1. Scope

This repository supplies the Firefox-side GARP/1.24 browser gateway. It is integrated into Firefox source and compiled into a custom Firefox build. It is not a WebExtension.

The development chain is:

```text
Windows 11
  -> MozillaBuild
  -> Firefox source
  -> Firefox object directory
  -> GARP source integration
  -> custom Firefox build
  -> Firefox runtime
  -> GARP localhost connection
```

The external GARP client and GRISP semantic processing are outside this repository.

## 2. Recommended storage

The documented project layout is:

```text
G:\
├── FileDiskImages\
│   └── FireFoxDevelopmentV1.vhdx
├── Tools\
│   ├── MozillaBuild\
│   ├── Rust\
│   └── nvm\
├── mozbuild\
│   └── sccache\
└── Temp\
```

Mount the VHDX as `R:` and use:

```text
R:\firefox
R:\firefox-obj
```

The 50 GB VHDX is this project's documented layout, not a universal Firefox capacity requirement.

## 3. Create the VHDX

Create:

```text
G:\FileDiskImages\FireFoxDevelopmentV1.vhdx
```

Recommended settings:

```text
50 GB
VHDX
Fixed size
GPT
NTFS
4096-byte allocation unit
Drive letter R:
Volume label FirefoxDevelopmentV1
```

Windows Disk Management can be opened with:

```text
diskmgmt.msc
```

## 4. MozillaBuild

Install MozillaBuild in:

```text
G:\Tools\MozillaBuild
```

Start it with:

```text
G:\Tools\MozillaBuild\start-shell.bat
```

Run normal Firefox build commands from that shell. Do not add `G:\Tools\MozillaBuild\bin` to the normal Windows PATH merely to make Firefox builds work.

## 5. Build state and cache

Use:

```text
MOZBUILD_STATE_PATH=G:\mozbuild
SCCACHE_DIR=G:\mozbuild\sccache
```

Create the directories as required.

Optional user-managed tools may live under `G:\Tools`, but Firefox bootstrap should determine the versions expected by the checkout.

Do not globally force Firefox with an arbitrary `PYTHON` variable or `MOZ_OBJDIR`.

## 6. Python, Node.js and Rust

Firefox uses all three in its build/tooling ecosystem. Run `./mach bootstrap` and let the Firefox build environment establish the versions appropriate to the checkout.

A separately managed installation may exist for unrelated work, but should not be used to override Firefox's required versions without a deliberate build configuration change.

## 7. Antivirus

Firefox builds touch a very large number of files. Review antivirus exclusions for the MozillaBuild directory, Firefox source, build-state directory, and object directory as appropriate for the machine:

```text
G:\Tools\MozillaBuild
G:\mozbuild
R:\firefox
R:\firefox-obj
```

Do not disable antivirus globally.

## 8. Firefox checkout

Start:

```text
G:\Tools\MozillaBuild\start-shell.bat
```

Then:

```bash
cd /r
git clone https://github.com/mozilla-firefox/firefox.git firefox
cd firefox
```

The source tree should be:

```text
R:\firefox
```

## 9. Bootstrap

From the Firefox source tree:

```bash
./mach bootstrap
```

Follow the bootstrap prompts and allow it to establish the dependencies expected by the checkout.

## 10. mozconfig

Create:

```text
R:\firefox\mozconfig
```

with:

```bash
mk_add_options MOZ_OBJDIR=@TOPSRCDIR@/../firefox-obj
ac_add_options --with-ccache=sccache
```

This puts the object directory at:

```text
R:\firefox-obj
```

## 11. Initial Firefox build

```bash
cd /r/firefox
./mach build -j8
```

For lower sustained CPU load:

```bash
./mach build -j4
```

or:

```bash
./mach build -j2
```

## 12. Install GARP manually

Copy:

```text
browser\components\aistarter\
```

to:

```text
R:\firefox\browser\components\aistarter\
```

This distribution intentionally contains no installer. Manual source-tree installation is the supported workflow.

The component has exactly one `moz.build`:

```text
R:\firefox\browser\components\aistarter\moz.build
```

Do not add subordinate `moz.build` files under the component's child directories.

## 13. Register the component directory

Edit:

```text
R:\firefox\browser\components\moz.build
```

Add:

```python
'aistarter',
```

to the existing sorted `DIRS` list.

The supplied `aistarter\moz.build` uses `EXTRA_JS_MODULES` to package all GARP modules. It does **not** use `FINAL_TARGET` or `FINAL_TARGET_FILES`.

## 14. Verify the packaged modules

After building, verify these files exist:

```text
R:\firefox-obj\dist\bin\modules\aistarter\AIAutomation.sys.mjs
R:\firefox-obj\dist\bin\modules\aistarter\garp\GarpConnection.sys.mjs
R:\firefox-obj\dist\bin\modules\aistarter\actors\AIAutomationChild.sys.mjs
R:\firefox-obj\dist\bin\modules\aistarter\actors\AIAutomationParent.sys.mjs
```

The corresponding runtime URLs are:

```text
resource:///modules/aistarter/AIAutomation.sys.mjs
resource:///modules/aistarter/garp/...
resource:///modules/aistarter/actors/AIAutomationParent.sys.mjs
resource:///modules/aistarter/actors/AIAutomationChild.sys.mjs
```

## 15. Register the JSWindowActor

Register the actor in the existing `JSWINDOWACTORS` table used by the checkout.

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

## 16. Integrate AIAutomation startup

Use:

```text
integration\BrowserGlue.integration.txt
```

for the startup insertion reference. The goal is exactly one `AIAutomationService` instance, started during Firefox startup and shut down with Firefox.

The startup import must resolve to:

```text
resource:///modules/aistarter/AIAutomation.sys.mjs
```

## 17. GARP secret

Set the same deployment secret used by the GARP client before starting Firefox:

```bash
export GARP_SECRET="0123456789abcdef0123456789abcdef"
```

The implementation requires at least 32 UTF-8 bytes and has no fallback deployment secret.

## 18. Build with GARP

```bash
cd /r/firefox
./mach build -j8
```

If Firefox reports an `UnsortedError`, sort the incoming list in the affected `moz.build` file lexically.

## 19. Run

```bash
export GARP_SECRET="0123456789abcdef0123456789abcdef"
./mach run
```

Default listener:

```text
127.0.0.1:9999
```

## 20. Test

Standalone protocol test:

```bash
node tests/Garp124Conformance.mjs
```

Expected:

```text
GARP/1.24 hybrid conformance vectors: PASS
```

Live integration should additionally verify actor creation, provider inspection, the GARP handshake, `CAPABILITIES`, and initial `BROWSER_STATUS`.

## 21. Incremental development

For JavaScript-only GARP changes:

```bash
cd /r/firefox
./mach build -j8
```

Then restart Firefox.

Do not clobber the object directory after every source change.

## 22. Update Firefox

Before updating:

```bash
git status
git diff
```

Then update and rebuild:

```bash
git pull origin main
./mach build -j8
```

Avoid destructive commands such as `git reset --hard` or `git clean -fdx` unless local work is intentionally being discarded.

## 23. Backup

The VHDX contains:

```text
R:\firefox
R:\firefox-obj
```

The physical host locations outside the VHDX require separate backup if needed:

```text
G:\Tools\MozillaBuild
G:\mozbuild
G:\mozbuild\sccache
G:\Temp
```

## 24. Troubleshooting

### MozillaBuild commands are unavailable

Start:

```text
G:\Tools\MozillaBuild\start-shell.bat
```

### Python is wrong

Do not force an arbitrary Python with a global `PYTHON` variable. Re-open MozillaBuild and verify the Firefox build virtual environment.

### sccache is unavailable

Check:

```text
G:\mozbuild\sccache
```

and:

```bash
which sccache
```

### `UnsortedError`

Firefox's mozbuild lists are strict-order lists. Sort the affected list alphabetically.

### Actor cannot be found

Check:

```text
AIAutomation
resource:///modules/aistarter/actors/AIAutomationParent.sys.mjs
resource:///modules/aistarter/actors/AIAutomationChild.sys.mjs
```

Then verify the actor modules exist under:

```text
R:\firefox-obj\dist\bin\modules\aistarter\actors\
```

### GARP authentication fails

Check that Firefox and the GARP client use the same `GARP_SECRET` and that it encodes to at least 32 UTF-8 bytes.

### Provider automation fails

Inspect the corresponding adapter under:

```text
providers\
```

Provider websites can change their DOM independently of this project.

## 25. Final layout

```text
G:\
├── FileDiskImages\
│   └── FireFoxDevelopmentV1.vhdx
├── Tools\
│   ├── MozillaBuild\
│   ├── Rust\
│   └── nvm\
├── mozbuild\
│   └── sccache\
└── Temp\
```

Mounted as:

```text
R:\
├── firefox\
│   ├── mozconfig
│   └── ...
└── firefox-obj\
```

GARP integration:

```text
R:\firefox\browser\components\aistarter\
```

Build:

```bash
cd /r/firefox
./mach build -j8
```

Run:

```bash
export GARP_SECRET="0123456789abcdef0123456789abcdef"
./mach run
```
