# Spec A — Stack-Aware Workflow Specialization

> Make the cognitive-architecture SDLC flows **language- and framework-aware**
> without forking a workflow per stack. The reasoning spine stays generic; only
> the implementation edge specializes, resolved at runtime from a stack
> descriptor. Design target: a cognitive architecture so effective that a
> frontier model *reaches for it* rather than reasoning unaided — the repo's core
> thesis, instantiated for polyglot work.

**Revision note (v2).** Revised after a Fable adversarial FMECA/poka-yoke/TRIZ
vetting pass whose engine claims were re-verified against the praxec source
(`/home/mc/working/mcp-flowgate`, file:line cited inline). The headline change:
§2 was grounded on constraint **V11 (no nested flows), which the engine has
RELAXED** — so this version re-grounds the mechanism on the *actual* engine. Two
gates remain open by explicit request (§11): a **repo-priority/precedence**
mechanism, and a **full HOP-schema vetting before any code is written**.

This is **Spec A of a family of four**. Three subsystems it names but does not
design are carried separately:

- **Spec B — the declarative detector MCP tool** (`detect`'s deterministic
  engine: tree-sitter + pluggable matchers, playbook→config compilation,
  severity-tagged rules). Spec A defines its *consumer contract* (the `detect`
  slot); Spec B designs the producer.
- **Spec C — worktree parallelism lifecycle** (true git-worktree isolation for
  concurrent implement units + PR-back + cleanup-on-merge). Execution substrate.
- **Spec D — specialization authoring** (updates to `praxec-meta` so users author
  their own stack packs against the contracts A/B define; see §8.1).

Sequencing: **Spec A → Spec B → Spec C → Spec D.** The slot contracts here *are*
Spec B's public API (contract precedes tool); Spec D authors against A/B.

---

## 0. The core/config boundary (the principle that governs everything)

The design goal is **maximum in configuration, minimum in core code** — but "core"
is not empty. The line:

> **Core holds the stable typed contracts.** The HOP (hand-off point) typed core,
> the slot I/O types, the `SchemaBound` primitive, the tri-state gate enum, the
> `Severity` enum. Compile-time, ships with the binary, extends `praxec-schema`
> (which already uses typify). This is the *only* core codebase change the design
> requires, and it is small and stable — a bounded contract surface, not content.
>
> **Config holds all the variability.** Stack packs, `detect` rulesets, idiom
> lenses, codegen scripts, dispatch flows, stack profiles, severity retunes.
> Everything that *varies per stack* is a pack/config concern with no core code.

Why the typed core *cannot* be config: the spine branches only on typed core
fields (§4.2); typify is build-time while packs load at runtime; and the
guarantee that a malformed handoff can't cross a transition is a compile-time
property config can't provide. "Minimal core" means the core *is the contract*,
not the content.

---

## 1. The core move

The cognitive layer is already language-agnostic in *structure*. Orchestrators
(`flow.add-feature`, `flow.safe-refactor`, `flow.bugfix-from-error-log`, …) call
capabilities (`cap.verify.workspace-green`), which bottom out in
`scripts-library/` leaf scripts. Rust is baked into the **leaves**
(`test.cargo.workspace`, `lint.rust.clippy-strict`, `build.cargo.release`), not
the reasoning. The reasoning MCP tools — `fmeca`, `cpm-planner`, `elicitation`,
`scientific-process`, `log-analyzer`, `crossmatrix` — are language-neutral.

So the seam is clean:

> **Cognitive orchestration + reasoning MCP tools stay shared. Only the
> toolchain-and-idiom leaves specialize. Language bites at the implementation
> edge, never in the reasoning.**

This spec adds a **slot-resolution layer + a pack format + a config surface**. It
is a *seam-and-registry* job. **Honest scope (corrected in v2):** the *pattern*
reuse is dense (config layering, `model_resolver` walk, V22 closed-world,
`final_answer` conformance retry, doctor rules, lifecycle conventions) — but the
resolver, dispatch flows, registry validation, and per-unit resolution are all
**new code**. The earlier "≈90% already exists" claim was optimistic; the
patterns exist, the code does not.

### Rejected alternative: the specialization matrix

Forking a whole orchestrator per stack — `{Rust, C#, Python, Go, TS} ×
{React, Preact, Vue, …} × {add-feature, bugfix, …}` — yields hundreds of
near-identical files whose shared 90% must be edited N times to improve one step.
Rejected: specialization is **data the spine pulls in**, not a workflow you fork.

---

## 2. Engine grounding (re-verified against source)

All claims below were confirmed by reading `/home/mc/working/mcp-flowgate`.

### 2.1 V11 is RELAXED — flows may nest flows

`crates/praxec-core/src/validate.rs:225` — *"V11 (flows-must-not-invoke-flows)
RELAXED: flows may now invoke other flows via `kind: workflow`."* Runtime
recursion is bounded: `MAX_WORKFLOW_DEPTH = 10`
(`crates/praxec-executors/src/workflow.rs:74`), fail-fast with
`WORKFLOW_DEPTH_EXCEEDED` (`:158-164`).

**Consequences:**
- The bounded `check → fix → check` loops (lint, detect-codemod) become
  **reusable flows** with guarded back-edges — **no inline duplication.** The
  earlier "loops must inline into the spine" corollary is gone.
- `docs/spec-fmeca-converge.md` teaches the stale "must inline" rule and **must be
  de-staled** (§9).

### 2.2 V10 is still ACTIVE — capabilities may not invoke workflows

`validate.rs:1621` — *"V10 — capabilities MUST NOT invoke other workflows … only
flows may invoke other workflows."* So anything that dispatches to a sub-workflow
must be a **flow**, not a capability. Simple leaf work stays a capability.

### 2.3 Slot resolution mechanism (was "open"; now resolved)

Both mechanisms the v1 draft proposed are **refuted by the live engine**:
- **Dynamic `definitionId`** (`cap.verify.${stack.profile}`) — dead. V22 requires
  every `kind: workflow` ref to statically resolve at load
  (`config.rs:2450`, `UNRESOLVED_WORKFLOW_REF`), and the executor reads
  `definitionId` raw with no template rendering (`workflow.rs:142`).
- **Dispatch *capability*** — dead, by V10 (§2.2).

**The engine-true mechanisms (all config, no forced core change):**
1. **Additive layering + host override (single-stack / explicit — the common
   case).** Repos deep-merge, later-wins, arrays concatenate (`config.rs:7`,
   `:191-198`); each repo is uniquely namespaced (V20, `:2209`). Dropping a stack
   pack into `repos:` **unions its namespaced definitions in** — genuinely
   additive, no central edit. The host may shadow a generic slot with the stack's
   binding via an explicit `overrides:` entry (V23, `:2227-2256`). **Host-config
   only.**
2. **Per-slot dispatch *flow* (polyglot / per-deliverable runtime selection).** A
   flow (legal post-§2.1) branches on the stack descriptor to literal per-stack
   targets, with an **unguarded generic default** (which also makes it
   warning-clean, matching the real doctor rule at `validate.rs:367`). It is a
   **YAML flow in a pack — config, not core.** Adding a stack costs one config
   edit to this flow.
3. **Optional future engine feature:** template-resolved `definitionId` against a
   load-time-declared candidate set (preserving V22's closed world) → makes even
   (2) zero-touch. **Polish, never required.** Do not build first; the dispatch
   flows carry an explicit deletion plan if it lands.

### 2.4 Nesting vs spawning (both available)

- **Spawning (confirmed, `praxec-agents/src/orchestrator.rs`, `gateway.rs`):** an
  orchestrator *starts* independent flow instances as their own top-level
  lifecycles, coordinated via the mission/outcome model — own audit trail, own
  HITL surface, own worktree (Spec C). This is how **parallelism** is expressed.
- **Nesting (now legal, depth-capped):** available for composition where a
  synchronous sub-flow result is wanted.

Parallel implement units (§7) use spawning; the fix-loops use nesting.

---

## 3. The six slots

A **slot** is a stack-resolved unit of work honoring a **typed I/O contract**
(the HOP, §4). Resolution is by the mechanisms in §2.3. The spine knows only the
contract, never the innards — so a specialization ranges from a one-line cap to a
multi-state flow.

| Slot | Kind | Fires | Specializes by |
|---|---|---|---|
| `scaffold` | deterministic | new-artifact only (conditional) | native generator / template / codegen |
| `detect` | deterministic | anti-pattern pass | Spec-B rulesets (tree-sitter etc.) |
| `implement` | lens | code-writing | hash-pinned idiom **skill** |
| `verify` | toolchain | correctness gate | build/test command |
| `lint_format` | toolchain | style gate | linter/formatter command |
| `framework layering` | resolution dimension | — | the stack descriptor chain |

Generic-spine, **not** slots (untouched): design, FMECA, validate,
review-as-judgment.

### 3.1 `verify` — the correctness gate

- **Deliverable:** "what we asked was delivered." Bound to *this deliverable's
  acceptance criteria*, not blanket workspace-green.
- **In:** `{ cwd, file_set?, changed_only }`
- **Out:** `{ status: pass | fail | not_evaluated, summary,
  criteria: [{ id, met, evidence }], findings: [...] }`. **`status` is a typed
  tri-state** (see §6) — the spine branches on it, never on prose. `pass` iff
  `criteria.all(met)`.
- **Evidence required (FM4 poka-yoke):** a criterion with `met:true` and empty
  `evidence` is a load-time doctor warning; a registration mapping zero criteria
  is flagged. Guards against a vacuously-green verify.
- **Scope TRIZ (FM4):** `changed_only` runs in the inner implement loop; a full
  `verify.workspace.green` runs once at cohort merge (both scripts already
  exist). Fast inner gate, thorough outer net.
- **Registrations:** `cap.verify.rust` (cargo build+test), `.python`
  (pytest+mypy), `.ts-react` (tsc+vitest).
- **Generic fallback:** runs a user-declared verify command, labelled
  `user-declared (unaudited)` in the run record (typed provenance, not prose).
  Unknown stack *and* no command → `status: not_evaluated` — never a silent pass.

### 3.2 `lint_format` — the style gate

- **Deliverable:** "the diff conforms to the stack's style/lint standard."
- **Shape:** a bounded **`check → {clean? exit} → fix → check …`** loop — now a
  **reusable flow** (§2.1, guarded back-edge + circuit breaker), not inlined.
  Remaining findings on breaker-exhaustion → `review` (advisory).
- **Leaves:** `cap.lint.check.<stack>` (rustfmt/clippy, prettier/eslint incl.
  stock `eslint-plugin-react-hooks`, ruff) + `cap.lint.fix.<stack>`.
- **Ordering (FM5):** detect-codemods run **before** style fixes so the style
  pass sees final code; the loop breaks early unless finding count strictly
  decreases (progress-monotonicity).
- **Mode:** advisory + auto-fix on. Correctness (verify) is the hard gate; style
  is fix-or-flag unless a stack opts into blocking.
- **Generic fallback:** user-declared lint command, else skip (advisory).

### 3.3 `detect` — the deterministic anti-pattern slot ("outperform frontier")

> **Contract PROVISIONAL until Spec B's vetting closes (FM13).** Keep the
> *envelope* minimal (a located-findings list); confine all Spec-B variance to the
> `fix` value. Contract-hash pinning (V15/V16) makes any later change loud at load.

Finds the **bespoke** smells stock linters miss and returns them **located**, so
the fix loop and `review` get "defect at file:line + how to fix," not "reason
about the whole codebase." A rule *knows*; a model *hopes*.

- **Deliverable:** one rule-set per invocation. Strictly deterministic — no LLM in
  detection. (Full engine = **Spec B**.)
- **In:** `{ cwd, file_set?, changed_only, ruleset }`
- **Out:** `{ status: pass | fail | not_evaluated, findings:
  [{ file, line, rule_id, severity, message, fix }] }` where `fix: SchemaBound`
  (§4.1) = `{ kind: "codemod"|"manual", recipe? }`.
- **Registrations:** `cap.detect.ts-react` (react-doctor: `useEffect`-as-state,
  effect-derived-state, index-as-key …), `.rust`, `.python`, and
  `cap.detect.conventions` (project ruleset).
- **Fix pairing:** `kind == "codemod"` → the bounded loop (§3.2); `manual` →
  located finding flows to `implement`/`review`.
- **No rules for a stack → `status: not_evaluated`** (typed), never `pass`. "I had
  nothing to check with" ≠ "clean."

### 3.4 `scaffold` — deterministic skeleton + wiring (contract-first, config-driven)

Conditional (new-artifact only). Hands the model a correct skeleton so a commodity
model fills bodies instead of guessing conventions — and, via contract-first,
makes each downstream spec **deterministically smaller and complete** so a cheap
model can actually finish it.

- **Deliverable:** "the new artifact exists with correct structure and wiring for
  the stack, ready to fill." **Skeleton + wiring, never logic.**
- **Config-driven, not core (kept, not demoted).** Each layer is a pack
  registration shelling a generator; the contract layer shells codegen. No core
  code.
- **Layers (contract-first pipeline):**
  - `contract` — protobuf / OpenAPI / GraphQL. Often language-agnostic (the
    `.proto`/`.yaml` is the artifact) with per-language codegen backends. Fires
    **first**; enables contract-driven and consumer-driven development.
  - `solution` — project/service/workspace structure.
  - `implementation` — the code artifact.
  - Pipeline: `scaffold(contract) → codegen (protoc/openapi-generator) →
    scaffold(implementation stubs)`.
- **In:** `{ cwd, layer, artifact_kind, name, target_path?, options }`
- **Out:** `{ created: [file], wired: [file], layer, generated_from?, summary }`
  — `generated_from` marks a contract-generated stub so downstream steps don't
  hand-edit the generated surface.
- **Registrations:** `cap.scaffold.rust`, `.ts-react`, `.go`, `.python`, plus
  contract-stack packs (`cap.scaffold.protobuf`, `cap.scaffold.openapi`).
- **Phasing:** the *mechanism* (layers + codegen pipeline) ships in Phase 1; which
  *concrete contract stacks* ship first is the only thing sequenced.
- **Generic fallback:** no template → bare file + note; never fabricates a
  structure it doesn't know.

### 3.5 `implement` — the idiom-lens slot

The only lens slot. A commodity model writes code; the specialization is guidance.

- **Deliverable:** "the code fulfills the acceptance criteria," written into the
  scaffold. **Operates on ONE tight unit — never the whole feature.** Decomposition
  is CPM's job (§7).
- **Specialization = a hash-pinned idiom `skill`** (`lens.implement.<stack>`),
  injected as guidance — the existing agent/skill/prompt contract. Step stays one;
  guidance swaps. Lens carries a lifecycle field (`experimental` → `stable`).
- **In:** `{ cwd, deliverable, acceptance_criteria, skeleton_files, findings?,
  idiom_lens }`
- **Out:** `{ changed: [file], summary, notes }`
- **Bounded** by the verify loop.
- **Escape hatch:** a stack may register a full `cap.implement.<stack>` for a
  different *procedure* (codegen-heavy stacks); default is lens-injection.
- **Generic fallback — graceful:** no lens → generic implement, still correct
  (verify is the gate). Advisory, not a blocker.

### 3.6 `framework layering` — the resolution dimension

Not a step. A second dimension of the stack descriptor governing how framework
specializations compose with the language specialization. Mechanics in §5.

---

## 4. The HOP (hand-off point) model

Every step-to-step transfer is a **HOP** — a typed handoff contract. Every slot
`contract out` above *is* a HOP. **The HOP typed core is the one core-codebase
change (§0); it extends `praxec-schema` (typify).**

> **Gate (§11): the full HOP schema set is vetted before any code is written
> against it.** This section is the design intent, not the frozen schema.

### 4.1 Nested schema: typed core + `SchemaBound` extension points

One cohesive payload — a compile-time-typed core whose *designated fields* are
schema-bound extension points mapped deterministically to an inner (config-time)
schema:

```rust
// Tier-1 core, typify'd from a compile-time schema (ships with the binary)
struct Finding {
    file: String,
    line: u32,
    rule_id: String,
    severity: Severity,   // spine branches on this → fully typed
    fix: SchemaBound,     // the ONE extension point in v1 (see scoping below)
}

struct SchemaBound {
    schema_ref: SchemaRef,        // names an inner schema in the pack registry
    value: serde_json::Value,     // validated at runtime against that schema
}
```

At the HOP boundary the engine maps `schema_ref → inner schema (pack registry) →
validate(value)`, **fail-fast** on missing/invalid. Registry integrity extends the
V22 closed-world pattern: **all `schema_ref`s must resolve at config load**
(namespaced per pack like definitionIds), so a bad pack fails at load, not mid-run
(FM6).

**Scope (v2, per vetting):** ship `SchemaBound` for the **one real extension point
(`fix`)** only; generalize to a full registry when a *second* consumer appears.
Avoids speculative generality.

### 4.2 The boundary rule (poka-yoke)

> The core HOP is typed (typify) and declares its extension points explicitly as
> `SchemaBound` fields. **The spine branches only on typed core fields — never on
> the inner `value`, never on prose.** Each `SchemaBound` maps deterministically to
> a pack-registered inner schema, validated at the boundary.
>
> **Metastructure = the typed envelope + declared extension points. Instance = the
> inner validated value.** One nested payload, both contracts.

Runtime validation of pack-authored inner values **extends the existing agent
conformance loop** (`rig_runner.rs` `final_answer` `expected_keys`/`expected_types`
+ retry-with-feedback) to full `jsonschema` validation — `jsonschema` is already a
workspace dep. Persistent nonconformance = content `FailureClass` → existing model
chain-walk escalation (FM7). No parallel abstraction.

### 4.3 HOP vs blackboard

- **HOP:** transient, typed, point-to-point. Output of one step = typed input of
  the next.
- **Blackboard:** durable, shared, multi-reader — deliverable spec, acceptance
  criteria, stack descriptor, decisions.

**Handoff design pass (implementation section):** classify every step edge —
typed HOP vs blackboard write — cheap because the slot contracts already define
the envelopes.

---

## 5. Stack descriptor + resolution

### 5.1 The descriptor and the chain

`{ language, frameworks: [set], primary_framework, project }` → an ordered chain,
most-specific-first:

```
[ project:<name> → framework:<primary> (+ additive framework links) → language:<lang> → generic ]
```

The chain-walk follows the *pattern* of `model_resolver` (`walk.rs` `walk:164`,
`try_next:216`) but is **new code** — `model_resolver` is first-match-wins only,
and Spec A needs dual semantics (§5.2). Adapted, not reused.

### 5.2 Composition semantics (the one-line rule)

> **Knowledge accumulates (union down the chain); artifacts and commands resolve
> (one link wins).**

- **Additive** — `detect` rulesets, `implement` lenses, convention rules:
  concatenate every link; the severity threshold decides what gates.
- **Override / most-specific-wins** — `scaffold` template, `verify`/`lint`
  command: the most specific link wins.

### 5.3 Settled sub-decisions

1. **Framework is a set of additive links, exactly one `primary`.** All frameworks
   (react, redux, tailwind) contribute additive `detect`/`lens` rules; the
   `primary` governs the override slots.
2. **Family inheritance = load-time merge** (`preact` declares `parent:
   react-family`, imports+diffs at load). **Demoted to follow-on** (§10) — a flat
   `preact` pack that copies react rules is Phase-1-sufficient until a third family
   member exists.
3. **Per-rule config override — yes.** Additive on the rule *set*, most-specific-
   wins on a rule's *severity/threshold*. Equal-specificity duplicate `rule_id` =
   **load error** (FM10).

### 5.4 Per-deliverable resolution — reject-at-plan (FM3)

Stack is a property of the **file-set a unit touches**. A unit whose file-set
**spans stacks is a CPM *planning error*** — split the unit — **never**
precedence-resolved at runtime. Explicit config always wins. Every slot HOP
carries stack **provenance**; a `STACK_RESOLVED` audit event records the chain +
evidence per unit (mirrors `MODEL_RESOLVER_WALK`). **Manifest auto-detection is
demoted to Phase 2; explicit config is the Phase-1 floor.**

### 5.5 Generic fallback

Every deterministic branch ships an **explicit default** (`generic`) — the honest
floor, and what makes packs ship **warning-clean** (matches the real doctor rule,
§9 #7). No stack ever hits a dead branch.

### 5.6 OPEN — repo-priority / precedence (gate, §11)

Today cross-repo ids are **namespaced** (no collision) and only the **host** may
override a repo id via explicit `overrides:` (`config.rs:2227-2256`). There is
**no repo-over-repo priority** — a company repo cannot automatically override a
shared repo (e.g. `cognitive-architectures`) for the same logical slot. **We need
a configurable priority/precedence** so a higher-priority repo wins. Likely
config-expressible (order repos; resolution prefers the higher-priority namespace
in the dispatch/override), but the mechanism is **unverified and must be designed**
before relying on it — including whether it needs a small core addition to the
merge/override logic or stays pure config.

---

## 6. Cross-cutting principles (pinned)

1. **Core/config boundary (§0).** Core = stable typed contracts; config = all
   variability.
2. **Commodity-model granularity.** Each slot is one constrained deliverable. No
   slot does two jobs.
3. **Decompose bundled ops into single-deliverable mini-workflows** — reusable
   flows (§2.1), not inlined.
4. **Severity everywhere.** One shared `Severity` enum in the typed core; a gate is
   `block at ≥ threshold`; per-stack override down the chain. One threshold
   surface (FM9).
5. **Typed tri-state gate status** (`pass | fail | not_evaluated`) — replaces prose
   "honest-empty" notes. The spine and `review` branch on the enum; "no tool"
   surfaces as `not_evaluated`, never a disguised pass (FM8). Typed enum +
   exhaustive match.
6. **Honest degradation.** "No tool" surfaces (`not_evaluated`, fail-fast). "No
   guidance" degrades gracefully (advisory).

### Observability additions (from vetting)

The engine's transition records + audit events already trace per-step. This design
adds exactly three: **`STACK_RESOLVED`** provenance events (§5.4), the **tri-state
gate status surfaced in mission outcomes** (so `not_evaluated` gates are countable
per run), and **loop round/finding-count telemetry** (breaker-exhaustion rate).
Premature completion is structurally caught by the outcomes/`met` wiring `verify`
targets; policy regressions are load-loud via contract-hash pinning (V15/V16).

---

## 7. Implement granularity + CPM scheduling

The `implement` slot operates on **one tight unit**. A deliverable decomposes into
many small units, run **parallel (disjoint file-sets, via spawning §2.4) or chained
(dependent)** — never one massive implement step. Decomposition + scheduling is
**cpm-planner's** job:

> cpm-planner produces the **unit DAG** (dependencies, file-set ownership,
> parallelizable cohorts, and the reject-at-plan split of stack-spanning units,
> §5.4). The spine executes each unit as a tight `implement → verify → lint/detect`
> loop. CPM manages plan + progress.

Ties three threads: commodity granularity, critical-path/file-set-ownership
orchestration, and Spec C worktrees (parallel units → true isolation). The
**CPM ↔ spine HOP shape** is an open question (§11).

---

## 8. Config / registry surface (compose on the fly)

Users **declare**, runtime **resolves**. Three-tier, generic is the floor:

1. **Explicit user config** — a stack-profile registry (the Phase-1 floor).
2. **Auto-detected per-deliverable** — manifests + file-set (**Phase 2**, §5.4).
3. **Generic language-agnostic fallback** — when nothing matches.

**Additive packs need zero core change (verified, §2.3):** single-stack via
`repos:` layering + `overrides:`; polyglot via a dispatch flow (config). Pack
packaging rides the existing `repos:`/namespace/`overrides:` model verbatim.

**Acceptance gate — one parity proof per pack.** A pack is accepted when a single
benchmark deliverable, run both ways (commodity+architecture vs frontier-unaided),
demonstrates the thesis for that stack. One proof, not a dashboard.

### 8.1 Authoring specialization packs (meta updates → Spec D)

`praxec-meta` today authors *generic* caps/flows, tool-inventory-first. It is not
slot-/stack-/pack-aware. Spec D adds:

- **`meta/flow.author-specialization-pack`** — author a whole stack pack (profile +
  slot registrations + idiom-lens skill + `detect`-ruleset stub) as a unit,
  **contract-aware** against each slot's typed HOP (§3, §4).
- **Slot-contract-aware capability authoring** — draft `cap.verify.<stack>` against
  the slot's HOP, not a free-form snippet.
- **Stack-profile / chain authoring** — descriptor, chain overrides, severity
  retunes (§5.3.3), and (once §5.6 lands) repo-priority declarations.
- **Steer toward packs, not forks (§1).** The tool-inventory-first opening state
  extends to **stack detection** from manifests.

`detect`-ruleset authoring (playbook→config) is shared with **Spec B**.

---

## 9. Risks / authoring prerequisites

We **author these packs through** `meta/flow.author-flow` (dogfooding), so these
known gaps are prerequisites on our own build path (from the change-request raft):

- **#4** `meta/flow.author-flow` passes the goal string into
  `cap.implement.emit-yaml` as `kind`; must pass a normalized `kind`.
- **#5** `meta/cap.verify.check-config` checks standalone; must support the parent
  gateway context or an explicit wrapper.
- **#8** Large inline `yaml_text` hangs; needs file-based payload or an
  artifact-path output.
- **#7** Existing packs emit 22 "deterministic branch state, no default" warnings;
  our explicit-default design (§5.5) is warning-clean by construction — new packs
  must be too.
- **De-stale `docs/spec-fmeca-converge.md`** — its "loops must inline" rationale is
  based on the now-relaxed V11 (§2.1); update it so authors stop learning an
  obsolete constraint.

---

## 10. Out of scope for Spec A

- **Spec B — detector engine.** Seed TRIZ resolution: separate the universal
  **rule schema** from per-mechanism **matcher backends**
  (`treesitter|regex|token|native-adapter`); one rule id carries per-grammar
  variants; playbook→config is prior-action. Full TRIZ in Spec B.
- **Spec C — worktree lifecycle.**
- **Spec D — specialization authoring** (§8.1).
- **Demoted to follow-on (not cut):** family load-time inheritance (§5.3.2);
  manifest auto-detection (§5.4); `SchemaBound` generalization beyond `fix` (§4.1).
  All additive later, no migration cost (greenfield). **Contract-first scaffolding
  is NOT demoted** — it is kept as config (§3.4).
- **praxec-core DX backlog** (routed, not designed): `praxec check`
  serve-readiness; noisy MCP stderr; `--input-file` for command/query; human-gate
  retry hint; Windows `*.log`-as-directory display.

---

## 11. Open questions & gates for the vetting pass

**Resolved by the v2 engine re-grounding:**
- ~~Dynamic `definitionId` vs dispatch capability~~ → both refuted; mechanism is
  layering + dispatch flow (§2.3).
- ~~Capability-loop expressiveness~~ → dissolved; loops are reusable flows (§2.1).

**Still open:**
1. **Runtime `jsonschema` validation of `SchemaBound` values** — extend the
   `final_answer` conformance loop (Adapted; deps present, §4.2). Confirm the
   retry/FailureClass wiring covers it.
2. **CPM ↔ spine HOP shape** — the exact handoff between a cpm-planner unit DAG and
   the per-unit loop (§7).

**Gates (must clear before coding):**
3. **Repo-priority / precedence (§5.6)** — design the configurable
   company-over-shared-repo override; verify config-only vs small-core.
4. **Full HOP-schema vetting (§4)** — the complete typed-core schema set is vetted
   as a unit *before any code is written against it* (explicit requirement — this
   is the core-codebase change, so it must be right first).

---

*v2 — revised after Fable adversarial FMECA vetting; engine claims re-verified
against source. Design + vetting driven with Fable; build runs the normal path.
Companion specs: B (detector engine), C (worktree lifecycle), D (specialization
authoring).*
