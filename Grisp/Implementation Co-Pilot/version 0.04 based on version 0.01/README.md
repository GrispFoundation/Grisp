GRISP Delphi Implementation (minimal core)
=========================================

This bundle contains a minimal, production-oriented Delphi implementation of a GRISP
text-processor core: a lexer, a parser for the human-friendly surface language, and
a small deterministic executor that emits canonical events. The implementation is
intended to be used as the deterministic backend for LLM-driven workflows.

Files:
- src/GrispLexer.pas     : deterministic lexer for the surface language
- src/GrispParser.pas    : parser producing a compact AST / canonical IR fragment
- src/GrispExecutor.pas  : deterministic executor applying a small action set
- src/Grisp.pas          : CLI harness that reads GRISP text from stdin and runs it
- docs/grammar.grisp     : the human-friendly surface grammar (normative subset)
- LICENSE                : MIT license

Build
-----
Use Delphi (Embarcadero) or Free Pascal (FPC) compatible compiler. Example (FPC):
  fpc src/Grisp.pas

Run
---
Provide a GRISP program on stdin. The tool prints canonical JSON events to stdout.

Design notes
------------
- Only Delphi/Object Pascal source is included (no Python or other languages).
- The implementation focuses on determinism, readability, and a minimal actionable subset:
  CreateNode, UpdateField, EmitEvent, Query.
- The parser maps the surface language to a compact internal representation; the executor
  performs deterministic actions and emits canonical JSON events.
- Error handling: deterministic INVALID_IR style errors are emitted as JSON and the
  process exits with non-zero status.

Conformance
----------
This implementation is intentionally minimal but follows the v0.58 kernel design:
- deterministic tokenization and parsing
- deterministic ordering of actions
- structured error reporting for invalid IR