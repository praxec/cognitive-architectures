# Spec A.1 — The HOP Typed-Core Schema Set

> The concrete design of the **one core-codebase change** Spec A allows
> (`docs/spec-stack-aware-specialization.md` §0, §4): the HOP (hand-off point)
> typed core in `praxec-schema`, the `SchemaBound` primitive scoped to the one
> real extension point (`fix` on a detect `Finding`), the tri-state `GateStatus`
> enum, the shared `Severity` enum, and the five slot contract-outs of §3.
> This document clears §11 gate 4 ("full HOP-schema vetting before any code is
> written"). Every engine claim below was verified firsthand against
> `/home/mc/working/mcp-flowgate` (file:line cited); two claims were verified
> **empirically** by running the proposed schema through the real typify
> pipeline (§1.2).

Status: **design, pre-implementation.** Companion to Spec A (parent), Spec B
(detect producer), Spec C (worktrees), Spec D (authoring).

---

## Revision note (v2) — converged design + Fable-vet punch-list

v1 (below) is grounded and correct but predates two decisions. Where the body
conflicts, **this note wins**; the body is retained for its verified grounding.

1. **First-class `hop_slot` primitive (supersedes "convention + detect-heuristic").**
   A slot is a declared transition marker; at load the engine **injects** the
   canonical `<slot>In` as the transition `inputSchema` and `<slot>Out` as the
   `$.context.<slot>` blackboard-slot schema, then resolves `cap.<slot>.<stack>`.
   Enforcement rides seams that already run per-transition: input
   `validate_schema(transition.inputSchema)` (`runtime_submit.rs:749`), output
   `validate_blackboard_writes` (`runtime_records.rs:47`, **kind-agnostic, all 5
   write paths** — a raw `kind:agent` `{status:"pass"}` write is already rejected).
   The slot table is V13. So "unbypassable" is **reject-at-load + already-existing
   runtime validation**, not a new heuristic. The FM-7/FM-9/FM-13 bypass class
   largely evaporates (slot-ness declared, contract engine-owned); the §5 lints
   remain only as defense for non-slot writes.

2. **Vocabulary lives in a STANDALONE `hop.schema.json`, NOT wired into typify /
   `build.rs`.** Because `hopRecord` and typify Rust types are **deferred** (item 3),
   there is no typed `TransitionRecord.hop` field, so the E1 cross-file-`$ref`
   panic **is sidestepped entirely** — it constrained only typify *type generation*,
   which we no longer do. The file is shipped as bytes (`include_str!` **in
   praxec-core directly**, avoiding a new praxec-core→praxec-schema dep edge) and
   enforced at **runtime** via the jsonschema registry. The core value is
   **un-forkable contract bytes + runtime validation**, not compile-time safety
   (vet-confirmed: typify types have zero runtime consumers).

3. **Add `<slot>In` defs** — the v1 set has only `*Out`. The frozen set adds
   `verifyIn`/`detectIn`/`scaffoldIn`/`implementIn`/`lintFormatIn` (matching parent
   §3 `In:` lines), making **input** contracts real and enforced. **Defer**
   `hopRecord` and typify types to "when a consumer exists"; derive
   `not_evaluated`/gate counts from the existing `blackboardDelta` (reconcile the
   "mission outcomes" vehicle with parent §6 — flagged like the §7.6 FailureClass
   note).

4. **Vet punch-list applied:** §4.5 delete the agent-schema **bundler**
   (praxec-agents already deps praxec-core:18 — reuse `compile_validator`) and fix
   the source to the child cap's own `/snippet/outputs`; §4.2 add **step 2b**
   (compile all `snippet.outputs` fragments registry-aware at load, FM-3) +
   **canonical-spelling** enforcement (`praxec://hop#/$defs/<def>` only — the `$id`
   URL spelling also resolves and would evade L2, FM-2); §4.3 **force
   `HOP_REGISTRY` init at serve startup + unit test** (FM-1); §4.4 replace the
   `SCHEMA_BOUND_PATHS` path-DSL with a **hardcoded walk of `findings[].fix`**,
   match designation on the canonical `$ref` fragment tail (inline-copy evasion =
   accepted residual, FM-9); **drop `hopRecord.schema_refs`** (kills cross-crate
   `ExecuteResult` plumbing, duplicates `blackboardDelta`, FM-10); E1b (shared
   bare-name def keyspace across typify inputs) is a **future guard** only — moot
   while the file is standalone. Path nit: `runtime_schema.rs` →
   `runtime/runtime_schema.rs`.

5. **Load-time validity layer** (mirrors parent §4.5): composition soundness,
   typed-mapping compatibility, resolution coverage, slot-contract conformance —
   proving **structural** validity at load; the honest boundary is that semantic
   correctness and runtime behavior fall to runtime fail-fast.

6. **Minimality (three buckets):** *strictly required* = registry-aware
   `compile_validator` + `SchemaBound` (V24 + L2) + the `gateway-config` `schemas:`
   property; *core-vs-config choice* = the vocabulary bytes → **core-anchor for
   un-forkability**; *optional/deferred* = typify types, `hopRecord`.

7. **Parallel edges** — the fan-out/fan-in typed-boundary extension is defined in
   parent §7.1 (a sequenced extension over `kind: parallel`/`cpm-planner`, not a
   new scheduler); the same `In`/`Out` contracts type its map/reduce boundaries.

---

## 1. Engine grounding — the seams this design extends

### 1.1 Verified seams (file:line)

| Seam | Where | What it establishes |
|---|---|---|
| Source-of-truth schemas | `/home/mc/working/mcp-flowgate/schemas/` — `transition-record.schema.json`, `workflow-response.schema.json`, `gateway-config.schema.json`, `praxec-repo.schema.json` | `transition-record.schema.json:1-47` is a flat object (camelCase fields, `blackboardDelta`, `executor {kind, ok, durationMs}`, no `$defs` yet). `workflow-response.schema.json:81-192` already uses same-file `#/$defs/...` refs and builds today — proof the `$defs` pattern works through the pipeline. |
| typify build | `crates/praxec-schema/build.rs:13-17` | Fixed input list `["gateway-config.schema.json", "transition-record.schema.json", "workflow-response.schema.json"]`; each file goes through `add_root_schema` (`build.rs:22-33`) into one `TypeSpace`, emitted as `$OUT_DIR/types.rs`. |
| Typed-view exposure | `crates/praxec-schema/src/lib.rs:1-16` | "The runtime in `praxec-core` operates on `serde_json::Value` for flexibility; these types are convenience for callers that want them." The HOP types follow the same stance. |
| Workspace deps | `/home/mc/working/mcp-flowgate/Cargo.toml:49` `jsonschema = "0.46"`, `:71` `typify = "0.6"`, `:74` `schemars = "0.8"` | No new dependencies needed. |
| Cap-output projection | `crates/praxec-core/src/use_binding.rs` — `resolve_use_inputs:68`, `project_use_outputs:117`, `validate_outputs_against_snippet:153` (jsonschema compile at `:183`), `SchemaViolation:49` | The **existing runtime jsonschema seam**: a capability's declared `snippet.outputs` fragments are validated against the projected output values, all violations collected, audit-ready. |
| Load-time `use:` expansion | `crates/praxec-core/src/config.rs:406-414` (pass 7-sexies), `expand_use_bindings:480`, `_snippetOutputs` embed at `:578` | Snippet output schemas are resolved at **config load** and embedded on the executor config, "so the runtime executor has the schema in hand without doing a DefinitionStore lookup" (`config.rs:460-464`). |
| Executor I/O | `crates/praxec-executors/src/workflow.rs:141-148` (`executor_config` is a `serde_json::Value`; `definitionId` read raw), `:176-184` (`use` block + `_snippetOutputs` read), `:445-451` (envelope validation call), `:483-492` (`ExecutorError::SchemaViolation` fail-fast with joined per-slot reasons) | The exact call site the SchemaBound inner validation extends. |
| Context write path | `crates/praxec-core/src/mapping.rs:18` `merge_output` (call sites `runtime_submit.rs:939, 1076, 1183`), `read_in_scopes:215` | How a slot's output lands at `$.context.<key>`. |
| HOP transience mechanic | `crates/praxec-core/src/runtime/runtime_chain.rs:1143-1200` `clear_state_local_slots_on_exit` — `slots: {<name>: {scope: state}}` context keys are auto-cleared on state exit, with a `workflow.slot.cleared` audit event | The HOP-vs-blackboard lifecycle split (§4.3 of Spec A) is **already mechanized**; no core change needed for it. |
| Agent conformance loop | `crates/praxec-agents/src/rig_runner.rs` — `conforms:173` (keys + declared types), `final_answer` boundary check `:512-517`, retry-with-feedback `conformance_feedback:223`, text salvage `salvage_result:141` | The seam that runtime `SchemaBound`/HOP validation for **agent** producers extends to full jsonschema. |
| Conformance config plumbing | `crates/praxec-agents/src/config.rs:63` `expected_output_keys`, `:72` `expected_output_types`; forwarded to the session at `executor.rs:197-198`; **composed at runtime** by auto-drive from the capability's `inputSchema.required` (`runtime_chain.rs:532-540`) into the agent config (`runtime_chain.rs:596-597`) | Where `expected_output_schema` (new) slots in beside the two existing fields. |
| Escalation wiring | `crates/praxec-core/src/model_resolver/classify.rs:19-42` (`FailureClass`, closed enum), `from_executor_error:106-126` — `AGENT_NO_RESULT`/`AGENT_RESULT_FAILED` → `Capability`; **`SchemaViolation` → `ContentOther` (surfaces)**; `is_infrastructure:48-60` (Capability escalates); chain-walk `walk.rs:164` / `try_next:216`; classified in the agent executor at `executor.rs:318`; NoResult→Capability→escalate proven by tests `executor.rs:664-711` | Persistent agent nonconformance escalates up the model chain; deterministic-producer schema violations surface. §4.4 relies on this exact split. |
| V22 closed-world pattern | `config.rs:2452-2476` `validate_workflow_refs_resolve` — walk merged config, `bail!` `UNRESOLVED_WORKFLOW_REF` with a fix-it message | The pattern the load-time `schema_ref` registry check (V24) copies. |
| V23 override discipline | `config.rs:2227-2256` (`ANONYMOUS_OVERRIDE` / `STALE_OVERRIDE`) | Precedent for loud, explicit config-surface extension. |
| Transition-record emission | `crates/praxec-core/src/runtime/runtime.rs:958-1075` `emit_transition_record` — record json built at `:1036-1053`; **additive-optional field precedent**: script `subject`/`hash` (`:983-1016`, "Fields are additive + optional"); `blackboardDelta` carries the full per-transition context diff (`:1021-1025`, computed at `runtime_submit.rs:1300`) | Where the `hop` summary attaches, and why the record does **not** duplicate the full payload. |
| jsonschema registry API | `~/.cargo/.../jsonschema-0.46.10/src/options.rs:297` `with_registry(&referencing::Registry)`; usage `Registry::new().add(uri, json).prepare()` at `options.rs:1157-1174` | How config-authored `$ref`s into the shipped core schema resolve at validation time. |
| Config surface is closed | `gateway-config.schema.json` and `praxec-repo.schema.json` both declare top-level `additionalProperties: false` (verified by parsing both files) | A new `schemas:` registry block **requires** a one-property extension of `gateway-config.schema.json` (§4.2). |

### 1.2 Two empirical findings that shaped the layout

**E1 — typify 0.6.2 does not support cross-file `$ref`s.** A minimal
reproduction (two root schemas added to one `TypeSpace`, the second referencing
the first via `hop.schema.json#/$defs/gateStatus`) **panics** in
`typify-impl-0.6.2/src/convert.rs:1344`:
`external references are not supported`. Consequence: any type the
`TransitionRecord` struct is to reference at compile time **must live in the
same schema file**. A separate `hop.schema.json` would either fork the type set
(record couldn't reference it — a parallel abstraction) or not exist. So:
**all HOP defs go into `transition-record.schema.json`'s `$defs`** — which is
also the most literal reading of the locked decision ("it EXTENDS
`transition-record.schema.json`").

**E2 — the exact schema in §2 generates cleanly through the real pipeline.**
The full extended `transition-record.schema.json` below was run through a
byte-equivalent copy of `build.rs` (same typify 0.6.2 / schemars 0.8 versions,
alongside the real `gateway-config.schema.json` and
`workflow-response.schema.json`). Generated, with **no name collisions**
against the ~140 existing types:

```
pub enum   GateStatus { Pass, Fail, NotEvaluated }        // serde-renamed pass|fail|not_evaluated
pub enum   Severity   { Info, Warning, Error, Critical }
pub struct SchemaBound { schema_ref: SchemaBoundSchemaRef, value: ::serde_json::Value }
pub struct Finding, Criterion, StackProvenance (+ StackProvenanceSource)
pub struct VerifyOut, DetectOut, ScaffoldOut (+ ScaffoldOutLayer), ImplementOut, LintFormatOut
pub struct HopRecord (+ HopRecordSlot)
pub struct TransitionRecord { …, hop: Option<HopRecord>, … }
```

Note in particular: `"value": true` maps to `::serde_json::Value` — exactly the
`SchemaBound { schema_ref, value }` shape §4.1 of Spec A specifies, with the
inner value opaque to the compile-time type.

---

## 2. The typed-core schema set

### 2.1 Design shape: the envelope IS the slot-out

Spec A §4.2: "**Metastructure = the typed envelope + declared extension
points.** Instance = the inner validated value." The envelope is realized as
**the slot-out object itself** — there is **no wrapper type** (`HopEnvelope {
slot, payload }` union) in v1:

- The spine branches on `$.context.<slot>.status` — a wrapper adds a nesting
  level every guard expression must traverse, for no consumer.
- The one place a cross-slot discriminated view is needed — the audit record —
  gets a flat typed **summary** (`hopRecord`, §2.3), not the payload: the full
  payload is already in `blackboardDelta` (`runtime.rs:1021-1025`), so a full
  envelope on the record would be pure duplication.
- typify's untagged/const-tagged union output is the least ergonomic thing it
  generates; nothing consumes it in v1. Cut per no-speculative-generality. If a
  second consumer appears (e.g. a dashboard wanting `Vec<AnyHop>`), a
  `oneOf`-over-five def is additive later.

Shared vocabulary (`severity`, `gateStatus`, `schemaBound`, `finding`,
`criterion`, `stackProvenance`) lives once in `$defs` and is `$ref`'d by every
slot-out — one `Severity`, one `GateStatus`, exactly as §6.4/§6.5 pin.

**Field naming.** Payload fields are `snake_case` (`rule_id`, `schema_ref`,
`generated_from`) — they are **context-facing** vocabulary, and the engine's
context keys are snake_case throughout (`$.context.vet_findings`
`use_binding.rs:15-17`, `affinity_override` `runtime_chain.rs:567`). The
existing record-level fields stay camelCase untouched; the new `hop` key is
case-neutral and its innards adopt the payload vocabulary rather than
translating at the audit boundary.

### 2.2 The extended `transition-record.schema.json` (verbatim, tested)

Everything below the `hop` property line is **new**; everything above is the
current file (`transition-record.schema.json:1-46`) unchanged.

```json
{
  "$id": "https://praxec.dev/schemas/transition-record.schema.json",
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "TransitionRecord",
  "description": "One immutable record per applied workflow transition, emitted as a workflow.transition audit event.",
  "type": "object",
  "required": ["workflowId", "definitionId", "definitionVersion", "seq", "timestamp", "fromState", "toState", "transition", "actor"],
  "additionalProperties": false,
  "properties": {
    "workflowId": { "type": "string" },
    "…": "— existing properties :10-45 unchanged —",

    "hop": {
      "$ref": "#/$defs/hopRecord",
      "description": "Present when this transition's executor produced a slot HOP (its snippet.outputs $ref one of the slot-out defs below). A typed, queryable summary — the full payload is in blackboardDelta. Additive + optional, same convention as the script executor's subject/hash fields."
    }
  },
  "$defs": {
    "severity": {
      "type": "string",
      "enum": ["info", "warning", "error", "critical"],
      "description": "The ONE shared severity vocabulary (Spec A §6.4). Order is semantic (info < warning < error < critical) for gate thresholds, but the SPINE never compares severities — producers compute gate status; severity appears core-side only on findings and in the hopRecord.severity_max observability field."
    },
    "gateStatus": {
      "type": "string",
      "enum": ["pass", "fail", "not_evaluated"],
      "description": "Spec A §6.5 — typed tri-state. `not_evaluated` = 'I had nothing to check with', never a disguised pass. The spine branches on this and only this."
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
      "description": "Spec A §4.1 — the compile-time-typed extension point. `value` is serde_json::Value in the generated type; validated at the HOP boundary against the pack schema named by schema_ref. v1 scope: exactly ONE designated use — finding.fix."
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
          "description": "Typed provenance, not prose (Spec A §3.1): `user-declared` marks the unaudited user-command fallback; `generic` marks the honest floor."
        },
        "chain": { "type": "array", "items": { "type": "string" }, "default": [], "description": "The walked resolution chain, most-specific-first — mirrors MODEL_RESOLVER_WALK's walked_levels (walk.rs:169)." }
      },
      "description": "Spec A §5.4 — every slot HOP carries stack provenance."
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
          "description": "THE v1 SchemaBound extension point. Optional: verify/lint findings may carry no remediation payload; detect producers SHOULD populate it (Spec B contract). All Spec-B variance confines here (FM13)."
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
        "evidence": { "type": "string", "description": "Free-text in v1 (§7.1). met:true with empty evidence is a doctor WARNING (Spec A §3.1 FM4), deliberately not a schema failure." }
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
    "detectOut": {
      "type": "object",
      "required": ["status", "findings", "provenance"],
      "additionalProperties": false,
      "properties": {
        "status": { "$ref": "#/$defs/gateStatus", "description": "not_evaluated when no ruleset exists for the stack — never pass (Spec A §3.3)." },
        "findings": { "type": "array", "items": { "$ref": "#/$defs/finding" } },
        "ruleset": { "type": "string", "description": "Which ruleset ran (observability; optional)." },
        "provenance": { "$ref": "#/$defs/stackProvenance" }
      }
    },
    "scaffoldOut": {
      "type": "object",
      "required": ["created", "wired", "layer", "summary", "provenance"],
      "additionalProperties": false,
      "properties": {
        "created": { "type": "array", "items": { "type": "string" } },
        "wired": { "type": "array", "items": { "type": "string" } },
        "layer": { "type": "string", "enum": ["contract", "solution", "implementation"], "description": "Closed set per Spec A §3.4 (poka-yoke: typed enum over string)." },
        "generated_from": { "type": "string", "description": "Contract artifact this stub was generated from — marks a generated surface downstream steps must not hand-edit." },
        "summary": { "type": "string" },
        "provenance": { "$ref": "#/$defs/stackProvenance" }
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
    "lintFormatOut": {
      "type": "object",
      "required": ["status", "findings", "fixed", "provenance"],
      "additionalProperties": false,
      "properties": {
        "status": { "$ref": "#/$defs/gateStatus" },
        "findings": { "type": "array", "items": { "$ref": "#/$defs/finding" }, "description": "REMAINING findings after this pass — findings.length drives the loop's progress-monotonicity breaker (Spec A §3.2 FM5)." },
        "fixed": { "type": "array", "items": { "type": "string" }, "description": "Files touched by auto-fix this pass (aligns with created/wired/changed convention; §7.4)." },
        "provenance": { "$ref": "#/$defs/stackProvenance" }
      }
    },
    "hopRecord": {
      "type": "object",
      "required": ["slot", "provenance"],
      "additionalProperties": false,
      "properties": {
        "slot": { "type": "string", "enum": ["verify", "detect", "scaffold", "implement", "lint_format"] },
        "status": { "$ref": "#/$defs/gateStatus", "description": "Present iff the slot is a gate (verify/detect/lint_format). Makes not_evaluated gates countable per run (Spec A §6 observability)." },
        "severity_max": { "$ref": "#/$defs/severity" },
        "finding_count": { "type": "integer", "minimum": 0 },
        "schema_refs": { "type": "array", "items": { "type": "string" }, "default": [], "description": "The inner schemas that were resolved+validated on this HOP — audit trail for the SchemaBound boundary." },
        "provenance": { "$ref": "#/$defs/stackProvenance" }
      },
      "description": "The record-level HOP summary. Full payload lives in blackboardDelta; this is the typed, queryable slice."
    }
  }
}
```

### 2.3 Wiring changes in `praxec-schema`

**`build.rs`: zero change.** `transition-record.schema.json` is already in the
fixed input list (`build.rs:14-16`); its `$defs` flow through the existing
`add_root_schema` call (verified, §1.2 E2).

**`src/lib.rs`: one addition** — export the raw schema text so `praxec-core`
can build the runtime jsonschema registry (§4.3) from the same bytes typify
consumed (single source of truth, no drift):

```rust
/// The raw transition-record schema (source of truth for the HOP typed core).
/// praxec-core registers this under the alias URI `praxec://hop` so that
/// config-authored `$ref`s into `#/$defs/*` resolve at validation time.
pub const HOP_CORE_SCHEMA: &str =
    include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../schemas/transition-record.schema.json"));
```

(Path mechanics identical to `build.rs:6-11`'s `../../schemas` resolution.)

### 2.4 What a pack-registered inner schema looks like (CONFIG, shown for contrast)

Not core — this is the content the `fix` SchemaBound points at, shipped by a
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

### 2.5 The `<slot>In` contracts (v2 addition — makes input contracts real)

The v1 body defined only `*Out`. The frozen set adds the five `*In` defs so a
slot's **input** is engine-injected and validated on entry
(`validate_schema(transition.inputSchema)`, `runtime_submit.rs:749`). These live in
the same standalone `hop.schema.json` `$defs` as the `*Out` defs. Shapes track
parent §3:

```json
"verifyIn":    { "type": "object", "required": ["cwd"],
  "additionalProperties": false,
  "properties": { "cwd": {"type":"string"},
    "file_set": {"type":"array","items":{"type":"string"}},
    "changed_only": {"type":"boolean","default": false} } },

"detectIn":    { "type": "object", "required": ["cwd","ruleset"],
  "additionalProperties": false,
  "properties": { "cwd": {"type":"string"},
    "file_set": {"type":"array","items":{"type":"string"}},
    "changed_only": {"type":"boolean","default": false},
    "ruleset": {"type":"string"} } },

"scaffoldIn":  { "type": "object", "required": ["cwd","layer","artifact_kind","name"],
  "additionalProperties": false,
  "properties": { "cwd": {"type":"string"},
    "layer": {"type":"string","enum":["contract","solution","implementation"]},
    "artifact_kind": {"type":"string"}, "name": {"type":"string"},
    "target_path": {"type":"string"}, "options": {"type":"object"} } },

"implementIn": { "type": "object", "required": ["cwd","deliverable","acceptance_criteria"],
  "additionalProperties": false,
  "properties": { "cwd": {"type":"string"}, "deliverable": {"type":"object"},
    "acceptance_criteria": {"type":"array","items":{"$ref":"#/$defs/criterion"}},
    "skeleton_files": {"type":"array","items":{"type":"string"}},
    "findings": {"type":"array","items":{"$ref":"#/$defs/finding"}},
    "idiom_lens": {"type":"string"} } },

"lintFormatIn":{ "type": "object", "required": ["cwd"],
  "additionalProperties": false,
  "properties": { "cwd": {"type":"string"},
    "file_set": {"type":"array","items":{"type":"string"}},
    "changed_only": {"type":"boolean","default": false},
    "fix": {"type":"boolean","default": true} } }
```

Note `implementIn.acceptance_criteria` reuses `#/$defs/criterion` — the same
criteria whose `met` flags `verifyOut` reports, so the **composition check**
(parent §4.5) can prove the verify step consumes the criteria the implement step
was given. (Field `implementIn.findings` reuses `#/$defs/finding`, letting a
`detect`/`verify` `Out` chain into a fix step through a validated mapping.)

---

## 3. Extends-vs-new map

| Type / surface | Disposition | Grounding |
|---|---|---|
| `severity`, `gateStatus`, `schemaBound`, `stackProvenance`, `finding`, `criterion`, `verifyOut`, `detectOut`, `scaffoldOut`, `implementOut`, `lintFormatOut`, `hopRecord` | **Extend `transition-record.schema.json`** — new `$defs` entries | Forced by E1 (typify externals panic, `typify-impl-0.6.2/src/convert.rs:1344`) + the locked decision. `$defs` precedent: `workflow-response.schema.json:81-192` builds today. |
| `TransitionRecord.hop` | **Extend `transition-record.schema.json`** — one new optional property | Additive-optional precedent: script `subject`/`hash` on the executor descriptor, `runtime.rs:983-1016`. Old records (no `hop`) stay valid — property is not in `required` (`transition-record.schema.json:7`). |
| `schemas:` config block | **Extend `gateway-config.schema.json`** — one new optional top-level property (repo-file layout mirrors the existing `workflows:`/`skills:` blocks) | Required because the config surface is closed: `gateway-config.schema.json` top level is `additionalProperties: false` (verified). File is already in `build.rs:14`. |
| `workflow-response.schema.json` | **Untouched** | The response's `context` is deliberately an untyped `object` (`workflow-response.schema.json:11`) — HOP payloads ride through it unchanged; `outcomes`/`result.status` are already typed (`:60-74`, `:94-110`). Typing the response's context would be a parallel abstraction. |
| `praxec-repo.schema.json` | **Untouched** | It describes repo *metadata* (`name`/`namespace`/`layout`), not definition content. `schemas:` entries live in the repo's config files like every other definition block, namespaced by `load_repo` (V20, `config.rs:2209` region). |
| New schema file | **None** | Rejected: E1 makes a referenced separate file impossible; an unreferenced one is a parallel abstraction. |
| `build.rs` input list | **No change** | `transition-record.schema.json` and `gateway-config.schema.json` already listed (`build.rs:13-17`). |

---

## 4. Boundary-validation design

Four layers — one at load, three at runtime — every one an extension of a
cited existing seam. No new abstraction.

### 4.1 Overview

```
CONFIG LOAD                     RUNTIME (deterministic producer)          RUNTIME (agent producer)
───────────                     ────────────────────────────────          ────────────────────────
V24: schemas: compile           L1 envelope: snippet.outputs $refs        L3 in-session: conforms()
     + schema_ref closed        → validate_outputs_against_snippet          upgraded to full jsonschema
     world (extends V22)          (use_binding.rs:153, registry-aware)      (rig_runner.rs:173/512)
                                L2 SchemaBound: finding.fix value          retry w/ iter_errors feedback
                                → new validate_schema_bound_values         exhaustion → AGENT_NO_RESULT
                                  (workflow.rs, after :445)                → Capability → chain-walk
                                failure → ExecutorError::SchemaViolation    (classify.rs:106-126,
                                → ContentOther → SURFACES                    walk.rs:216)
```

### 4.2 Load time — V24, the closed-world schema registry (extends V22)

New load pass in `config.rs`, sibling to `validate_workflow_refs_resolve`
(`config.rs:2452-2476`), running after repo merge:

1. **Collect** the merged top-level `schemas:` map (entries already
   namespace-prefixed by `load_repo`, exactly like definitionIds — V20).
2. **Compile every entry** with `jsonschema::validator_for` (the compile-check
   pattern already used at `use_binding.rs:183` and `runtime_schema.rs:38`).
   A schema that fails to compile →
   `bail!("V24 SCHEMA_INVALID: schemas entry '<ns>/<name>' does not compile: <err>")`.
   **A bad pack fails at load, not mid-run** (Spec A FM6).
3. **Closed-world `schema_ref` check**: walk the merged config for every
   statically-declared `schema_ref` literal (today: Spec B ruleset blocks and
   any cap-config `fix` defaults; the walk mirrors
   `collect_unresolved_workflow_refs`, `config.rs:2478+`). Unresolved →
   `bail!("V24 SCHEMA_REF_UNRESOLVED: '<ref>' … Unprefixed names resolve in the
   declaring repo's OWN namespace; to reference another pack's schema, fully
   qualify as <namespace>/<name>.")` — same fix-it voice as V22
   (`config.rs:2468-2474`).
4. The compiled validators are retained as
   `Arc<HashMap<String, jsonschema::Validator>>` on the runtime (the
   "compile at load, hand to runtime" move `_snippetOutputs` already makes at
   `config.rs:578`).

*Honesty note:* until Spec B lands rulesets in config, step 3 has few static
occurrences to check — the load-time guarantee is then mostly step 2 (all
registered schemas compile) and the runtime defense-in-depth of §4.4. The walk
is written once; Spec B's ruleset block makes it bite.

### 4.3 Runtime L1 — envelope validation (existing seam, made registry-aware)

Slot caps declare their contract-out by `$ref` into the shipped core defs:

```yaml
# cap.verify.rust (pack config)
snippet:
  outputs:
    verify: { "$ref": "praxec://hop#/$defs/verifyOut" }
```

The whole existing pipeline then applies unchanged: `expand_use_bindings`
embeds it as `_snippetOutputs` at load (`config.rs:406-414, :578`); the
workflow executor projects the child's context (`workflow.rs:443-444` →
`project_use_outputs`, `use_binding.rs:117`) and validates
(`validate_outputs_against_snippet`, `use_binding.rs:153`, called at
`workflow.rs:445-451`); violations → audit `cap.output.schema_violation` +
`ExecutorError::SchemaViolation` (`workflow.rs:460-492`).

**The one change:** both jsonschema compile sites —
`use_binding.rs:183` and `runtime_schema.rs:38` (`validate_schema`, also used
for start-input validation, `runtime_schema.rs:29-46`) — switch from bare
`jsonschema::validator_for(schema)` to a shared helper:

```rust
// praxec-core: one process-wide registry, built once from praxec_schema::HOP_CORE_SCHEMA
static HOP_REGISTRY: LazyLock<jsonschema::Registry> = LazyLock::new(|| {
    jsonschema::Registry::new()
        .add("praxec://hop", serde_json::from_str(praxec_schema::HOP_CORE_SCHEMA).expect("shipped schema parses"))
        .expect("valid URI")
        .prepare()
        .expect("shipped schema is a valid registry resource")
});

pub(crate) fn compile_validator(schema: &Value) -> Result<jsonschema::Validator, jsonschema::ValidationError<'static>> {
    jsonschema::options().with_registry(&HOP_REGISTRY).build(schema)
}
```

API verified against `jsonschema-0.46.10/src/options.rs:297` (`with_registry`)
and the crate's own test at `options.rs:1157-1174`
(`Registry::new().add(uri, json).prepare()`). The alias URI `praxec://hop`
keeps config-side refs short and stable even though the document's `$id` is
the transition-record URL. Schemas containing no external ref behave exactly
as before — the change is strictly widening.

### 4.4 Runtime L2 — `SchemaBound.value` validation (deterministic producers)

New helper in `use_binding.rs` (the module that already owns
`SchemaViolation:49`), called in `workflow.rs` immediately after the L1 call
at `:445-451`, inside the same violation-handling block:

```rust
/// v1 designation table — the ONE extension point (Spec A §4.1 scoping).
/// Keyed by the core def the snippet output $refs; values are the paths at
/// which SchemaBound instances live inside that payload. Closed const —
/// extending it is a deliberate core change (poka-yoke, not a registry).
const SCHEMA_BOUND_PATHS: &[(&str, &str)] = &[
    ("verifyOut",     "findings[*].fix"),
    ("detectOut",     "findings[*].fix"),
    ("lintFormatOut", "findings[*].fix"),
];

pub fn validate_schema_bound_values(
    snippet_outputs: &Value,                      // the embedded _snippetOutputs
    projected: &Map<String, Value>,               // from project_use_outputs
    registry: &HashMap<String, jsonschema::Validator>, // §4.2 step 4
) -> Result<Vec<String> /* validated schema_refs, for hopRecord.schema_refs */, Vec<SchemaViolation>>
```

Semantics, fail-fast with rich diagnostics throughout:

- For each projected output whose snippet schema `$ref`s a designated def,
  walk the designated paths. For each present `fix`:
  - Deserialize the `{schema_ref, value}` envelope (already
    envelope-validated by L1 — L2 never re-checks shape).
  - `schema_ref` not in the registry →
    `SchemaViolation { slot, reason: "finding[3].fix.schema_ref 'x/y' is not a registered schema; registered: [..]" }`.
    This is defense-in-depth: V24 makes it unreachable for honest configs, but
    the invariant must not depend on producer discipline (same rationale as
    `try_next`'s content-failure recheck, `walk.rs:210-215`).
  - `value` invalid → violation carrying every `iter_errors` message (the
    collection style of `use_binding.rs:198-207`).
- Errors funnel into the **existing** violation path at `workflow.rs:452-492`:
  `cap.output.schema_violation` audit event, `emit_cap_terminated`, then
  `ExecutorError::SchemaViolation` (`error.rs:121`, `Permanent` class
  `error.rs:329`).

**Failure routing (deliberate):** `ExecutorError::SchemaViolation` classifies
as `FailureClass::ContentOther` (`classify.rs:104-105, :125`), which
**surfaces** (`is_infrastructure:48-60` excludes it) — correct, because a
*deterministic* producer emitting a malformed fix payload is a tool/pack bug;
walking the model chain cannot repair it. Escalation is reserved for agent
producers (§4.5).

### 4.5 Runtime L3 — the agent conformance loop, extended to full jsonschema

This is the seam Spec A §4.2 names ("extends the existing `final_answer`
conformance loop"). Today the loop enforces keys + scalar types:
`conforms` (`rig_runner.rs:173`) at the `final_answer` boundary
(`:512-517`), on salvaged text (`:141-156`), with re-prompt feedback
(`conformance_feedback:223`). Extension:

1. **`AgentExecConfig` gains** `expected_output_schema: Option<Value>`
   (sibling of `expected_output_keys:63` / `expected_output_types:72` in
   `agents/config.rs`; forwarded to the session like the others at
   `executor.rs:197-198`).
2. **Auto-drive composes it**: where the composer already lifts
   `inputSchema.required` / property types (`runtime_chain.rs:521-540`) into
   the agent config (`:596-597`), it now also passes the capability's full
   output schema (the `_snippetOutputs` fragment, `$ref`s pre-resolved against
   the `praxec://hop` registry at load so praxec-agents needs no registry —
   praxec-agents stays registry-free).
3. **`conforms` upgrade**: when a schema is present, the session compiles it
   once and full-validates the candidate `output`; keys/types checks remain
   the cheap fast path when no schema is declared. `SchemaBound.value`
   validation for agent-emitted findings needs no special case: the composed
   schema can only express the envelope, so the inner value is checked by L2
   when the projection crosses the workflow executor — the agent loop's job is
   to make the *envelope* conform in-session, cheaply.
4. **Feedback gets richer, not different**: `conformance_feedback` includes
   the validator's `iter_errors` lines, so a wrong-shape answer is corrected
   in-session "instead of failing the post-run snippet contract and wasting
   the whole run" (the existing rationale, `rig_runner.rs:507-511`).
5. **Persistent nonconformance** exhausts `max_turns` → `AGENT_NO_RESULT` →
   `FailureClass::Capability` (`classify.rs:96-112`; test
   `executor.rs:664-711`) → `is_infrastructure() == true` (`classify.rs:57`)
   → the chain-walk escalates to a stronger model (`walk.rs:164`,
   `try_next:216`, classified at `executor.rs:318`). **No new wiring** —
   FM7's requirement falls out of the existing path.

> Spec-wording reconciliation: Spec A §4.2 says "persistent nonconformance =
> content `FailureClass`". In the engine's taxonomy the *escalatable* class is
> `Capability` (a weak-model gap), not `ContentSchema`/`ContentOther` (which
> deliberately surface, `classify.rs:34-36`). The behavior Spec A intends —
> "→ existing model chain-walk escalation" — is exactly the `Capability`
> routing above; this doc pins that reading (§7.6).

---

## 5. Context projection fit

**No structural change to projection.** The typed HOPs are ordinary JSON in
`$.context`; the whole path is existing code:

1. A slot capability writes its slot-out to its own `$.context.<name>`; the
   host's `use:` block binds it —
   `use.outputs: { "$.context.verify": "verify" }`.
2. Load time: `expand_use_bindings` synthesizes the transition `output:`
   mapping and embeds `_snippetOutputs` (`config.rs:406-414, 480, 578`).
3. Run time: `project_use_outputs` (`use_binding.rs:117`) pulls the child's
   context values → L1/L2 validation (§4.3/§4.4) → `merge_output`
   (`mapping.rs:18`; call sites `runtime_submit.rs:939, 1076, 1183`) writes
   the host's `$.context.<key>`.
4. **The spine branches on typed core fields only**: guard expressions read
   `$.context.verify.status == "pass"` etc. via the same `read_in_scopes`
   expression engine (`mapping.rs:215`). Nothing reads `fix.value`; nothing
   reads prose. The boundary rule (Spec A §4.2) is enforced by *validated
   shape at the write* + *review of dispatch flows at authoring* — the spine
   cannot branch on what config never surfaces to it.

**Conventions (config, not core):**

- **Well-known context keys** — each slot lands at the key named by the slot
  (`$.context.verify`, `.detect`, `.scaffold`, `.implement`, `.lint_format`).
  Pure pack convention; dispatch flows and guards depend on it, core does not.
- **HOP transience is declared, already mechanized** — spine states declare
  the slot keys state-scoped: `slots: { verify: { scope: state } }` →
  auto-cleared with a `workflow.slot.cleared` audit event on state exit
  (`clear_state_local_slots_on_exit`, `runtime_chain.rs:1143-1200`). This is
  the HOP/blackboard lifecycle split of Spec A §4.3 with **zero new code**.
  Loop states (check→fix→check) exit only when the loop resolves, so
  loop-carried findings persist exactly as long as the loop.

**One addition (core, small):** the `hop` summary on the transition record.
`emit_transition_record` (`runtime.rs:971`) attaches `record["hop"]` when the
transition's executor carried a designated `_snippetOutputs` $ref — slot from
the def name, `status`/`severity_max`/`finding_count` lifted from the
already-validated payload, `schema_refs` returned by L2 (§4.4), `provenance`
copied through. Same additive-optional style as the script `subject`/`hash`
enrichment (`runtime.rs:983-1016`). The full payload is **not** duplicated:
`blackboardDelta` already carries it (`runtime.rs:1021-1025`,
`runtime_submit.rs:1300`).

---

## 6. HOP-vs-blackboard edge classification (SDLC spine)

Mechanically both ride `$.context`; the classification is **lifecycle +
write-discipline** (Spec A §4.3): HOPs are typed, point-to-point,
state-scoped (auto-cleared, §5); blackboard entries are durable, multi-reader,
workflow-scoped.

| Edge | Class | Payload / key | Scope |
|---|---|---|---|
| CPM unit assignment → implement loop | HOP (shape = Spec A §11 open Q2; out of scope here) | per-unit deliverable + file-set | state (per unit) |
| scaffold → implement | **HOP** | `scaffoldOut` at `$.context.scaffold` — `created`/`wired` seed the unit's file surface; `generated_from` marks no-hand-edit files | state |
| implement → verify | **HOP** | `implementOut` at `$.context.implement` — `changed` scopes `changed_only` verify | state |
| verify → loop controller (retry/advance) | **HOP** | `verifyOut` at `$.context.verify` — guard branches on `.status` | state |
| detect → codemod fix loop | **HOP** | `detectOut` at `$.context.detect` — `findings[*].fix` (SchemaBound) pairs `kind: codemod` to the bounded loop | state (loop-carried) |
| detect → implement / review (manual fixes) | **HOP** | same `detectOut`; `kind: manual` findings flow as located guidance | state |
| lint check → lint fix (bounded loop) | **HOP** | `lintFormatOut` at `$.context.lint_format` — `findings.length` drives progress-monotonicity breaker | state (loop-carried) |
| any gate → review (breaker exhaustion) | **HOP** | residual `findings` arrays, advisory | state |
| deliverable spec / brief | **Blackboard** | seed `$.input` + durable context keys | workflow |
| acceptance criteria | **Blackboard** | written once at design, read by implement + verify (criteria ids join `verifyOut.criteria[].id`) | workflow |
| stack descriptor + resolution provenance | **Blackboard** | the resolved profile; per-HOP `provenance` snapshots it point-in-time | workflow |
| decisions log / design artifacts | **Blackboard** | multi-reader | workflow |
| mission outcomes / status | Neither — engine surface | `workflow-response.outcomes` (`workflow-response.schema.json:60-74`), ADR-0008 | engine |
| loop counters (`_fire_count.*`, while-iters) | Neither — engine bookkeeping | scrubbed by the engine (`runtime_chain.rs:1162-1166, 1229-1249`), filtered from agent prompts (`render_agent_data_block`, `:1209`) | engine |

Rule of thumb an author can apply: **if two non-adjacent steps read it, it's
blackboard; if exactly the next step (or the loop it gates) reads it, it's a
HOP and gets `scope: state`.**

---

## 7. Open / risky choices

1. **`criterion.evidence`: free-text string in v1.** Structured evidence
   (`{kind, uri, summary}` like the response `evidence` def,
   `workflow-response.schema.json:159-169`) is strictly additive later
   (greenfield, no deprecation windows). The FM4 guard ("met:true + empty
   evidence") is a doctor **warning**, deliberately not schema-enforceable —
   encoding it as a schema conditional would turn an honesty nudge into a
   run-killer.
2. **Finding location: `line` required, `end_line`/`column` optional.** Spec
   B's tree-sitter matchers natively produce spans — certain, not
   speculative — and adding the optional fields now spares a core rev in the
   very next spec. Single-line producers simply omit them.
3. **`severity` value set `info|warning|error|critical`, no `Ord` in core.**
   The spine never compares severities; producers compute gate status against
   the (config-side) threshold; `severity_max` is observability-only. If a
   core-side comparison consumer ever appears, add a `rank()` helper then —
   the enum order in the schema is already the semantic order.
4. **`lintFormatOut.fixed` = file paths**, aligning with the
   `created`/`wired`/`changed` file-list convention. The alternative (the
   resolved findings themselves) is richer but duplicates what the round
   telemetry (Spec A §6) already counts. Revisit if the fix loop needs
   per-rule fix attribution.
5. **`implementOut.notes` = `array<string>`** (the spec's prose says "notes",
   plural; a single blob invites prose-branching).
6. **"content FailureClass" wording**: pinned to `Capability` for
   agent-producer exhaustion (escalatable) and `ContentOther` for
   deterministic-producer violations (surfaces) — see §4.5 note. If Spec A's
   author intended `ContentSchema` for the agent path, that class would
   *surface* instead of escalate (`classify.rs:57` excludes it), contradicting
   FM7's "→ chain-walk escalation"; flagged for the parent spec to absorb.
7. **Versioning/migration: additive-only, no version field.** Transition
   records are immutable history; the `hop` property is optional so all
   existing records remain schema-valid. Policy: `$defs` evolve additively
   (new optional fields, new defs); a breaking change is a **new def name**
   (`verifyOut2`), not a mutation — and pack-side drift is already load-loud
   via contract-hash pinning (V15/V16). No `hop_version` field: it would be a
   knob with no reader (measurement must change a decision).
8. **`hopRecord.status` optional** (absent for scaffold/implement). The
   alternative — forcing `pass` on non-gates — would fabricate gate signals
   and corrupt the `not_evaluated` count the observability section exists to
   surface.
9. **`schema_ref` grammar** (`^[a-z0-9][a-z0-9._-]*(/[a-z0-9][a-z0-9._-]*)?$`)
   assumes V20's `<namespace>/<name>` shape; confirm the exact namespace
   charset against `load_repo`'s prefixer during implementation and tighten
   the pattern to match — the pattern must never be *looser* than the loader.
10. **V24's static `schema_ref` walk is thin until Spec B** (§4.2 honesty
    note). The runtime unresolved-ref fail-fast (§4.4) carries the invariant
    in the interim.

---

## 8. Minimality check (§0 audit)

The complete core diff, enumerated:

| # | Change | Size | Why it cannot be config |
|---|---|---|---|
| 1 | `transition-record.schema.json`: 12 `$defs` + 1 optional property | 1 file, ~150 lines of schema | The whole point: compile-time types (typify is build-time; packs load at runtime — Spec A §0). |
| 2 | `gateway-config.schema.json`: 1 optional `schemas:` property | ~10 lines | Top-level config surface is `additionalProperties: false`; opening a registry block is definitionally a schema change. |
| 3 | `praxec-schema/src/lib.rs`: `HOP_CORE_SCHEMA` const | 2 lines | Single-sourcing the bytes typify consumed for the runtime registry. |
| 4 | `build.rs` | **zero** | Both touched schema files already in the input list (`build.rs:13-17`). |
| 5 | V24 load pass + compiled-validator map | 1 function + 1 walk, patterned on `config.rs:2452-2476` | Load-time fail-fast is a core guarantee config cannot self-enforce (FM6). |
| 6 | Registry-aware `compile_validator` at 2 call sites (`use_binding.rs:183`, `runtime_schema.rs:38`) | ~15 lines | `$ref praxec://hop#…` cannot resolve without it; strictly widening. |
| 7 | `validate_schema_bound_values` + `SCHEMA_BOUND_PATHS` const + 1 call after `workflow.rs:445` | 1 helper, 1 three-row const | The boundary map (`schema_ref → schema → validate`) is the SchemaBound contract itself (§4.1). The const is the *scope limiter* — v1's "fix only" lock made structural. |
| 8 | `expected_output_schema` + `conforms` upgrade + feedback phrasing in praxec-agents | 1 field, ~30 lines | Extends the existing loop rather than adding a validator elsewhere — the no-parallel-abstraction requirement. |
| 9 | `hop` summary lift in `emit_transition_record` | ~25 lines | The record is engine-emitted; only the engine can attach it. |

**Deliberately pushed OUT of core (config / later):**
- All inner `fix` schemas, rulesets, severity thresholds, slot registrations,
  dispatch flows, stack profiles — pack config (Spec A §2.3/§8).
- Well-known context keys and `scope: state` HOP declarations — pack YAML
  conventions riding existing mechanics (§5).
- The `HopEnvelope` discriminated-union type — cut, no v1 consumer (§2.1).
- SchemaBound generalization to a registry of extension points — cut per the
  v1 lock; `SCHEMA_BOUND_PATHS` is where a second consumer would land, loudly.
- Severity ordering helper, `hop_version`, structured evidence, family
  inheritance, manifest auto-detection — all additive later, none blocks v1.
- `STACK_RESOLVED` audit events and per-unit resolution — Spec A resolver
  work, not typed-core; the core only *carries* their result
  (`stackProvenance`).

Nothing in rows 1–9 varies per stack; everything that varies per stack has a
config home. That is §0's boundary, held.

---

*Grounding: all file:line references against `mcp-flowgate` @ branch
`readme-repositioning` (a6537d8), 2026-07-08. Empirical checks (§1.2) ran
typify 0.6.2 / schemars 0.8.22 / jsonschema 0.46.10 — the exact workspace
versions.*
