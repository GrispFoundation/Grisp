# GSDA/3.1 Delphi implementation baseline

This is a replacement for the previous split V1/V2 scaffold.

## Files

- `GSDA31.pas` — authoritative kernel, state, canonical JSON, identity formulas, peer authentication, intent model, coverage, package construction, revision commit, publication gate.
- `GSDA31_Conformance.dpr` — first conformance harness.

## Design choice

The implementation intentionally has one execution path. Old `GSDAKernel`, `GSDAKernelV2`, `GSDAPublication`, `GSDAPublicationV2`, `GSDACoverage*`, and `GSDATraceability*` units should not be mixed with this implementation.

## Important status

This is a kernel-first implementation baseline, not a claim that every GSDA/3.1 requirement is already complete. The remaining major work is the full typed scorer/reliability subsystem, exact signed-128 aggregation implementation, complete HYBRID intent extractor, full finding/repair/decision stores, authenticated human signature verification, full package/replay machinery, and the complete publication linter.

The purpose of this baseline is to establish one coherent authoritative implementation that later work can extend without preserving the previous V1/V2 semantic contradictions.
