# GRISP Trust Model v0.1

**Specification status:** Draft  
**Layer:** AI Substrate IR (Layer 1)  
**Depends on:** GRISP Canonical IR v1.2, Boundary Contract v0.1  
**Author:** Skybuck / GRISP Project  
**Date:** 2026-06-10  

---

## 1. Purpose

This document defines the trust model for the GRISP AI substrate layer. It specifies:

- How values acquire trust levels
- How trust levels propagate through the IR pipeline
- How trust levels constrain action execution
- How trust levels interact with capability boundaries
- How trust violations are reported

The trust model is the mechanism by which the GRISP substrate tracks the provenance
and reliability of every value that flows from LLM output through the rule engine to
tool execution and back.

---

## 2. Motivation

Values in a GRISP substrate pipeline originate from fundamentally different sources
with different reliability and safety properties:

- An LLM may assert a database query string that was never validated
- A tool may return a user ID that was verified by an external system
- A human operator may explicitly confirm a destructive action
- The engine itself may derive a value deterministically from other trusted values

Treating all these values identically creates two failure modes:

1. **Under-restriction**: an LLM-asserted value is passed directly to a destructive
   tool without verification, enabling prompt injection or hallucination-driven damage.
2. **Over-restriction**: a system-derived value from a verified computation is blocked
   because the pipeline cannot distinguish it from an unverified LLM assertion.

The trust model solves this by attaching provenance metadata to individual values and
propagating it compositionally through every operation.

---

## 3. Trust Levels

Trust levels form a strict partial order. Higher trust levels permit more operations.

### 3.1 Level Definitions

| Trust Level        | Code | Description |
|--------------------|------|-------------|
| `llm_asserted`     | 0    | Value was produced by an LLM and has not been independently verified. Lowest trust. |
| `tool_returned`    | 1    | Value was returned by a tool execution. Trust is conditional on the tool's own trust classification (see §6). |
| `system_derived`   | 2    | Value was computed deterministically by the GRISP engine from other values. Trust is inherited compositionally (see §5). |
| `human_confirmed`  | 3    | Value was explicitly confirmed by a human operator. Highest trust. |

### 3.2 Ordering

```
llm_asserted < tool_returned < system_derived < human_confirmed
```

This ordering defines the **minimum trust** operator used in composition (§5).

### 3.3 Special Cases

**`unknown`**: A value whose provenance cannot be determined. Treated as `llm_asserted`
for all trust decisions. Engines must not silently promote `unknown` to a higher level.

**`system_derived` from `llm_asserted` inputs**: If a `system_derived` value is computed
from one or more `llm_asserted` inputs, its effective trust level is `llm_asserted`, not
`system_derived`. See §5 for full composition rules.

---

## 4. Trust Annotations in the IR

### 4.1 Annotating Fact Nodes

Every fact node in the Canonical IR may carry a `_trust` field at the top level and
optionally on individual field values.

**Top-level trust** applies to the entire fact as a default:

```json
{
  "type": "Task",
  "id": "task-001",
  "lifecycle": "pending",
  "_trust": {
    "level": "tool_returned",
    "source": "task-service",
    "acquired_at": "2026-06-10T12:00:00Z",
    "session_turn": 3
  }
}
```

**Field-level trust** overrides the top-level trust for specific fields:

```json
{
  "type": "Task",
  "id": "task-001",
  "lifecycle": "pending",
  "query_override": "SELECT * FROM secrets",
  "_trust": {
    "level": "tool_returned",
    "source": "task-service"
  },
  "_field_trust": {
    "query_override": {
      "level": "llm_asserted",
      "source": "llm:gpt-session-42",
      "session_turn": 3
    }
  }
}
```

Field-level trust takes precedence over top-level trust for any operation that reads
that specific field.

### 4.2 Trust Annotation Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "TrustAnnotation",
  "type": "object",
  "required": ["level"],
  "additionalProperties": false,
  "properties": {
    "level": {
      "type": "string",
      "enum": ["llm_asserted", "tool_returned", "system_derived", "human_confirmed", "unknown"]
    },
    "source": {
      "type": "string",
      "description": "Identifier of the originating system, model, tool, or operator."
    },
    "acquired_at": {
      "type": "string",
      "format": "date-time",
      "description": "When this trust annotation was assigned."
    },
    "session_turn": {
      "type": "integer",
      "minimum": 0,
      "description": "The session turn index at which this value was introduced."
    },
    "trace_id": {
      "type": "string",
      "description": "Links to a resolution_trace entry for this value's provenance."
    },
    "promoted_by": {
      "type": "string",
      "description": "If trust was promoted (e.g. by human confirmation), the operator or mechanism that did so."
    },
    "promotion_reason": {
      "type": "string",
      "description": "Human-readable reason for trust promotion."
    }
  }
}
```

### 4.3 Annotating Expression AST Nodes

For values within the expression AST (Canonical IR v1.2), trust annotations attach
to the `meta` field which is already defined as extensible:

```json
{
  "kind": "field",
  "var": "Task",
  "field": "query_override",
  "meta": {
    "trust": {
      "level": "llm_asserted",
      "source": "llm:session-42",
      "session_turn": 3
    }
  }
}
```

Engines that perform trust-aware execution must read trust from `meta.trust` when
present. Engines that do not implement trust-aware execution must ignore `meta.trust`
(per the existing Canonical IR requirement that unknown meta fields be ignored).

---

## 5. Trust Propagation Rules

Trust propagates compositionally through every operation the engine performs.
The fundamental principle is: **a composed value can never be more trusted than
its least-trusted input**.

### 5.1 The Minimum Trust Operator

For any operation that combines values v₁, v₂, ..., vₙ:

```
trust(result) = min(trust(v₁), trust(v₂), ..., trust(vₙ))
```

Where `min` uses the ordering defined in §3.2.

### 5.2 Propagation by Operation Type

**Arithmetic and string operations**

```
let NewCapacity = Specialist.capacity_used + Cost
```

If `capacity_used` is `tool_returned` and `Cost` is `llm_asserted`, then
`NewCapacity` is `llm_asserted`.

**Field access**

```
Task.query_override
```

Trust of the accessed field is the field-level trust if present, otherwise the
top-level trust of the containing fact.

**Function calls**

```
call CanExecute(Specialist, Task)
```

Result trust is `min(trust(Specialist), trust(Task))` unless `CanExecute` is
a declared effect function with its own trust policy (see §6.2).

**Collection operations (for, filter, map)**

The trust of any value produced by iterating a collection is `min(trust(collection),
trust(element))` for each element.

**Conditional expressions**

```
if cond then a else b
```

Result trust is `min(trust(cond), trust(a), trust(b))`.

This is conservative: even if only one branch executes, the engine cannot know at
compile time which branch will be taken, so both must contribute to result trust.

### 5.3 Explicit Trust Promotion

Trust can only be promoted by an explicit `confirm` action (see §7.3). Promotions
are recorded in the resolution trace and carry a `promoted_by` annotation.

Engines must reject any implicit trust promotion — that is, any situation where a
computed result would have higher trust than its minimum-trust input without an
explicit confirm action in the rule.

### 5.4 Trust Isolation for `system_derived`

A value is `system_derived` only if:

1. It was computed entirely from other `system_derived` or `human_confirmed` values, AND
2. The computation itself is a deterministic pure function

If either condition is false, the value is NOT `system_derived`. The level falls to
the minimum of its inputs per §5.1.

---

## 6. Tool Trust Classification

Tools themselves have trust classifications that affect how their return values are
annotated.

### 6.1 Tool Trust Classes

| Class        | Description | Returned Value Trust |
|--------------|-------------|----------------------|
| `verified`   | Tool is a known, controlled system with stable contracts | `tool_returned` |
| `external`   | Tool calls an external API or service outside the system boundary | `tool_returned` |
| `llm_facing` | Tool's inputs are directly shaped by LLM output (e.g. a query builder) | `llm_asserted` |
| `privileged` | Tool has destructive, irreversible, or high-impact effects | Requires `human_confirmed` inputs |

### 6.2 Tool Trust Declarations in G-Blocks

Tool definitions must declare their trust class:

```
node tool.database.query {
    query: string
    returns: array<Row>
    trust_class: identifier = trust.llm_facing
    side_effects: identifier = effects.read
    requires_input_trust: identifier = trust.human_confirmed
}
```

The `requires_input_trust` field declares the minimum trust level required for
each input. If any input falls below this threshold, the engine must either:

1. Emit a `clarify` action requesting trust elevation, or
2. Reject the action with a `TRUST_VIOLATION` error

### 6.3 Trust Downgrade for `llm_facing` Tools

When a tool is classified `llm_facing`, its return values are annotated `llm_asserted`
regardless of the tool's internal verification, because the tool's output is considered
shaped by the LLM input. This prevents laundering untrusted values through a tool call.

---

## 7. Trust-Gated Actions

Certain actions in the GRISP rule engine are gated by trust requirements.

### 7.1 Default Trust Gates

| Action Type | Minimum Input Trust Required |
|-------------|------------------------------|
| `update`    | `tool_returned`              |
| `create`    | `tool_returned`              |
| `delete`    | `human_confirmed`            |
| `call`      | Determined by tool's `requires_input_trust` |
| `emit`      | `llm_asserted` (no gate)     |
| `clarify`   | `llm_asserted` (no gate)     |

These defaults can be overridden in the runtime profile (see §7.2).

### 7.2 Runtime Profile Overrides

The runtime profile may declare per-rule trust gate overrides:

```json
{
  "rules": {
    "AssignPendingTask": {
      "trust_gates": {
        "update": "human_confirmed",
        "create": "tool_returned"
      }
    }
  }
}
```

This allows production deployments to enforce stricter gates than the defaults
for sensitive rules.

### 7.3 The `confirm` Action

The `confirm` action is a new first-class action that promotes the trust level of
a named value, subject to operator approval. It does not execute directly — it
produces a pending confirmation request that must be resolved by a human operator
before execution continues.

**Syntax (rule manifest):**

```json
{
  "confirm": "Task.query_override",
  "required_level": "human_confirmed",
  "reason": "Query string was LLM-asserted and targets a privileged tool",
  "timeout_ms": 300000,
  "on_timeout": "fail"
}
```

**Semantics:**

1. Engine emits a `confirm_request` event with the named value and reason.
2. Execution of the current rule is suspended.
3. When the operator approves, the trust annotation on the named value is updated
   to `human_confirmed` with `promoted_by` set to the operator identity.
4. The rule re-evaluates with the promoted value.
5. If the operator rejects, the rule fails with `TRUST_PROMOTION_REJECTED`.
6. If `timeout_ms` elapses without response, `on_timeout` governs behaviour.

---

## 8. Taint Tracking

Taint tracking is the runtime enforcement of trust propagation. Where §5 defines
the rules, this section defines how engines track them.

### 8.1 Taint Tags

Every value in the engine's working memory carries a taint tag alongside its data
value. The taint tag is a trust annotation (§4.2). Taint tags are:

- Initialized when a fact enters the engine (from the `GrispExecutionRequest`)
- Updated compositionally on every operation (per §5)
- Checked at every trust-gated action (per §7)
- Recorded in the resolution trace on every update

### 8.2 Taint Propagation for `llm_asserted`

Because `llm_asserted` is the minimum trust level, any computation that touches
an `llm_asserted` value produces an `llm_asserted` result. This means a single
LLM-originated value can taint an entire downstream computation.

This is intentional. The solution is not to weaken propagation but to use explicit
`confirm` actions at the appropriate boundary to elevate trust under human oversight.

### 8.3 Taint Containment Zones

Rules may declare `taint_boundary: true` in their metadata. This indicates that
the rule is explicitly designed to validate and promote untrusted inputs. Rules
with `taint_boundary: true`:

- May accept `llm_asserted` inputs regardless of the default gates
- Must emit only `system_derived` or higher outputs (the engine enforces this)
- Are subject to enhanced audit logging

Example metadata declaration:

```json
{
  "metadata": {
    "taint_boundary": true,
    "idempotent": true,
    "tags": ["validation", "trust-elevation"]
  }
}
```

If a taint boundary rule attempts to emit an `llm_asserted` output, the engine
must reject the action with `TAINT_BOUNDARY_VIOLATION`.

### 8.4 Cross-Rule Taint

When a fact updated by Rule A is later read by Rule B, Rule B inherits the taint
tags on the updated fields. Taint does not reset between rules.

This means taint from an LLM-originated value can propagate across multiple rule
firings. The resolution trace records each propagation hop so the full chain can
be reconstructed for audit.

---

## 9. Trust in the Boundary Contract

The trust model integrates with the boundary contract (spec/boundary-contract-v0.1)
as follows.

### 9.1 Inbound: `GrispExecutionRequest`

The `context` field on the request carries a default trust level for the batch:

```json
{
  "context": {
    "origin": "llm",
    "default_trust_level": "llm_asserted",
    "trust_overrides": [
      {
        "fact_id": "task-001",
        "field": "id",
        "level": "tool_returned",
        "source": "task-service"
      }
    ]
  }
}
```

`trust_overrides` allows the substrate to assert higher trust for specific fields
without elevating the entire request. The engine applies overrides before any rule
evaluation begins.

### 9.2 Outbound: `GrispExecutionResult`

Each action in the result carries the trust level of its payload:

```json
{
  "type": "call",
  "payload": { ... },
  "trust_level": "llm_asserted",
  "trust_blocked": false
}
```

`trust_blocked: true` indicates the action was not executed because a trust gate
prevented it. The substrate must then decide whether to initiate a `confirm` flow
or report the failure to the LLM.

### 9.3 Trust Violations in Results

Trust violations are reported as a distinct category in the result, separate from
runtime errors:

```json
{
  "trust_violations": [
    {
      "rule_id": "AssignPendingTask",
      "action_index": 2,
      "violation_type": "INSUFFICIENT_TRUST" | "TAINT_BOUNDARY_VIOLATION" | "TRUST_PROMOTION_REJECTED",
      "required_level": "tool_returned",
      "actual_level": "llm_asserted",
      "value_path": "Task.query_override",
      "trace_id": "trace-abc-123"
    }
  ]
}
```

---

## 10. Resolution Trace Integration

Every trust decision is recorded in the resolution trace so it can be audited,
debugged, and replayed.

### 10.1 Trust Trace Entry Schema

```json
{
  "trace_id": "string",
  "session_id": "string",
  "session_turn": 12,
  "entries": [
    {
      "seq": 1,
      "kind": "trust_assignment",
      "value_path": "Task.query_override",
      "level": "llm_asserted",
      "source": "llm:session-42",
      "reason": "Value originated from LLM output normalization"
    },
    {
      "seq": 2,
      "kind": "trust_propagation",
      "operation": "binary_op:+",
      "inputs": [
        { "path": "Specialist.capacity_used", "level": "tool_returned" },
        { "path": "Cost", "level": "llm_asserted" }
      ],
      "output": { "path": "NewCapacity", "level": "llm_asserted" },
      "rule": "AssignPendingTask"
    },
    {
      "seq": 3,
      "kind": "trust_gate_check",
      "action": "update",
      "value_path": "Task",
      "required_level": "tool_returned",
      "actual_level": "llm_asserted",
      "result": "blocked",
      "rule": "AssignPendingTask"
    },
    {
      "seq": 4,
      "kind": "trust_promotion",
      "value_path": "Task.query_override",
      "from_level": "llm_asserted",
      "to_level": "human_confirmed",
      "promoted_by": "operator:alice",
      "promotion_reason": "Reviewed query, confirmed safe for execution"
    }
  ]
}
```

### 10.2 Trace Retention

Trust traces are retained according to the `audit` retention tier defined in the
GRISP manifest retention policy. Trust traces must never be pruned below the audit
retention period, regardless of other retention settings.

---

## 11. Interaction with Existing GRISP Constructs

### 11.1 Pattern Matching in `when` Blocks

Trust levels do not affect whether a pattern matches. A fact with `llm_asserted`
fields matches patterns the same as a fully trusted fact. Trust gates are enforced
in the `then` block at action execution time, not at pattern match time.

Rationale: separating match from trust-gate allows rules to inspect untrusted values
(e.g. to emit a `clarify` action) without requiring trust elevation just to read them.

### 11.2 `metadata.reads` and `metadata.writes`

The declared read and write sets in rule metadata implicitly declare trust exposure.
Engines in production mode (`safety.production_mode: true`) should warn when a
declared write set includes fields that may carry `llm_asserted` values based on
static analysis of the rule body.

### 11.3 Policy Inheritance

Policies declared in the manifest (`use: [{ policy: "TimeoutRetry3x" }]`) do not
affect trust levels. A policy governs execution behaviour (retry, rate limit,
circuit breaker) but does not promote or demote trust.

### 11.4 Idempotent Rules

Rules declared `idempotent: true` in metadata may be re-fired on replay. On replay,
the original trust annotations from the resolution trace are restored — trust is not
re-derived from the replayed inputs. This ensures replay fidelity.

---

## 12. Implementation Requirements

### 12.1 Required (MUST)

- Engines MUST maintain taint tags for every value in working memory during rule evaluation.
- Engines MUST apply trust propagation rules (§5) on every operation.
- Engines MUST enforce trust gates (§7) before executing any gated action.
- Engines MUST record trust assignments and propagations in the resolution trace (§10).
- Engines MUST treat `unknown` trust as `llm_asserted`.
- Engines MUST reject implicit trust promotion (any computed result with higher trust than its minimum-trust input, absent an explicit `confirm` action).

### 12.2 Recommended (SHOULD)

- Engines SHOULD perform static analysis to flag rules whose write sets are reachable from `llm_asserted` inputs without a `confirm` or taint boundary.
- Engines SHOULD surface trust levels in debug output and tooling.
- Engines SHOULD warn when a `privileged` tool is called with inputs below `human_confirmed`.

### 12.3 Optional (MAY)

- Engines MAY implement trust-aware query optimisation (e.g. short-circuit pattern matching for untrusted collection bindings).
- Engines MAY expose trust levels via a runtime introspection API.
- Engines MAY implement trust-level metrics for telemetry.

---

## 13. Open Questions

The following questions are deferred to a future revision:

1. **Trust level for tool chains**: If Tool A's output feeds Tool B's input, should
   the substrate model the trust of the chain, or treat each tool call independently?
   Current spec treats each call independently (Tool B's inputs are evaluated at call
   time). A chain model may be necessary for complex multi-tool workflows.

2. **LLM self-reporting trust**: Some LLM outputs include explicit confidence scores.
   Should high-confidence LLM assertions be eligible for automatic trust promotion
   to `tool_returned`? Current spec says no — LLM confidence is not equivalent to
   external verification. This may be revisited with evidence from deployment.

3. **Trust decay over time**: Should `human_confirmed` trust degrade to `tool_returned`
   after a session expires? This has implications for long-running sessions where a
   human approval becomes stale.

4. **Federated trust**: In multi-agent scenarios where one GRISP instance calls another,
   how does trust propagate across the instance boundary? This requires a separate spec.

---

## 14. Summary

| Concept               | Where Defined    | Key Rule |
|-----------------------|------------------|----------|
| Trust levels          | §3               | Strict ordering: llm < tool < system < human |
| Trust annotation      | §4               | Per-value, per-field, in IR meta |
| Trust propagation     | §5               | min(inputs) — never promotes implicitly |
| Tool trust classes    | §6               | llm_facing tools return llm_asserted |
| Trust gates           | §7               | delete requires human_confirmed by default |
| confirm action        | §7.3             | Only explicit path to trust promotion |
| Taint tracking        | §8               | Every value carries a taint tag at runtime |
| Taint boundary rules  | §8.3             | Validation rules that sanitize untrusted inputs |
| Boundary contract     | §9               | trust_overrides on request, trust_blocked on result |
| Resolution trace      | §10              | Immutable audit record of every trust decision |

---

*End of GRISP Trust Model v0.1*
