# Firefox AI Automation + GARP/1.24

**Firefox-side integration and build instructions**

This repository contains the Firefox-side implementation of **GARP/1.24 — Gateway AI Runtime Protocol**.

The implementation is deliberately **Selenium-free**. Firefox itself provides the browser automation substrate through Firefox chrome/parent code, JSWindowActors, and provider-specific adapters.

This README is intentionally focused on:

* Windows 11 development storage
* VHDX creation and mounting
* MozillaBuild installation
* Build tools and environment variables
* Firefox source checkout
* Firefox bootstrap
* Integrating GARP/1.24 into the Firefox source tree
* Firefox source integration
* Building Firefox
* Running Firefox
* Basic troubleshooting

The GARP/1.24 protocol specification remains the authoritative document for protocol behavior. This README does not reproduce the protocol specification.

---

# 1. Prerequisites

Before installing this project, make sure the required host environment is available.

## 1.1 Operating system

The primary documented environment is:

```text
Windows 11
64-bit
```

The instructions below assume a normal Windows 11 desktop development machine.

The Firefox source tree and build commands described here are intended for a supported Firefox source-build environment.

---

## 1.2 MozillaBuild

Install a current MozillaBuild release appropriate for the Firefox checkout.

This project expects MozillaBuild at:

```text
G:\Tools\MozillaBuild
```

Start the build environment with:

```text
G:\Tools\MozillaBuild\start-shell.bat
```

Firefox build commands should normally be run from that shell.

---

## 1.3 Dedicated development storage

This project assumes a dedicated Firefox development VHDX:

```text
G:\FileDiskImages\FireFoxDevelopmentV1.vhdx
```

with:

```text
50 GB
VHDX
Fixed size
GPT
NTFS
4096-byte / 4 KB allocation unit
```

The VHDX is mounted as:

```text
R:
```

The Firefox source and Firefox object/build output are both placed on this volume:

```text
R:\firefox
R:\firefox-obj
```

The same-volume arrangement is intentional and is part of the recommended project setup.

---

## 1.4 Git

Git is required to obtain and update the Firefox source tree.

The Firefox repository used by these instructions is:

```text
https://github.com/mozilla-firefox/firefox.git
```

MozillaBuild provides Git tooling for the standard Windows Firefox development workflow.

---

## 1.5 Firefox source-build dependencies

Firefox has a substantial build toolchain.

The Firefox bootstrap system is responsible for obtaining/configuring the versions required by the Firefox checkout.

Run:

```bash
./mach bootstrap
```

before the first full build.

Do not assume that an independently installed compiler, Rust version, Python version, Node.js version, or other development tool is automatically compatible with the Firefox checkout.

---

## 1.6 Python

Firefox's build system uses Python extensively.

Python is therefore a genuine Firefox build dependency.

However, this project does **not** require a manually selected global Python installation.

Use the Python environment provided by MozillaBuild/Firefox's bootstrap and build tooling.

Do not create a global:

```text
PYTHON=...
```

environment variable to force Firefox to use an arbitrary Python installation.

A separate Python installation may exist on the machine for unrelated development work, but it is not necessary to configure one specifically for this project.

---

## 1.7 Node.js

Firefox uses Node.js for parts of its build and tooling infrastructure.

The Firefox bootstrap/build system determines the required version for the checkout.

If Node.js is separately managed with nvm, it may be stored on `G:`:

```text
G:\Tools\nvm
G:\Tools\nvmmodejs
```

but this is optional.

---

## 1.8 Rust

Firefox requires Rust for several components.

The Firefox bootstrap/build system determines and installs the Rust toolchain required by the particular Firefox checkout.

A user-managed Rust installation can also be stored on `G:`:

```text
G:\Tools\Rust
```

but it should not be used to override the Firefox checkout's required toolchain arbitrarily.

---

## 1.9 Network access

The initial setup requires network access to obtain:

* Firefox source code
* Firefox build dependencies
* Rust/toolchain components
* Mozilla build tooling as required
* other source dependencies

A normal Internet connection is therefore required during initial bootstrap.

---

## 1.10 Disk space

The VHDX used by this project is:

```text
50 GB
```

This is the development-volume size used by the documented setup.

A Firefox source checkout plus a full object directory can consume substantial space, especially during builds.

Monitor free space on:

```text
R:
```

during development.

The VHDX should not be allowed to fill completely.

---

## 1.11 GARP client

The Firefox component is the **GARP server/gateway side**.

A separate GARP/GRISP client is required for end-to-end protocol testing.

That client may be written in Delphi or another language capable of implementing the GARP/1.24 wire protocol.

It is outside the scope of this repository.

---

# 2. Scope

This repository covers the **Firefox-side browser gateway implementation**.

It includes:

```text
Firefox chrome/parent integration
JSWindowActors
GARP connection handling
GARP authentication
GARP framing
GARP JSON validation
GARP session management
GARP request management
provider registry
provider adapters
persistent authentication replay protection
diagnostics
protocol-level tests
```

The repository's primary purpose is to provide the Firefox implementation required for an AI runtime to communicate with AI provider websites through the GARP/1.24 gateway.

---

## 2.1 In scope

The following are part of this project:

```text
Firefox integration
    ↓
AIAutomationService
    ↓
GARP transport/authentication
    ↓
session/request management
    ↓
JSWindowActor communication
    ↓
provider-specific browser automation
```

The provider adapters are responsible for interacting with provider websites through Firefox.

---

## 2.2 Installation scope

This project is **not installed as a normal Firefox WebExtension**.

There is no normal:

```text
Firefox Add-ons Manager
.xpi installation
WebExtension installation
```

step.

The GARP implementation runs inside Firefox's privileged browser/chrome environment and therefore has to be integrated into the **Firefox source tree** and compiled as part of Firefox.

The installation process is:

```text
GARP repository
        |
        | copy source files
        v
Firefox source checkout
        |
        +-- browser/components/aistarter/
        |
        +-- moz.build integration
        +-- JSWindowActor registration
        +-- Firefox startup integration
        |
        v
./mach build
        |
        v
Custom Firefox build containing GARP/1.24
```

The actual installation therefore occurs at the **Firefox source/build level**, not through Firefox's normal add-on system.

---

## 2.3 What is installed where?

### Physical build/storage disk

```text
G:\
├── FileDiskImages\
│   └── FireFoxDevelopmentV1.vhdx
│
├── Tools\
│   └── MozillaBuild\
│
└── mozbuild\
    └── sccache\
```

### Firefox development VHDX

Mounted as:

```text
R:
```

Firefox source:

```text
R:\firefox
```

Firefox object/build output:

```text
R:\firefox-obj
```

GARP source integration:

```text
R:\firefox\browser\components\aistarter\
```

---

## 2.4 What the GARP package changes

The package adds Firefox-side source files such as:

```text
AIAutomation.sys.mjs
AIAutomationParent.sys.mjs
AIAutomationChild.sys.mjs

GarpAuth.sys.mjs
GarpConnection.sys.mjs
GarpErrors.sys.mjs
GarpFrame.sys.mjs
GarpJson.sys.mjs
GarpRegistry.sys.mjs
GarpReplayStore.sys.mjs
GarpSchema.sys.mjs
GarpUtil.sys.mjs

Provider adapters
Request/session modules
Diagnostics
```

It also requires a small number of changes to the Firefox source tree outside `aistarter`, notably:

```text
browser/components/moz.build
```

and the Firefox startup / JSWindowActor registration locations appropriate to the Firefox revision being built.

The package does **not** replace the Firefox source tree.

It adds the GARP component and the minimum Firefox integration required to compile and start it.

---

## 2.5 Runtime scope

After compilation, GARP runs as part of the custom Firefox process.

The runtime relationship is:

```text
Custom Firefox
    |
    +-- AIAutomationService
    |
    +-- GARP server
    |
    +-- JSWindowActors
    |
    +-- provider adapters
    |
    +-- AI provider websites
```

The external AI runtime/GARP client connects to Firefox over the configured GARP transport.

Provider websites do not receive or install the GARP component.

---

## 2.6 Firefox user profile

A normal Firefox profile is still used at runtime.

The profile contains Firefox runtime state such as:

```text
cookies
login sessions
provider authentication
Firefox preferences
GARP authentication replay state
```

The GARP source code itself is **not** installed into the Firefox profile.

Do not copy the `.mjs` source files into a Firefox profile directory.

The GARP source belongs in the Firefox source tree and is compiled into the custom Firefox build.

---

## 2.7 Out of scope

The following are intentionally outside this repository.

### GRISP semantic processing

This implementation does not decide whether an AI result is a valid GRISP artifact.

GRISP artifact semantics belong to the AI runtime/client layer.

### AI quality evaluation

This project does not judge:

```text
answer quality
reasoning quality
factual quality
model intelligence
```

It provides the browser gateway through which the AI runtime can interact with a provider.

### Provider accounts

The repository does not create or manage:

```text
Google accounts
OpenAI accounts
Anthropic accounts
Microsoft accounts
xAI accounts
Perplexity accounts
DeepSeek accounts
other provider accounts
```

The Firefox profile must already have whatever provider authentication is required.

### Provider website stability

Provider websites can change independently of this project.

Changes to:

```text
DOM structure
selectors
accessibility tree
contenteditable implementation
button layout
streaming behavior
login flow
```

can require updates to the corresponding provider adapter.

### GARP client implementation

This repository provides the Firefox gateway side.

It does not provide the external AI runtime/GARP client.

### Production deployment infrastructure

The repository does not define:

```text
service managers
Windows services
enterprise secret management
remote deployment
fleet management
production monitoring infrastructure
```

The GARP shared secret must be provisioned by the deployment environment.

---

## 2.8 Security boundary

Firefox chrome/parent code is part of the trusted browser-side GARP implementation.

Provider websites are treated as external systems.

Provider DOM observations therefore pass through the project's:

```text
validation
evidence checks
session fencing
page-generation fencing
actor fencing
provider-context fencing
```

before they become authoritative GARP state.

The implementation must not treat an arbitrary provider DOM response as inherently trustworthy.

---

# 3. Recommended Windows 11 architecture

The recommended development layout uses a dedicated **50 GB fixed-size VHDX** for the Firefox source tree and Firefox build/object output.

The VHDX is stored on the physical `G:` drive.

The VHDX is mounted as `R:`.

The recommended layout is:

```text
G:\
├── FileDiskImages\
│   └── FireFoxDevelopmentV1.vhdx
│
├── Tools\
│   ├── MozillaBuild\
│   ├── Rust\
│   ├── nvm\
│   └── ...
│
├── mozbuild\
│   └── sccache\
│
└── Temp\
```

The VHDX is mounted by Windows as:

```text
R:
```

The Firefox development volume then contains:

```text
R:\
├── firefox\
│   ├── mach
│   ├── mozconfig
│   ├── browser\
│   ├── dom\
│   ├── toolkit\
│   └── ...
│
└── firefox-obj\
```

The critical rule is:

> **Firefox source and Firefox object/build output must remain on the same mounted volume.**

For this project:

```text
R:\firefox
R:\firefox-obj
```

are deliberately on the same VHDX.

The VHDX itself resides physically on:

```text
G:\FileDiskImages\FireFoxDevelopmentV1.vhdx
```

---

# 4. Create the Firefox development VHDX

The project uses:

```text
VHDX
50 GB
Fixed size
GPT
NTFS
4096-byte / 4 KB allocation unit
Drive letter R:
```

The VHDX file is:

```text
G:\FileDiskImages\FireFoxDevelopmentV1.vhdx
```

## 4.1 Create the host directory

Create:

```text
G:\FileDiskImages
```

The final VHDX path is:

```text
G:\FileDiskImages\FireFoxDevelopmentV1.vhdx
```

## 4.2 Open Disk Management

Press:

```text
Win + X
```

and select:

```text
Disk Management
```

or run:

```text
diskmgmt.msc
```

## 4.3 Create the VHDX

Select:

```text
Action
    ->
Create VHD
```

Use:

```text
Location:
    G:\FileDiskImages\FireFoxDevelopmentV1.vhdx

Virtual hard disk size:
    50 GB

Virtual hard disk format:
    VHDX

Virtual hard disk type:
    Fixed size
```

## 4.4 Initialize as GPT

When Windows asks for the partition style, select:

```text
GPT (GUID Partition Table)
```

Do not select:

```text
MBR
```

## 4.5 Create the NTFS volume

Create a New Simple Volume.

Use:

```text
Drive letter:
    R:

Filesystem:
    NTFS

Allocation unit size:
    4096 bytes

Volume label:
    FirefoxDevelopmentV1
```

The completed relationship is:

```text
G:\FileDiskImages\FireFoxDevelopmentV1.vhdx
                    |
                    | mounted
                    v
                   R:\
```

---

# 5. MozillaBuild installation

Install MozillaBuild on:

```text
G:\Tools\MozillaBuild
```

Start it with:

```text
G:\Tools\MozillaBuild\start-shell.bat
```

For this project, Firefox build commands should be run from the MozillaBuild shell.

MozillaBuild's startup script establishes its required environment.

---

# 6. Windows 11 environment variables

The core environment variables are:

```text
MOZBUILD_STATE_PATH=G:\mozbuild

MOZILLABUILD=G:\Tools\MozillaBuild

SCCACHE_DIR=G:\mozbuild\sccache
```

Create:

```text
G:\mozbuild
G:\mozbuild\sccache
```

as required.

## Optional tool locations

When these tools are user-managed outside Firefox bootstrap:

```text
CARGO_HOME=G:\Tools\Rust\Cargo

RUSTUP_HOME=G:\Tools\Rust\Rustup

NVM_HOME=G:\Tools\nvm

NVM_SYMLINK=G:\Tools\nvmmodejs

TEMP=G:\Temp

TMP=G:\Temp
```

Optional:

```text
UV_CACHE_DIR=G:\Tools\uv-cache
```

Do not globally configure:

```text
MOZ_OBJDIR
PYTHON
```

`MOZ_OBJDIR` belongs in the Firefox checkout's `mozconfig`.

`PYTHON` should not be used to force an arbitrary Python installation into the Firefox build.

---

# 7. PATH and MozillaBuild

Do not manually add:

```text
G:\Tools\MozillaBuild\bin
```

to the Windows PATH merely for Firefox builds.

Start MozillaBuild with:

```text
G:\Tools\MozillaBuild\start-shell.bat
```

The startup script prepares the appropriate environment.

Other user-managed tools may require PATH entries.

For example:

```text
G:\Tools\Rust\Cargo\bin
G:\Tools\nvmmodejs
```

may be placed in PATH if those tools are intentionally managed there.

Do not replace the whole Windows PATH.

Avoid unrelated Cygwin/MSYS installations taking precedence over MozillaBuild tools.

Do not place quotation marks around individual PATH entries.

Use:

```text
G:\Tools\Rust\Cargo\bin
```

not:

```text
"G:\Tools\Rust\Cargo\bin"
```

---

# 8. Fresh Firefox checkout

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

The source tree is:

```text
R:\firefox
```

Do not place the Firefox source on another volume.

---

# 9. Bootstrap Firefox

From:

```text
R:\firefox
```

run:

```bash
./mach bootstrap
```

Follow the Firefox bootstrap prompts.

The bootstrap process prepares the compiler and other dependencies required by the Firefox checkout.

---

# 10. Configure `mozconfig`

Create:

```text
R:\firefox\mozconfig
```

Use:

```bash
mk_add_options MOZ_OBJDIR=@TOPSRCDIR@/../firefox-obj
ac_add_options --with-ccache=sccache
```

The resulting layout is:

```text
R:\firefox
R:\firefox-obj
```

Both are on the same VHDX.

---

# 11. Install GARP into Firefox

This is a **source-tree integration step**, not a normal Firefox add-on installation.

Copy:

```text
browser/components/aistarter/
```

from this repository into:

```text
R:\firefox\browser\components\aistarter\
```

The package contains:

```text
aistarter\
    AIAutomation.sys.mjs
    moz.build

    actors\
    diagnostics\
    garp\
    providers\
    requests\
    sessions\
```

There is **one and only one** `moz.build` in the GARP component: `aistarter\moz.build`.

There are no `moz.build` files under `actors`, `diagnostics`, `garp`, `providers`, `requests`, or `sessions`.

Do not flatten the directory structure.

The GARP component uses the proven `EXTRA_JS_MODULES` packaging technique. The component does **not** use `FINAL_TARGET`, `FINAL_TARGET_FILES`, or child-directory `DIRS` for its internal JavaScript directories.

The relevant part of `aistarter\moz.build` is structured as:

```python
EXTRA_JS_MODULES.aistarter += [
    "AIAutomation.sys.mjs",
]

EXTRA_JS_MODULES.aistarter.actors += [
    "actors/AIAutomationChild.sys.mjs",
    "actors/AIAutomationParent.sys.mjs",
]

EXTRA_JS_MODULES.aistarter.diagnostics += [
    "diagnostics/AIAutomationDiagnostics.sys.mjs",
]

EXTRA_JS_MODULES.aistarter.garp += [
    # GARP modules...
]

EXTRA_JS_MODULES.aistarter.providers += [
    # Provider modules...
]

EXTRA_JS_MODULES.aistarter.requests += [
    # Request modules...
]

EXTRA_JS_MODULES.aistarter.sessions += [
    # Session modules...
]
```

With the working Firefox configuration, these modules are expected under:

```text
R:\firefox-obj\dist\bin\modules\aistarter\
```

The actor pair is therefore also packaged below:

```text
R:\firefox-obj\dist\bin\modules\aistarter\actors\
```

---

# 12. Register the component

Edit:

```text
R:\firefox\browser\components\moz.build
```

Add:

```python
"aistarter",
```

to the existing `DIRS` list.

The supplied `aistarter\moz.build` packages the component's JavaScript files directly. It does not use `DIRS` to descend into `actors`, `diagnostics`, `garp`, `providers`, `requests`, or `sessions`.

Do not replace Firefox's complete `browser/components/moz.build`.

---

# 13. Start AIAutomationService

Use:

```text
integration\BrowserGlue.integration.txt
```

from this repository as the integration reference.

The intended startup sequence is:

```text
Firefox startup
        |
        +-- load AIAutomation.sys.mjs
        |
        +-- create exactly one AIAutomationService
        |
        +-- initialize/start GARP
```

The service module URL is:

```text
resource:///modules/aistarter/AIAutomation.sys.mjs
```

Do not create multiple service instances.

The exact BrowserGlue insertion point depends on the Firefox checkout.

---

# 14. Register the JSWindowActor

Register:

```text
AIAutomation
```

with:

```text
AIAutomationParent.sys.mjs
AIAutomationChild.sys.mjs
```

Use the Firefox checkout's existing `JSWINDOWACTORS` registry; do not create a second registry for GARP.

The registration must use these runtime module URLs:

```javascript
AIAutomation: {
  parent: {
    esModuleURI:
      "resource:///modules/aistarter/actors/AIAutomationParent.sys.mjs",
  },
  child: {
    esModuleURI:
      "resource:///modules/aistarter/actors/AIAutomationChild.sys.mjs",
  },
  allFrames: true,
  safeForUntrustedWebProcess: true,
},
```

The actor name must match:

```text
AIAutomation
```

The parent-side code obtains the actor with:

```javascript
windowGlobal.getActor("AIAutomation")
```

Do **not** use the old URLs:

```text
resource:///modules/aistarter/actors/AIAutomationParent.sys.mjs
resource:///modules/aistarter/actors/AIAutomationChild.sys.mjs
```

for this package. The actors are packaged as `EXTRA_JS_MODULES.aistarter.actors` modules.

---

# 15. Configure the GARP shared secret

Set:

```text
GARP_SECRET
```

to a deployment-provisioned secret containing at least 32 raw bytes.

For protocol testing:

```text
0123456789abcdef0123456789abcdef
```

From MozillaBuild:

```bash
export GARP_SECRET="0123456789abcdef0123456789abcdef"
```

Never commit production secrets to the source tree.

---

# 16. Build Firefox

From:

```text
R:\firefox
```

run:

```bash
./mach build -j8
```

The object/build output should appear under:

```text
R:\firefox-obj
```

---

# 17. Low-heat builds with `-j8`

The recommended build command is:

```bash
./mach build -j8
```

The `-j` option controls build parallelism.

`-j8` allows approximately eight normal build jobs to run concurrently.

It does not guarantee that only eight operating-system threads will ever exist because individual compiler and helper processes may create additional threads.

The purpose is to reduce sustained build load.

Typical settings:

```text
-j2
    coolest
    slowest

-j4
    low load
    slower

-j8
    moderate load
    recommended

-j16
    higher throughput
    higher sustained load
```

The project's recommended setting is:

```text
-j8
```

because it is a practical compromise between build time and sustained CPU heat/noise.

---

# 18. Verify GARP packaging

Before starting Firefox, verify that the application output contains:

```text
R:\firefox-obj\dist\bin\modules\aistarter\AIAutomation.sys.mjs
R:\firefox-obj\dist\bin\modules\aistarter\garp\GarpRegistry.sys.mjs
R:\firefox-obj\dist\bin\modules\aistarter\providers\ProviderRegistry.sys.mjs
R:\firefox-obj\dist\bin\modules\aistarter\requests\GarpRequestManager.sys.mjs
R:\firefox-obj\dist\bin\modules\aistarter\sessions\AIAutomationSessionManager.sys.mjs
R:\firefox-obj\dist\bin\modules\aistarter\diagnostics\AIAutomationDiagnostics.sys.mjs
R:\firefox-obj\dist\bin\modules\aistarter\actors\AIAutomationParent.sys.mjs
R:\firefox-obj\dist\bin\modules\aistarter\actors\AIAutomationChild.sys.mjs
```

These correspond to:

```text
resource:///modules/aistarter/...
```

The actor modules correspond to:

```text
resource:///modules/aistarter/actors/...
```

The main module must not be installed under:

```text
R:\firefox-obj\dist\bin\browser\modules\aistarter\AIAutomation.sys.mjs
```

If `AIAutomation.sys.mjs` is not present under `dist\bin\modules\aistarter`, fix `browser\components\aistarter\moz.build` before investigating BrowserGlue or actor registration.

---

# 19. Run Firefox

After a successful build:

```bash
export GARP_SECRET="0123456789abcdef0123456789abcdef"
./mach run
```

Firefox will launch from the locally built object directory.

The GARP service will be part of that custom Firefox build once the required source integration has been completed.

---

# 20. Test the GARP component

The protocol-level test does not require the complete Firefox runtime.

From the GARP repository:

```bash
node tests/Garp124Conformance.mjs
```

Expected:

```text
GARP/1.24 hybrid conformance vectors: PASS
```

For an end-to-end test, use a GARP client to connect to the Firefox gateway.

The default listener is:

```text
127.0.0.1:9999
```

Live integration should verify, at minimum:

```text
AIAutomationService startup
GARP handshake
CAPABILITIES
BROWSER_STATUS
JSWindowActor creation
provider inspection
CREATE_SESSION
PROMPT
streaming/terminal events
```

---

# 21. Incremental development

After modifying GARP source files:

```bash
cd /r/firefox
./mach build -j8
```

Restart Firefox:

```bash
./mach run
```

Do not automatically delete the object directory after every change.

If Firefox explicitly requires a clean build:

```bash
./mach clobber
./mach build -j8
```

---

# 22. Updating Firefox

Before updating the checkout:

```bash
cd /r/firefox
git status
git diff
```

Preserve local GARP changes.

Then:

```bash
git pull origin main
```

Rebuild:

```bash
./mach build -j8
```

Avoid destructive commands such as:

```bash
git reset --hard
git clean -fdx
```

unless you deliberately intend to discard local work.

---

# 23. VHDX backup

The Firefox source and Firefox object directory are contained in:

```text
G:\FileDiskImages\FireFoxDevelopmentV1.vhdx
```

When the VHDX is mounted as:

```text
R:
```

the corresponding directories are:

```text
R:\firefox
R:\firefox-obj
```

Backing up the VHDX therefore captures the Firefox source and object/build tree contained inside it.

The separate physical `G:` directories:

```text
G:\Tools\MozillaBuild
G:\mozbuild
G:\mozbuild\sccache
G:\Temp
```

are outside the VHDX and need separate backup if they are important.

---

# 24. Troubleshooting

## VHDX is not available

Verify that:

```text
G:\FileDiskImages\FireFoxDevelopmentV1.vhdx
```

exists and is mounted as:

```text
R:
```

---

## Firefox source is on the wrong drive

The intended source location is:

```text
R:\firefox
```

The intended object location is:

```text
R:\firefox-obj
```

Both must be on the Firefox development VHDX.

---

## Object directory is on the wrong drive

Check:

```text
R:\firefox\mozconfig
```

for:

```bash
mk_add_options MOZ_OBJDIR=@TOPSRCDIR@/../firefox-obj
```

Also check that `MOZ_OBJDIR` is not globally defined in Windows.

---

## MozillaBuild commands are unavailable

Start:

```text
G:\Tools\MozillaBuild\start-shell.bat
```

Do not rely on a normal Windows command prompt having MozillaBuild's internal tools configured.

Do not add:

```text
G:\Tools\MozillaBuild\bin
```

to PATH merely to compensate.

---

## Python is unavailable

Firefox uses Python during the build.

First verify that MozillaBuild was started through:

```text
G:\Tools\MozillaBuild\start-shell.bat
```

Then:

```bash
which python
```

Do not force a different Python installation with a global `PYTHON` variable.

---

## sccache is unavailable

Verify:

```text
SCCACHE_DIR=G:\mozbuild\sccache
```

Then:

```bash
which sccache
```

Also verify that `mozconfig` contains:

```bash
ac_add_options --with-ccache=sccache
```

---

## Build is too hot

Use:

```bash
./mach build -j4
```

or:

```bash
./mach build -j2
```

Lower `-j` values reduce parallelism at the cost of build speed.

---

## Build is unexpectedly slow

Check that:

```text
R:\firefox
R:\firefox-obj
```

are on the intended VHDX.

Check:

```text
G:\mozbuild\sccache
```

is available.

Also check antivirus activity on the Firefox source/object directories and build-tool directories.

---

## `AIAutomation.sys.mjs` cannot be found

First verify the physical application output:

```text
R:\firefox-obj\dist\bin\modules\aistarter\AIAutomation.sys.mjs
```

The runtime URL is:

```text
resource:///modules/aistarter/AIAutomation.sys.mjs
```

Do not use:

```text
resource:///modules/aistarter/AIAutomation.sys.mjs
```

with a file installed under `dist\bin\browser\modules\aistarter`.

If the physical file is missing, inspect:

```text
R:\firefox\browser\components\aistarter\moz.build
```

and ensure it uses `EXTRA_JS_MODULES.aistarter` rather than `FINAL_TARGET` or `FINAL_TARGET_FILES`.

---

## JavaScript actor cannot be found

Verify:

```text
AIAutomationParent.sys.mjs
AIAutomationChild.sys.mjs
```

exist under:

```text
R:\firefox-obj\dist\bin\modules\aistarter\actors\
```

and that the actor registration uses:

```text
AIAutomation
resource:///modules/aistarter/actors/AIAutomationParent.sys.mjs
resource:///modules/aistarter/actors/AIAutomationChild.sys.mjs
```

Do not use `resource:///actors/...` for this package.

---

## GARP authentication fails

Verify:

```text
GARP_SECRET
```

is set in the environment from which Firefox was launched.

Also verify that the configured secret is at least 32 raw bytes and that the client is using the same deployment secret.

---

## Provider automation fails

Inspect the corresponding adapter under:

```text
providers\
```

Provider websites can change their DOM independently of this project.

---

# 25. Recommended final environment

The physical `G:` drive:

```text
G:\
├── FileDiskImages\
│   └── FireFoxDevelopmentV1.vhdx
│
├── Tools\
│   ├── MozillaBuild\
│   ├── Rust\
│   └── nvm\
│
├── mozbuild\
│   └── sccache\
│
└── Temp\
```

The mounted VHDX:

```text
R:\
├── firefox\
│   ├── mozconfig
│   ├── mach
│   ├── browser\
│   ├── dom\
│   └── ...
│
└── firefox-obj\
```

Environment:

```text
MOZBUILD_STATE_PATH=G:\mozbuild
MOZILLABUILD=G:\Tools\MozillaBuild
SCCACHE_DIR=G:\mozbuild\sccache
```

Optional:

```text
CARGO_HOME=G:\Tools\Rust\Cargo
RUSTUP_HOME=G:\Tools\Rust\Rustup

NVM_HOME=G:\Tools\nvm
NVM_SYMLINK=G:\Tools\nvmmodejs

TEMP=G:\Temp
TMP=G:\Temp

UV_CACHE_DIR=G:\Tools\uv-cache
```

Do not globally configure:

```text
MOZ_OBJDIR
PYTHON
```

Firefox `mozconfig`:

```bash
mk_add_options MOZ_OBJDIR=@TOPSRCDIR@/../firefox-obj
ac_add_options --with-ccache=sccache
```

Start MozillaBuild:

```text
G:\Tools\MozillaBuild\start-shell.bat
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

---

# 26. Official references

Firefox Windows build:

https://firefox-source-docs.mozilla.org/setup/windows_build.html

Firefox build configuration:

https://firefox-source-docs.mozilla.org/setup/configuring_build_options.html

Firefox JSWindowActors:

https://firefox-source-docs.mozilla.org/dom/ipc/jsactors.html

Firefox sccache:

https://firefox-source-docs.mozilla.org/build/buildsystem/sccache-dist.html

Windows VHD/VHDX management:

https://learn.microsoft.com/en-us/windows-server/storage/disk-management/manage-virtual-hard-disks

Windows disk initialization:

https://learn.microsoft.com/en-us/windows-server/storage/disk-management/initialize-new-disks

---

# 27. Final rules

```text
1. VHDX:
   G:\FileDiskImages\FireFoxDevelopmentV1.vhdx

2. Mount VHDX as:
   R:

3. Firefox source:
   R:\firefox

4. Firefox object/build output:
   R:\firefox-obj

5. Keep source and object output on the same volume.

6. MozillaBuild:
   G:\Tools\MozillaBuild

7. Start MozillaBuild with:
   G:\Tools\MozillaBuild\start-shell.bat

8. Do not manually add:
   G:\Tools\MozillaBuild\bin
   to PATH merely for Firefox builds.

9. Mozilla build state:
   G:\mozbuild

10. sccache:
    G:\mozbuild\sccache

11. Do not globally set:
    MOZ_OBJDIR

12. Do not globally set:
    PYTHON

13. Configure MOZ_OBJDIR locally in:
    R:\firefox\mozconfig

14. Use:
    ./mach build -j8

    for the normal low-heat build.

15. GARP is integrated into the Firefox source tree.
    It is not installed as a normal Firefox WebExtension.

16. GARP JavaScript is packaged with one component moz.build
    using EXTRA_JS_MODULES.* namespaces.

17. Do not add subordinate GARP moz.build files.

18. Do not use FINAL_TARGET or FINAL_TARGET_FILES for this component.

19. The actor runtime URLs are:
    resource:///modules/aistarter/actors/...

20. Keep production GARP secrets outside the source tree.

21. The GARP/1.24 specification remains authoritative
    for protocol behavior.
```
