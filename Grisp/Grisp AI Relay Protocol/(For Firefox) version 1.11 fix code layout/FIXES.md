# GARP/1.24 packaging fix

This package deliberately uses the proven moz.build technique from the older
working GARP implementation.

1. There is exactly one component `moz.build`:
   `browser/components/aistarter/moz.build`.
2. There is no `FINAL_TARGET` override.
3. There are no `FINAL_TARGET_FILES` declarations.
4. There are no subordinate `moz.build` files under actors, diagnostics, garp,
   providers, requests, or sessions.
5. All JavaScript files are packaged through `EXTRA_JS_MODULES` namespaces.
6. The actor pair is therefore exposed as ordinary modules at:
   `resource:///modules/aistarter/actors/...`.
7. The JSWindowActor registry must use those module URLs.
8. `AIAutomation.sys.mjs` remains at
   `resource:///modules/aistarter/AIAutomation.sys.mjs`.

Expected physical application output for the browser target is:

  dist/bin/modules/aistarter/AIAutomation.sys.mjs
  dist/bin/modules/aistarter/actors/AIAutomationParent.sys.mjs
  dist/bin/modules/aistarter/actors/AIAutomationChild.sys.mjs

Do not reintroduce `FINAL_TARGET`, `FINAL_TARGET_FILES`, or nested component
`moz.build` files when integrating this package into the Firefox source tree.


## Runtime correction

Removed the invalid `resource://gre/modules/Services.sys.mjs` import from `AIAutomation.sys.mjs`. Firefox privileged module scope provides `Services` directly. No other `resource://gre/modules/*.sys.mjs` imports are present in the GARP component.
