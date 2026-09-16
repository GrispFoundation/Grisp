Build packaging note
====================

The aistarter JavaScript modules are intentionally installed with FINAL_TARGET_FILES,
not EXTRA_JS_MODULES.

The source tree layout must map to these runtime paths:

  dist/bin/modules/aistarter/AIAutomation.sys.mjs
  dist/bin/modules/aistarter/garp/*.sys.mjs
  dist/bin/modules/aistarter/providers/*.sys.mjs
  dist/bin/modules/aistarter/requests/*.sys.mjs
  dist/bin/modules/aistarter/sessions/*.sys.mjs
  dist/bin/modules/aistarter/diagnostics/*.sys.mjs
  dist/bin/actors/AIAutomationParent.sys.mjs
  dist/bin/actors/AIAutomationChild.sys.mjs

This is why the moz.build files use FINAL_TARGET_FILES.modules.aistarter.*.

Do not change these back to EXTRA_JS_MODULES unless the import URLs are changed too.
Firefox's EXTRA_JS_MODULES destination is $(FINAL_TARGET)/modules, whereas the
GARP imports use resource:///modules/aistarter/....
