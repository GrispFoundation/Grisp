GARP/1.24 Firefox build integration
=================================

The important packaging rule is in:

    browser/components/aistarter/moz.build

It deliberately sets:

    FINAL_TARGET = 'dist/bin'

because browser/moz.build exports DIST_SUBDIR = "browser". Without this override,
Firefox can package the module beneath dist/bin/browser while the source imports it
from resource:///modules/aistarter/....

The aistarter moz.build is intentionally all-in-one. Do not split the module lists
back into child moz.build files unless the final target is kept identical.

Expected output:

    dist/bin/modules/aistarter/AIAutomation.sys.mjs
    dist/bin/modules/aistarter/garp/*.sys.mjs
    dist/bin/modules/aistarter/providers/*.sys.mjs
    dist/bin/modules/aistarter/requests/*.sys.mjs
    dist/bin/modules/aistarter/sessions/*.sys.mjs
    dist/bin/modules/aistarter/diagnostics/*.sys.mjs
    dist/bin/actors/AIAutomationParent.sys.mjs
    dist/bin/actors/AIAutomationChild.sys.mjs
