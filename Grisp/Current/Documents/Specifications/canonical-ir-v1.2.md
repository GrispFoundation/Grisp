Canonical IR v1.2 Specification

This document defines the canonical intermediate representation (IR) that GRISP toolchains must emit and engines must consume. The IR is the single stable contract between parsers, manifest compilers, verifiers, and runtimes. Freeze this IR first — grammar and syntactic sugar may evolve, but the IR must remain stable for cross-engine compatibility.

1. Purpose and design principles
Purpose

Provide a compact, unambiguous, machine-readable representation of GRISP manifests.

Make selection-affecting metadata explicit and verifiable.

Enable deterministic comparison, trace replay, and cross-engine conformance testing.

Design principles

Minimality: include only what engines need to execute deterministically.

Normal form: normalize aliases, expressions, and patterns into structured constraints.

Explicitness: expose inferred reads and writes, ordering, and selection flags.

Stable serialization: canonical JSON encoding and canonical graph hashing for checkpoints.

Extensibility: allow non-breaking additions via optional fields and versioning.

2. Top level IR shape
High level JSON object

json
{
  "ir_version": "grisp-v1.2",
  "manifest_id": "string",
  "manifest_version": "string",
  "nodes": [ ... ],
  "edges": [ ... ],
  "functions": [ ... ],
  "rules": [ ... ],
  "runtime_profile_ref": "string or null",
  "metadata": { ... }
}
Key sections and purpose

nodes: canonical node type declarations and field schemas.

edges: canonical edge type declarations.

functions: function signatures and implementation markers.

rules: fully normalized rule definitions used by the engine.

runtime_profile_ref: pointer to the runtime profile to be merged at execution time.

metadata: manifest level metadata (author, created_at, compatibility).

Field types

Each top level array contains objects with typed fields. The IR uses a small set of primitive types: identifier, string, number, integer, boolean, enum, array, and structured objects.

3. Rules representation and normalization
Rule object shape

json
{
  "name": "AcquireLeaseForPendingTask",
  "priority": 80,
  "metadata": {
    "idempotent": false,
    "depends_on": ["ActivatePlannedTask"],
    "emits": ["LEASE_ACQUIRED"],
    "custom": { /* optional freeform metadata */ }
  },
  "when": [ /* ordered list of normalized patterns */ ],
  "then": [ /* ordered list of normalized actions */ ],
  "hooks": {
    "after_commit": [ /* list of hook identifiers */ ],
    "on_failure": [ /* list of hook identifiers */ ]
  },
  "inferred_reads": ["Task.lifecycle","Task.cost"],
  "inferred_writes": ["Task.lifecycle","Lease"],
  "selection_affecting": true,
  "id": "rule-uuid"
}
Normalization rules

Aliases normalized: A: Agent where role == "Specialist" becomes a binding object { "var":"A", "type":"Agent", "constraints":[{ "field":"role","op":"eq","value":"Specialist" }] }.

Expressions canonicalized: binary expressions are represented as structured AST nodes with explicit operator and operands.

Collections expanded: Completed many Task where ... order by created_at asc, id asc becomes a collection object with explicit order_by array.

Edge patterns normalized: edge has_capability(A -> C) becomes { "edge":"has_capability", "from":"A", "to":"C" }.

Create targets normalized: both create Lease { ... } and create L: Lease { ... } produce a canonical create action with optional result_var.

Reads and writes: manifest-compile must compute inferred_reads and inferred_writes and include them in the IR. If production mode requires explicit sets, the IR must include declared_reads and declared_writes and a boolean declared_sets_required.

Why normalization matters

Engines can optimize and plan from structured constraints rather than raw text.

Deterministic selection and conflict detection rely on explicit read/write sets and normalized patterns.

4. Canonical serialization and graph hashing
Canonical JSON rules

To ensure identical IR bytes across toolchains:

Object key ordering: keys in every JSON object are sorted lexicographically.

Whitespace: use compact JSON with no insignificant whitespace.

Number formatting: integers as digits, floats with minimal decimal digits but deterministic formatting.

String encoding: UTF-8 with JSON escaping; no normalization of Unicode beyond NFC.

Array ordering: arrays are ordered as emitted by manifest-compile and must be preserved.

Graph hashing algorithm (normative)

Used for Checkpoint.graph_hash and conformance checks:

Canonical graph snapshot: produce a canonical JSON object with two top arrays: nodes and edges.

nodes: list of node objects sorted by (type, id) ascending.

edges: list of edge objects sorted by (type, from_id, to_id) ascending.

Node serialization: each node object contains type, id, and a deterministic ordering of fields (field names sorted).

Edge serialization: each edge object contains type, from, to, and sorted attributes.

Canonical JSON: serialize the canonical graph object using the canonical JSON rules above.

Hash: compute SHA-256 over the canonical JSON bytes and encode as lowercase hex string.

Checkpoint example

json
{
  "checkpoint": {
    "tick": 12345,
    "graph_hash": "a3f4...e9b2",
    "created_at": 1680000000,
    "manifest_version": "grisp-v1.2"
  }
}
Why canonical hashing is normative

Engines must be able to compare checkpoints and verify identical graph states across implementations.

Deterministic replay and trace comparison rely on canonical graph hashes.

5. Validation rules and conformance tests
Static validation performed by manifest-compile

Grammar to IR mapping: ensure all AST constructs map to IR forms.

Type checking: field types, enum values, and function signatures.

Function category checks: forbid nondeterministic functions in when.

Reads/writes inference: compute inferred_reads and inferred_writes.

Production mode enforcement: require declared_reads/declared_writes for selection-affecting rules.

Lease invariant warnings: detect rules that could violate SingleActiveLeasePerTask and warn or fail depending on mode.

Capability closure checks: detect cycles in capability_extends and warn.

Runtime validation performed by engines

Lease invariants: enforce single active lease per task, epoch monotonicity, expiry invariant atomically.

Transaction atomicity: apply rewrites with canonical locking and rollback on failure.

Conflict detection: use inferred_writes and declared_writes to prevent concurrent conflicting transactions.

Event ordering metadata: emit tick_number, transaction_commit_sequence, and event_index with each Event.

Conformance test suite

Reference scheduler tests: canonical scenarios that exercise priority, fairness, matchAge boosting, and conflict resolution. Engines claiming reference compatibility must reproduce the canonical event traces.

Lease churn tests: concurrent acquire/renew/steal scenarios verifying epoch monotonicity and no double active leases.

Checkpoint and replay tests: create checkpoint at tick N, restore, and reproduce trace from N+1 to N+K.

Manifest-compile tests: ensure parsers produce identical IR for canonical source examples.

6. Examples
AcquireLease rule in canonical IR

json
{
  "name": "AcquireLeaseForPendingTask",
  "priority": 80,
  "metadata": {
    "idempotent": false,
    "depends_on": ["ActivatePlannedTask"],
    "emits": ["LEASE_ACQUIRED"]
  },
  "when": [
    {
      "kind": "binding",
      "var": "Task",
      "type": "Task",
      "constraints": [
        { "field": "lifecycle", "op": "eq", "value": "pending" },
        { "field": "cost", "op": "bind", "var": "Cost" }
      ]
    },
    {
      "kind": "binding",
      "var": "Agent",
      "type": "Agent",
      "constraints": [
        { "field": "role", "op": "eq", "value": "Specialist" }
      ]
    },
    {
      "kind": "edge",
      "edge": "has_capability",
      "from": "Agent",
      "to": "Cap"
    },
    {
      "kind": "edge",
      "edge": "requires_capability",
      "from": "Task",
      "to": "Cap"
    },
    {
      "kind": "existence",
      "exists": false,
      "pattern": {
        "kind": "binding",
        "var": "L",
        "type": "Lease",
        "constraints": [
          { "field": "task", "op": "eq_var", "var": "Task" },
          { "field": "status", "op": "eq", "value": "active" }
        ]
      }
    }
  ],
  "then": [
    {
      "kind": "create",
      "type": "Lease",
      "result_var": "NewLease",
      "fields": {
        "id": { "expr": { "fn": "NewId", "args": [] } },
        "task": { "expr": { "var": "Task" } },
        "agent": { "expr": { "var": "Agent" } },
        "created_at": { "expr": { "var": "TickStartTime" } },
        "renewed_at": { "expr": { "var": "TickStartTime" } },
        "expires_at": { "expr": { "op": "+", "left": { "var": "TickStartTime" }, "right": 30000 } },
        "status": "active",
        "owner_epoch": { "expr": { "fn": "NextLeaseEpoch", "args": [{ "var": "Task" }] } }
      }
    },
    {
      "kind": "update",
      "target": "Task",
      "assigns": [
        { "field": "lifecycle", "value": "assigned" },
        { "field": "updated_at", "value": { "var": "TickStartTime" } }
      ]
    },
    {
      "kind": "emit",
      "type": "LEASE_ACQUIRED",
      "class": "operational",
      "payload": { "task": { "var": "Task" }, "agent": { "var": "Agent" } }
    }
  ],
  "inferred_reads": ["Task.lifecycle", "Task.cost", "Agent.role"],
  "inferred_writes": ["Task.lifecycle", "Lease"],
  "selection_affecting": true,
  "id": "rule-acquire-0001"
}
Canonical IR manifest snippet

json
{
  "ir_version": "grisp-v1.2",
  "manifest_id": "example-acquire-lease",
  "manifest_version": "1.0.0",
  "nodes": [
    { "name": "Task", "fields": { "id":"identifier", "lifecycle":"string", "cost":"integer" } },
    { "name": "Lease", "fields": { "id":"identifier", "task":"Task", "agent":"Agent", "owner_epoch":"integer", "expires_at":"number", "status":"enum(active,expired,released,stolen)" } }
  ],
  "edges": [
    { "name": "has_capability", "from":"Agent", "to":"Capability" },
    { "name": "requires_capability", "from":"Task", "to":"Capability" }
  ],
  "rules": [ /* rule object above */ ],
  "runtime_profile_ref": "runtime.delphi.yaml"
}
Final notes and next steps
Freeze recommendation

Freeze the Canonical IR v1.2 now. It is the stable contract that enables independent parsers and engines to interoperate.

After IR freeze, finalize the Runtime Profile JSON Schema and the Reference Scheduler test suite.

Offer

If you want, I will now produce one of the following artifacts ready to copy/paste:

Runtime Profile JSON Schema with selection-affecting annotations and scheduler profile fields.

Full Canonical IR JSON Schema (machine readable) for manifest-compile output validation.

Reference Scheduler test suite with canonical scenarios and expected IR traces.

manifest-compile mapping guide from AST to Canonical IR with transformation rules and examples.

Which artifact should I generate next?