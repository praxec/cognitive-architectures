# Spec A.1 — The HOP Typed-Core Schema Set

> The concrete design of the **one core-codebase change** Spec A allows
> (`docs/spec-stack-aware-specialization.md` §0, §2.3, §4): the canonical HOP
> (hand-off point) vocabulary shipped as a standalone `schemas/hop.schema.json`,
> the `hop_slot:` first-class primitive that injects and enforces it, the
> `SchemaBound` extension point scoped to the one real use (`fix` on a `finding`),
> the tri-state `GateStatus`, the shared `Severity`, and a typed `In`/`Out`
> contract for each of the five specialization slots. This document clears the
> parent §11 gate ("full HOP-schema vetting before any code is written"). Every
> engine claim is verified firsthand against `/home/mc/working/mcp-flowgate`
> (file:line inline).

Status: **design, pre-implementation.** Companion to Spec A (parent), Spec B
(detect producer), Spec C (worktrees), Spec D (authoring).

---

## 0. The shape of the design in one paragraph

The HOP vocabulary is **one canonical JSON Schema file** — `schemas/hop.schema.json`
— shipped in the binary and **enforced at runtime by jsonschema validation**, not
by generated Rust types. A slot is a **first-class declared marker** (`hop_slot:`)
on a transition; at load the engine **injects** that slot's canonical `In` schema
as the transition's `inputSchema` and its canonical `Out` schema as the
`$.context.<slot>` blackboard-slot schema, then resolves the concrete
`cap.<slot>.<stack>`. Both contracts are then enforced by **per-transition seams
that already exist** — so an LLM (or an LLM-authored flow) cannot produce or
consume a slot HOP that dodges its contract. The only core codebase change is the
one schema file plus the load-time injector/validator that wires it in; every
per-stack variability lives in config.

---

## 1. Engine grounding — the seams this design rides

All claims verified firsthand against `/home/mc/working/mcp-flowgate`.

### 1.1 Enforcement already exists per-transition (the key facts)

| Seam | Where | What it gives us |
|---|---|---|
| **Output validation, kind-agnostic** | `crates/praxec-core/src/runtime/runtime_records.rs:47` `validate_blackboard_writes` — called on **all five** output-merge paths (`runtime_submit.rs:958`, `:1190-1191`; `runtime_chain.rs:802`, `:878`, `:343`) | Validates a transition's `output:` writes against the typed `blackboard:` slot schema **regardless of executor kind**. A raw `kind:agent` writing `{status:"pass"}` into a typed slot is already rejected `BLACKBOARD_TYPE_ERROR` (`runtime_submit.rs:967`) before the transition advances. This is why "unbypassable at runtime" is *mostly already built*. |
| Slot predicate constraints | `crates/praxec-core/src/slot/slot_constraint.rs:54` `evaluate_constraints`, called `runtime_submit.rs:984` | Non-JSON-Schema predicates at the same write site (`SLOT_CONSTRAINT_VIOLATED`). |
| **Input validation, per-transition** | `crates/praxec-core/src/runtime/runtime_submit.rs:749-767` `validate_schema(transition.inputSchema)` + `apply_schema_defaults` | Every submit validates the actor's `arguments` against the transition `inputSchema`, rejecting `INPUT_SCHEMA_VIOLATION`. Input contracts need **no new validation machinery** — only that the transition's `inputSchema` *be* the canonical `<slot>In`. |
| Injector precedent | `crates/praxec-core/src/config.rs:425` `synthesize_input_schema` (from an `inputs:` block); `:480` `expand_use_bindings` (synthesizes the `output:` mapping, embeds `_snippetOutputs`) | Direct precedent for the load-time move `hop_slot:` makes — synthesize/inject a schema onto a transition at load. |
| Slot table | V13 (`crates/praxec-core/src/slot/slot_table.rs`) | The typed blackboard-slot table `validate_blackboard_writes` checks against. `hop_slot:` injects the slot's `Out` schema into this table for `$.context.<slot>`. |
| `slots:` keyword is taken | `crates/praxec-core/src/runtime/runtime_chain.rs:1172` — `states.<name>.slots` are state-scoped blackboard decls (auto-clear) | The specialization marker must use a **distinct keyword**: `hop_slot:` (collision called out deliberately). |
| Cap-output projection + envelope validation | `crates/praxec-core/src/use_binding.rs` — `project_use_outputs:117`, `validate_outputs_against_snippet:153` (jsonschema compile `:183`), `SchemaViolation:49` | The existing seam that validates a cap's `snippet.outputs` fragments against projected values — made registry-aware (§4.3) so a `$ref` into the shipped `hop.schema.json` resolves. |
| Load-time `use:` expansion | `config.rs:406-414`, `expand_use_bindings:480`, `_snippetOutputs` embed `:578` | Snippet output schemas resolved at load and embedded on the executor config. |
| Executor I/O | `crates/praxec-executors/src/workflow.rs:441-492` — envelope validation call `:445-451`, `ExecutorError::SchemaViolation` fail-fast `:483-492` | The call site the `SchemaBound` inner validation extends. |
| Context write path | `crates/praxec-core/src/mapping.rs:18` `merge_output` (`runtime_submit.rs:939, 1076, 1183`), `read_in_scopes:215` | How a slot's output lands at `$.context.<key>` and how guards read it. |
| HOP transience mechanic | `runtime_chain.rs:1143-1200` `clear_state_local_slots_on_exit` — `slots:{<name>:{scope:state}}` context keys auto-cleared on state exit (`workflow.slot.cleared` event) | The HOP/blackboard lifecycle split (§6) is **already mechanized**; no core change. |
| Agent conformance loop | `crates/praxec-agents/src/rig_runner.rs` — `conforms:173` (keys + declared types), `final_answer` boundary `:512-517`, `conformance_feedback:223`, `salvage_result:141` | The seam runtime `SchemaBound`/HOP validation for **agent** producers extends to full jsonschema. praxec-agents already depends on praxec-core (`crates/praxec-agents/Cargo.toml:18`). |
| Escalation wiring | `crates/praxec-core/src/model_resolver/classify.rs:19-42` (`FailureClass`), `from_executor_error:106-126` — `AGENT_NO_RESULT`/`AGENT_RESULT_FAILED` → `Capability`; `SchemaViolation` → `ContentOther`; `is_infrastructure:48-60` (Capability escalates); chain-walk `walk.rs:164`/`try_next:216`; test `executor.rs:664-711` | Persistent agent nonconformance escalates up the model chain; deterministic-producer schema violations surface (§4.4/§4.5). |
| V22 closed-world pattern | `config.rs:2452-2476` `validate_workflow_refs_resolve` — walk merged config, `bail!` `UNRESOLVED_WORKFLOW_REF` | The pattern the load-time `$ref`/`schema_ref` check (V24) copies. |
| V23 override discipline | `config.rs:2227-2256` (`ANONYMOUS_OVERRIDE`/`STALE_OVERRIDE`) | Precedent for loud, explicit config-surface extension. |
| jsonschema registry API | `~/.cargo/.../jsonschema-0.46.10/src/options.rs:297` `with_registry(&referencing::Registry)`; `Registry::new().add(uri, json).prepare()` `:1157-1174` | How config-authored `$ref`s into the shipped schema resolve at validation time. Verified: an alias URI (`praxec://hop`) that differs from the document `$id` resolves correctly, and a resource is *also* addressable by its own `$id` — see the canonical-spelling guard (§4.2). |
| Config surface is closed | `gateway-config.schema.json` top level is `additionalProperties: false` (verified) | A new `schemas:` registry block requires a one-property extension of `gateway-config.schema.json` (§4.2). |

### 1.2 Why the vocabulary is a standalone file, not typed structs

The vocabulary ships as **bytes for runtime validation**, not as typify-generated
Rust types. Two grounded reasons:

- **The runtime has no consumer for the types.** The spine branches on JSON via
  the expression engine (`read_in_scopes`, `mapping.rs:215`); guards read
  `$.context.verify.status == "pass"`; no crate depends on `praxec-schema`
  (verified across `crates/*/Cargo.toml`). Generated structs would be inert. The
  guarantee comes from **runtime jsonschema validation**, not from types.
- **typify 0.6.2 cannot resolve cross-file `$ref`s** — `convert_reference`
  unconditionally `panic!("external references are not supported")`
  (`typify-impl-0.6.2/src/convert.rs:1343-1345`; identical in 0.7.0 at `:1357`),
  reproduced in a harness. This *only* constrains type generation, which we do
  not do — so a standalone `hop.schema.json` with internal `$ref`s is clean.
  (Recorded as a **future guard**: if a typed view is ever wanted, the defs would
  need to move into a single typify input file, and def names must then be unique
  across input files — typify shares one bare-name def keyspace, `util.rs:551-561`.)

So `hop.schema.json` stays out of `build.rs`. It is loaded by `praxec-core` via
`include_str!` and registered for runtime validation (§4.3).

---

## 2. The typed-core schema set — `schemas/hop.schema.json`

### 2.1 Structure: one file, per-activity contracts, shared building blocks

`hop.schema.json` is a single JSON Schema document whose `$defs` hold:

- **shared building blocks** — `severity`, `gateStatus`, `schemaBound`,
  `stackProvenance`, `finding`, `criterion` — defined **once** and `$ref`'d by the
  slot contracts (one `Severity`, one `GateStatus`, one `Finding` shape across all
  slots), and
- **a distinct `In` and `Out` contract per slot activity** — `verifyIn`/`verifyOut`,
  `detectIn`/`detectOut`, `scaffoldIn`/`scaffoldOut`, `implementIn`/`implementOut`,
  `lintFormatIn`/`lintFormatOut`.

These are the **specialization-slot** contracts — the interop boundary between the
generic spine and any stack's pack, which is exactly why they must be identical
everywhere (hence core + un-forkable). Non-slot steps (design, FMECA, review) pass
data through `$.context` too, but validated by ordinary per-flow config schemas,
not this frozen vocabulary.

**Anti-divergence (why one canonical file cannot drift).** There are no copies. A
workflow holds a `hop_slot:` marker; a slot cap holds a `$ref` into
`praxec://hop#/$defs/<def>`; the engine injects the single definition. A load-time
check resolves every such `$ref` (§4.2, V24-style), canonical-spelling is enforced
(§4.2), and contract-hash pinning (V15/V16) makes any change loud. One definition,
referenced everywhere, un-forkable by a pack or a workflow.

**Field naming.** Payload fields are `snake_case` (`rule_id`, `schema_ref`,
`generated_from`) — the engine's context keys are snake_case throughout
(`$.context.vet_findings` `use_binding.rs:15-17`).

### 2.2 The vocabulary (`schemas/hop.schema.json`)

```json
{
  "$id": "https://praxec.dev/schemas/hop.schema.json",
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "PraxecHopVocabulary",
  "description": "Canonical hand-off-point contracts for the specialization slots. Registered at runtime under alias praxec://hop; referenced by slot caps and injected by the hop_slot: primitive. Runtime-validated, not typify-generated.",
  "$defs": {
    "severity": {
      "type": "string",
      "enum": ["info", "warning", "error", "critical"],
      "description": "The ONE shared severity vocabulary (parent §6). Order is semantic (info < warning < error < critical) for config-side gate thresholds, but the SPINE never compares severities — producers compute gate status; severity appears core-side only on findings."
    },
    "gateStatus": {
      "type": "string",
      "enum": ["pass", "fail", "not_evaluated"],
      "description": "Parent §6 — typed tri-state. `not_evaluated` = 'I had nothing to check with', never a disguised pass. The spine branches on this and only this."
    },
    "schemaBound": {
      "type": "object",
      "required": ["schema_ref", "value"],
      "additionalProperties": false,
      "properties": {
        "schema_ref": {
          "type": "string",
          "pattern": "^[a-z0-9][a-z0-9._-]*(/[a-z0-9][a-z0-9._-]*)?$",
          "description": "Names a pack-registered inner schema (top-level `schemas:` block), namespaced per repo like definitionIds (V20). Must resolve at CONFIG LOAD (V24, §4.2); unresolved at runtime = fail-fast defense-in-depth."
        },
        "value": true
      },
      "description": "Parent §4 — the runtime-validated extension point. `value` is opaque JSON, validated at the HOP boundary against the pack schema named by schema_ref. v1 scope: exactly ONE designated use — finding.fix."
    },
    "stackProvenance": {
      "type": "object",
      "required": ["stack", "source"],
      "additionalProperties": false,
      "properties": {
        "stack": { "type": "string", "description": "The chain link that won resolution, e.g. 'framework:react' / 'language:rust' / 'generic'." },
        "source": {
          "type": "string",
          "enum": ["pack", "user-declared", "generic"],
          "description": "Typed provenance, not prose (parent §3.1): `user-declared` marks the unaudited user-command fallback; `generic` marks the honest floor."
        },
        "chain": { "type": "array", "items": { "type": "string" }, "default": [], "description": "The walked resolution chain, most-specific-first — mirrors MODEL_RESOLVER_WALK's walked_levels (walk.rs:169)." }
      },
      "description": "Parent §5.4 — every slot HOP carries stack provenance."
    },
    "finding": {
      "type": "object",
      "required": ["file", "line", "rule_id", "severity", "message"],
      "additionalProperties": false,
      "properties": {
        "file": { "type": "string" },
        "line": { "type": "integer", "minimum": 1 },
        "end_line": { "type": "integer", "minimum": 1, "description": "Optional span end (tree-sitter producers, Spec B). Absent = single line." },
        "column": { "type": "integer", "minimum": 1 },
        "rule_id": { "type": "string" },
        "severity": { "$ref": "#/$defs/severity" },
        "message": { "type": "string" },
        "fix": {
          "$ref": "#/$defs/schemaBound",
          "description": "THE v1 SchemaBound extension point. Optional: verify/lint findings may carry no remediation payload; detect producers SHOULD populate it (Spec B contract). All Spec-B variance confines here."
        }
      }
    },
    "criterion": {
      "type": "object",
      "required": ["id", "met", "evidence"],
      "additionalProperties": false,
      "properties": {
        "id": { "type": "string" },
        "met": { "type": "boolean" },
        "evidence": { "type": "string", "description": "Free-text in v1 (§9). met:true with empty evidence is a doctor WARNING (parent §3.1), deliberately not a schema failure." }
      }
    },

    "verifyIn": {
      "type": "object", "required": ["cwd"], "additionalProperties": false,
      "properties": {
        "cwd": { "type": "string" },
        "file_set": { "type": "array", "items": { "type": "string" } },
        "changed_only": { "type": "boolean", "default": false }
      }
    },
    "verifyOut": {
      "type": "object",
      "required": ["status", "summary", "criteria", "provenance"],
      "additionalProperties": false,
      "properties": {
        "status": { "$ref": "#/$defs/gateStatus", "description": "pass iff criteria.all(met). Producer-computed; spine branches here." },
        "summary": { "type": "string" },
        "criteria": { "type": "array", "items": { "$ref": "#/$defs/criterion" } },
        "findings": { "type": "array", "items": { "$ref": "#/$defs/finding" }, "default": [] },
        "provenance": { "$ref": "#/$defs/stackProvenance" }
      }
    },
    "detectIn": {
      "type": "object", "required": ["cwd", "ruleset"], "additionalProperties": false,
      "properties": {
        "cwd": { "type": "string" },
        "file_set": { "type": "array", "items": { "type": "string" } },
        "changed_only": { "type": "boolean", "default": false },
        "ruleset": { "type": "string" }
      }
    },
    "detectOut": {
      "type": "object",
      "required": ["status", "findings", "provenance"],
      "additionalProperties": false,
      "properties": {
        "status": { "$ref": "#/$defs/gateStatus", "description": "not_evaluated when no ruleset exists for the stack — never pass (parent §3.3)." },
        "findings": { "type": "array", "items": { "$ref": "#/$defs/finding" } },
        "ruleset": { "type": "string", "description": "Which ruleset ran (observability; optional)." },
        "provenance": { "$ref": "#/$defs/stackProvenance" }
      }
    },
    "scaffoldIn": {
      "type": "object", "required": ["cwd", "layer", "artifact_kind", "name"], "additionalProperties": false,
      "properties": {
        "cwd": { "type": "string" },
        "layer": { "type": "string", "enum": ["contract", "solution", "implementation"] },
        "artifact_kind": { "type": "string" },
        "name": { "type": "string" },
        "target_path": { "type": "string" },
        "options": { "type": "object" }
      }
    },
    "scaffoldOut": {
      "type": "object",
      "required": ["created", "wired", "layer", "summary", "provenance"],
      "additionalProperties": false,
      "properties": {
        "created": { "type": "array", "items": { "type": "string" } },
        "wired": { "type": "array", "items": { "type": "string" } },
        "layer": { "type": "string", "enum": ["contract", "solution", "implementation"], "description": "Closed set per parent §3.4." },
        "generated_from": { "type": "string", "description": "Contract artifact this stub was generated from — marks a surface downstream steps must not hand-edit." },
        "summary": { "type": "string" },
        "provenance": { "$ref": "#/$defs/stackProvenance" }
      }
    },
    "implementIn": {
      "type": "object", "required": ["cwd", "deliverable", "acceptance_criteria"], "additionalProperties": false,
      "properties": {
        "cwd": { "type": "string" },
        "deliverable": { "type": "object" },
        "acceptance_criteria": { "type": "array", "items": { "$ref": "#/$defs/criterion" } },
        "skeleton_files": { "type": "array", "items": { "type": "string" } },
        "findings": { "type": "array", "items": { "$ref": "#/$defs/finding" } },
        "idiom_lens": { "type": "string" }
      }
    },
    "implementOut": {
      "type": "object",
      "required": ["changed", "summary", "provenance"],
      "additionalProperties": false,
      "properties": {
        "changed": { "type": "array", "items": { "type": "string" } },
        "summary": { "type": "string" },
        "notes": { "type": "array", "items": { "type": "string" }, "default": [] },
        "provenance": { "$ref": "#/$defs/stackProvenance" }
      }
    },
    "lintFormatIn": {
      "type": "object", "required": ["cwd"], "additionalProperties": false,
      "properties": {
        "cwd": { "type": "string" },
        "file_set": { "type": "array", "items": { "type": "string" } },
        "changed_only": { "type": "boolean", "default": false },
        "fix": { "type": "boolean", "default": true }
      }
    },
    "lintFormatOut": {
      "type": "object",
      "required": ["status", "findings", "fixed", "provenance"],
      "additionalProperties": false,
      "properties": {
        "status": { "$ref": "#/$defs/gateStatus" },
        "findings": { "type": "array", "items": { "$ref": "#/$defs/finding" }, "description": "REMAINING findings after this pass — findings.length drives the loop's progress-monotonicity breaker (parent §3.2)." },
        "fixed": { "type": "array", "items": { "type": "string" }, "description": "Files touched by auto-fix this pass (aligns with created/wired/changed convention)." },
        "provenance": { "$ref": "#/$defs/stackProvenance" }
      }
    }
  }
}
```

**Cross-slot type links that make the composition check real (§5).**
`implementIn.acceptance_criteria` reuses `#/$defs/criterion` — the same criteria
whose `met` flags `verifyOut` reports — so the load-time composition check can
prove `verify` consumes the criteria `implement` was given.
`implementIn.findings` reuses `#/$defs/finding`, letting a `detect`/`verify` `Out`
chain into a fix step through a validated mapping.

### 2.3 What a pack-registered inner schema looks like (CONFIG, for contrast)

Not core — this is the content the `fix` `SchemaBound` points at, shipped by a
stack pack (Spec B owns its evolution):

```yaml
# in a stack pack's repo config — namespaced to e.g. "cogarch/fix.ts-codemod" by load_repo (V20)
schemas:
  fix.ts-codemod:
    type: object
    required: [kind]
    additionalProperties: false
    properties:
      kind:   { enum: [codemod, manual] }
      recipe: { type: string }
```

A detect producer then emits
`fix: { schema_ref: "cogarch/fix.ts-codemod", value: { kind: "codemod", recipe: "…" } }`.

---

## 3. The `hop_slot` primitive — declared, injected, unbypassable

A slot is a **first-class declared transition marker**: `hop_slot: <name>` (the
keyword avoids the taken `slots:`, `runtime_chain.rs:1172`). Declaring
`hop_slot: verify` makes the engine, at **load time**:

1. **Inject** the canonical `verifyIn` (from `hop.schema.json`) as the transition's
   `inputSchema`, and `verifyOut` as the `$.context.verify` blackboard-slot schema
   in the slot table (V13). The author cannot supply, omit, or diverge the
   contract — the engine owns it. (Precedent: `synthesize_input_schema`
   `config.rs:425`, `expand_use_bindings` `config.rs:480`.)
2. **Resolve** the marker to the concrete `cap.verify.<stack>` (parent §2.3
   mechanisms: additive repo layering + `overrides:`, or a dispatch flow).

Both contracts are then enforced by seams **that already run on every transition**:
input via `validate_schema(transition.inputSchema)` (`runtime_submit.rs:749` →
`INPUT_SCHEMA_VIOLATION`), output via `validate_blackboard_writes`
(`runtime_records.rs:47`, kind-agnostic, all five write paths). A raw `kind:agent`
writing `{status:"pass"}` into `$.context.verify` is therefore already rejected at
runtime before the transition advances.

**Why this is an allowlist, not a denylist.** Slot-ness is *declared* and the
contract is *engine-owned*, so "a slot without its contract" is unrepresentable —
there is no un-fenced convention to *detect* and no schema-identity to *match*.
This eliminates the bypass class an earlier detect-heuristic approach had to hunt
(a `kind:agent` slot write, a cap with no output schema, an inline-copied
non-canonical schema, a dual `$ref` spelling). Those become moot; the load lints
in §7 remain only as defense for **non-slot** writes to a slot-named key.

**New engine work for the primitive:** the `hop_slot:` load-time expansion pass
(inject `In`/`Out`, wire resolution) + one doctor rule. Runtime enforcement is
reuse.

---

## 4. Boundary validation

Four layers — one at load, three at runtime — each an extension of a cited seam,
no new abstraction.

```
CONFIG LOAD                         RUNTIME (deterministic producer)        RUNTIME (agent producer)
───────────                         ────────────────────────────────        ────────────────────────
V24: register hop.schema.json;      L1 envelope: snippet.outputs $refs      L3 in-session: conforms()
     compile all `schemas:` +       → validate_outputs_against_snippet       upgraded to full jsonschema
     `snippet.outputs` fragments;     (use_binding.rs:153, registry-aware)   (rig_runner.rs:173/512),
     closed-world schema_ref;       L2 SchemaBound: findings[].fix value      retry w/ iter_errors feedback;
     canonical-spelling check       → validate_schema_bound_values           exhaustion → AGENT_NO_RESULT
                                       (workflow.rs, after :445)              → Capability → chain-walk
                                     failure → SchemaViolation → ContentOther  (classify.rs, walk.rs:216)
                                       → SURFACES
```

### 4.1 Load time — V24 closed-world registry (extends V22)

New load pass in `config.rs`, sibling to `validate_workflow_refs_resolve`
(`config.rs:2452-2476`), after repo merge:

1. **Register** `praxec_core`'s bundled `hop.schema.json` bytes under alias
   `praxec://hop`, and **collect** the merged top-level `schemas:` map (entries
   namespace-prefixed by `load_repo`, V20).
2. **Compile every `schemas:` entry** with the registry-aware `compile_validator`
   (§4.2). Failure → `bail!("V24 SCHEMA_INVALID: schemas entry '<ns>/<name>' does not compile: <err>")`.
   A bad pack fails at load, not mid-run.
3. **Step 2b — compile every `snippet.outputs` fragment** the same way (the
   `_snippetOutputs` embed pass already visits them all, `config.rs:571-578`). A
   typo'd core `$ref` (`verifyOutt`) or unregistered scheme fails **at load**, not
   at first execution.
4. **Closed-world `schema_ref` check** — walk the merged config for every static
   `schema_ref` literal (mirrors `collect_unresolved_workflow_refs`,
   `config.rs:2478+`). Unresolved → `bail!("V24 SCHEMA_REF_UNRESOLVED: '<ref>' … fully qualify as <namespace>/<name>.")` — the V22 fix-it voice.
5. **Canonical-spelling check** — any `$ref` into the shipped vocabulary must be
   spelled `praxec://hop#/$defs/<def>`. The document is *also* resolvable by its
   own `$id` URL (verified), and that spelling would satisfy L1 while evading the
   L2 `SchemaBound` designation (which matches on the canonical fragment) — so a
   non-canonical spelling into the shipped schema is rejected/normalized at load.
6. Retain the compiled validators as `Arc<HashMap<String, jsonschema::Validator>>`
   on the runtime (the "compile at load, hand to runtime" move `_snippetOutputs`
   already makes, `config.rs:578`).

*Honesty note:* until Spec B lands rulesets in config, step 4 has few static
occurrences to check — the load-time guarantee is then mostly steps 2–3 (all
registered schemas and all snippet fragments compile) plus the runtime
defense-in-depth of §4.3. The walk is written once; Spec B's ruleset block makes
it bite.

### 4.2 Registry-aware `compile_validator`

Slot caps declare their contract-out by `$ref` into the shipped vocabulary:

```yaml
# cap.verify.rust (pack config)
snippet:
  outputs:
    verify: { "$ref": "praxec://hop#/$defs/verifyOut" }
```

The existing pipeline applies unchanged (`expand_use_bindings` embeds
`_snippetOutputs`; the workflow executor projects and validates at
`workflow.rs:445-451`). **The one change:** the two jsonschema compile sites —
`use_binding.rs:183` and `runtime/runtime_schema.rs:38` (`validate_schema`, also
start-input validation) — switch from bare `jsonschema::validator_for` to a shared
registry-aware helper:

```rust
// praxec-core: one process-wide registry, built once from the bundled hop.schema.json bytes
static HOP_REGISTRY: LazyLock<jsonschema::Registry> = LazyLock::new(|| {
    jsonschema::Registry::new()
        .add("praxec://hop", serde_json::from_str(HOP_SCHEMA).expect("shipped hop schema parses"))
        .expect("valid URI")
        .prepare()
        .expect("shipped hop schema is a valid registry resource")
});

// bundled bytes, single-sourced (no praxec-core → praxec-schema dep edge)
const HOP_SCHEMA: &str = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../schemas/hop.schema.json"));

pub(crate) fn compile_validator(schema: &Value) -> Result<jsonschema::Validator, jsonschema::ValidationError<'static>> {
    jsonschema::options().with_registry(&HOP_REGISTRY).build(schema)
}
```

API verified against `jsonschema-0.46.10/src/options.rs:297` and the crate test
`:1157-1174`. The alias URI keeps config-side refs short and stable. Schemas with
no external `$ref` behave exactly as before — the change is strictly widening.

**FM-1 mitigation:** the `LazyLock` `.expect()`s would otherwise panic on *first
deref mid-run* if the shipped bytes were malformed. Force the registry at **serve
init** (one deref) and add a unit test asserting it prepares — so a broken shipped
schema is a boot failure, not a latent crash.

### 4.3 `SchemaBound.value` validation (deterministic producers)

New helper in `use_binding.rs` (which already owns `SchemaViolation:49`), called in
`workflow.rs` right after the L1 call at `:445-451`, inside the same
violation-handling block. **v1 designation is hardcoded** — the one extension point
is `findings[].fix`, so a small explicit walk, not a path-DSL:

```rust
// The ONE v1 extension point (parent §4 scoping): SchemaBound lives at findings[].fix
// on verifyOut / detectOut / lintFormatOut. Extending this set is a deliberate core change.
```

Semantics, fail-fast with rich diagnostics:

- For each projected output whose snippet schema `$ref`s a designated slot-out,
  walk its `findings[].fix`. For each present `fix` (already envelope-validated by
  L1 — L2 never re-checks shape):
  - `schema_ref` not in the registry → `SchemaViolation { slot, reason:
    "finding[3].fix.schema_ref 'x/y' is not a registered schema; registered: [..]" }`
    (defense-in-depth: V24 makes it unreachable for honest configs, but the
    invariant must not depend on producer discipline — same rationale as
    `try_next`'s content-failure recheck, `walk.rs:210-215`).
  - `value` invalid → violation carrying every `iter_errors` message
    (`use_binding.rs:198-207` style).
- Errors funnel into the **existing** path `workflow.rs:452-492`:
  `cap.output.schema_violation` audit, `emit_cap_terminated`, then
  `ExecutorError::SchemaViolation`.

**Failure routing (deliberate):** `SchemaViolation` classifies as
`FailureClass::ContentOther` (`classify.rs:104-105, :125`), which **surfaces**
(`is_infrastructure` excludes it) — correct, because a *deterministic* producer
emitting a malformed `fix` is a tool/pack bug the model chain cannot repair.

*Accepted residual (FM-9):* an inline-copied, structurally-identical slot-out
schema (no `$ref`) passes L1 but evades L2 designation. The canonical-spelling
check (§4.1 step 5) catches wrong-*spelling* refs; a full structural copy is a
low-probability curated-pack authoring error, and L1 still enforces the full
envelope shape — only the inner `fix.value` escapes. Accepted, given
contract-hash pinning (V15/V16) keeps packs stable.

### 4.4 The agent conformance loop, extended to full jsonschema (agent producers)

Today the loop enforces keys + scalar types: `conforms` (`rig_runner.rs:173`) at
the `final_answer` boundary (`:512-517`), with `conformance_feedback:223`.
Extension:

1. **`AgentExecConfig` gains** `expected_output_schema: Option<Value>` (sibling of
   `expected_output_keys`/`expected_output_types`, `agents/config.rs:63/72`;
   forwarded like the others at `executor.rs:197-198`).
2. **Auto-drive composes it** where it already lifts `inputSchema.required`
   (`runtime_chain.rs:521-540`) into the agent config (`:596-597`). The schema is
   the **child capability's own `/snippet/outputs`** fragment (in scope via the
   child `definition` while the composer drives the child's transitions) — **not**
   the host's `_snippetOutputs` (which is out of scope there). The join rule: a
   key's schema is enforced iff the argument key equals the snippet output name,
   else fall back to keys/types.
3. **No bundler.** praxec-agents already depends on praxec-core
   (`Cargo.toml:18`), so the session compiles the fragment with the shared
   `compile_validator` (registry-aware). praxec-agents needs no registry of its
   own and no ref-inlining pass.
4. **`conforms` upgrade:** when a schema is present, full-validate the candidate
   `output`; keys/types remain the fast path when none is declared. `SchemaBound`
   inner values need no special case here — the composed schema expresses only the
   envelope; the inner value is checked by L2 when the projection crosses the
   workflow executor **for a use-bound slot cap** (the sanctioned path). A direct,
   non-use-bound agent write is the FM-7 case handled by §7's lint.
5. **Feedback is richer, not different:** `conformance_feedback` includes the
   validator's `iter_errors` lines, correcting a wrong-shape answer in-session
   rather than wasting the whole run.
6. **Persistent nonconformance** exhausts `max_turns` → `AGENT_NO_RESULT` →
   `FailureClass::Capability` (`classify.rs:96-112`; test `executor.rs:664-711`) →
   `is_infrastructure()` → chain-walk escalation (`walk.rs:164`, `try_next:216`).
   **No new wiring.**

**FailureClass reconciliation (flag for the parent):** the parent's "persistent
nonconformance = content `FailureClass`" is self-contradictory in engine terms —
content classes never trigger chain-walk fall-through (`classify.rs:34-36`). The
correct, engine-consistent reading, pinned here: **agent exhaustion →
`Capability` (escalates); deterministic `SchemaViolation` → `ContentOther`
(surfaces).** The parent should adopt this wording (its §4.1 `severity`-comment
and §4.2 FailureClass phrasing).

---

## 5. Load-time validity layer (the "workflow typechecker")

Because slots are first-class and their `In`/`Out` are engine-known, more than
per-step shape is provable at load. Each check converts a runtime failure class
into a load failure a flow cannot even load with — especially valuable for
LLM-authored flows (Spec D):

- **Composition soundness** — every required `<B>In` field is *satisfiable* from an
  upstream slot's `<Out>` or a declared input/blackboard source in the flow. A
  mis-wired chain will not load. (The cross-slot `$ref` links in §2.2 — e.g.
  `implementIn.acceptance_criteria` reusing `criterion` — are what make this
  checkable.)
- **Typed-mapping compatibility** — a mapping feeding a `string` context path into
  an integer-typed field is a load error, not a runtime surprise.
- **Slot-contract conformance** — a `hop_slot: X` resolves to a cap whose declared
  I/O matches the injected `<X>In`/`<X>Out` (trivially true when the engine
  injects, checked when a cap declares its own).
- **Resolution coverage** — every stack a flow claims to support has a registered
  slot cap or a generic default (no dead branch → warning-clean, parent §5.5).

**Honest boundary.** These prove **structural** validity (shapes present, refs
resolve, mappings compatible, chains satisfiable). They **cannot** prove
**semantic correctness** (a shape-valid mapping of the *wrong* field) or **runtime
behavior** (whether the verify command actually exercises the code). Those fall to
runtime fail-fast + review. The principle: *prove at load everything structurally
provable; runtime fail-fast everything else; nothing silent.*

---

## 6. Context projection + HOP-vs-blackboard

### 6.1 Chaining is mappings, not schema identity

HOPs flow through `$.context`; **A's `Out` is not B's `In`** — they are independent
contracts joined by a **mapping** (the argument projection). A slot writes its
`Out` to `$.context.<slot>` (validated on exit); the flow maps a slice of context
into the next step's `arguments`; that step's `arguments` are validated against its
`In` on entry. This allows fan-in (a step draws from several upstream outputs +
the blackboard), fan-out, and transformation. Both ends are validated, so a
wrong-*shape* mapping fails fast at entry; a shape-valid *wrong-field* mapping is
the semantic limit §5 names.

No structural change to projection is needed — the whole path is existing code
(`project_use_outputs` `use_binding.rs:117` → L1/L2 → `merge_output` `mapping.rs:18`
→ guards via `read_in_scopes` `mapping.rs:215`).

### 6.2 Transience is already mechanized

Spine states declare slot keys state-scoped — `slots: { verify: { scope: state } }`
→ auto-cleared with a `workflow.slot.cleared` event on state exit
(`clear_state_local_slots_on_exit`, `runtime_chain.rs:1143-1200`). This is the
HOP/blackboard lifecycle split with **zero new code**. Loop states (check→fix→check)
exit only when the loop resolves, so loop-carried findings persist exactly as long
as the loop. (Note: `scope: state` is the state-scoped `slots:` decl; the
specialization marker is the distinct `hop_slot:` — §3.)

### 6.3 Edge classification (SDLC spine)

HOPs are typed, point-to-point, state-scoped; blackboard entries are durable,
multi-reader, workflow-scoped.

| Edge | Class | Payload / key | Scope |
|---|---|---|---|
| CPM unit assignment → implement loop | HOP (shape = parent §11 open Q2) | per-unit deliverable + file-set | state |
| scaffold → implement | **HOP** | `scaffoldOut` @ `$.context.scaffold`; `created`/`wired` seed the file surface | state |
| implement → verify | **HOP** | `implementOut` @ `$.context.implement`; `changed` scopes `changed_only` verify | state |
| verify → loop controller | **HOP** | `verifyOut` @ `$.context.verify`; guard branches on `.status` | state |
| detect → codemod fix loop | **HOP** | `detectOut`; `findings[].fix` (SchemaBound) pairs `kind:codemod` to the loop | state (loop-carried) |
| lint check → lint fix | **HOP** | `lintFormatOut`; `findings.length` drives the breaker | state (loop-carried) |
| any gate → review (breaker exhaustion) | **HOP** | residual `findings`, advisory | state |
| deliverable spec / acceptance criteria | **Blackboard** | seed `$.input`; criteria ids join `verifyOut.criteria[].id` | workflow |
| stack descriptor + resolution provenance | **Blackboard** | resolved profile; per-HOP `provenance` snapshots it | workflow |
| mission outcomes / status | Engine surface | `workflow-response.outcomes` (`:60-74`) | engine |

Rule of thumb: **if two non-adjacent steps read it, it's blackboard; if exactly
the next step (or the loop it gates) reads it, it's a HOP with `scope: state`.**

---

## 7. Poka-yoke lints (defense for non-slot writes)

With `hop_slot:` first-class, the bypass class largely evaporates. Two load-time
lints remain as defense for authoring mistakes on **non-slot** paths:

- **A transition that writes a slot-named key (`$.context.{verify,detect,scaffold,implement,lint_format}`)
  without an injected `hop_slot` contract errors at load.** The core knows the five
  slot names; a slot-named write with no contract is the FM-7/FM-13 hole. Slots
  MUST be `hop_slot:`-declared. (Softens the earlier over-strong claim "the spine
  cannot branch on what config never surfaces" — config *can* surface an
  unvalidated write on a non-slot path; this lint closes it.)
- **Gate guards must compare `== "pass"`.** A negative-form guard (`status != "fail"`)
  reads `not_evaluated`/missing as pass, defeating the tri-state. A doctor lint on
  dispatch-flow guards flags negative comparisons against `.status`.

---

## 8. Deferred (optional — added when a consumer exists)

- **typify Rust types** — zero runtime consumers today (§1.2). If a Rust-side
  consumer (cockpit, a dashboard) ever wants typed views, generate then; the E1
  cross-file constraint and the def-name-uniqueness guard (§1.2) apply at that
  point, not now.
- **`hopRecord` transition-record summary** — a typed, queryable per-transition
  slice (`slot`/`status`/`severity_max`/`finding_count`/`provenance`). Deferred:
  `blackboardDelta` (`runtime.rs:1021-1025`) already carries the full per-transition
  payload, so `not_evaluated`/gate counts are derivable by a query. If built later,
  it attaches additively to the transition record (script `subject`/`hash`
  precedent, `runtime.rs:983-1016`) and **omits `schema_refs`** (that field alone
  required cross-crate `ExecuteResult` plumbing and duplicated `blackboardDelta`).
- **Observability vehicle — open, flagged for the parent.** Parent §6 pins gate
  status surfaced in *mission outcomes*; this doc defers `hopRecord` and derives
  counts from `blackboardDelta`. Reconcile with the parent (same treatment as the
  §4.4 FailureClass flag): either wire gate status into `workflow-response.outcomes`
  or accept the `blackboardDelta`-query path.

---

## 9. Open / risky choices

1. **`criterion.evidence`: free-text in v1.** Structured evidence (`{kind, uri,
   summary}`) is additive later. The FM4 guard ("met:true + empty evidence") is a
   doctor **warning**, deliberately not schema-enforceable (a schema conditional
   would turn an honesty nudge into a run-killer).
2. **Finding location:** `line` required, `end_line`/`column` optional — Spec B's
   tree-sitter matchers produce spans natively; adding the optional fields now
   spares a schema rev next spec. Single-line producers omit them.
3. **`severity` set `info|warning|error|critical`, no `Ord` in core** — the spine
   never compares; producers compute gate status against the config-side threshold.
   If a core comparison consumer appears, add `rank()` then; the schema order is
   already semantic.
4. **`lintFormatOut.fixed` = file paths** — aligns with `created`/`wired`/`changed`.
5. **`implementOut.notes` = `array<string>`** — plural, so a single blob doesn't
   invite prose-branching.
6. **Additive-only versioning, no version field** — `$defs` evolve additively; a
   breaking change is a **new def name** (`verifyOut2`), not a mutation; pack drift
   is load-loud via V15/V16. No `hop_version` (a knob with no reader).
7. **`schema_ref` grammar** assumes V20's `<namespace>/<name>` shape; confirm the
   exact namespace charset against `load_repo`'s prefixer during implementation and
   tighten to match — never looser than the loader.

---

## 10. Minimality — the three buckets

The premise, verified: the engine already provides transport (`project_use_outputs`
+ `merge_output`), transience (`clear_state_local_slots_on_exit`), and per-transition
audit (`emit_transition_record` + `blackboardDelta`). This design re-implements
none of them. The core change decomposes:

**Bucket 1 — strictly required (no config path):**
| Change | Why config can't do it |
|---|---|
| `schemas/hop.schema.json` (the vocabulary bytes) + `include_str!` in praxec-core | Shipped, un-forkable interop contract; runtime-registered. |
| `gateway-config.schema.json`: one optional `schemas:` property | Top-level config is `additionalProperties:false`; opening the registry block is a schema change. |
| Registry-aware `compile_validator` (2 sites) + `HOP_REGISTRY` (+ serve-init + test) | A `$ref praxec://hop#…` cannot resolve without it; strictly widening. |
| V24 load pass (register + compile `schemas:` + step-2b fragments + closed-world + canonical-spelling) | Load-time fail-fast is a core guarantee config can't self-enforce. |
| `validate_schema_bound_values` (hardcoded `findings[].fix` walk) + 1 call after `workflow.rs:445` | The `schema_ref → schema → validate(value)` step is engine behavior. |
| `hop_slot:` load-time expansion (inject `In`/`Out`, wire resolution) + 1 doctor rule | Declared-slot injection — the primitive itself (§3). |
| Two non-slot lints (§7) | Load-time structural guards. |

**Bucket 2 — core-vs-config choice, resolved to CORE:** the vocabulary content.
It *could* live as a config pack schema `$ref`'d via the existing seam, but a
config-owned vocab is forkable/overridable (V23); a **core-shipped one is
un-forkable and single-sourced**. The interop contract earns core-anchoring — the
core value is un-forkable contract **bytes enforced at runtime**, not compile-time
types.

**Bucket 3 — optional / deferred:** typify Rust types (inert, no consumer),
`hopRecord` + its emission lift (`blackboardDelta` serves the query), the
observability-vehicle reconciliation (§8).

**Agent-side (praxec-agents):** `expected_output_schema` field + `conforms`
upgrade + feedback phrasing — extends the existing loop, no parallel abstraction,
no bundler (§4.4).

Nothing in Bucket 1 varies per stack; everything that varies per stack has a config
home. That is parent §0's boundary, held. The parallel fan-out/fan-in edges reuse
these same `In`/`Out` contracts to type their map/reduce boundaries — defined as a
sequenced extension in parent §7.1, not a new mechanism here.

---

*Grounding: all file:line references against `mcp-flowgate` (2026-07-08). The
jsonschema registry behavior (alias URI vs `$id` dual addressability), the typify
cross-file-`$ref` panic, and the FailureClass routing were each reproduced/verified
in a harness against the exact workspace versions (jsonschema 0.46.10, typify
0.6.2, schemars 0.8).*
