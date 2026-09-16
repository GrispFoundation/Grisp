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

Firefox places these namespaces below its JavaScript module target as:

  $(FINAL_TARGET)/modules/aistarter/

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
