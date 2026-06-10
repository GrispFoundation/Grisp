Below are **six canonical golden-file examples** (source `.grisp` snippets and their **expected Canonical IR v1.2** outputs). Each pair is a compact, deterministic example you can drop into CI as a golden file for `manifest-compile` tests. The IR is normalized per the Canonical IR v1.2 rules: **every value is an expression node**, `inferred_reads`/`inferred_writes` are present, IDs are deterministic placeholders (implementations compute via `id_generation`), and hooks/events are marked appropriately.

Copy each pair into separate files (e.g., `golden-01-acquire-source.grisp`, `golden-01-acquire-ir.json`) and use them to validate that different compilers produce identical IR bytes.

---

### Example 01 — AcquireLease (basic acquire)

**Source (`AcquireLease.grisp`)**
```grisp
rule AcquireLease priority=80 {
  metadata {
    idempotent = false
    emits = ["LEASE_ACQUIRED"]
  }
  when {
    Task: Task where lifecycle == "pending"
    Agent: Agent where role == "Specialist"
    not exists Lease where Lease.task == Task and Lease.status == "active"
  }
  then {
    create Lease {
      task: Task,
      agent: Agent,
      created_at: TickStartTime,
      renewed_at: TickStartTime,
      expires_at: TickStartTime + 30000,
      status: "active",
      owner_epoch: NextLeaseEpoch(Task)
    }
    update Task { lifecycle: "assigned", updated_at: TickStartTime }
    emit Event(type="LEASE_ACQUIRED", class="operational", payload={ task: Task.id, agent: Agent.id })
  }
}
```

**Canonical IR (`AcquireLease.ir.json`)** (abridged)
```json
{
  "ir_version":"grisp-v1.2",
  "manifest_id":"golden-01-acquire",
  "manifest_version":"1.0.0",
  "id_generation": { "method":"sha256_canonical_json" },
  "nodes":[
    { "name":"Task", "fields": { "id":{"type":"identifier"}, "lifecycle":{"type":"string"}, "updated_at":{"type":"number"} } },
    { "name":"Agent", "fields": { "id":{"type":"identifier"}, "role":{"type":"string"} } },
    { "name":"Lease", "fields": { "id":{"type":"identifier"}, "task":{"type":"Task"}, "agent":{"type":"Agent"}, "created_at":{"type":"number"}, "renewed_at":{"type":"number"}, "expires_at":{"type":"number"}, "status":{"type":{"enum":["active","expired","released","stolen"]}}, "owner_epoch":{"type":"integer"} } }
  ],
  "edges":[
    { "name":"has_capability","from":"Agent","to":"Capability" },
    { "name":"requires_capability","from":"Task","to":"Capability" }
  ],
  "functions":[
    { "name":"NextLeaseEpoch","kind":"pure","signature":"(Task)->integer","external":true }
  ],
  "rules":[
    {
      "id":"rule-acquire-0001",
      "name":"AcquireLease",
      "priority":80,
      "metadata":{"idempotent":false,"emits":["LEASE_ACQUIRED"]},
      "when":[
        { "kind":"binding", "var":"Task", "type":"Task", "constraints":[ { "field":"lifecycle","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"pending" } } ] },
        { "kind":"binding", "var":"Agent", "type":"Agent", "constraints":[ { "field":"role","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"Specialist" } } ] },
        { "kind":"existence", "exists":false, "pattern": {
            "kind":"binding","var":"L","type":"Lease","constraints":[
              { "field":"task","op":"eq_var","var":"Task" },
              { "field":"status","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"active" } }
            ]
          }
        }
      ],
      "then":[
        {
          "kind":"create",
          "type":"Lease",
          "result_var":"NewLease",
          "fields":{
            "id":{ "expr":{ "kind":"call","fn":"NewId","args":[] } },
            "task":{ "expr":{ "kind":"var","name":"Task" } },
            "agent":{ "expr":{ "kind":"var","name":"Agent" } },
            "created_at":{ "expr":{ "kind":"var","name":"TickStartTime" } },
            "renewed_at":{ "expr":{ "kind":"var","name":"TickStartTime" } },
            "expires_at":{ "expr":{ "kind":"binary","op":"+","left":{ "kind":"var","name":"TickStartTime" },"right":{ "kind":"literal","literal_type":"integer","value":30000 } } },
            "status":{ "expr":{ "kind":"literal","literal_type":"string","value":"active" } },
            "owner_epoch":{ "expr":{ "kind":"call","fn":"NextLeaseEpoch","args":[{ "kind":"var","name":"Task" }] } }
          }
        },
        {
          "kind":"update",
          "target":"Task",
          "assigns":[
            { "field":"lifecycle","value":{ "kind":"literal","literal_type":"string","value":"assigned" } },
            { "field":"updated_at","value":{ "kind":"var","name":"TickStartTime" } }
          ]
        },
        {
          "kind":"emit",
          "emit":{
            "type":"LEASE_ACQUIRED",
            "class":"operational",
            "payload":{ "task":{ "kind":"field","var":"Task","field":"id" }, "agent":{ "kind":"field","var":"Agent","field":"id" } },
            "emit_hint":{ "sample_rate":0.01, "aggregate_key":"Task.id" },
            "non_deterministic":false
          }
        }
      ],
      "inferred_reads":["Task.lifecycle","Task.id","Agent.role","Agent.id"],
      "inferred_writes":["Lease","Lease.expires_at","Lease.owner_epoch","Task.lifecycle","Task.updated_at"],
      "declared_reads":null,
      "declared_writes":null
    }
  ],
  "inferred_reads_index": { "Task.lifecycle":["AcquireLease"], "Agent.role":["AcquireLease"] }
}
```

---

### Example 02 — RenewLease (renewal with epoch check)

**Source (`RenewLease.grisp`)**
```grisp
rule RenewLease priority=90 {
  when {
    Lease: Lease where Lease.agent == Agent and Lease.owner_epoch == Epoch and Lease.status == "active"
    Agent: Agent where id == Lease.agent
  }
  then {
    call RenewLeaseEffect(Lease.id, Epoch)  ; effect function performs atomic renew with epoch check
    update Lease { renewed_at: TickStartTime, expires_at: TickStartTime + 30000 }
    emit Event(type="LEASE_RENEWED", class="operational", payload={ lease: Lease.id, epoch: Lease.owner_epoch })
  }
}
```

**Canonical IR (`RenewLease.ir.json`)** (abridged)
```json
{
  "ir_version":"grisp-v1.2",
  "manifest_id":"golden-02-renew",
  "manifest_version":"1.0.0",
  "id_generation":{ "method":"sha256_canonical_json" },
  "nodes":[ /* Task/Agent/Lease as before */ ],
  "functions":[
    { "name":"RenewLeaseEffect","kind":"effect","signature":"(identifier,integer)->void","external":true,
      "effect_meta":{ "idempotent":true, "timeout_ms":5000, "on_timeout":"retry" } }
  ],
  "rules":[
    {
      "id":"rule-renew-0001",
      "name":"RenewLease",
      "priority":90,
      "when":[
        { "kind":"binding","var":"Lease","type":"Lease","constraints":[
            { "field":"agent","op":"eq_var","var":"Agent" },
            { "field":"owner_epoch","op":"eq_var","var":"Epoch" },
            { "field":"status","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"active" } }
          ]
        },
        { "kind":"binding","var":"Agent","type":"Agent","constraints":[ { "field":"id","op":"eq_var","var":"Lease.agent" } ] }
      ],
      "then":[
        { "kind":"call", "call":{ "fn":"RenewLeaseEffect", "args":[ { "kind":"field","var":"Lease","field":"id" }, { "kind":"var","name":"Epoch" } ] } },
        { "kind":"update", "target":"Lease", "assigns":[
            { "field":"renewed_at", "value":{ "kind":"var","name":"TickStartTime" } },
            { "field":"expires_at", "value":{ "kind":"binary","op":"+","left":{ "kind":"var","name":"TickStartTime" },"right":{ "kind":"literal","literal_type":"integer","value":30000 } } }
          ]
        },
        { "kind":"emit", "emit":{ "type":"LEASE_RENEWED", "class":"operational", "payload":{ "lease":{ "kind":"field","var":"Lease","field":"id" }, "epoch":{ "kind":"field","var":"Lease","field":"owner_epoch" } }, "non_deterministic":false } }
      ],
      "inferred_reads":["Lease.agent","Lease.owner_epoch","Lease.status","Lease.id"],
      "inferred_writes":["Lease.renewed_at","Lease.expires_at"]
    }
  ]
}
```

---

### Example 03 — StealLease (steal after heartbeat timeout)

**Source (`StealLease.grisp`)**
```grisp
rule StealLease priority=85 {
  when {
    Lease: Lease where Lease.expires_at < TickStartTime or Lease.heartbeat_at < TickStartTime - 60000
    Agent: Agent where role == "Specialist"
    not exists Lease where Lease.task == Lease.task and Lease.status == "active" and Lease.owner_epoch > Lease.owner_epoch
  }
  then {
    create Lease { task: Lease.task, agent: Agent, created_at: TickStartTime, renewed_at: TickStartTime, expires_at: TickStartTime + 30000, status: "active", owner_epoch: NextLeaseEpoch(Lease.task) }
    update oldLease { status: "stolen" }  ; oldLease is the matched Lease
    emit Event(type="LEASE_STOLEN", class="operational", payload={ old: Lease.id, new: NewLease.id })
  }
}
```

**Canonical IR (`StealLease.ir.json`)** (abridged)
```json
{
  "ir_version":"grisp-v1.2",
  "manifest_id":"golden-03-steal",
  "manifest_version":"1.0.0",
  "nodes":[ /* as before */ ],
  "rules":[
    {
      "id":"rule-steal-0001",
      "name":"StealLease",
      "priority":85,
      "when":[
        { "kind":"binding","var":"Lease","type":"Lease","constraints":[
            { "field":"expires_at","op":"lt","value":{ "kind":"var","name":"TickStartTime" } },
            { "field":"heartbeat_at","op":"lt","value":{ "kind":"binary","op":"-","left":{ "kind":"var","name":"TickStartTime" },"right":{ "kind":"literal","literal_type":"integer","value":60000 } } }
          ]
        },
        { "kind":"binding","var":"Agent","type":"Agent","constraints":[ { "field":"role","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"Specialist" } } ] }
      ],
      "then":[
        {
          "kind":"create",
          "type":"Lease",
          "result_var":"NewLease",
          "fields":{
            "task":{ "expr":{ "kind":"field","var":"Lease","field":"task" } },
            "agent":{ "expr":{ "kind":"var","name":"Agent" } },
            "created_at":{ "expr":{ "kind":"var","name":"TickStartTime" } },
            "renewed_at":{ "expr":{ "kind":"var","name":"TickStartTime" } },
            "expires_at":{ "expr":{ "kind":"binary","op":"+","left":{ "kind":"var","name":"TickStartTime" },"right":{ "kind":"literal","literal_type":"integer","value":30000 } } },
            "status":{ "expr":{ "kind":"literal","literal_type":"string","value":"active" } },
            "owner_epoch":{ "expr":{ "kind":"call","fn":"NextLeaseEpoch","args":[ { "kind":"field","var":"Lease","field":"task" } ] } }
          }
        },
        { "kind":"update", "target":"Lease", "assigns":[ { "field":"status","value":{ "kind":"literal","literal_type":"string","value":"stolen" } } ] },
        { "kind":"emit", "emit":{ "type":"LEASE_STOLEN", "class":"operational", "payload":{ "old":{ "kind":"field","var":"Lease","field":"id" }, "new":{ "kind":"field","var":"NewLease","field":"id" } }, "non_deterministic":false } }
      ],
      "inferred_reads":["Lease.expires_at","Lease.heartbeat_at","Lease.task","Agent.role"],
      "inferred_writes":["Lease.status","Lease","Lease.owner_epoch"]
    }
  ]
}
```

---

### Example 04 — ExpireLease (expiry cleanup)

**Source (`ExpireLease.grisp`)**
```grisp
rule ExpireLease priority=70 {
  when {
    Lease: Lease where Lease.expires_at < TickStartTime and Lease.status == "active"
  }
  then {
    update Lease { status: "expired" }
    emit Event(type="LEASE_EXPIRED", class="operational", payload={ lease: Lease.id })
  }
}
```

**Canonical IR (`ExpireLease.ir.json`)**
```json
{
  "ir_version":"grisp-v1.2",
  "manifest_id":"golden-04-expire",
  "manifest_version":"1.0.0",
  "rules":[
    {
      "id":"rule-expire-0001",
      "name":"ExpireLease",
      "priority":70,
      "when":[
        { "kind":"binding","var":"Lease","type":"Lease","constraints":[
            { "field":"expires_at","op":"lt","value":{ "kind":"var","name":"TickStartTime" } },
            { "field":"status","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"active" } }
          ]
        }
      ],
      "then":[
        { "kind":"update", "target":"Lease", "assigns":[ { "field":"status","value":{ "kind":"literal","literal_type":"string","value":"expired" } } ] },
        { "kind":"emit", "emit":{ "type":"LEASE_EXPIRED", "class":"operational", "payload":{ "lease":{ "kind":"field","var":"Lease","field":"id" } }, "non_deterministic":false } }
      ],
      "inferred_reads":["Lease.expires_at","Lease.status","Lease.id"],
      "inferred_writes":["Lease.status"]
    }
  ]
}
```

---

### Example 05 — Capability Hierarchy (capability_extends + closure hint)

**Source (`Capabilities.grisp`)**
```grisp
node Capability {
  id: identifier
  name: string
}
edge capability_extends(Capability -> Capability)

# Static data (could be loaded as nodes)
# Python -> Programming, Rust -> Programming
```

**Canonical IR (`Capabilities.ir.json`)**
```json
{
  "ir_version":"grisp-v1.2",
  "manifest_id":"golden-05-capabilities",
  "manifest_version":"1.0.0",
  "nodes":[ { "name":"Capability", "fields": { "id":{"type":"identifier"}, "name":{"type":"string"} } } ],
  "edges":[ { "name":"capability_extends", "from":"Capability", "to":"Capability", "acyclic":true } ],
  "capability_hints": { "materialize_closure": true, "closure_refresh_interval_ms": 3600000 }
}
```

---

### Example 06 — Simple Task Flow (depends_on, hooks, declared sets)

**Source (`TaskFlow.grisp`)**
```grisp
rule PlanTask priority=60 {
  metadata { emits = ["TASK_PLANNED"] }
  when { Goal: Goal where status == "new" }
  then {
    create Task { goal: Goal, lifecycle: "pending" }
    emit Event(type="TASK_PLANNED", class="audit", payload={ goal: Goal.id })
  }
}

rule AssignTask priority=50 {
  metadata { depends_on = ["PlanTask"], emits = ["TASK_ASSIGNED"] }
  when {
    Task: Task where lifecycle == "pending"
    Agent: Agent where has_capacity == true
  }
  then {
    create Lease { task: Task, agent: Agent, expires_at: TickStartTime + 60000, owner_epoch: NextLeaseEpoch(Task) }
    update Task { lifecycle: "assigned" }
    emit Event(type="TASK_ASSIGNED", class="operational", payload={ task: Task.id, agent: Agent.id })
  }
}
```

**Canonical IR (`TaskFlow.ir.json`)** (abridged)
```json
{
  "ir_version":"grisp-v1.2",
  "manifest_id":"golden-06-taskflow",
  "manifest_version":"1.0.0",
  "nodes":[ /* Goal, Task, Agent, Lease */ ],
  "rules":[
    {
      "id":"rule-plan-0001",
      "name":"PlanTask",
      "priority":60,
      "metadata":{"emits":["TASK_PLANNED"]},
      "when":[ { "kind":"binding","var":"Goal","type":"Goal","constraints":[ { "field":"status","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"new" } } ] } ],
      "then":[
        { "kind":"create","type":"Task","result_var":"NewTask","fields":{ "goal":{ "expr":{ "kind":"var","name":"Goal" } }, "lifecycle":{ "expr":{ "kind":"literal","literal_type":"string","value":"pending" } } } },
        { "kind":"emit","emit":{ "type":"TASK_PLANNED","class":"audit","payload":{ "goal":{ "kind":"field","var":"Goal","field":"id" } }, "non_deterministic":false } }
      ],
      "inferred_reads":["Goal.status","Goal.id"],
      "inferred_writes":["Task"]
    },
    {
      "id":"rule-assign-0001",
      "name":"AssignTask",
      "priority":50,
      "metadata":{"depends_on":["PlanTask"],"emits":["TASK_ASSIGNED"]},
      "when":[
        { "kind":"binding","var":"Task","type":"Task","constraints":[ { "field":"lifecycle","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"pending" } } ] },
        { "kind":"binding","var":"Agent","type":"Agent","constraints":[ { "field":"has_capacity","op":"eq","value":{ "kind":"literal","literal_type":"boolean","value":true } } ] }
      ],
      "then":[
        { "kind":"create","type":"Lease","result_var":"NewLease","fields":{
            "task":{ "expr":{ "kind":"var","name":"Task" } },
            "agent":{ "expr":{ "kind":"var","name":"Agent" } },
            "expires_at":{ "expr":{ "kind":"binary","op":"+","left":{ "kind":"var","name":"TickStartTime" },"right":{ "kind":"literal","literal_type":"integer","value":60000 } } },
            "owner_epoch":{ "expr":{ "kind":"call","fn":"NextLeaseEpoch","args":[ { "kind":"var","name":"Task" } ] } }
          }
        },
        { "kind":"update","target":"Task","assigns":[ { "field":"lifecycle","value":{ "kind":"literal","literal_type":"string","value":"assigned" } } ] },
        { "kind":"emit","emit":{ "type":"TASK_ASSIGNED","class":"operational","payload":{ "task":{ "kind":"field","var":"Task","field":"id" }, "agent":{ "kind":"field","var":"Agent","field":"id" } }, "non_deterministic":false } }
      ],
      "inferred_reads":["Task.lifecycle","Agent.has_capacity","Task.id","Agent.id"],
      "inferred_writes":["Lease","Task.lifecycle"]
    }
  ]
}
```

---

## How to use these golden files in CI

1. **Place** each source `.grisp` and expected IR `.json` pair in a `golden/` directory.  
2. **Run** your parser + `manifest-compile` to produce `out.ir.json`.  
3. **Normalize** `out.ir.json` using canonical JSON rules (key ordering, compact serialization).  
4. **Compare** bytes to the golden IR file. Any difference indicates a normalization or inference mismatch.  
5. **If** your toolchain supports multiple languages, run the same test across implementations and assert byte-for-byte equality.

---

If you want, I can now:
- Produce **10 more** golden files covering edge cases (concurrent conflicting writes, complex capability closures, nested collections, large manifests), or
- Generate a **small test harness** (shell + Node/Python scripts) that runs `manifest-compile` across multiple toolchains and verifies byte-for-byte equality, or
- Produce **canonical IR golden files with full canonical JSON bytes** (already serialized) for direct byte comparison.

Which of those would you like next?



Below are **ten additional canonical golden-file examples** (source `.grisp` snippets and their expected Canonical IR v1.2 outputs). These cover edge cases and tricky scenarios: conflicting writes, declared read/write enforcement, nondeterministic hooks, effect timeouts, capability closure, nested collections, checkpointing, event sampling, complex ordering, and large-manifest excerpt. Use them in CI to validate `manifest-compile` behavior and IR determinism.

Save each pair as `golden-07-*.grisp` and `golden-07-*.ir.json`, etc.

---

### Example 07 — Conflicting Writes (concurrent updates)

**Source (`ConflictingWrites.grisp`)**
```grisp
rule IncCounterA priority=100 {
  when { Counter: Counter where id == "A" }
  then { update Counter { value: Counter.value + 1 } }
}

rule SetCounterAZero priority=90 {
  when { Counter: Counter where id == "A" and reset == true }
  then { update Counter { value: 0 } }
}
```

**Canonical IR (`ConflictingWrites.ir.json`)** (abridged)
```json
{
  "ir_version":"grisp-v1.2",
  "manifest_id":"golden-07-conflict",
  "manifest_version":"1.0.0",
  "nodes":[ { "name":"Counter", "fields": { "id":{"type":"identifier"}, "value":{"type":"integer"}, "reset":{"type":"boolean"} } } ],
  "rules":[
    {
      "id":"rule-inc-a",
      "name":"IncCounterA",
      "priority":100,
      "when":[ { "kind":"binding","var":"Counter","type":"Counter","constraints":[ { "field":"id","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"A" } } ] } ],
      "then":[ { "kind":"update","target":"Counter","assigns":[ { "field":"value","value":{ "kind":"binary","op":"+","left":{ "kind":"field","var":"Counter","field":"value" },"right":{ "kind":"literal","literal_type":"integer","value":1 } } } ] } ],
      "inferred_reads":["Counter.id","Counter.value"],
      "inferred_writes":["Counter.value"]
    },
    {
      "id":"rule-setzero-a",
      "name":"SetCounterAZero",
      "priority":90,
      "when":[ { "kind":"binding","var":"Counter","type":"Counter","constraints":[ { "field":"id","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"A" } }, { "field":"reset","op":"eq","value":{ "kind":"literal","literal_type":"boolean","value":true } } ] } ],
      "then":[ { "kind":"update","target":"Counter","assigns":[ { "field":"value","value":{ "kind":"literal","literal_type":"integer","value":0 } } ] } ],
      "inferred_reads":["Counter.id","Counter.reset"],
      "inferred_writes":["Counter.value"]
    }
  ]
}
```

---

### Example 08 — Declared Reads/Writes (production mode)

**Source (`DeclaredSets.grisp`)**
```grisp
rule SafeAssign priority=80 {
  metadata { emits = ["SAFE_ASSIGN"] }
  when { Task: Task where lifecycle == "pending" }
  then {
    create Lease { task: Task, agent: Agent, owner_epoch: NextLeaseEpoch(Task) }
    update Task { lifecycle: "assigned" }
    emit Event(type="SAFE_ASSIGN", class="operational", payload={ task: Task.id })
  }
}
```

**Canonical IR (`DeclaredSets.ir.json`)** (abridged; declared sets present)
```json
{
  "ir_version":"grisp-v1.2",
  "manifest_id":"golden-08-declared",
  "manifest_version":"1.0.0",
  "rules":[
    {
      "id":"rule-safeassign-0001",
      "name":"SafeAssign",
      "priority":80,
      "metadata":{"emits":["SAFE_ASSIGN"]},
      "when":[ { "kind":"binding","var":"Task","type":"Task","constraints":[ { "field":"lifecycle","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"pending" } } ] } ],
      "then":[ /* create/update/emit normalized */ ],
      "inferred_reads":["Task.lifecycle","Task.id"],
      "inferred_writes":["Lease","Task.lifecycle"],
      "declared_reads":["Task.lifecycle","Task.id"],
      "declared_writes":["Lease","Task.lifecycle"]
    }
  ]
}
```

---

### Example 09 — Hook with Nondeterministic Function

**Source (`HookNondet.grisp`)**
```grisp
rule NotifyOnAssign priority=40 {
  when { Task: Task where lifecycle == "assigned" }
  then {
    emit Event(type="TASK_ASSIGNED", class="operational", payload={ task: Task.id })
  }
  hooks {
    after_commit: [ "SendSlackNotification" ]
  }
}
```

**Hook definition (runtime/hook)** — hook is nondeterministic and external.

**Canonical IR (`HookNondet.ir.json`)** (abridged)
```json
{
  "ir_version":"grisp-v1.2",
  "manifest_id":"golden-09-hook",
  "manifest_version":"1.0.0",
  "rules":[
    {
      "id":"rule-notify-0001",
      "name":"NotifyOnAssign",
      "priority":40,
      "when":[ { "kind":"binding","var":"Task","type":"Task","constraints":[ { "field":"lifecycle","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"assigned" } } ] } ],
      "then":[ { "kind":"emit", "emit":{ "type":"TASK_ASSIGNED","class":"operational","payload":{ "task":{ "kind":"field","var":"Task","field":"id" } }, "non_deterministic":false } } ],
      "hooks": {
        "after_commit":[ { "id":"SendSlackNotification", "idempotent":false, "timeout_ms":5000, "non_deterministic":true } ]
      },
      "inferred_reads":["Task.lifecycle","Task.id"],
      "inferred_writes":[]
    }
  ]
}
```

---

### Example 10 — Effect Timeout and on_timeout=escalate

**Source (`EffectTimeout.grisp`)**
```grisp
rule ExternalProvision priority=30 {
  when { Request: ProvisionRequest where status == "pending" }
  then {
    call ProvisionVM(Request.id)  ; effect fn with timeout and escalate policy
    update Request { status: "provisioning" }
  }
}
```

**Function metadata**: `ProvisionVM` is `effect` with `effect_meta: { idempotent: true, timeout_ms: 10000, on_timeout: "escalate" }`.

**Canonical IR (`EffectTimeout.ir.json`)** (abridged)
```json
{
  "ir_version":"grisp-v1.2",
  "manifest_id":"golden-10-effect-timeout",
  "manifest_version":"1.0.0",
  "functions":[ { "name":"ProvisionVM","kind":"effect","signature":"(identifier)->void","external":true,"effect_meta":{"idempotent":true,"timeout_ms":10000,"on_timeout":"escalate"} } ],
  "rules":[
    {
      "id":"rule-provision-0001",
      "name":"ExternalProvision",
      "priority":30,
      "when":[ { "kind":"binding","var":"Request","type":"ProvisionRequest","constraints":[ { "field":"status","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"pending" } } ] } ],
      "then":[ { "kind":"call","call":{ "fn":"ProvisionVM","args":[ { "kind":"field","var":"Request","field":"id" } ] } }, { "kind":"update","target":"Request","assigns":[ { "field":"status","value":{ "kind":"literal","literal_type":"string","value":"provisioning" } } ] } ],
      "inferred_reads":["ProvisionRequest.status","ProvisionRequest.id"],
      "inferred_writes":["ProvisionRequest.status"]
    }
  ]
}
```

---

### Example 11 — Nested Collections and Aggregation

**Source (`NestedCollections.grisp`)**
```grisp
rule TopAgents priority=20 {
  when {
    Task: Task where lifecycle == "pending"
    Completed many Task where lifecycle == "completed" order by completed_at desc, id asc
  }
  then {
    let top = Completed[0:5]  ; top 5 completed tasks
    emit Event(type="TOP_AGENTS", class="debug", payload={ top_count: len(top) })
  }
}
```

**Canonical IR (`NestedCollections.ir.json`)** (abridged)
```json
{
  "ir_version":"grisp-v1.2",
  "manifest_id":"golden-11-nested",
  "manifest_version":"1.0.0",
  "rules":[
    {
      "id":"rule-topagents-0001",
      "name":"TopAgents",
      "priority":20,
      "when":[
        { "kind":"binding","var":"Task","type":"Task","constraints":[ { "field":"lifecycle","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"pending" } } ] },
        { "kind":"collection","collection":{ "var":"Completed","type":"Task","constraints":[ { "field":"lifecycle","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"completed" } } ], "order_by":[ { "field":"completed_at","direction":"desc" }, { "field":"id","direction":"asc" } ] } }
      ],
      "then":[
        { "kind":"let","let_name":"top","expr":{ "kind":"collection","source":{ "type":"Task","query":{} }, "order_by":[ { "field":"completed_at","direction":"desc" }, { "field":"id","direction":"asc" } ], "limit":5 } },
        { "kind":"emit","emit":{ "type":"TOP_AGENTS","class":"debug","payload":{ "top_count":{ "kind":"call","fn":"len","args":[ { "kind":"var","name":"top" } ] } }, "non_deterministic":false } }
      ],
      "inferred_reads":["Task.lifecycle","Task.completed_at","Task.id"],
      "inferred_writes":[]
    }
  ]
}
```

---

### Example 12 — Capability Closure Large Graph Hint

**Source (`CapabilityClosureHint.grisp`)**
```grisp
# capability graph is large and mostly static; request materialized closure
# runtime profile will set materialize_closure: true
node Capability { id: identifier, name: string }
edge capability_extends(Capability -> Capability)
```

**Canonical IR (`CapabilityClosureHint.ir.json`)**
```json
{
  "ir_version":"grisp-v1.2",
  "manifest_id":"golden-12-capclosure",
  "manifest_version":"1.0.0",
  "nodes":[ { "name":"Capability","fields":{ "id":{"type":"identifier"}, "name":{"type":"string"} } } ],
  "edges":[ { "name":"capability_extends","from":"Capability","to":"Capability","acyclic":true } ],
  "capability_hints": { "materialize_closure": true, "closure_refresh_interval_ms": 86400000 }
}
```

---

### Example 13 — Checkpoint and Graph Hash Example

**Source (`CheckpointExample.grisp`)**
```grisp
# No rules; demonstrate checkpoint node creation semantics (runtime may emit checkpoints)
node Checkpoint { id: identifier, tick: integer, graph_hash: string, created_at: number, manifest_version: string }
```

**Canonical IR (`CheckpointExample.ir.json`)**
```json
{
  "ir_version":"grisp-v1.2",
  "manifest_id":"golden-13-checkpoint",
  "manifest_version":"1.0.0",
  "nodes":[ { "name":"Checkpoint","fields":{ "id":{"type":"identifier"}, "tick":{"type":"integer"}, "graph_hash":{"type":"string"}, "created_at":{"type":"number"}, "manifest_version":{"type":"string"} } } ],
  "notes":"Graph hashing algorithm: canonical JSON of nodes+edges sorted, SHA-256 hex."
}
```

---

### Example 14 — Event Sampling and Emit Hints

**Source (`EventSampling.grisp`)**
```grisp
rule SampledTelemetry priority=10 {
  when { Task: Task where lifecycle == "running" }
  then {
    emit Event(type="TASK_HEARTBEAT", class="operational", payload={ task: Task.id }, emit_hint={ sample_rate: 0.05, aggregate_key: "Task.id" })
  }
}
```

**Canonical IR (`EventSampling.ir.json`)**
```json
{
  "ir_version":"grisp-v1.2",
  "manifest_id":"golden-14-sampling",
  "manifest_version":"1.0.0",
  "rules":[
    {
      "id":"rule-sample-0001",
      "name":"SampledTelemetry",
      "priority":10,
      "when":[ { "kind":"binding","var":"Task","type":"Task","constraints":[ { "field":"lifecycle","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"running" } } ] } ],
      "then":[ { "kind":"emit","emit":{ "type":"TASK_HEARTBEAT","class":"operational","payload":{ "task":{ "kind":"field","var":"Task","field":"id" } }, "emit_hint":{ "sample_rate":0.05, "aggregate_key":"Task.id" }, "non_deterministic":false } } ],
      "inferred_reads":["Task.lifecycle","Task.id"],
      "inferred_writes":[]
    }
  ]
}
```

---

### Example 15 — Complex Ordering and Tie-breakers

**Source (`OrderingTieBreak.grisp`)**
```grisp
rule HighPriorityTask priority=100 {
  when { Task: Task where priority >= 90 and lifecycle == "pending" }
  then { emit Event(type="HIGH_PRIORITY", class="operational", payload={ task: Task.id }) }
}
```

**Runtime profile**: tie_breaker = "rule_name" (default deterministic).

**Canonical IR (`OrderingTieBreak.ir.json`)**
```json
{
  "ir_version":"grisp-v1.2",
  "manifest_id":"golden-15-ordering",
  "manifest_version":"1.0.0",
  "rules":[
    {
      "id":"rule-highprio-0001",
      "name":"HighPriorityTask",
      "priority":100,
      "when":[ { "kind":"binding","var":"Task","type":"Task","constraints":[ { "field":"priority","op":">=","value":{ "kind":"literal","literal_type":"integer","value":90 } }, { "field":"lifecycle","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"pending" } } ] } ],
      "then":[ { "kind":"emit","emit":{ "type":"HIGH_PRIORITY","class":"operational","payload":{ "task":{ "kind":"field","var":"Task","field":"id" } }, "non_deterministic":false } } ],
      "inferred_reads":["Task.priority","Task.lifecycle","Task.id"],
      "inferred_writes":[]
    }
  ]
}
```

---

### Example 16 — Large Manifest Excerpt (many nodes/rules) — abbreviated

**Source (`LargeManifestExcerpt.grisp`)**
```grisp
# Excerpt: many node types and a rule that touches multiple types
node Worker { id: identifier, capacity: integer, status: string }
node Job { id: identifier, required_capacity: integer, status: string }
edge assigned_to(Job -> Worker)

rule ScheduleJob priority=95 {
  when {
    Job: Job where status == "queued"
    Worker: Worker where capacity >= Job.required_capacity and status == "idle"
  }
  then {
    create Lease { task: Job, agent: Worker, expires_at: TickStartTime + 120000, owner_epoch: NextLeaseEpoch(Job) }
    update Job { status: "scheduled" }
    update Worker { capacity: Worker.capacity - Job.required_capacity }
    emit Event(type="JOB_SCHEDULED", class="operational", payload={ job: Job.id, worker: Worker.id })
  }
}
```

**Canonical IR (`LargeManifestExcerpt.ir.json`)** (abridged)
```json
{
  "ir_version":"grisp-v1.2",
  "manifest_id":"golden-16-large-excerpt",
  "manifest_version":"1.0.0",
  "nodes":[
    { "name":"Worker","fields":{ "id":{"type":"identifier"},"capacity":{"type":"integer"},"status":{"type":"string"} } },
    { "name":"Job","fields":{ "id":{"type":"identifier"},"required_capacity":{"type":"integer"},"status":{"type":"string"} } },
    { "name":"Lease","fields":{ "id":{"type":"identifier"},"task":{"type":"Job"},"agent":{"type":"Worker"},"expires_at":{"type":"number"},"owner_epoch":{"type":"integer"} } }
  ],
  "edges":[ { "name":"assigned_to","from":"Job","to":"Worker" } ],
  "rules":[
    {
      "id":"rule-schedule-0001",
      "name":"ScheduleJob",
      "priority":95,
      "when":[
        { "kind":"binding","var":"Job","type":"Job","constraints":[ { "field":"status","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"queued" } } ] },
        { "kind":"binding","var":"Worker","type":"Worker","constraints":[ { "field":"capacity","op":">=","value":{ "kind":"field","var":"Job","field":"required_capacity" } }, { "field":"status","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"idle" } } ] }
      ],
      "then":[ /* create lease, update job, update worker, emit normalized */ ],
      "inferred_reads":["Job.status","Job.required_capacity","Job.id","Worker.capacity","Worker.status","Worker.id"],
      "inferred_writes":["Lease","Job.status","Worker.capacity"]
    }
  ]
}
```

---

## Next steps and options

I can continue with any of the following (pick one or more):

- **Generate 10 more golden files** covering additional edge cases (conflicting leases under heavy churn, capability cycles, deep nested expressions, large closure graphs).  
- **Produce canonical JSON byte outputs** (fully serialized, canonicalized) for each golden IR so CI can do byte-for-byte comparisons.  
- **Create a small test harness** (shell + Node/Python scripts) that runs `manifest-compile`, canonicalizes JSON, and compares against golden files across multiple toolchains.  
- **Produce a `manifest-compile --mode=production` checklist** and sample CI job YAML for GitHub Actions.

Tell me which artifact you want next and I’ll generate it ready to copy/paste.




### Additional golden-file edge cases (10 compact examples)

Below are **10 more canonical golden-file examples** (source `.grisp` + expected Canonical IR v1.2 outputs, abridged). Each targets a specific edge case likely to surface interoperability or compiler-normalization bugs. Save each pair as `golden-17-*.grisp` and `golden-17-*.ir.json` for CI.

---

#### Example 17 — Race Condition with Competing Creates  
**Source**
```grisp
rule CreateIfMissing priority=100 {
  when { Key: Key where id == "k1" }
  then {
    not exists Value where Value.key == Key.id
    create Value { key: Key.id, value: "v1" }
  }
}
```
**Canonical IR** (abridged)
```json
{
  "manifest_id":"golden-17-race",
  "rules":[
    {
      "name":"CreateIfMissing",
      "priority":100,
      "when":[
        { "kind":"binding","var":"Key","type":"Key","constraints":[ { "field":"id","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"k1" } } ] },
        { "kind":"existence","exists":false,"pattern":{ "kind":"binding","var":"V","type":"Value","constraints":[ { "field":"key","op":"eq_var","var":"Key.id" } ] } }
      ],
      "then":[
        { "kind":"create","type":"Value","result_var":"NewValue","fields":{ "key":{ "expr":{ "kind":"field","var":"Key","field":"id" } }, "value":{ "expr":{ "kind":"literal","literal_type":"string","value":"v1" } } } }
      ],
      "inferred_reads":["Key.id","Value.key"],
      "inferred_writes":["Value"]
    }
  ]
}
```

---

#### Example 18 — Large Payload and Binary Data Hint  
**Source**
```grisp
rule StoreBlob priority=50 {
  when { Upload: Upload where status == "ready" }
  then {
    create Blob { id: Upload.id, data: Upload.payload, size: len(Upload.payload) }
    update Upload { status: "stored" }
  }
}
```
**Canonical IR** (abridged)
```json
{
  "manifest_id":"golden-18-blob",
  "rules":[
    {
      "name":"StoreBlob",
      "priority":50,
      "when":[ { "kind":"binding","var":"Upload","type":"Upload","constraints":[ { "field":"status","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"ready" } } ] } ],
      "then":[
        { "kind":"create","type":"Blob","result_var":"NewBlob","fields":{
            "id":{ "expr":{ "kind":"field","var":"Upload","field":"id" } },
            "data":{ "expr":{ "kind":"field","var":"Upload","field":"payload" } },
            "size":{ "expr":{ "kind":"call","fn":"len","args":[ { "kind":"field","var":"Upload","field":"payload" } ] } }
          }
        },
        { "kind":"update","target":"Upload","assigns":[ { "field":"status","value":{ "kind":"literal","literal_type":"string","value":"stored" } } ] }
      ],
      "inferred_reads":["Upload.status","Upload.id","Upload.payload"],
      "inferred_writes":["Blob","Upload.status"]
    }
  ]
}
```

---

#### Example 19 — Regex Constraint and Index Hint  
**Source**
```grisp
rule MatchEmail priority=60 {
  when { User: User where email =~ /@example\.com$/ }
  then { emit Event(type="USER_MATCH", class="debug", payload={ user: User.id }) }
}
```
**Canonical IR** (abridged)
```json
{
  "manifest_id":"golden-19-regex",
  "rules":[
    {
      "name":"MatchEmail",
      "priority":60,
      "when":[ { "kind":"binding","var":"User","type":"User","constraints":[ { "field":"email","op":"regex","value":{ "kind":"literal","literal_type":"string","value":"@example\\.com$" } } ] } ],
      "then":[ { "kind":"emit","emit":{ "type":"USER_MATCH","class":"debug","payload":{ "user":{ "kind":"field","var":"User","field":"id" } }, "non_deterministic":false } } ],
      "inferred_reads":["User.email","User.id"],
      "inferred_writes":[]
    }
  ]
}
```

---

#### Example 20 — Temporal Window and Sliding Aggregation  
**Source**
```grisp
rule RecentFailures priority=40 {
  when {
    Failure many Event where type == "FAIL" and timestamp > TickStartTime - 3600000 order by timestamp desc
  }
  then {
    let recent = Failure[0:100]
    emit Event(type="RECENT_FAILURES", class="operational", payload={ count: len(recent) })
  }
}
```
**Canonical IR** (abridged)
```json
{
  "manifest_id":"golden-20-temporal",
  "rules":[
    {
      "name":"RecentFailures",
      "priority":40,
      "when":[
        { "kind":"collection","collection":{ "var":"Failure","type":"Event","constraints":[ { "field":"type","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"FAIL" } }, { "field":"timestamp","op":">","value":{ "kind":"binary","op":"-","left":{ "kind":"var","name":"TickStartTime" },"right":{ "kind":"literal","literal_type":"integer","value":3600000 } } } ], "order_by":[ { "field":"timestamp","direction":"desc" } ] } }
      ],
      "then":[
        { "kind":"let","let_name":"recent","expr":{ "kind":"collection","source":{ "type":"Event","query":{} },"order_by":[ { "field":"timestamp","direction":"desc" } ], "limit":100 } },
        { "kind":"emit","emit":{ "type":"RECENT_FAILURES","class":"operational","payload":{ "count":{ "kind":"call","fn":"len","args":[ { "kind":"var","name":"recent" } ] } }, "non_deterministic":false } }
      ],
      "inferred_reads":["Event.type","Event.timestamp"],
      "inferred_writes":[]
    }
  ]
}
```

---

#### Example 21 — Transactional Rollback on Effect Failure  
**Source**
```grisp
rule ProvisionWithRollback priority=30 {
  when { Request: ProvisionRequest where status == "pending" }
  then {
    update Request { status: "provisioning" }
    call ProvisionVM(Request.id)  ; effect may fail
    update Request { status: "done" }
  }
  hooks { on_failure: [ "RollbackProvision" ] }
}
```
**Canonical IR** (abridged)
```json
{
  "manifest_id":"golden-21-rollback",
  "functions":[ { "name":"ProvisionVM","kind":"effect","signature":"(identifier)->void","external":true,"effect_meta":{"idempotent":true,"timeout_ms":10000,"on_timeout":"fail"} } ],
  "rules":[
    {
      "name":"ProvisionWithRollback",
      "priority":30,
      "when":[ { "kind":"binding","var":"Request","type":"ProvisionRequest","constraints":[ { "field":"status","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"pending" } } ] } ],
      "then":[
        { "kind":"update","target":"Request","assigns":[ { "field":"status","value":{ "kind":"literal","literal_type":"string","value":"provisioning" } } ] },
        { "kind":"call","call":{ "fn":"ProvisionVM","args":[ { "kind":"field","var":"Request","field":"id" } ] } },
        { "kind":"update","target":"Request","assigns":[ { "field":"status","value":{ "kind":"literal","literal_type":"string","value":"done" } } ] }
      ],
      "hooks": { "on_failure":[ { "id":"RollbackProvision","idempotent":true,"non_deterministic":true } ] },
      "inferred_reads":["ProvisionRequest.status","ProvisionRequest.id"],
      "inferred_writes":["ProvisionRequest.status"]
    }
  ]
}
```

---

#### Example 22 — Cross-manifest Reference and Compatibility Hint  
**Source**
```grisp
# This rule references a node defined in another manifest; manifest-compile must preserve the reference.
rule CrossManifestRef priority=10 {
  when { External: ExternalNode where tag == "x" }
  then { emit Event(type="EXT_REF", class="debug", payload={ id: External.id }) }
}
```
**Canonical IR** (abridged)
```json
{
  "manifest_id":"golden-22-crossref",
  "metadata":{ "references":[ "other-manifest-id@1.0.0" ] },
  "rules":[
    {
      "name":"CrossManifestRef",
      "priority":10,
      "when":[ { "kind":"binding","var":"External","type":"ExternalNode","constraints":[ { "field":"tag","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"x" } } ] } ],
      "then":[ { "kind":"emit","emit":{ "type":"EXT_REF","class":"debug","payload":{ "id":{ "kind":"field","var":"External","field":"id" } }, "non_deterministic":false } } ],
      "inferred_reads":["ExternalNode.tag","ExternalNode.id"],
      "inferred_writes":[]
    }
  ]
}
```

---

#### Example 23 — Schema Constraint Declaration (unique constraint)  
**Source**
```grisp
node Lease {
  id: identifier
  task: Task
  status: string
}
constraint SingleActiveLeasePerTask {
  unique(Lease.task) where Lease.status == "active"
}
```
**Canonical IR** (abridged)
```json
{
  "manifest_id":"golden-23-constraint",
  "nodes":[ { "name":"Lease","fields":{ "id":{"type":"identifier"},"task":{"type":"Task"},"status":{"type":"string"} } } ],
  "constraints":[
    { "name":"SingleActiveLeasePerTask","kind":"unique","target":"Lease.task","where":{ "kind":"expression","expr":{ "kind":"binary","op":"==","left":{ "kind":"field","var":"Lease","field":"status" },"right":{ "kind":"literal","literal_type":"string","value":"active" } } } }
  ]
}
```

---

#### Example 24 — Wildcard Field Matching and Projection  
**Source**
```grisp
rule ProjectFields priority=20 {
  when { Item: Item where tags contains "urgent" }
  then {
    let proj = { id: Item.id, meta: Item.metadata }
    emit Event(type="PROJECTED", class="debug", payload=proj)
  }
}
```
**Canonical IR** (abridged)
```json
{
  "manifest_id":"golden-24-wildcard",
  "rules":[
    {
      "name":"ProjectFields",
      "priority":20,
      "when":[ { "kind":"binding","var":"Item","type":"Item","constraints":[ { "field":"tags","op":"contains","value":{ "kind":"literal","literal_type":"string","value":"urgent" } } ] } ],
      "then":[
        { "kind":"let","let_name":"proj","expr":{ "kind":"object","fields":{ "id":{ "kind":"field","var":"Item","field":"id" }, "meta":{ "kind":"field","var":"Item","field":"metadata" } } } },
        { "kind":"emit","emit":{ "type":"PROJECTED","class":"debug","payload":{ "proj":{ "kind":"var","name":"proj" } }, "non_deterministic":false } }
      ],
      "inferred_reads":["Item.tags","Item.id","Item.metadata"],
      "inferred_writes":[]
    }
  ]
}
```

---

#### Example 25 — Deeply Nested Expression and Canonicalization Stress Test  
**Source**
```grisp
rule ComplexExpr priority=5 {
  when { X: X where computeScore(X.metrics) > threshold and (X.flag == true or X.count > 10) }
  then { update X { score: normalize(computeScore(X.metrics) + offset) } }
}
```
**Canonical IR** (abridged)
```json
{
  "manifest_id":"golden-25-deepexpr",
  "rules":[
    {
      "name":"ComplexExpr",
      "priority":5,
      "when":[
        { "kind":"binding","var":"X","type":"X","constraints":[
            { "field":"metrics","op":"expr","value":{ "kind":"call","fn":"computeScore","args":[ { "kind":"field","var":"X","field":"metrics" } ] } },
            { "field":"cond","op":"expr","value":{ "kind":"binary","op":"and","left":{ "kind":"binary","op":">","left":{ "kind":"call","fn":"computeScore","args":[ { "kind":"field","var":"X","field":"metrics" } ] },"right":{ "kind":"var","name":"threshold" } },"right":{ "kind":"binary","op":"or","left":{ "kind":"binary","op":"==","left":{ "kind":"field","var":"X","field":"flag" },"right":{ "kind":"literal","literal_type":"boolean","value":true } },"right":{ "kind":"binary","op":">","left":{ "kind":"field","var":"X","field":"count" },"right":{ "kind":"literal","literal_type":"integer","value":10 } } } } } ]
        }
      ],
      "then":[
        { "kind":"update","target":"X","assigns":[ { "field":"score","value":{ "kind":"call","fn":"normalize","args":[ { "kind":"binary","op":"+","left":{ "kind":"call","fn":"computeScore","args":[ { "kind":"field","var":"X","field":"metrics" } ] },"right":{ "kind":"var","name":"offset" } } ] } } ] }
      ],
      "inferred_reads":["X.metrics","X.flag","X.count"],
      "inferred_writes":["X.score"]
    }
  ]
}
```

---

If you want, I can now:

- **Produce canonicalized JSON bytes** for these 10 examples so they are ready as golden files, or  
- **Add 10 more edge cases** (e.g., capability cycles, deep closure materialization, heavy churn lease stress, multi-tenant isolation), or  
- **Generate CI-ready commit patches** that add these golden pairs to a repository layout.

Tell me which next artifact you prefer and I’ll generate it immediately.



### Ten additional edge-case golden examples (26–35)

Below are **10 more compact golden-file pairs** (source `.grisp` snippet and expected Canonical IR v1.2 output, abridged). Save each pair as `golden-26-*.grisp` and `golden-26-*.ir.json` for CI. Each example targets a specific interoperability or normalization edge case.

---

#### Example 26 — Multi-field Unique Constraint with Partial Index
**Source**
```grisp
node User { id: identifier, email: string, tenant: string }
constraint UniqueEmailPerTenant {
  unique(User.email, User.tenant)
}
```
**Canonical IR (abridged)**
```json
{
  "manifest_id":"golden-26-unique-email",
  "nodes":[ { "name":"User","fields":{ "id":{"type":"identifier"},"email":{"type":"string"},"tenant":{"type":"string"} } } ],
  "constraints":[ { "name":"UniqueEmailPerTenant","kind":"unique","target":["User.email","User.tenant"] } ]
}
```

---

#### Example 27 — Multi-tenant Isolation Hint and Namespace Binding
**Source**
```grisp
rule TenantScopedAssign priority=70 {
  when {
    Tenant: Tenant where id == ctx.tenant_id
    Task: Task where tenant == Tenant.id and lifecycle == "pending"
  }
  then {
    create Lease { task: Task, agent: selectAgentForTenant(Tenant.id) }
  }
}
```
**Canonical IR (abridged)**
```json
{
  "manifest_id":"golden-27-tenant",
  "rules":[
    {
      "name":"TenantScopedAssign",
      "priority":70,
      "when":[
        { "kind":"binding","var":"Tenant","type":"Tenant","constraints":[ { "field":"id","op":"eq","value":{ "kind":"var","name":"ctx.tenant_id" } } ] },
        { "kind":"binding","var":"Task","type":"Task","constraints":[ { "field":"tenant","op":"eq_var","var":"Tenant.id" }, { "field":"lifecycle","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"pending" } } ] }
      ],
      "then":[
        { "kind":"create","type":"Lease","result_var":"NewLease","fields":{ "task":{ "expr":{ "kind":"var","name":"Task" } }, "agent":{ "expr":{ "kind":"call","fn":"selectAgentForTenant","args":[ { "kind":"field","var":"Tenant","field":"id" } ] } } } }
      ],
      "inferred_reads":["Tenant.id","Task.tenant","Task.lifecycle"],
      "inferred_writes":["Lease"]
    }
  ]
}
```

---

#### Example 28 — Partial Update with Nested Object Merge Semantics
**Source**
```grisp
rule MergeMetadata priority=50 {
  when { Item: Item where id == "x" }
  then {
    update Item { metadata: merge(Item.metadata, { seen_by: add(Item.metadata.seen_by, User.id) }) }
  }
}
```
**Canonical IR (abridged)**
```json
{
  "manifest_id":"golden-28-merge",
  "rules":[
    {
      "name":"MergeMetadata",
      "priority":50,
      "when":[ { "kind":"binding","var":"Item","type":"Item","constraints":[ { "field":"id","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"x" } } ] } ],
      "then":[
        { "kind":"update","target":"Item","assigns":[ { "field":"metadata","value":{ "kind":"call","fn":"merge","args":[ { "kind":"field","var":"Item","field":"metadata" }, { "kind":"object","fields":{ "seen_by":{ "kind":"call","fn":"add","args":[ { "kind":"field","var":"Item","field":"metadata.seen_by" }, { "kind":"field","var":"User","field":"id" } ] } } } ] } } ] }
      ],
      "inferred_reads":["Item.id","Item.metadata","User.id"],
      "inferred_writes":["Item.metadata"]
    }
  ]
}
```

---

#### Example 29 — Multi-Edge Pattern and Path Matching
**Source**
```grisp
rule PathMatch priority=60 {
  when {
    A: NodeA where id == "a1"
    edge e1(A -> B)
    edge e2(B -> C)
    C: NodeC where flag == true
  }
  then { emit Event(type="PATH_FOUND", class="operational", payload={ a: A.id, c: C.id }) }
}
```
**Canonical IR (abridged)**
```json
{
  "manifest_id":"golden-29-path",
  "rules":[
    {
      "name":"PathMatch",
      "priority":60,
      "when":[
        { "kind":"binding","var":"A","type":"NodeA","constraints":[ { "field":"id","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"a1" } } ] },
        { "kind":"edge","edge":"e1","from":"A","to":"B" },
        { "kind":"edge","edge":"e2","from":"B","to":"C" },
        { "kind":"binding","var":"C","type":"NodeC","constraints":[ { "field":"flag","op":"eq","value":{ "kind":"literal","literal_type":"boolean","value":true } } ] }
      ],
      "then":[ { "kind":"emit","emit":{ "type":"PATH_FOUND","class":"operational","payload":{ "a":{ "kind":"field","var":"A","field":"id" }, "c":{ "kind":"field","var":"C","field":"id" } }, "non_deterministic":false } } ],
      "inferred_reads":["NodeA.id","NodeC.flag","NodeC.id"],
      "inferred_writes":[]
    }
  ]
}
```

---

#### Example 30 — Conditional Create (guarded by computed predicate)
**Source**
```grisp
rule ConditionalCreate priority=55 {
  when { X: X where score(X) > threshold }
  then {
    if not exists Marker where Marker.x == X.id {
      create Marker { x: X.id, created_at: TickStartTime }
    }
  }
}
```
**Canonical IR (abridged)**
```json
{
  "manifest_id":"golden-30-cond-create",
  "rules":[
    {
      "name":"ConditionalCreate",
      "priority":55,
      "when":[ { "kind":"binding","var":"X","type":"X","constraints":[ { "field":"cond","op":"expr","value":{ "kind":"binary","op":">","left":{ "kind":"call","fn":"score","args":[ { "kind":"var","name":"X" } ] },"right":{ "kind":"var","name":"threshold" } } } ] } ],
      "then":[
        { "kind":"existence","exists":false,"pattern":{ "kind":"binding","var":"Marker","type":"Marker","constraints":[ { "field":"x","op":"eq_var","var":"X.id" } ] } },
        { "kind":"create","type":"Marker","result_var":"NewMarker","fields":{ "x":{ "expr":{ "kind":"field","var":"X","field":"id" } }, "created_at":{ "expr":{ "kind":"var","name":"TickStartTime" } } } }
      ],
      "inferred_reads":["X","Marker.x","X.id"],
      "inferred_writes":["Marker"]
    }
  ]
}
```

---

#### Example 31 — Backpressure Hint and Rate-limited Rule
**Source**
```grisp
rule RateLimitedIngest priority=20 {
  when { Ingest: Ingest where ready == true }
  then {
    create Work { ingest: Ingest.id }
  }
}
```
**Runtime profile**: per-rule `rate_limit.max_per_tick = 10`

**Canonical IR (abridged)**
```json
{
  "manifest_id":"golden-31-rate",
  "rules":[
    {
      "name":"RateLimitedIngest",
      "priority":20,
      "when":[ { "kind":"binding","var":"Ingest","type":"Ingest","constraints":[ { "field":"ready","op":"eq","value":{ "kind":"literal","literal_type":"boolean","value":true } } ] } ],
      "then":[ { "kind":"create","type":"Work","result_var":"NewWork","fields":{ "ingest":{ "expr":{ "kind":"field","var":"Ingest","field":"id" } } } } ],
      "inferred_reads":["Ingest.ready","Ingest.id"],
      "inferred_writes":["Work"],
      "custom": { "runtime_hints": { "rate_limit": { "max_per_tick": 10 } } }
    }
  ]
}
```

---

#### Example 32 — Multi-tenant Conflict Resolution with Priority Boost
**Source**
```grisp
rule TenantPriorityBoost priority=80 {
  when { Task: Task where tenant == "T1" and lifecycle == "pending" }
  then { emit Event(type="TENANT_TASK", class="operational", payload={ task: Task.id }) }
}
```
**Runtime profile**: scheduler_overrides.priority_boost = +20 for this rule

**Canonical IR (abridged)**
```json
{
  "manifest_id":"golden-32-tenant-boost",
  "rules":[
    {
      "name":"TenantPriorityBoost",
      "priority":80,
      "when":[ { "kind":"binding","var":"Task","type":"Task","constraints":[ { "field":"tenant","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"T1" } }, { "field":"lifecycle","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"pending" } } ] } ],
      "then":[ { "kind":"emit","emit":{ "type":"TENANT_TASK","class":"operational","payload":{ "task":{ "kind":"field","var":"Task","field":"id" } }, "non_deterministic":false } } ],
      "inferred_reads":["Task.tenant","Task.lifecycle","Task.id"],
      "inferred_writes":[],
      "custom": { "runtime_hints": { "scheduler_overrides": { "priority_boost": 20 } } }
    }
  ]
}
```

---

#### Example 33 — Cross-rule Atomicity Hint (transaction grouping)
**Source**
```grisp
rule GroupedActions priority=90 {
  when { A: A where ready == true }
  then {
    update A { status: "processing" }
    update B { linked: A.id }  ; B is deterministically chosen
  }
}
```
**Canonical IR (abridged)**
```json
{
  "manifest_id":"golden-33-atomic",
  "rules":[
    {
      "name":"GroupedActions",
      "priority":90,
      "when":[ { "kind":"binding","var":"A","type":"A","constraints":[ { "field":"ready","op":"eq","value":{ "kind":"literal","literal_type":"boolean","value":true } } ] } ],
      "then":[
        { "kind":"update","target":"A","assigns":[ { "field":"status","value":{ "kind":"literal","literal_type":"string","value":"processing" } } ] },
        { "kind":"update","target":"B","assigns":[ { "field":"linked","value":{ "kind":"field","var":"A","field":"id" } } ] }
      ],
      "inferred_reads":["A.ready","A.id"],
      "inferred_writes":["A.status","B.linked"],
      "custom": { "transaction": { "atomic": true } }
    }
  ]
}
```

---

#### Example 34 — Deterministic Randomness Seed Hint (for reference compatibility)
**Source**
```grisp
rule DeterministicSample priority=10 {
  when { Item: Item where score > 0.5 }
  then {
    if rand() < 0.1 {
      emit Event(type="SAMPLED", class="debug", payload={ id: Item.id })
    }
  }
}
```
**Canonical IR (abridged)**
```json
{
  "manifest_id":"golden-34-deterministic-rand",
  "rules":[
    {
      "name":"DeterministicSample",
      "priority":10,
      "when":[ { "kind":"binding","var":"Item","type":"Item","constraints":[ { "field":"score","op":">","value":{ "kind":"literal","literal_type":"number","value":0.5 } } ] } ],
      "then":[
        { "kind":"call","call":{ "fn":"rand","args":[] } },
        { "kind":"emit","emit":{ "type":"SAMPLED","class":"debug","payload":{ "id":{ "kind":"field","var":"Item","field":"id" } }, "non_deterministic":true } }
      ],
      "inferred_reads":["Item.score","Item.id"],
      "inferred_writes":[]
    }
  ],
  "custom": { "deterministic_random_seed": "manifest-seed-0001" }
}
```

---

#### Example 35 — Deep Capability Cycle Detection (validation warning)
**Source**
```grisp
edge extends(Capability -> Capability)
# cycle: A extends B, B extends A (static data)
```
**Canonical IR (abridged)**
```json
{
  "manifest_id":"golden-35-capcycle",
  "edges":[ { "name":"extends","from":"Capability","to":"Capability" } ],
  "validation": {
    "capability_closure": { "has_cycle": true, "cycle_examples":[ ["A","B","A"] ], "warning":"capability_extends contains cycles; manifest-compile should warn or fail depending on mode" }
  }
}
```

---

If you want, I can now:

- **Produce canonicalized JSON bytes** for these 10 examples (ready-to-copy `.ir.json` files), or  
- **Add 10 more edge cases** (covering extreme scale, nested closures, heavy lease churn patterns), or  
- **Generate CI patches** that add these golden pairs and update the `verify-golden.sh` harness.

Which would you like next?


### Ten additional edge-case golden examples 36–45

Below are ten more compact golden-file pairs (source `.grisp` snippet and expected Canonical IR v1.2 output, abridged). Save each pair as `golden-36-*.grisp` and `golden-36-*.ir.json` for CI. Each example targets a specific interoperability or normalization edge case.

---

#### Example 36 — Polymorphic Field Types
**Source**
```grisp
node Payload {
  id: identifier
  content: string | object
}
rule HandlePayload priority=50 {
  when { P: Payload where typeof(P.content) == "string" }
  then { emit Event(type="STRING_PAYLOAD", class="debug", payload={ id: P.id, text: P.content }) }
}
```
**Canonical IR** (abridged)
```json
{
  "manifest_id":"golden-36-polymorphic",
  "nodes":[ { "name":"Payload","fields":{ "id":{"type":"identifier"},"content":{"type":"string|object"} } } ],
  "rules":[
    {
      "name":"HandlePayload",
      "priority":50,
      "when":[ { "kind":"binding","var":"P","type":"Payload","constraints":[ { "field":"content","op":"typeof_eq","value":{ "kind":"literal","literal_type":"string","value":"string" } } ] } ],
      "then":[ { "kind":"emit","emit":{ "type":"STRING_PAYLOAD","class":"debug","payload":{ "id":{ "kind":"field","var":"P","field":"id" }, "text":{ "kind":"field","var":"P","field":"content" } }, "non_deterministic":false } } ],
      "inferred_reads":["Payload.content","Payload.id"],
      "inferred_writes":[]
    }
  ]
}
```

---

#### Example 37 — Optional Field Access with Safe Navigation
**Source**
```grisp
rule SafeAccess priority=40 {
  when { U: User where U.profile?.email != null }
  then { emit Event(type="HAS_EMAIL", class="debug", payload={ user: U.id, email: U.profile?.email }) }
}
```
**Canonical IR** (abridged)
```json
{
  "manifest_id":"golden-37-safe-access",
  "rules":[
    {
      "name":"SafeAccess",
      "priority":40,
      "when":[ { "kind":"binding","var":"U","type":"User","constraints":[ { "field":"profile.email","op":"not_null","value":{ "kind":"literal","literal_type":"null","value":null } } ] } ],
      "then":[ { "kind":"emit","emit":{ "type":"HAS_EMAIL","class":"debug","payload":{ "user":{ "kind":"field","var":"U","field":"id" }, "email":{ "kind":"field","var":"U","field":"profile.email","safe":true } }, "non_deterministic":false } } ],
      "inferred_reads":["User.profile.email","User.id"],
      "inferred_writes":[]
    }
  ]
}
```

---

#### Example 38 — Multi-tenant Schema Versioning Hint
**Source**
```grisp
node Document { id: identifier, tenant: string, schema_version: integer, body: object }
rule MigrateDoc priority=30 {
  when { D: Document where D.schema_version < 3 }
  then { call MigrateDocument(D.id, D.schema_version) }
}
```
**Canonical IR** (abridged)
```json
{
  "manifest_id":"golden-38-schema-migrate",
  "nodes":[ { "name":"Document","fields":{ "id":{"type":"identifier"},"tenant":{"type":"string"},"schema_version":{"type":"integer"},"body":{"type":"object"} } } ],
  "functions":[ { "name":"MigrateDocument","kind":"effect","signature":"(identifier,integer)->void","external":true } ],
  "rules":[
    {
      "name":"MigrateDoc",
      "priority":30,
      "when":[ { "kind":"binding","var":"D","type":"Document","constraints":[ { "field":"schema_version","op":"<","value":{ "kind":"literal","literal_type":"integer","value":3 } } ] } ],
      "then":[ { "kind":"call","call":{ "fn":"MigrateDocument","args":[ { "kind":"field","var":"D","field":"id" }, { "kind":"field","var":"D","field":"schema_version" } ] } } ],
      "inferred_reads":["Document.schema_version","Document.id"],
      "inferred_writes":[]
    }
  ],
  "custom": { "multi_tenant": true }
}
```

---

#### Example 39 — Partial Index Hint and Query Plan Suggestion
**Source**
```grisp
rule FastMatch priority=70 {
  when { Item: Item where status == "active" and region == "eu-west" }
  then { emit Event(type="ITEM_ACTIVE", class="operational", payload={ id: Item.id }) }
}
```
**Canonical IR** (abridged)
```json
{
  "manifest_id":"golden-39-partial-index",
  "rules":[
    {
      "name":"FastMatch",
      "priority":70,
      "when":[ { "kind":"binding","var":"Item","type":"Item","constraints":[ { "field":"status","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"active" } }, { "field":"region","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"eu-west" } } ] } ],
      "then":[ { "kind":"emit","emit":{ "type":"ITEM_ACTIVE","class":"operational","payload":{ "id":{ "kind":"field","var":"Item","field":"id" } }, "non_deterministic":false } } ],
      "inferred_reads":["Item.status","Item.region","Item.id"],
      "inferred_writes":[],
      "custom": { "index_hints": [ { "fields": ["status","region"], "type": "partial" } ] }
    }
  ]
}
```

---

#### Example 40 — Multi-Rule Atomic Commit Grouping
**Source**
```grisp
rule A1 priority=100 {
  when { X: X where ready == true }
  then { update X { state: "step1" } }
}
rule A2 priority=100 {
  when { X: X where state == "step1" }
  then { update X { state: "step2" } }
}
# Hint: group A1 and A2 into a single atomic transaction when possible
```
**Canonical IR** (abridged)
```json
{
  "manifest_id":"golden-40-atomic-group",
  "rules":[
    { "name":"A1","priority":100,"when":[{ "kind":"binding","var":"X","type":"X","constraints":[{ "field":"ready","op":"eq","value":{ "kind":"literal","literal_type":"boolean","value":true } }]}],"then":[{ "kind":"update","target":"X","assigns":[{ "field":"state","value":{ "kind":"literal","literal_type":"string","value":"step1" } }]}],"inferred_reads":["X.ready"],"inferred_writes":["X.state"],"custom":{ "transaction_group":"group-A" } },
    { "name":"A2","priority":100,"when":[{ "kind":"binding","var":"X","type":"X","constraints":[{ "field":"state","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"step1" } }]}],"then":[{ "kind":"update","target":"X","assigns":[{ "field":"state","value":{ "kind":"literal","literal_type":"string","value":"step2" } }]}],"inferred_reads":["X.state"],"inferred_writes":["X.state"],"custom":{ "transaction_group":"group-A" } }
  ]
}
```

---

#### Example 41 — Schema Evolution Backwards Compatibility Hint
**Source**
```grisp
node Order { id: identifier, items: array<object>, version: integer }
rule HandleOldOrders priority=20 {
  when { O: Order where O.version < 2 }
  then { call MigrateOrderV1ToV2(O.id) }
}
```
**Canonical IR** (abridged)
```json
{
  "manifest_id":"golden-41-schema-evo",
  "nodes":[ { "name":"Order","fields":{ "id":{"type":"identifier"},"items":{"type":"array<object>"},"version":{"type":"integer"} } } ],
  "functions":[ { "name":"MigrateOrderV1ToV2","kind":"effect","signature":"(identifier)->void","external":true } ],
  "rules":[ { "name":"HandleOldOrders","priority":20,"when":[{ "kind":"binding","var":"O","type":"Order","constraints":[{ "field":"version","op":"<","value":{ "kind":"literal","literal_type":"integer","value":2 } }]}],"then":[{ "kind":"call","call":{ "fn":"MigrateOrderV1ToV2","args":[{ "kind":"field","var":"O","field":"id" }] } }],"inferred_reads":["Order.version","Order.id"],"inferred_writes":[]} ],
  "custom": { "schema_evolution": { "backwards_compatible": true } }
}
```

---

#### Example 42 — Large Join Pattern with Many Variables
**Source**
```grisp
rule MultiJoin priority=10 {
  when {
    A: A where flag == true
    edge e1(A -> B)
    edge e2(B -> C)
    edge e3(C -> D)
    D: D where active == true
  }
  then { emit Event(type="CHAIN_FOUND", class="operational", payload={ a: A.id, d: D.id }) }
}
```
**Canonical IR** (abridged)
```json
{
  "manifest_id":"golden-42-multijoin",
  "rules":[
    {
      "name":"MultiJoin",
      "priority":10,
      "when":[
        { "kind":"binding","var":"A","type":"A","constraints":[ { "field":"flag","op":"eq","value":{ "kind":"literal","literal_type":"boolean","value":true } } ] },
        { "kind":"edge","edge":"e1","from":"A","to":"B" },
        { "kind":"edge","edge":"e2","from":"B","to":"C" },
        { "kind":"edge","edge":"e3","from":"C","to":"D" },
        { "kind":"binding","var":"D","type":"D","constraints":[ { "field":"active","op":"eq","value":{ "kind":"literal","literal_type":"boolean","value":true } } ] }
      ],
      "then":[ { "kind":"emit","emit":{ "type":"CHAIN_FOUND","class":"operational","payload":{ "a":{ "kind":"field","var":"A","field":"id" }, "d":{ "kind":"field","var":"D","field":"id" } }, "non_deterministic":false } } ],
      "inferred_reads":["A.flag","D.active","A.id","D.id"],
      "inferred_writes":[]
    }
  ]
}
```

---

#### Example 43 — Soft Delete Pattern and Tombstone Handling
**Source**
```grisp
rule SoftDelete priority=60 {
  when { Entity: Entity where deleted == true and tombstone_expires_at < TickStartTime }
  then { delete Entity where id == Entity.id }
}
```
**Canonical IR** (abridged)
```json
{
  "manifest_id":"golden-43-soft-delete",
  "rules":[
    {
      "name":"SoftDelete",
      "priority":60,
      "when":[ { "kind":"binding","var":"Entity","type":"Entity","constraints":[ { "field":"deleted","op":"eq","value":{ "kind":"literal","literal_type":"boolean","value":true } }, { "field":"tombstone_expires_at","op":"lt","value":{ "kind":"var","name":"TickStartTime" } } ] } ],
      "then":[ { "kind":"delete","target":"Entity","when":{ "kind":"binary","op":"==","left":{ "kind":"field","var":"Entity","field":"id" },"right":{ "kind":"field","var":"Entity","field":"id" } } } ],
      "inferred_reads":["Entity.deleted","Entity.tombstone_expires_at","Entity.id"],
      "inferred_writes":["Entity"]
    }
  ]
}
```

---

#### Example 44 — Cross-tenant Data Leak Prevention Hint
**Source**
```grisp
rule PreventCrossTenant priority=100 {
  when {
    A: A where tenant == ctx.tenant_id
    B: B where tenant != ctx.tenant_id and linked_to == A.id
  }
  then { update B { linked_to: null } }
}
```
**Canonical IR** (abridged)
```json
{
  "manifest_id":"golden-44-cross-tenant",
  "rules":[
    {
      "name":"PreventCrossTenant",
      "priority":100,
      "when":[
        { "kind":"binding","var":"A","type":"A","constraints":[ { "field":"tenant","op":"eq","value":{ "kind":"var","name":"ctx.tenant_id" } } ] },
        { "kind":"binding","var":"B","type":"B","constraints":[ { "field":"tenant","op":"neq","value":{ "kind":"var","name":"ctx.tenant_id" } }, { "field":"linked_to","op":"eq_var","var":"A.id" } ] }
      ],
      "then":[ { "kind":"update","target":"B","assigns":[ { "field":"linked_to","value":{ "kind":"literal","literal_type":"null","value":null } } ] } ],
      "inferred_reads":["A.tenant","A.id","B.tenant","B.linked_to"],
      "inferred_writes":["B.linked_to"],
      "custom": { "security": { "cross_tenant_protection": true } }
    }
  ]
}
```

---

#### Example 45 — Deterministic Merge of Concurrent Events
**Source**
```grisp
rule MergeEvents priority=85 {
  when {
    E1: Event where key == K and type == "update"
    E2: Event where key == K and type == "update" and E2.timestamp > E1.timestamp
  }
  then { update Aggregate { value: merge(E1.payload, E2.payload), updated_at: E2.timestamp } }
}
```
**Canonical IR** (abridged)
```json
{
  "manifest_id":"golden-45-merge-events",
  "rules":[
    {
      "name":"MergeEvents",
      "priority":85,
      "when":[
        { "kind":"binding","var":"E1","type":"Event","constraints":[ { "field":"key","op":"eq_var","var":"K" }, { "field":"type","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"update" } } ] },
        { "kind":"binding","var":"E2","type":"Event","constraints":[ { "field":"key","op":"eq_var","var":"K" }, { "field":"type","op":"eq","value":{ "kind":"literal","literal_type":"string","value":"update" } }, { "field":"timestamp","op":">","value":{ "kind":"field","var":"E1","field":"timestamp" } } ] }
      ],
      "then":[ { "kind":"update","target":"Aggregate","assigns":[ { "field":"value","value":{ "kind":"call","fn":"merge","args":[ { "kind":"field","var":"E1","field":"payload" }, { "kind":"field","var":"E2","field":"payload" } ] } }, { "field":"updated_at","value":{ "kind":"field","var":"E2","field":"timestamp" } } ] } ],
      "inferred_reads":["Event.key","Event.type","Event.timestamp","Event.payload"],
      "inferred_writes":["Aggregate.value","Aggregate.updated_at"]
    }
  ]
}
```

---

If you want, I can now:

- Produce **canonicalized JSON bytes** for these ten examples so they are ready as golden `.ir.json` files, or  
- Add **10 more** edge cases focusing on extreme scale and stress patterns, or  
- Generate a **CI patch** that adds all new golden pairs and updates the verification harness.

Which would you like next?





### golden-36-polymorphic.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-36-polymorphic","manifest_version":"1.0.0","nodes":[{"name":"Payload","fields":{"content":{"type":"string|object"},"id":{"type":"identifier"}}],"rules":[{"id":"rule-handlepayload-0001","inferred_reads":["Payload.content","Payload.id"],"inferred_writes":[],"name":"HandlePayload","priority":50,"then":[{"emit":{"class":"debug","non_deterministic":false,"payload":{"id":{"kind":"field","var":"P","field":"id"},"text":{"kind":"field","var":"P","field":"content"}},"type":"STRING_PAYLOAD"},"kind":"emit"}],"when":[{"constraints":[{"field":"content","op":"typeof_eq","value":{"kind":"literal","literal_type":"string","value":"string"}}],"kind":"binding","type":"Payload","var":"P"}]}]}
```

### golden-37-safe-access.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-37-safe-access","manifest_version":"1.0.0","rules":[{"id":"rule-safeaccess-0001","inferred_reads":["User.profile.email","User.id"],"inferred_writes":[],"name":"SafeAccess","priority":40,"then":[{"emit":{"class":"debug","non_deterministic":false,"payload":{"email":{"kind":"field","var":"U","field":"profile.email","safe":true},"user":{"kind":"field","var":"U","field":"id"}},"type":"HAS_EMAIL"},"kind":"emit"}],"when":[{"constraints":[{"field":"profile.email","op":"not_null","value":{"kind":"literal","literal_type":"null","value":null}}],"kind":"binding","type":"User","var":"U"}]}]}
```

### golden-38-schema-migrate.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-38-schema-migrate","manifest_version":"1.0.0","custom":{"multi_tenant":true},"functions":[{"effect_meta":null,"external":true,"kind":"effect","name":"MigrateDocument","signature":"(identifier,integer)->void"}],"nodes":[{"name":"Document","fields":{"body":{"type":"object"},"id":{"type":"identifier"},"schema_version":{"type":"integer"},"tenant":{"type":"string"}}}],"rules":[{"id":"rule-migratedoc-0001","inferred_reads":["Document.id","Document.schema_version"],"inferred_writes":[],"name":"MigrateDoc","priority":30,"then":[{"call":{"fn":"MigrateDocument","args":[{"kind":"field","var":"D","field":"id"},{"kind":"field","var":"D","field":"schema_version"}]},"kind":"call"}],"when":[{"constraints":[{"field":"schema_version","op":"<","value":{"kind":"literal","literal_type":"integer","value":3}}],"kind":"binding","type":"Document","var":"D"}]}]}
```

### golden-39-partial-index.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-39-partial-index","manifest_version":"1.0.0","rules":[{"custom":{"index_hints":[{"fields":["status","region"],"type":"partial"}]},"id":"rule-fastmatch-0001","inferred_reads":["Item.id","Item.region","Item.status"],"inferred_writes":[],"name":"FastMatch","priority":70,"then":[{"emit":{"class":"operational","non_deterministic":false,"payload":{"id":{"kind":"field","var":"Item","field":"id"}},"type":"ITEM_ACTIVE"},"kind":"emit"}],"when":[{"constraints":[{"field":"region","op":"eq","value":{"kind":"literal","literal_type":"string","value":"eu-west"}},{"field":"status","op":"eq","value":{"kind":"literal","literal_type":"string","value":"active"}}],"kind":"binding","type":"Item","var":"Item"}]}]}
```

### golden-40-atomic-group.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-40-atomic-group","manifest_version":"1.0.0","rules":[{"custom":{"transaction":{"atomic":true},"transaction_group":"group-A"},"id":"rule-a1-0001","inferred_reads":["X.ready"],"inferred_writes":["X.state"],"name":"A1","priority":100,"then":[{"assigns":[{"field":"state","value":{"kind":"literal","literal_type":"string","value":"step1"}}],"kind":"update","target":"X"}],"when":[{"constraints":[{"field":"ready","op":"eq","value":{"kind":"literal","literal_type":"boolean","value":true}}],"kind":"binding","type":"X","var":"X"}]},{"custom":{"transaction_group":"group-A"},"id":"rule-a2-0001","inferred_reads":["X.state"],"inferred_writes":["X.state"],"name":"A2","priority":100,"then":[{"assigns":[{"field":"state","value":{"kind":"literal","literal_type":"string","value":"step2"}}],"kind":"update","target":"X"}],"when":[{"constraints":[{"field":"state","op":"eq","value":{"kind":"literal","literal_type":"string","value":"step1"}}],"kind":"binding","type":"X","var":"X"}]}]}
```

### golden-41-schema-evo.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-41-schema-evo","manifest_version":"1.0.0","custom":{"schema_evolution":{"backwards_compatible":true}},"functions":[{"effect_meta":null,"external":true,"kind":"effect","name":"MigrateOrderV1ToV2","signature":"(identifier)->void"}],"nodes":[{"name":"Order","fields":{"id":{"type":"identifier"},"items":{"type":"array<object>"},"version":{"type":"integer"}}}],"rules":[{"id":"rule-handleoldorders-0001","inferred_reads":["Order.id","Order.version"],"inferred_writes":[],"name":"HandleOldOrders","priority":20,"then":[{"call":{"fn":"MigrateOrderV1ToV2","args":[{"kind":"field","var":"O","field":"id"}]},"kind":"call"}],"when":[{"constraints":[{"field":"version","op":"<","value":{"kind":"literal","literal_type":"integer","value":2}}],"kind":"binding","type":"Order","var":"O"}]}]}
```

### golden-42-multijoin.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-42-multijoin","manifest_version":"1.0.0","rules":[{"id":"rule-multijoin-0001","inferred_reads":["A.flag","A.id","D.active","D.id"],"inferred_writes":[],"name":"MultiJoin","priority":10,"then":[{"emit":{"class":"operational","non_deterministic":false,"payload":{"a":{"kind":"field","var":"A","field":"id"},"d":{"kind":"field","var":"D","field":"id"}},"type":"CHAIN_FOUND"},"kind":"emit"}],"when":[{"constraints":[{"field":"flag","op":"eq","value":{"kind":"literal","literal_type":"boolean","value":true}}],"kind":"binding","type":"A","var":"A"},{"edge":"e1","from":"A","kind":"edge","to":"B"},{"edge":"e2","from":"B","kind":"edge","to":"C"},{"edge":"e3","from":"C","kind":"edge","to":"D"},{"constraints":[{"field":"active","op":"eq","value":{"kind":"literal","literal_type":"boolean","value":true}}],"kind":"binding","type":"D","var":"D"}]}]}
```

### golden-43-soft-delete.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-43-soft-delete","manifest_version":"1.0.0","rules":[{"id":"rule-softdelete-0001","inferred_reads":["Entity.deleted","Entity.id","Entity.tombstone_expires_at"],"inferred_writes":["Entity"],"name":"SoftDelete","priority":60,"then":[{"kind":"delete","target":"Entity","when":{"kind":"binary","op":"==","left":{"kind":"field","var":"Entity","field":"id"},"right":{"kind":"field","var":"Entity","field":"id"}}}],"when":[{"constraints":[{"field":"deleted","op":"eq","value":{"kind":"literal","literal_type":"boolean","value":true}},{"field":"tombstone_expires_at","op":"lt","value":{"kind":"var","name":"TickStartTime"}}],"kind":"binding","type":"Entity","var":"Entity"}]}]}
```

### golden-44-cross-tenant.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-44-cross-tenant","manifest_version":"1.0.0","custom":{"security":{"cross_tenant_protection":true}},"rules":[{"id":"rule-preventcross-0001","inferred_reads":["A.id","A.tenant","B.linked_to","B.tenant"],"inferred_writes":["B.linked_to"],"name":"PreventCrossTenant","priority":100,"then":[{"assigns":[{"field":"linked_to","value":{"kind":"literal","literal_type":"null","value":null}}],"kind":"update","target":"B"}],"when":[{"constraints":[{"field":"tenant","op":"eq","value":{"kind":"var","name":"ctx.tenant_id"}}],"kind":"binding","type":"A","var":"A"},{"constraints":[{"field":"tenant","op":"neq","value":{"kind":"var","name":"ctx.tenant_id"}},{"field":"linked_to","op":"eq_var","var":"A.id"}],"kind":"binding","type":"B","var":"B"}]}]}
```

### golden-45-merge-events.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-45-merge-events","manifest_version":"1.0.0","rules":[{"id":"rule-mergeevents-0001","inferred_reads":["Event.key","Event.payload","Event.timestamp"],"inferred_writes":["Aggregate.updated_at","Aggregate.value"],"name":"MergeEvents","priority":85,"then":[{"assigns":[{"field":"value","value":{"kind":"call","fn":"merge","args":[{"kind":"field","var":"E1","field":"payload"},{"kind":"field","var":"E2","field":"payload"}]}},{"field":"updated_at","value":{"kind":"field","var":"E2","field":"timestamp"}}],"kind":"update","target":"Aggregate"}],"when":[{"constraints":[{"field":"key","op":"eq_var","var":"K"},{"field":"type","op":"eq","value":{"kind":"literal","literal_type":"string","value":"update"}}],"kind":"binding","type":"Event","var":"E1"},{"constraints":[{"field":"key","op":"eq_var","var":"K"},{"field":"type","op":"eq","value":{"kind":"literal","literal_type":"string","value":"update"}},{"field":"timestamp","op":">","value":{"kind":"field","var":"E1","field":"timestamp"}}],"kind":"binding","type":"Event","var":"E2"}]}]}
```

If you want, I can now:
- produce these same files as downloadable canonicalized artifacts (one ZIP with all `.ir.json` files),  
- add the corresponding `.grisp` source files into the `golden/` directory layout and produce a CI patch, or  
- generate the canonical byte-for-byte golden files for the earlier batches (examples 01–35) as well. Which would you like next?




### golden-01-acquire.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-01-acquire","manifest_version":"1.0.0","id_generation":{"method":"sha256_canonical_json"},"nodes":[{"name":"Agent","fields":{"id":{"type":"identifier"},"role":{"type":"string"}}},{"name":"Lease","fields":{"agent":{"type":"Agent"},"created_at":{"type":"number"},"expires_at":{"type":"number"},"id":{"type":"identifier"},"owner_epoch":{"type":"integer"},"renewed_at":{"type":"number"},"status":{"type":{"enum":["active","expired","released","stolen"]}}}},{"name":"Task","fields":{"cost":{"type":"integer"},"id":{"type":"identifier"},"lifecycle":{"type":"string"},"updated_at":{"type":"number"}}}],"edges":[{"name":"has_capability","from":"Agent","to":"Capability"},{"name":"requires_capability","from":"Task","to":"Capability"}],"functions":[{"name":"NextLeaseEpoch","kind":"pure","signature":"(Task)->integer","external":true}],"rules":[{"id":"rule-acquire-0001","name":"AcquireLease","priority":80,"metadata":{"emits":["LEASE_ACQUIRED"],"idempotent":false},"when":[{"kind":"binding","var":"Task","type":"Task","constraints":[{"field":"lifecycle","op":"eq","value":{"kind":"literal","literal_type":"string","value":"pending"}},{"field":"cost","op":"bind","var":"Cost"}]},{"kind":"binding","var":"Agent","type":"Agent","constraints":[{"field":"role","op":"eq","value":{"kind":"literal","literal_type":"string","value":"Specialist"}}]},{"kind":"edge","edge":"has_capability","from":"Agent","to":"Cap"},{"kind":"existence","exists":false,"pattern":{"kind":"binding","var":"L","type":"Lease","constraints":[{"field":"task","op":"eq_var","var":"Task"},{"field":"status","op":"eq","value":{"kind":"literal","literal_type":"string","value":"active"}}]}}],"then":[{"kind":"create","type":"Lease","result_var":"NewLease","fields":{"agent":{"expr":{"kind":"var","name":"Agent"}},"created_at":{"expr":{"kind":"var","name":"TickStartTime"}},"expires_at":{"expr":{"kind":"binary","op":"+","left":{"kind":"var","name":"TickStartTime"},"right":{"kind":"literal","literal_type":"integer","value":30000}}},"id":{"expr":{"kind":"call","fn":"NewId","args":[]}},"owner_epoch":{"expr":{"kind":"call","fn":"NextLeaseEpoch","args":[{"kind":"var","name":"Task"}]}},"renewed_at":{"expr":{"kind":"var","name":"TickStartTime"}},"status":{"expr":{"kind":"literal","literal_type":"string","value":"active"}}}},{"kind":"update","target":"Task","assigns":[{"field":"lifecycle","value":{"kind":"literal","literal_type":"string","value":"assigned"}},{"field":"updated_at","value":{"kind":"var","name":"TickStartTime"}}]},{"kind":"emit","emit":{"type":"LEASE_ACQUIRED","class":"operational","payload":{"agent":{"kind":"var","name":"Agent"},"task":{"kind":"var","name":"Task"}},"non_deterministic":false}}],"inferred_reads":["Agent.role","Task.cost","Task.lifecycle"],"inferred_writes":["Lease","Task.lifecycle"]}]}
```

---

### golden-02-renew.ir.json
```json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-02-renew","manifest_version":"1.0.0","id_generation":{"method":"sha256_canonical_json"},"nodes":[{"name":"Agent","fields":{"id":{"type":"identifier"},"role":{"type":"string"}}},{"name":"Lease","fields":{"agent":{"type":"Agent"},"expires_at":{"type":"number"},"id":{"type":"identifier"},"owner_epoch":{"type":"integer"},"renewed_at":{"type":"number"},"status":{"type":"string"},"task":{"type":"Task"}}},{"name":"Task","fields":{"id":{"type":"identifier"},"lifecycle":{"type":"string"}}}],"functions":[{"name":"RenewLeaseEffect","kind":"effect","signature":"(identifier,integer)->void","external":true,"effect_meta":{"idempotent":true,"on_timeout":"retry","timeout_ms":5000}}],"rules":[{"id":"rule-renew-0001","name":"RenewLease","priority":90,"when":[{"kind":"binding","var":"Lease","type":"Lease","constraints":[{"field":"agent","op":"eq_var","var":"Agent"},{"field":"owner_epoch","op":"eq_var","var":"Epoch"},{"field":"status","op":"eq","value":{"kind":"literal","literal_type":"string","value":"active"}}]},{"kind":"binding","var":"Agent","type":"Agent","constraints":[{"field":"id","op":"eq_var","var":"Lease.agent"}]}],"then":[{"kind":"call","call":{"fn":"RenewLeaseEffect","args":[{"kind":"field","var":"Lease","field":"id"},{"kind":"var","name":"Epoch"}]}},{"kind":"update","target":"Lease","assigns":[{"field":"renewed_at","value":{"kind":"var","name":"TickStartTime"}},{"field":"expires_at","value":{"kind":"binary","op":"+","left":{"kind":"var","name":"TickStartTime"},"right":{"kind":"literal","literal_type":"integer","value":30000}}}]},{"kind":"emit","emit":{"type":"LEASE_RENEWED","class":"operational","payload":{"epoch":{"kind":"field","var":"Lease","field":"owner_epoch"},"lease":{"kind":"field","var":"Lease","field":"id"}},"non_deterministic":false}}],"inferred_reads":["Lease.id","Lease.owner_epoch","Lease.status"],"inferred_writes":["Lease.expires_at","Lease.renewed_at"]}]}
```

---

### golden-03-steal.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-03-steal","manifest_version":"1.0.0","id_generation":{"method":"sha256_canonical_json"},"nodes":[{"name":"Agent","fields":{"id":{"type":"identifier"},"role":{"type":"string"}}},{"name":"Lease","fields":{"agent":{"type":"Agent"},"created_at":{"type":"number"},"expires_at":{"type":"number"},"heartbeat_at":{"type":"number"},"id":{"type":"identifier"},"owner_epoch":{"type":"integer"},"renewed_at":{"type":"number"},"status":{"type":{"enum":["active","expired","released","stolen"]}},"task":{"type":"Task"}}},{"name":"Task","fields":{"id":{"type":"identifier"}}}],"functions":[{"name":"NextLeaseEpoch","kind":"pure","signature":"(Task)->integer","external":true}],"rules":[{"id":"rule-steal-0001","name":"StealLease","priority":85,"when":[{"kind":"binding","var":"Lease","type":"Lease","constraints":[{"field":"expires_at","op":"lt","value":{"kind":"var","name":"TickStartTime"}},{"field":"heartbeat_at","op":"lt","value":{"kind":"binary","op":"-","left":{"kind":"var","name":"TickStartTime"},"right":{"kind":"literal","literal_type":"integer","value":60000}}}]},{"kind":"binding","var":"Agent","type":"Agent","constraints":[{"field":"role","op":"eq","value":{"kind":"literal","literal_type":"string","value":"Specialist"}}]}],"then":[{"kind":"create","type":"Lease","result_var":"NewLease","fields":{"agent":{"expr":{"kind":"var","name":"Agent"}},"created_at":{"expr":{"kind":"var","name":"TickStartTime"}},"expires_at":{"expr":{"kind":"binary","op":"+","left":{"kind":"var","name":"TickStartTime"},"right":{"kind":"literal","literal_type":"integer","value":30000}}},"owner_epoch":{"expr":{"kind":"call","fn":"NextLeaseEpoch","args":[{"kind":"field","var":"Lease","field":"task"}]}},"renewed_at":{"expr":{"kind":"var","name":"TickStartTime"}},"status":{"expr":{"kind":"literal","literal_type":"string","value":"active"}},"task":{"expr":{"kind":"field","var":"Lease","field":"task"}}}},{"kind":"update","target":"Lease","assigns":[{"field":"status","value":{"kind":"literal","literal_type":"string","value":"stolen"}}]},{"kind":"emit","emit":{"type":"LEASE_STOLEN","class":"operational","payload":{"new":{"kind":"field","var":"NewLease","field":"id"},"old":{"kind":"field","var":"Lease","field":"id"}},"non_deterministic":false}}],"inferred_reads":["Agent.role","Lease.expires_at","Lease.heartbeat_at","Lease.task"],"inferred_writes":["Lease","Lease.owner_epoch","Lease.status"]}]}
```

---

### golden-04-expire.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-04-expire","manifest_version":"1.0.0","id_generation":{"method":"sha256_canonical_json"},"nodes":[{"name":"Lease","fields":{"expires_at":{"type":"number"},"id":{"type":"identifier"},"status":{"type":"string"}}}],"rules":[{"id":"rule-expire-0001","name":"ExpireLease","priority":70,"when":[{"kind":"binding","var":"Lease","type":"Lease","constraints":[{"field":"expires_at","op":"lt","value":{"kind":"var","name":"TickStartTime"}},{"field":"status","op":"eq","value":{"kind":"literal","literal_type":"string","value":"active"}}]}],"then":[{"kind":"update","target":"Lease","assigns":[{"field":"status","value":{"kind":"literal","literal_type":"string","value":"expired"}}]},{"kind":"emit","emit":{"type":"LEASE_EXPIRED","class":"operational","payload":{"lease":{"kind":"field","var":"Lease","field":"id"}},"non_deterministic":false}}],"inferred_reads":["Lease.expires_at","Lease.id","Lease.status"],"inferred_writes":["Lease.status"]}]}
```

---

### golden-05-capabilities.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-05-capabilities","manifest_version":"1.0.0","nodes":[{"name":"Capability","fields":{"id":{"type":"identifier"},"name":{"type":"string"}}}],"edges":[{"name":"capability_extends","from":"Capability","to":"Capability","acyclic":true}],"custom":{"capability_hints":{"closure_refresh_interval_ms":3600000,"materialize_closure":true}}}
```

---

### golden-06-taskflow.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-06-taskflow","manifest_version":"1.0.0","id_generation":{"method":"sha256_canonical_json"},"nodes":[{"name":"Agent","fields":{"id":{"type":"identifier"},"has_capacity":{"type":"boolean"}}},{"name":"Checkpoint","fields":{"created_at":{"type":"number"},"graph_hash":{"type":"string"},"id":{"type":"identifier"},"manifest_version":{"type":"string"},"tick":{"type":"integer"}}},{"name":"Lease","fields":{"agent":{"type":"Agent"},"expires_at":{"type":"number"},"id":{"type":"identifier"},"owner_epoch":{"type":"integer"},"task":{"type":"Task"}}},{"name":"Task","fields":{"goal":{"type":"Goal"},"id":{"type":"identifier"},"lifecycle":{"type":"string"}}},{"name":"Goal","fields":{"id":{"type":"identifier"},"status":{"type":"string"}}}],"functions":[{"name":"NextLeaseEpoch","kind":"pure","signature":"(Task)->integer","external":true}],"rules":[{"id":"rule-plan-0001","name":"PlanTask","priority":60,"metadata":{"emits":["TASK_PLANNED"]},"when":[{"kind":"binding","var":"Goal","type":"Goal","constraints":[{"field":"status","op":"eq","value":{"kind":"literal","literal_type":"string","value":"new"}}]}],"then":[{"kind":"create","type":"Task","result_var":"NewTask","fields":{"goal":{"expr":{"kind":"var","name":"Goal"}},"lifecycle":{"expr":{"kind":"literal","literal_type":"string","value":"pending"}}}},{"kind":"emit","emit":{"type":"TASK_PLANNED","class":"audit","payload":{"goal":{"kind":"field","var":"Goal","field":"id"}},"non_deterministic":false}}],"inferred_reads":["Goal.id","Goal.status"],"inferred_writes":["Task"]},{"id":"rule-assign-0001","name":"AssignTask","priority":50,"metadata":{"depends_on":["PlanTask"],"emits":["TASK_ASSIGNED"]},"when":[{"kind":"binding","var":"Task","type":"Task","constraints":[{"field":"lifecycle","op":"eq","value":{"kind":"literal","literal_type":"string","value":"pending"}}]},{"kind":"binding","var":"Agent","type":"Agent","constraints":[{"field":"has_capacity","op":"eq","value":{"kind":"literal","literal_type":"boolean","value":true}}]}],"then":[{"kind":"create","type":"Lease","result_var":"NewLease","fields":{"agent":{"expr":{"kind":"var","name":"Agent"}},"expires_at":{"expr":{"kind":"binary","op":"+","left":{"kind":"var","name":"TickStartTime"},"right":{"kind":"literal","literal_type":"integer","value":60000}}},"owner_epoch":{"expr":{"kind":"call","fn":"NextLeaseEpoch","args":[{"kind":"var","name":"Task"}]}},"task":{"expr":{"kind":"var","name":"Task"}}}},{"kind":"update","target":"Task","assigns":[{"field":"lifecycle","value":{"kind":"literal","literal_type":"string","value":"assigned"}}]},{"kind":"emit","emit":{"type":"TASK_ASSIGNED","class":"operational","payload":{"agent":{"kind":"field","var":"Agent","field":"id"},"task":{"kind":"field","var":"Task","field":"id"}},"non_deterministic":false}}],"inferred_reads":["Agent.has_capacity","Agent.id","Task.id","Task.lifecycle"],"inferred_writes":["Lease","Task.lifecycle"]}]}
```

---

### golden-07-conflict.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-07-conflict","manifest_version":"1.0.0","nodes":[{"name":"Counter","fields":{"id":{"type":"identifier"},"reset":{"type":"boolean"},"value":{"type":"integer"}}}],"rules":[{"id":"rule-inc-a","name":"IncCounterA","priority":100,"when":[{"kind":"binding","var":"Counter","type":"Counter","constraints":[{"field":"id","op":"eq","value":{"kind":"literal","literal_type":"string","value":"A"}}]}],"then":[{"kind":"update","target":"Counter","assigns":[{"field":"value","value":{"kind":"binary","op":"+","left":{"kind":"field","var":"Counter","field":"value"},"right":{"kind":"literal","literal_type":"integer","value":1}}}]}],"inferred_reads":["Counter.id","Counter.value"],"inferred_writes":["Counter.value"]},{"id":"rule-setzero-a","name":"SetCounterAZero","priority":90,"when":[{"kind":"binding","var":"Counter","type":"Counter","constraints":[{"field":"id","op":"eq","value":{"kind":"literal","literal_type":"string","value":"A"}},{"field":"reset","op":"eq","value":{"kind":"literal","literal_type":"boolean","value":true}}]}],"then":[{"kind":"update","target":"Counter","assigns":[{"field":"value","value":{"kind":"literal","literal_type":"integer","value":0}}]}],"inferred_reads":["Counter.id","Counter.reset"],"inferred_writes":["Counter.value"]}]}
```

---

### golden-08-declared.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-08-declared","manifest_version":"1.0.0","rules":[{"id":"rule-safeassign-0001","name":"SafeAssign","priority":80,"metadata":{"emits":["SAFE_ASSIGN"]},"when":[{"kind":"binding","var":"Task","type":"Task","constraints":[{"field":"lifecycle","op":"eq","value":{"kind":"literal","literal_type":"string","value":"pending"}}]}],"then":[{"kind":"create","type":"Lease","result_var":"NewLease","fields":{"agent":{"expr":{"kind":"var","name":"Agent"}},"owner_epoch":{"expr":{"kind":"call","fn":"NextLeaseEpoch","args":[{"kind":"var","name":"Task"}]}},"task":{"expr":{"kind":"var","name":"Task"}}}},{"kind":"update","target":"Task","assigns":[{"field":"lifecycle","value":{"kind":"literal","literal_type":"string","value":"assigned"}}]},{"kind":"emit","emit":{"type":"SAFE_ASSIGN","class":"operational","payload":{"task":{"kind":"field","var":"Task","field":"id"}},"non_deterministic":false}}],"inferred_reads":["Task.id","Task.lifecycle"],"inferred_writes":["Lease","Task.lifecycle"],"declared_reads":["Task.id","Task.lifecycle"],"declared_writes":["Lease","Task.lifecycle"]}]}
```

---

### golden-09-hook.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-09-hook","manifest_version":"1.0.0","rules":[{"id":"rule-notify-0001","name":"NotifyOnAssign","priority":40,"when":[{"kind":"binding","var":"Task","type":"Task","constraints":[{"field":"lifecycle","op":"eq","value":{"kind":"literal","literal_type":"string","value":"assigned"}}]}],"then":[{"kind":"emit","emit":{"type":"TASK_ASSIGNED","class":"operational","payload":{"task":{"kind":"field","var":"Task","field":"id"}},"non_deterministic":false}}],"hooks":{"after_commit":[{"id":"SendSlackNotification","idempotent":false,"non_deterministic":true,"timeout_ms":5000}]},"inferred_reads":["Task.id","Task.lifecycle"],"inferred_writes":[]}]}
```

---

### golden-10-effect-timeout.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-10-effect-timeout","manifest_version":"1.0.0","functions":[{"name":"ProvisionVM","kind":"effect","signature":"(identifier)->void","external":true,"effect_meta":{"idempotent":true,"on_timeout":"escalate","timeout_ms":10000}}],"rules":[{"id":"rule-provision-0001","name":"ExternalProvision","priority":30,"when":[{"kind":"binding","var":"Request","type":"ProvisionRequest","constraints":[{"field":"status","op":"eq","value":{"kind":"literal","literal_type":"string","value":"pending"}}]}],"then":[{"kind":"call","call":{"fn":"ProvisionVM","args":[{"kind":"field","var":"Request","field":"id"}]}},{"kind":"update","target":"Request","assigns":[{"field":"status","value":{"kind":"literal","literal_type":"string","value":"provisioning"}}]}],"inferred_reads":["ProvisionRequest.id","ProvisionRequest.status"],"inferred_writes":["ProvisionRequest.status"]}]}
```

---

### golden-11-nested.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-11-nested","manifest_version":"1.0.0","rules":[{"id":"rule-topagents-0001","name":"TopAgents","priority":20,"when":[{"kind":"binding","var":"Task","type":"Task","constraints":[{"field":"lifecycle","op":"eq","value":{"kind":"literal","literal_type":"string","value":"pending"}}]},{"kind":"collection","collection":{"var":"Completed","type":"Task","constraints":[{"field":"lifecycle","op":"eq","value":{"kind":"literal","literal_type":"string","value":"completed"}}],"order_by":[{"field":"completed_at","direction":"desc"},{"field":"id","direction":"asc"}]}}],"then":[{"kind":"let","let_name":"top","expr":{"kind":"collection","source":{"type":"Task","query":{}},"limit":5,"order_by":[{"field":"completed_at","direction":"desc"},{"field":"id","direction":"asc"}]}},{"kind":"emit","emit":{"type":"TOP_AGENTS","class":"debug","payload":{"top_count":{"kind":"call","fn":"len","args":[{"kind":"var","name":"top"}]}},"non_deterministic":false}}],"inferred_reads":["Task.completed_at","Task.id","Task.lifecycle"],"inferred_writes":[]}]}
```

---

### golden-12-capclosure.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-12-capclosure","manifest_version":"1.0.0","nodes":[{"name":"Capability","fields":{"id":{"type":"identifier"},"name":{"type":"string"}}}],"edges":[{"name":"capability_extends","from":"Capability","to":"Capability","acyclic":true}],"custom":{"capability_hints":{"closure_refresh_interval_ms":86400000,"materialize_closure":true}}}
```

---

### golden-13-checkpoint.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-13-checkpoint","manifest_version":"1.0.0","nodes":[{"name":"Checkpoint","fields":{"created_at":{"type":"number"},"graph_hash":{"type":"string"},"id":{"type":"identifier"},"manifest_version":{"type":"string"},"tick":{"type":"integer"}}}],"notes":"Graph hashing algorithm: canonical JSON of nodes+edges sorted, SHA-256 hex."}
```

---

### golden-14-sampling.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-14-sampling","manifest_version":"1.0.0","rules":[{"id":"rule-sample-0001","name":"SampledTelemetry","priority":10,"when":[{"kind":"binding","var":"Task","type":"Task","constraints":[{"field":"lifecycle","op":"eq","value":{"kind":"literal","literal_type":"string","value":"running"}}]}],"then":[{"kind":"emit","emit":{"type":"TASK_HEARTBEAT","class":"operational","payload":{"task":{"kind":"field","var":"Task","field":"id"}},"emit_hint":{"aggregate_key":"Task.id","sample_rate":0.05},"non_deterministic":false}}],"inferred_reads":["Task.id","Task.lifecycle"],"inferred_writes":[]}]}
```

---

### golden-15-ordering.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-15-ordering","manifest_version":"1.0.0","rules":[{"id":"rule-highprio-0001","name":"HighPriorityTask","priority":100,"when":[{"kind":"binding","var":"Task","type":"Task","constraints":[{"field":"priority","op":">=","value":{"kind":"literal","literal_type":"integer","value":90}},{"field":"lifecycle","op":"eq","value":{"kind":"literal","literal_type":"string","value":"pending"}}]}],"then":[{"kind":"emit","emit":{"type":"HIGH_PRIORITY","class":"operational","payload":{"task":{"kind":"field","var":"Task","field":"id"}},"non_deterministic":false}}],"inferred_reads":["Task.id","Task.lifecycle","Task.priority"],"inferred_writes":[]}]}
```

---

### golden-16-large-excerpt.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-16-large-excerpt","manifest_version":"1.0.0","nodes":[{"name":"Job","fields":{"id":{"type":"identifier"},"required_capacity":{"type":"integer"},"status":{"type":"string"}}},{"name":"Lease","fields":{"agent":{"type":"Worker"},"expires_at":{"type":"number"},"id":{"type":"identifier"},"owner_epoch":{"type":"integer"},"task":{"type":"Job"}}},{"name":"Worker","fields":{"capacity":{"type":"integer"},"id":{"type":"identifier"},"status":{"type":"string"}}}],"edges":[{"name":"assigned_to","from":"Job","to":"Worker"}],"functions":[{"name":"NextLeaseEpoch","kind":"pure","signature":"(Job)->integer","external":true}],"rules":[{"id":"rule-schedule-0001","name":"ScheduleJob","priority":95,"when":[{"kind":"binding","var":"Job","type":"Job","constraints":[{"field":"status","op":"eq","value":{"kind":"literal","literal_type":"string","value":"queued"}}]},{"kind":"binding","var":"Worker","type":"Worker","constraints":[{"field":"capacity","op":">=","value":{"kind":"field","var":"Job","field":"required_capacity"}},{"field":"status","op":"eq","value":{"kind":"literal","literal_type":"string","value":"idle"}}]}],"then":[{"kind":"create","type":"Lease","result_var":"NewLease","fields":{"agent":{"expr":{"kind":"var","name":"Worker"}},"expires_at":{"expr":{"kind":"binary","op":"+","left":{"kind":"var","name":"TickStartTime"},"right":{"kind":"literal","literal_type":"integer","value":120000}}},"owner_epoch":{"expr":{"kind":"call","fn":"NextLeaseEpoch","args":[{"kind":"var","name":"Job"}]}},"task":{"expr":{"kind":"var","name":"Job"}}}},{"kind":"update","target":"Job","assigns":[{"field":"status","value":{"kind":"literal","literal_type":"string","value":"scheduled"}}]},{"kind":"update","target":"Worker","assigns":[{"field":"capacity","value":{"kind":"binary","op":"-","left":{"kind":"field","var":"Worker","field":"capacity"},"right":{"kind":"field","var":"Job","field":"required_capacity"}}}]},{"kind":"emit","emit":{"type":"JOB_SCHEDULED","class":"operational","payload":{"job":{"kind":"field","var":"Job","field":"id"},"worker":{"kind":"field","var":"Worker","field":"id"}},"non_deterministic":false}}],"inferred_reads":["Job.id","Job.required_capacity","Job.status","Worker.capacity","Worker.id","Worker.status"],"inferred_writes":["Job.status","Lease","Worker.capacity"]}]}
```

---

### golden-17-race.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-17-race","manifest_version":"1.0.0","rules":[{"id":"rule-createifmissing-0001","name":"CreateIfMissing","priority":100,"when":[{"kind":"binding","var":"Key","type":"Key","constraints":[{"field":"id","op":"eq","value":{"kind":"literal","literal_type":"string","value":"k1"}}]},{"kind":"existence","exists":false,"pattern":{"kind":"binding","var":"V","type":"Value","constraints":[{"field":"key","op":"eq_var","var":"Key.id"}]}}],"then":[{"kind":"create","type":"Value","result_var":"NewValue","fields":{"key":{"expr":{"kind":"field","var":"Key","field":"id"}},"value":{"expr":{"kind":"literal","literal_type":"string","value":"v1"}}}}],"inferred_reads":["Key.id","Value.key"],"inferred_writes":["Value"]}]}
```

---

### golden-18-blob.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-18-blob","manifest_version":"1.0.0","rules":[{"id":"rule-storeblob-0001","name":"StoreBlob","priority":50,"when":[{"kind":"binding","var":"Upload","type":"Upload","constraints":[{"field":"status","op":"eq","value":{"kind":"literal","literal_type":"string","value":"ready"}}]}],"then":[{"kind":"create","type":"Blob","result_var":"NewBlob","fields":{"data":{"expr":{"kind":"field","var":"Upload","field":"payload"}},"id":{"expr":{"kind":"field","var":"Upload","field":"id"}},"size":{"expr":{"kind":"call","fn":"len","args":[{"kind":"field","var":"Upload","field":"payload"}]}}}},{"kind":"update","target":"Upload","assigns":[{"field":"status","value":{"kind":"literal","literal_type":"string","value":"stored"}}]}],"inferred_reads":["Upload.id","Upload.payload","Upload.status"],"inferred_writes":["Blob","Upload.status"]}]}
```

---

### golden-19-regex.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-19-regex","manifest_version":"1.0.0","rules":[{"id":"rule-matchemail-0001","name":"MatchEmail","priority":60,"when":[{"kind":"binding","var":"User","type":"User","constraints":[{"field":"email","op":"regex","value":{"kind":"literal","literal_type":"string","value":"@example\\\\.com$"}}]}],"then":[{"kind":"emit","emit":{"type":"USER_MATCH","class":"debug","payload":{"user":{"kind":"field","var":"User","field":"id"}},"non_deterministic":false}}],"inferred_reads":["User.email","User.id"],"inferred_writes":[]}]}
```

---

### golden-20-temporal.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-20-temporal","manifest_version":"1.0.0","rules":[{"id":"rule-recentfailures-0001","name":"RecentFailures","priority":40,"when":[{"kind":"collection","collection":{"var":"Failure","type":"Event","constraints":[{"field":"type","op":"eq","value":{"kind":"literal","literal_type":"string","value":"FAIL"}},{"field":"timestamp","op":">","value":{"kind":"binary","op":"-","left":{"kind":"var","name":"TickStartTime"},"right":{"kind":"literal","literal_type":"integer","value":3600000}}}],"order_by":[{"field":"timestamp","direction":"desc"}]}}],"then":[{"kind":"let","let_name":"recent","expr":{"kind":"collection","source":{"type":"Event","query":{}},"limit":100,"order_by":[{"field":"timestamp","direction":"desc"}]}},{"kind":"emit","emit":{"type":"RECENT_FAILURES","class":"operational","payload":{"count":{"kind":"call","fn":"len","args":[{"kind":"var","name":"recent"}]}},"non_deterministic":false}}],"inferred_reads":["Event.timestamp","Event.type"],"inferred_writes":[]}]}
```

---

### golden-21-rollback.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-21-rollback","manifest_version":"1.0.0","functions":[{"name":"ProvisionVM","kind":"effect","signature":"(identifier)->void","external":true,"effect_meta":{"idempotent":true,"on_timeout":"fail","timeout_ms":10000}}],"rules":[{"id":"rule-provisionwithrollback-0001","name":"ProvisionWithRollback","priority":30,"when":[{"kind":"binding","var":"Request","type":"ProvisionRequest","constraints":[{"field":"status","op":"eq","value":{"kind":"literal","literal_type":"string","value":"pending"}}]}],"then":[{"kind":"update","target":"Request","assigns":[{"field":"status","value":{"kind":"literal","literal_type":"string","value":"provisioning"}}]},{"kind":"call","call":{"fn":"ProvisionVM","args":[{"kind":"field","var":"Request","field":"id"}]}},{"kind":"update","target":"Request","assigns":[{"field":"status","value":{"kind":"literal","literal_type":"string","value":"done"}}]}],"hooks":{"on_failure":[{"id":"RollbackProvision","idempotent":true,"non_deterministic":true}]},"inferred_reads":["ProvisionRequest.id","ProvisionRequest.status"],"inferred_writes":["ProvisionRequest.status"]}]}
```

---

### golden-22-crossref.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-22-crossref","manifest_version":"1.0.0","metadata":{"references":["other-manifest-id@1.0.0"]},"rules":[{"id":"rule-crossmanifestref-0001","name":"CrossManifestRef","priority":10,"when":[{"kind":"binding","var":"External","type":"ExternalNode","constraints":[{"field":"tag","op":"eq","value":{"kind":"literal","literal_type":"string","value":"x"}}]}],"then":[{"kind":"emit","emit":{"type":"EXT_REF","class":"debug","payload":{"id":{"kind":"field","var":"External","field":"id"}},"non_deterministic":false}}],"inferred_reads":["ExternalNode.id","ExternalNode.tag"],"inferred_writes":[]}]}
```

---

### golden-23-constraint.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-23-constraint","manifest_version":"1.0.0","nodes":[{"name":"Lease","fields":{"id":{"type":"identifier"},"status":{"type":"string"},"task":{"type":"Task"}}}],"constraints":[{"kind":"unique","name":"SingleActiveLeasePerTask","target":"Lease.task","where":{"kind":"expression","expr":{"kind":"binary","op":"==","left":{"kind":"field","var":"Lease","field":"status"},"right":{"kind":"literal","literal_type":"string","value":"active"}}}}]}
```

---

### golden-24-wildcard.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-24-wildcard","manifest_version":"1.0.0","rules":[{"id":"rule-projectfields-0001","name":"ProjectFields","priority":20,"when":[{"kind":"binding","var":"Item","type":"Item","constraints":[{"field":"tags","op":"contains","value":{"kind":"literal","literal_type":"string","value":"urgent"}}]}],"then":[{"kind":"let","let_name":"proj","expr":{"kind":"object","fields":{"id":{"kind":"field","var":"Item","field":"id"},"meta":{"kind":"field","var":"Item","field":"metadata"}}}},{"kind":"emit","emit":{"type":"PROJECTED","class":"debug","payload":{"proj":{"kind":"var","name":"proj"}},"non_deterministic":false}}],"inferred_reads":["Item.id","Item.metadata","Item.tags"],"inferred_writes":[]}]}
```

---

### golden-25-deepexpr.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-25-deepexpr","manifest_version":"1.0.0","rules":[{"id":"rule-complexexpr-0001","name":"ComplexExpr","priority":5,"when":[{"kind":"binding","var":"X","type":"X","constraints":[{"field":"cond","op":"expr","value":{"kind":"binary","op":"and","left":{"kind":"binary","op":">","left":{"kind":"call","fn":"computeScore","args":[{"kind":"field","var":"X","field":"metrics"}]},"right":{"kind":"var","name":"threshold"}},"right":{"kind":"binary","op":"or","left":{"kind":"binary","op":"==","left":{"kind":"field","var":"X","field":"flag"},"right":{"kind":"literal","literal_type":"boolean","value":true}},"right":{"kind":"binary","op":">","left":{"kind":"field","var":"X","field":"count"},"right":{"kind":"literal","literal_type":"integer","value":10}}}}}]}],"then":[{"kind":"update","target":"X","assigns":[{"field":"score","value":{"kind":"call","fn":"normalize","args":[{"kind":"binary","op":"+","left":{"kind":"call","fn":"computeScore","args":[{"kind":"field","var":"X","field":"metrics"}]},"right":{"kind":"var","name":"offset"}}]}}]}],"inferred_reads":["X.count","X.flag","X.metrics"],"inferred_writes":["X.score"]}]}
```

---

### golden-26-unique-email.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-26-unique-email","manifest_version":"1.0.0","nodes":[{"name":"User","fields":{"email":{"type":"string"},"id":{"type":"identifier"},"tenant":{"type":"string"}}}],"constraints":[{"kind":"unique","name":"UniqueEmailPerTenant","target":["User.email","User.tenant"]}]}
```

---

### golden-27-tenant.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-27-tenant","manifest_version":"1.0.0","rules":[{"id":"rule-tenantscopedassign-0001","name":"TenantScopedAssign","priority":70,"when":[{"kind":"binding","var":"Tenant","type":"Tenant","constraints":[{"field":"id","op":"eq","value":{"kind":"var","name":"ctx.tenant_id"}}]},{"kind":"binding","var":"Task","type":"Task","constraints":[{"field":"tenant","op":"eq_var","var":"Tenant.id"},{"field":"lifecycle","op":"eq","value":{"kind":"literal","literal_type":"string","value":"pending"}}]}],"then":[{"kind":"create","type":"Lease","result_var":"NewLease","fields":{"agent":{"expr":{"kind":"call","fn":"selectAgentForTenant","args":[{"kind":"field","var":"Tenant","field":"id"}]}},"task":{"expr":{"kind":"var","name":"Task"}}}}],"inferred_reads":["Task.lifecycle","Task.tenant","Tenant.id"],"inferred_writes":["Lease"]}]}
```

---

### golden-28-merge.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-28-merge","manifest_version":"1.0.0","rules":[{"id":"rule-mergemetadata-0001","name":"MergeMetadata","priority":50,"when":[{"kind":"binding","var":"Item","type":"Item","constraints":[{"field":"id","op":"eq","value":{"kind":"literal","literal_type":"string","value":"x"}}]}],"then":[{"kind":"update","target":"Item","assigns":[{"field":"metadata","value":{"kind":"call","fn":"merge","args":[{"kind":"field","var":"Item","field":"metadata"},{"kind":"object","fields":{"seen_by":{"kind":"call","fn":"add","args":[{"kind":"field","var":"Item","field":"metadata.seen_by"},{"kind":"field","var":"User","field":"id"}]}}}]}}]}],"inferred_reads":["Item.id","Item.metadata","User.id"],"inferred_writes":["Item.metadata"]}]}
```

---

### golden-29-path.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-29-path","manifest_version":"1.0.0","rules":[{"id":"rule-pathmatch-0001","name":"PathMatch","priority":60,"when":[{"kind":"binding","var":"A","type":"NodeA","constraints":[{"field":"id","op":"eq","value":{"kind":"literal","literal_type":"string","value":"a1"}}]},{"kind":"edge","edge":"e1","from":"A","to":"B"},{"kind":"edge","edge":"e2","from":"B","to":"C"},{"kind":"binding","var":"C","type":"NodeC","constraints":[{"field":"flag","op":"eq","value":{"kind":"literal","literal_type":"boolean","value":true}}]}],"then":[{"kind":"emit","emit":{"type":"PATH_FOUND","class":"operational","payload":{"a":{"kind":"field","var":"A","field":"id"},"c":{"kind":"field","var":"C","field":"id"}},"non_deterministic":false}}],"inferred_reads":["NodeA.id","NodeC.flag","NodeC.id"],"inferred_writes":[]}]}
```

---

### golden-30-cond-create.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-30-cond-create","manifest_version":"1.0.0","rules":[{"id":"rule-conditionalcreate-0001","name":"ConditionalCreate","priority":55,"when":[{"kind":"binding","var":"X","type":"X","constraints":[{"field":"cond","op":"expr","value":{"kind":"binary","op":">","left":{"kind":"call","fn":"score","args":[{"kind":"var","name":"X"}]},"right":{"kind":"var","name":"threshold"}}}]}],"then":[{"kind":"existence","exists":false,"pattern":{"kind":"binding","var":"Marker","type":"Marker","constraints":[{"field":"x","op":"eq_var","var":"X.id"}]}},{"kind":"create","type":"Marker","result_var":"NewMarker","fields":{"created_at":{"expr":{"kind":"var","name":"TickStartTime"}},"x":{"expr":{"kind":"field","var":"X","field":"id"}}}}],"inferred_reads":["Marker.x","X","X.id"],"inferred_writes":["Marker"]}]}
```

---

### golden-31-rate.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-31-rate","manifest_version":"1.0.0","rules":[{"id":"rule-ratelimitedingest-0001","name":"RateLimitedIngest","priority":20,"when":[{"kind":"binding","var":"Ingest","type":"Ingest","constraints":[{"field":"ready","op":"eq","value":{"kind":"literal","literal_type":"boolean","value":true}}]}],"then":[{"kind":"create","type":"Work","result_var":"NewWork","fields":{"ingest":{"expr":{"kind":"field","var":"Ingest","field":"id"}}}}],"inferred_reads":["Ingest.id","Ingest.ready"],"inferred_writes":["Work"],"custom":{"runtime_hints":{"rate_limit":{"max_per_tick":10}}}}]}
```

---

### golden-32-tenant-boost.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-32-tenant-boost","manifest_version":"1.0.0","rules":[{"id":"rule-tenantpriorityboost-0001","name":"TenantPriorityBoost","priority":80,"when":[{"kind":"binding","var":"Task","type":"Task","constraints":[{"field":"tenant","op":"eq","value":{"kind":"literal","literal_type":"string","value":"T1"}},{"field":"lifecycle","op":"eq","value":{"kind":"literal","literal_type":"string","value":"pending"}}]}],"then":[{"kind":"emit","emit":{"type":"TENANT_TASK","class":"operational","payload":{"task":{"kind":"field","var":"Task","field":"id"}},"non_deterministic":false}}],"inferred_reads":["Task.id","Task.lifecycle","Task.tenant"],"inferred_writes":[],"custom":{"runtime_hints":{"scheduler_overrides":{"priority_boost":20}}}}]}
```

---

### golden-33-atomic.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-33-atomic","manifest_version":"1.0.0","rules":[{"id":"rule-groupedactions-0001","name":"GroupedActions","priority":90,"when":[{"kind":"binding","var":"A","type":"A","constraints":[{"field":"ready","op":"eq","value":{"kind":"literal","literal_type":"boolean","value":true}}]}],"then":[{"kind":"update","target":"A","assigns":[{"field":"status","value":{"kind":"literal","literal_type":"string","value":"processing"}}]},{"kind":"update","target":"B","assigns":[{"field":"linked","value":{"kind":"field","var":"A","field":"id"}}]}],"inferred_reads":["A.id","A.ready"],"inferred_writes":["A.status","B.linked"],"custom":{"transaction":{"atomic":true}}}]}
```

---

### golden-34-deterministic-rand.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-34-deterministic-rand","manifest_version":"1.0.0","custom":{"deterministic_random_seed":"manifest-seed-0001"},"rules":[{"id":"rule-deterministicsample-0001","name":"DeterministicSample","priority":10,"when":[{"kind":"binding","var":"Item","type":"Item","constraints":[{"field":"score","op":">","value":{"kind":"literal","literal_type":"number","value":0.5}}]}],"then":[{"kind":"call","call":{"fn":"rand","args":[]}},{"kind":"emit","emit":{"type":"SAMPLED","class":"debug","payload":{"id":{"kind":"field","var":"Item","field":"id"}},"non_deterministic":true}}],"inferred_reads":["Item.id","Item.score"],"inferred_writes":[]}]}
```

---

### golden-35-capcycle.ir.json
```json
{"ir_version":"grisp-v1.2","manifest_id":"golden-35-capcycle","manifest_version":"1.0.0","edges":[{"name":"extends","from":"Capability","to":"Capability"}],"validation":{"capability_closure":{"has_cycle":true,"cycle_examples":[["A","B","A"]],"warning":"capability_extends contains cycles; manifest-compile should warn or fail depending on mode"}}}
```

---

If you want, I can now:

- Package these canonical `.ir.json` blocks into a single downloadable archive (ZIP) and provide instructions for adding them to your `golden/` directory, or  
- Produce the matching `.grisp` source files for each canonical IR (01–35) so your CI has both source and golden IR, or  
- Generate a Git patch that adds all canonical files into a repository layout with the verification harness.

Which of those would you like next?



One more time:


### Examples 01–12: `.grisp` source files

#### `golden-01-acquire.grisp`
```grisp
rule AcquireLease priority=80 {
  metadata { idempotent = false; emits = ["LEASE_ACQUIRED"] }
  when {
    Task: Task where lifecycle == "pending"
    Agent: Agent where role == "Specialist"
    not exists Lease where Lease.task == Task and Lease.status == "active"
  }
  then {
    create Lease {
      id: NewId(),
      task: Task,
      agent: Agent,
      created_at: TickStartTime,
      renewed_at: TickStartTime,
      expires_at: TickStartTime + 30000,
      status: "active",
      owner_epoch: NextLeaseEpoch(Task)
    }
    update Task { lifecycle: "assigned", updated_at: TickStartTime }
    emit Event(type="LEASE_ACQUIRED", class="operational", payload={ task: Task, agent: Agent })
  }
}
```

#### `golden-02-renew.grisp`
```grisp
rule RenewLease priority=90 {
  when {
    Lease: Lease where Lease.agent == Agent and Lease.owner_epoch == Epoch and Lease.status == "active"
    Agent: Agent where id == Lease.agent
  }
  then {
    call RenewLeaseEffect(Lease.id, Epoch)
    update Lease { renewed_at: TickStartTime, expires_at: TickStartTime + 30000 }
    emit Event(type="LEASE_RENEWED", class="operational", payload={ lease: Lease.id, epoch: Lease.owner_epoch })
  }
}
```

#### `golden-03-steal.grisp`
```grisp
rule StealLease priority=85 {
  when {
    Lease: Lease where Lease.expires_at < TickStartTime or Lease.heartbeat_at < TickStartTime - 60000
    Agent: Agent where role == "Specialist"
  }
  then {
    create Lease {
      id: NewId(),
      task: Lease.task,
      agent: Agent,
      created_at: TickStartTime,
      renewed_at: TickStartTime,
      expires_at: TickStartTime + 30000,
      status: "active",
      owner_epoch: NextLeaseEpoch(Lease.task)
    }
    update Lease { status: "stolen" }
    emit Event(type="LEASE_STOLEN", class="operational", payload={ old: Lease.id, new: NewLease.id })
  }
}
```

#### `golden-04-expire.grisp`
```grisp
rule ExpireLease priority=70 {
  when {
    Lease: Lease where Lease.expires_at < TickStartTime and Lease.status == "active"
  }
  then {
    update Lease { status: "expired" }
    emit Event(type="LEASE_EXPIRED", class="operational", payload={ lease: Lease.id })
  }
}
```

#### `golden-05-capabilities.grisp`
```grisp
node Capability {
  id: identifier
  name: string
}
edge capability_extends(Capability -> Capability)
# capability closure hint handled via runtime profile
```

#### `golden-06-taskflow.grisp`
```grisp
rule PlanTask priority=60 {
  metadata { emits = ["TASK_PLANNED"] }
  when { Goal: Goal where status == "new" }
  then {
    create Task { goal: Goal, lifecycle: "pending" }
    emit Event(type="TASK_PLANNED", class="audit", payload={ goal: Goal.id })
  }
}

rule AssignTask priority=50 {
  metadata { depends_on = ["PlanTask"], emits = ["TASK_ASSIGNED"] }
  when {
    Task: Task where lifecycle == "pending"
    Agent: Agent where has_capacity == true
  }
  then {
    create Lease { task: Task, agent: Agent, expires_at: TickStartTime + 60000, owner_epoch: NextLeaseEpoch(Task) }
    update Task { lifecycle: "assigned" }
    emit Event(type="TASK_ASSIGNED", class="operational", payload={ task: Task.id, agent: Agent.id })
  }
}
```

#### `golden-07-conflict.grisp`
```grisp
rule IncCounterA priority=100 {
  when { Counter: Counter where id == "A" }
  then { update Counter { value: Counter.value + 1 } }
}

rule SetCounterAZero priority=90 {
  when { Counter: Counter where id == "A" and reset == true }
  then { update Counter { value: 0 } }
}
```

#### `golden-08-declared.grisp`
```grisp
rule SafeAssign priority=80 {
  metadata { emits = ["SAFE_ASSIGN"] }
  when { Task: Task where lifecycle == "pending" }
  then {
    create Lease { task: Task, agent: Agent, owner_epoch: NextLeaseEpoch(Task) }
    update Task { lifecycle: "assigned" }
    emit Event(type="SAFE_ASSIGN", class="operational", payload={ task: Task.id })
  }
}
```

#### `golden-09-hook.grisp`
```grisp
rule NotifyOnAssign priority=40 {
  when { Task: Task where lifecycle == "assigned" }
  then {
    emit Event(type="TASK_ASSIGNED", class="operational", payload={ task: Task.id })
  }
  hooks {
    after_commit: [ "SendSlackNotification" ]
  }
}
```

#### `golden-10-effect-timeout.grisp`
```grisp
rule ExternalProvision priority=30 {
  when { Request: ProvisionRequest where status == "pending" }
  then {
    call ProvisionVM(Request.id)
    update Request { status: "provisioning" }
  }
}
# ProvisionVM effect_meta: idempotent=true, timeout_ms=10000, on_timeout=escalate
```

#### `golden-11-nested.grisp`
```grisp
rule TopAgents priority=20 {
  when {
    Task: Task where lifecycle == "pending"
    Completed many Task where lifecycle == "completed" order by completed_at desc, id asc
  }
  then {
    let top = Completed[0:5]
    emit Event(type="TOP_AGENTS", class="debug", payload={ top_count: len(top) })
  }
}
```

#### `golden-12-capclosure.grisp`
```grisp
node Capability {
  id: identifier
  name: string
}
edge capability_extends(Capability -> Capability)
# runtime profile should set materialize_closure = true for this manifest
```

---

### Examples 13–24: `.grisp` source files

#### `golden-13-checkpoint.grisp`
```grisp
node Checkpoint {
  id: identifier
  tick: integer
  graph_hash: string
  created_at: number
  manifest_version: string
}
# Checkpoints are emitted by runtime; schema declared here for tooling.
```

#### `golden-14-sampling.grisp`
```grisp
rule SampledTelemetry priority=10 {
  when { Task: Task where lifecycle == "running" }
  then {
    emit Event(type="TASK_HEARTBEAT", class="operational", payload={ task: Task.id }, emit_hint={ sample_rate: 0.05, aggregate_key: "Task.id" })
  }
}
```

#### `golden-15-ordering.grisp`
```grisp
rule HighPriorityTask priority=100 {
  when { Task: Task where priority >= 90 and lifecycle == "pending" }
  then { emit Event(type="HIGH_PRIORITY", class="operational", payload={ task: Task.id }) }
}
```

#### `golden-16-large-excerpt.grisp`
```grisp
node Worker { id: identifier, capacity: integer, status: string }
node Job { id: identifier, required_capacity: integer, status: string }
node Lease { id: identifier, task: Job, agent: Worker, expires_at: number, owner_epoch: integer }
edge assigned_to(Job -> Worker)

rule ScheduleJob priority=95 {
  when {
    Job: Job where status == "queued"
    Worker: Worker where capacity >= Job.required_capacity and status == "idle"
  }
  then {
    create Lease { task: Job, agent: Worker, expires_at: TickStartTime + 120000, owner_epoch: NextLeaseEpoch(Job) }
    update Job { status: "scheduled" }
    update Worker { capacity: Worker.capacity - Job.required_capacity }
    emit Event(type="JOB_SCHEDULED", class="operational", payload={ job: Job.id, worker: Worker.id })
  }
}
```

#### `golden-17-race.grisp`
```grisp
rule CreateIfMissing priority=100 {
  when {
    Key: Key where id == "k1"
    not exists Value where Value.key == Key.id
  }
  then {
    create Value { key: Key.id, value: "v1" }
  }
}
```

#### `golden-18-blob.grisp`
```grisp
rule StoreBlob priority=50 {
  when { Upload: Upload where status == "ready" }
  then {
    create Blob { id: Upload.id, data: Upload.payload, size: len(Upload.payload) }
    update Upload { status: "stored" }
  }
}
```

#### `golden-19-regex.grisp`
```grisp
rule MatchEmail priority=60 {
  when { User: User where email =~ /@example\.com$/ }
  then { emit Event(type="USER_MATCH", class="debug", payload={ user: User.id }) }
}
```

#### `golden-20-temporal.grisp`
```grisp
rule RecentFailures priority=40 {
  when {
    Failure many Event where type == "FAIL" and timestamp > TickStartTime - 3600000 order by timestamp desc
  }
  then {
    let recent = Failure[0:100]
    emit Event(type="RECENT_FAILURES", class="operational", payload={ count: len(recent) })
  }
}
```

#### `golden-21-rollback.grisp`
```grisp
rule ProvisionWithRollback priority=30 {
  when { Request: ProvisionRequest where status == "pending" }
  then {
    update Request { status: "provisioning" }
    call ProvisionVM(Request.id)
    update Request { status: "done" }
  }
  hooks { on_failure: [ "RollbackProvision" ] }
}
# ProvisionVM effect_meta: idempotent=true, timeout_ms=10000, on_timeout=fail
```

#### `golden-22-crossref.grisp`
```grisp
# References ExternalNode defined in another manifest
rule CrossManifestRef priority=10 {
  when { External: ExternalNode where tag == "x" }
  then { emit Event(type="EXT_REF", class="debug", payload={ id: External.id }) }
}
```

#### `golden-23-constraint.grisp`
```grisp
node Lease {
  id: identifier
  task: Task
  status: string
}
constraint SingleActiveLeasePerTask {
  unique(Lease.task) where Lease.status == "active"
}
```

#### `golden-24-wildcard.grisp`
```grisp
rule ProjectFields priority=20 {
  when { Item: Item where tags contains "urgent" }
  then {
    let proj = { id: Item.id, meta: Item.metadata }
    emit Event(type="PROJECTED", class="debug", payload=proj)
  }
}
```

---

### Examples 25–35: `.grisp` source files

#### `golden-25-deepexpr.grisp`
```grisp
rule ComplexExpr priority=5 {
  when { X: X where computeScore(X.metrics) > threshold and (X.flag == true or X.count > 10) }
  then { update X { score: normalize(computeScore(X.metrics) + offset) } }
}
```

#### `golden-26-unique-email.grisp`
```grisp
node User { id: identifier, email: string, tenant: string }
constraint UniqueEmailPerTenant { unique(User.email, User.tenant) }
```

#### `golden-27-tenant.grisp`
```grisp
rule TenantScopedAssign priority=70 {
  when {
    Tenant: Tenant where id == ctx.tenant_id
    Task: Task where tenant == Tenant.id and lifecycle == "pending"
  }
  then {
    create Lease { task: Task, agent: selectAgentForTenant(Tenant.id) }
  }
}
```

#### `golden-28-merge.grisp`
```grisp
rule MergeMetadata priority=50 {
  when { Item: Item where id == "x" }
  then {
    update Item { metadata: merge(Item.metadata, { seen_by: add(Item.metadata.seen_by, User.id) }) }
  }
}
```

#### `golden-29-path.grisp`
```grisp
rule PathMatch priority=60 {
  when {
    A: NodeA where id == "a1"
    edge e1(A -> B)
    edge e2(B -> C)
    C: NodeC where flag == true
  }
  then { emit Event(type="PATH_FOUND", class="operational", payload={ a: A.id, c: C.id }) }
}
```

#### `golden-30-cond-create.grisp`
```grisp
rule ConditionalCreate priority=55 {
  when { X: X where score(X) > threshold }
  then {
    if not exists Marker where Marker.x == X.id {
      create Marker { x: X.id, created_at: TickStartTime }
    }
  }
}
```

#### `golden-31-rate.grisp`
```grisp
rule RateLimitedIngest priority=20 {
  when { Ingest: Ingest where ready == true }
  then { create Work { ingest: Ingest.id } }
}
# runtime profile: rate_limit.max_per_tick = 10 for this rule
```

#### `golden-32-tenant-boost.grisp`
```grisp
rule TenantPriorityBoost priority=80 {
  when { Task: Task where tenant == "T1" and lifecycle == "pending" }
  then { emit Event(type="TENANT_TASK", class="operational", payload={ task: Task.id }) }
}
# runtime profile: scheduler_overrides.priority_boost = 20 for this rule
```

#### `golden-33-atomic.grisp`
```grisp
rule GroupedActions priority=90 {
  when { A: A where ready == true }
  then {
    update A { status: "processing" }
    update B { linked: A.id }  # B is deterministically chosen
  }
}
# hint: transaction.atomic = true for this rule
```

#### `golden-34-deterministic-rand.grisp`
```grisp
rule DeterministicSample priority=10 {
  when { Item: Item where score > 0.5 }
  then {
    if rand() < 0.1 {
      emit Event(type="SAMPLED", class="debug", payload={ id: Item.id })
    }
  }
}
# manifest-level deterministic_random_seed = "manifest-seed-0001"
```

#### `golden-35-capcycle.grisp`
```grisp
edge extends(Capability -> Capability)
# static data may create cycles; manifest-compile should detect and warn
```

---

**Files delivered:** the 35 `.grisp` source files above are the matching sources for the canonical IRs `golden-01` through `golden-35`. Use these files in your `golden/` directory alongside the canonical `.ir.json` files for CI byte-for-byte verification.