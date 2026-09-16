Build packaging note
====================

The aistarter JavaScript modules use the same proven EXTRA_JS_MODULES namespace
technique as the earlier working GARP implementation.

There is exactly one component moz.build:

  browser/components/aistarter/moz.build

There are NO moz.build files inside:

  actors/
  diagnostics/
  garp/
  providers/
  requests/
  sessions/

The single file declares:

  EXTRA_JS_MODULES.aistarter
  EXTRA_JS_MODULES.aistarter.actors
  EXTRA_JS_MODULES.aistarter.diagnostics
  EXTRA_JS_MODULES.aistarter.garp
  EXTRA_JS_MODULES.aistarter.providers
  EXTRA_JS_MODULES.aistarter.requests
  EXTRA_JS_MODULES.aistarter.sessions

Firefox places these namespaces below its JavaScript module directory as:

  dist/bin/modules/aistarter/

Expected runtime module URLs:

  resource:///modules/aistarter/AIAutomation.sys.mjs
  resource:///modules/aistarter/actors/AIAutomationParent.sys.mjs
  resource:///modules/aistarter/actors/AIAutomationChild.sys.mjs
  resource:///modules/aistarter/garp/*.sys.mjs
  resource:///modules/aistarter/providers/*.sys.mjs
  resource:///modules/aistarter/requests/*.sys.mjs
  resource:///modules/aistarter/sessions/*.sys.mjs
  resource:///modules/aistarter/diagnostics/*.sys.mjs

Do not use FINAL_TARGET, FINAL_TARGET_FILES, or DIRS for this component.
Do not move the actor modules to a separate actors target.  The actor registry
must use the resource:///modules/aistarter/actors/... URLs shown above.


Runtime timer note
------------------

Parent-side GARP modules run in privileged Firefox module scope and use Firefox
`nsITimer` objects for repeating and delayed work. Do not replace those timers
with bare `setInterval()` or `setTimeout()` calls. Provider-page code may use
the provider document's `window.setTimeout()` where required by the page DOM.


Runtime GARP debug tracing
--------------------------

The Firefox-side GARP implementation includes runtime-switchable diagnostics for
investigating protocol, session, provider, DOM, and generation problems without
attaching a native debugger. Debugging is disabled by default.

Level 1, lifecycle tracing:

  export GARP_DEBUG=1
  ./mach run

Level 2, detailed tracing:

  export GARP_DEBUG=2
  ./mach run

Level 1 records major connection, frame, authentication, session, prompt,
provider, generation, error, and cleanup milestones.

Level 2 additionally records child-actor calls/results, page-generation fencing,
provider selection, DOM selector searches, input discovery, text insertion and
verification, send-button discovery, submission verification, generation
observation, continuation handling, and individual observation iterations.

The diagnostics use Firefox dump() and appear in the Firefox process console.
GARP_DEBUG is an environment variable; it is not a special ./mach run --debug
option.

The intended diagnostic path is:

  connection -> frame -> authentication -> CREATE_SESSION -> SESSION_READY
  -> PROMPT -> provider/input selection -> DOM input -> submission
  -> INPUT_SUBMITTED -> GENERATION_STARTED -> generation observation
  -> GENERATION_DELTA/PROGRESS -> terminal generation event

Large strings and nested values are truncated to limit console volume.
Authentication secrets are never logged. Prompt text is represented by length,
not full contents.
