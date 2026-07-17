# Plan — House of Quality (QFD) over `crossmatrix`: TDD implementation

Status: PLAN (ready to execute). Date: 2026-07-17. Branch: `feat/hoq-matrix-mcp`.
Companion: `docs/spec-hoq-crossmatrix.md` (the design this operationalizes).

This is a bite-sized, red→green→commit TDD plan for the **minimum viable HOQ**
(spec §6.1c / §7 option c): make the crossmatrix-mcp engine *persist* an imported
model and expose the weighted rollup, then drop the pack capability that drives it.

Two work-streams in dependency order:

- **Part 1 — crossmatrix-mcp engine** (repo `/home/mc/working/crossmatrix`, cut a
  branch e.g. `feat/mcp-persist-analyze` off `dev`). BLOCKING — the pack cap is
  inert until this lands.
- **Part 2 — pack capability + skill** (this repo, branch `feat/hoq-matrix-mcp`).

Convention: each task is one failing test first (RED), the smallest change to
green (GREEN), then a commit. One assertion per test, mirroring the crossmatrix
core test style (`crates/crossmatrix/src/lib.rs:582-732`).

---

## 0. Grounding — what is real vs. hollow (file:line)

**The core engine is REAL and tested** — no math to build, only MCP plumbing:
- `crossmatrix::Model::load` — full validation (dangling cells, unknown tokens,
  unevidenced-inferred, cyclic/scale-mismatched contractions):
  `crates/crossmatrix/src/lib.rs:72-183`.
- `Model::marginalize(relation_id, axis)` — the **weighted technical-importance
  rollup**: per surviving member, `Σ(weight_of_rolled_member × max_observation)`.
  `lib.rs:209-314`. This is the genuine HOQ "floor" (importance × relationship,
  summed per HOW). Fully implemented + tested (`lib.rs:669-678`).
- `Model::contract(contraction_id)` — multi-hop chain cascade (e.g. req→char→fail
  exposure), sorted descending. `lib.rs:318-477`. Tested `lib.rs:712-720`.
- `Model::findings()` — staleness detection. `lib.rs:479-561`.
- Three-layer filesystem stores + 3-way merge + `open()` all built + tested:
  `crates/crossmatrix-mcp/src/store.rs`, `merge.rs`, `lib.rs:13-29`.

**The MCP projection is hollow** (`crates/crossmatrix-mcp/src/main.rs`):
- `S.model` is a plain `Option<Model>` (`main.rs:18-21`) set only by the
  test-only `S::new` (`main.rs:24-30`). Production `main()` is
  `S::default().serve(stdio())` → `model: None` (`main.rs:231-237`).
- The full-`model` import branch **only validates, never persists**
  (`main.rs:100-106`): `Model::load(...)` then discards the loaded model.
- Every real write op returns the "mutation ops deferred" no-op (`main.rs:107-111`).
- `analyze.contract` / `analyze.findings` / `validate` are implemented but read
  `self.model`, so they error `"no model loaded"` in production (`main.rs:127-166`).
- `analyze.marginalize` / `analyze.priority` are **not wired** — the query match
  has no arm; they fall through to the "not supported" stub (`main.rs:176-181`),
  even though `Model::marginalize` exists.

**Spec corrections (grounded):**
1. The spec (§6.2) says the fixtures "declare the WHAT×HOW relation but not the
   roof." **They already include the roof** — `rel_char_internal_conflict`
   (`dim_char → dim_char`, `relationType: opposes`, scale `qfd`) is declared in
   `examples/split/hoq.config.json` and has a cell in `demo.state.json`
   ("former 'roof'… crypto overhead increases latency"). The roof is
   data-driven and present — **no engine change needed for the roof**.
2. The spec maps "technical importance per HOW" to `analyze.contract`
   (§2, §6.1c). Precisely: `analyze.contract` returns per-**(from,to)-pair**
   contracted exposure over a *chain* (the fixture's chain is req→char→fail, i.e.
   requirement→failure exposure — not a per-HOW floor). The genuine
   **per-HOW technical-importance ranking** is `marginalize("rel_req_char", From)`
   (roll up the WHAT axis weighted by importance; survivors = HOWs). So the
   minimal build must **also expose `analyze.marginalize`** to deliver the HOQ
   floor. `analyze.contract` remains the (already-wired) req→fail exposure view.

---

## Part 1 — crossmatrix-mcp: persist + expose the rollup (BLOCKING)

Repo `/home/mc/working/crossmatrix`, off `dev`. All tasks touch
`crates/crossmatrix-mcp/src/main.rs` unless noted.

### Task E1 — make `S.model` interior-mutable (a command can persist for a later query)

Problem: `call_tool_impl(&self, …)` (`main.rs:59`) cannot set a plain
`model: Option<Model>` field. Persistence across the command→query round-trip (the
pack drives them as two separate tool calls in one MCP session) needs interior
mutability, like the existing `request_cache: Arc<Mutex<…>>` (`main.rs:20`).

- **RED:** new test in `mod tests`: build `S::default()`, issue a
  `crossmatrix.command` with `request.model` = the merged split-example model
  (use `crossmatrix_mcp::merge::merge` on the three `examples/split/*` fixtures,
  or a pre-merged literal), then `crossmatrix.query {kind: validate}` on the SAME
  `s` asserts `validated == true`. Fails today (model stays `None`).
- **GREEN:** change `model: Option<crossmatrix::Model>` →
  `model: Arc<Mutex<Option<crossmatrix::Model>>>` (`main.rs:19`). `#[derive(Default)]`
  still yields `None` inside. Update `S::new` (`main.rs:24-30`) to wrap in
  `Arc::new(Mutex::new(Some(model)))`. Update the three query arms that read
  `self.model` (`main.rs:128-131`, `149-151`, `166`) to
  `self.model.lock().unwrap().as_ref()`.
- **COMMIT:** `refactor(mcp): hold model behind Arc<Mutex> for cross-call persistence`.

### Task E2 — persist the imported model in the command import branch

- **RED:** test: `S::default()`, one `command` with `request.model` = merged
  example, then `query {kind: analyze.contract}` asserts `findings` non-empty —
  WITHOUT any `S::new` preload. Fails today (import validates then drops the model,
  `main.rs:100-106`).
- **GREEN:** in the `if let Some(model) = request.get("model")` branch
  (`main.rs:100`), on `Model::load(...) = Ok(loaded)` set
  `*self.model.lock().unwrap() = Some(loaded)` before returning
  `{ok:true, op, validated:true, links:["query"]}`. Keep the numeric-weight
  rejection (`main.rs:74-98`) and requestId idempotency (`main.rs:63-68,112-118`)
  unchanged — persistence happens only on a clean load.
- **COMMIT:** `feat(mcp): persist imported model so query sees it (ADR-0004 §B)`.

> This is the **one-call HOQ** the spec recommends (§6.1 option b / §7 option c):
> a single `command` imports the whole engine model; a following `query` analyzes
> it. No incremental `observe` write-API needed for v1.

### Task E3 — expose `analyze.marginalize` (the genuine per-HOW rollup)

Wrap the already-implemented `Model::marginalize` (`lib.rs:209-314`).

- **RED:** with the example model loaded (via E2 import, or `S::new`),
  `query {kind: analyze.marginalize, relationId: "rel_req_char", axis: "from"}`
  asserts a non-empty array of `{member, value}` for the HOW axis, sorted
  descending. Fails today (falls to the "not supported" stub, `main.rs:176-181`).
- **GREEN:** add a match arm in the `crossmatrix.query` block (`main.rs:126`):
  read `query.relationId` + `query.axis` (`"from"|"to"` → `crossmatrix::Axis`),
  lock+read the model, call `model.marginalize(rel, axis)`, serialize the
  `(String, f64)` pairs to `{member, value}` findings, sorted (already sorted by
  the engine, `lib.rs:311-313`). On `Err(UnweightedMemberForWeightedAnalysis)`
  return the diagnostic verbatim (fail-fast, recoverable) with legal `links`.
  Export `Axis` from the engine crate if not already `pub use` (it is —
  `lib.rs:565-569`).
- **COMMIT:** `feat(mcp): wire analyze.marginalize (weighted per-HOW rollup)`.

### Task E4 — end-to-end one-call-HOQ round-trip test (headless)

- **RED/GREEN (test only):** `S::default()` → import the merged example model →
  `analyze.marginalize rel_req_char from` → assert the ranked HOWs put a
  high-importance-driven characteristic on top (e.g. `char_response_latency` /
  `char_encryption` outrank a weakly-related HOW). Proves the pack's exact
  command→query drive works without `S::new`. Also assert `analyze.contract`
  returns the req→fail exposure findings from `ctr_req_failure_exposure`.
- **COMMIT:** `test(mcp): one-call HOQ round-trip (import → marginalize/contract)`.

### Task E5 (OPTIONAL, spec §6.3) — `analyze.priority`: normalized ranked HOW list

Built on E3. A HOQ consumer wants a normalized ranked list, not raw column sums.

- **RED:** `query {kind: analyze.priority, relationId: "rel_req_char"}` returns
  `[{how, raw, normalized, rank}]` (normalized = raw / maxRaw), rank ascending.
- **GREEN:** new arm: call `marginalize(rel, Axis::From)`, normalize + rank.
- **COMMIT:** `feat(mcp): analyze.priority (normalized HOW ranking)`.

Defer if v1 is happy ranking `analyze.marginalize` output in the cap.

### Task E6 (OPTIONAL, spec §6.1/§4.3) — durable store + `main()` load via env

In-process persistence (E1/E2) survives a single MCP session — enough for one HOQ
run (command then query on the same connection). Durability across runs needs the
stores wired:

- **GREEN:** in `main()` (`main.rs:231-237`) read `CROSSMATRIX_STORE_ROOT` (default
  `.`); build `ConfigStore/DimensionsStore/StateStore` on it; if a resolvable
  `stateId` is configured, pre-load via `crossmatrix_mcp::open` (`lib.rs:13-29`).
  On import, also `*_store.put(...)` the three layers so a later process re-opens.
- **FLAG:** this is the only piece needing a **gateway.yaml edit + MCP restart**
  (add `env: { CROSSMATRIX_STORE_ROOT: . }` to the `crossmatrix` connection). The
  USER performs it — do not edit `~/.config/praxec/gateway.yaml` here. Not
  required for a single-session v1 HOQ.

**Non-goals for v1 (deferred write-API, spec §6.1a):** incremental `observe`,
`dimension.register`, `relation.declare`, `member.propose`, `evidence.attach`,
`deprecate`, `expectedVersion` CAS on live mutations. v1 imports a whole model;
these remain the "mutation ops deferred" stub (`main.rs:107-111`).

---

## Part 2 — pack capability `cap.plan.house-of-quality` (this repo)

Branch `feat/hoq-matrix-mcp`. Blocked at runtime until Part 1 (E1-E3) lands, but
authored + shape-validated now. Modeled on `capabilities/cap.review.fmeca.yaml`.

**Design divergence from spec §3.3 (why):** the spec's YAML assumed incremental
`observe` + `op.kind: model.open`. The minimal engine (E1-E3) supports only
**whole-model import keyed on `request.model`** (a flat engine-schema doc, the
shape `merge()` emits — `merge.rs:86-93`). So the cap assembles a complete engine
model doc and imports it in ONE `command`, then queries. The **agent** produces the
fuzzy content as one model doc (scales are the fixed QFD/importance vocabulary;
dimensions = WHATs/HOWs; relation cells = relationship + roof tokens). The **engine**
does the math (`analyze.marginalize`) and the validation (observation-only
boundary rejects numeric weights + unknown tokens — `main.rs:74-98`, `lib.rs:142-169`).
The ranking is never agent-computed — invariant preserved.

State machine: `opening → relating → importing → analyzing → done`.

### Task P1 — author `skills/plan.hoq.relate.yaml`

- Static, hash-pinned instruction (mirrors `skills/review.fmeca.enumerate.yaml`):
  "You are given WHATs (each with an importance token low|medium|high), candidate
  HOWs, and the fixed `qfd` scale (none|weak|moderate|strong) + `importance`
  scale. Emit ONE engine model doc: `scales` (the two fixed scales verbatim),
  `dimensions` (`dim_req` from WHATs with `weightObservation` = the given
  importance token, `dim_char` from HOWs), `relations` (`rel_req_char`
  satisfies dim_req→dim_char with a cell per WHAT×HOW you judge related, carrying
  a `qfd` TOKEN + `provenanceClass`; `rel_char_roof` opposes dim_char→dim_char for
  synergy/conflict), and the `ctr` contraction. TOKENS ONLY — never a numeric
  weight or value. Omit `none` cells."
- **VERIFY:** skill file parses (pack skill loader / `praxec.query` describe).
- **COMMIT:** `feat(skill): plan.hoq.relate — HOQ token authoring`.

### Task P2 — author `capabilities/cap.plan.house-of-quality.yaml`

Full target artifact (drop-in; replaces the spec §3.3 sketch):

```yaml
# capabilities/cap.plan.house-of-quality.yaml
# House of Quality (QFD), computed not generated. LLM picks relationship/roof
# TOKENS; crossmatrix computes the weighted technical-importance ranking.
# Requires the `crossmatrix` connection (gateway.yaml:169) + crossmatrix-mcp
# persist/marginalize build (docs/plan-hoq-crossmatrix.md Part 1, E1-E3).
workflows:
  cap.plan.house-of-quality:
    verb: plan
    lifecycle: experimental
    description: >
      Deterministic House-of-Quality (QFD) over prioritized WHATs + candidate
      HOWs. The LLM picks relationship/roof tokens; crossmatrix computes the
      weighted technical-importance ranking (analyze.marginalize) + trade-off
      findings. Emits a ranked HOW list a design step consumes directly.
    snippet:
      inputs:
        model_id: { type: string, required: true }
        whats:    { type: array,  required: true }   # [{id,label,importance:low|medium|high}]
        hows:     { type: array,  required: true }   # [{id,label}]
        context:  { type: string, default: "" }
      outputs:
        ranked_hows:   { type: array }
        roof_findings: { type: array }
        report:        { type: object }
    initialState: opening
    states:

      # 1. Deterministic: pass inputs forward (methodology is static in the skill).
      opening:
        goal: Prepare the HOQ inputs for token authoring.
        transitions:
          open:
            target: relating
            actor: deterministic
            executor: { kind: noop }
            output:
              hoq_inputs: "$.workflow.input"

      # 2. Agent (fuzzy): emit ONE engine model doc, tokens only.
      relating:
        goal: >
          Read $.context (whats+importance, hows, and $.workflow.input.context).
          Emit `hoq_model` — a complete crossmatrix engine model: the fixed qfd +
          importance scales; dim_req (WHATs, weightObservation=importance token);
          dim_char (HOWs); rel_req_char (satisfies) with a cell per related
          WHAT×HOW carrying a qfd token + provenanceClass; rel_char_roof (opposes,
          dim_char->dim_char) for synergies/conflicts; the ctr_hoq contraction.
          TOKENS only — never a number.
        skills: [plan.hoq.relate]
        transitions:
          relate:
            target: importing
            actor: agent
            inputSchema:
              type: object
              required: [hoq_model]
              properties:
                hoq_model: { type: object }
            executor: { kind: noop }
            output:
              hoq_model: "$.arguments.hoq_model"

      # 3. Deterministic: import the model (engine validates + persists).
      importing:
        transitions:
          import:
            target: analyzing
            actor: deterministic
            executor:
              kind: mcp
              connection: crossmatrix
              tool: crossmatrix.command
              # crossmatrix takes {request:<envelope>}; import the whole model doc.
              map:
                request:
                  schemaVersion: "0.2.0"
                  requestId: "$.workflow.id"
                  modelId:   "$.workflow.input.model_id"
                  actor:     { actorType: llm, persona: analyst }
                  model:     "$.context.hoq_model"
            output:
              hoq_import: "$.output"

      # 4. Deterministic: the tool computes the per-HOW ranking (code, not LLM).
      analyzing:
        transitions:
          analyze:
            target: done
            actor: deterministic
            executor:
              kind: mcp
              connection: crossmatrix
              tool: crossmatrix.query
              map:
                request:
                  schemaVersion: "0.2.0"
                  modelId: "$.workflow.input.model_id"
                  query: { kind: analyze.marginalize, relationId: rel_req_char, axis: from }
            output:
              ranked_hows:   "$.output.findings"
              roof_findings: "$.output.findings"
              report:        "$.output"
      done: { terminal: true }
```

- **RED:** validate the cap loads — `praxec.query {subject: "cognitive/cap.plan.house-of-quality"}`
  (or the pack's static validator). Fails until the file exists / until schema is
  correct (verb `plan` permits `kind: mcp | noop` leaves — same class as
  `review`).
- **GREEN:** the file above; fix any validator complaints (slot conflicts,
  `$`-path shapes) exactly as `cap.review.fmeca.yaml` does.
- **COMMIT:** `feat(cap): cap.plan.house-of-quality (QFD over crossmatrix)`.

### Task P3 — reference connection file `connections/crossmatrix.yaml`

- Add the pack REFERENCE connection (spec §4.2) matching `connections/fmeca-mcp.yaml`
  style; key `crossmatrix` (same as the live gateway key `gateway.yaml:169`, so it
  resolves in both). No gateway edit — the live connection already exists.
- **COMMIT:** `docs(connections): crossmatrix reference connection`.

### Task P4 (OPTIONAL) — orchestrator `flow.plan.hoq-to-design.yaml`

Nest `cap.plan.house-of-quality` then feed `ranked_hows` into
`cap.plan.technical-design` + `flow.harden.fmeca-converge`, mirroring how
`orchestrators/flow.harden.fmeca-converge.yaml` nests `cap.review.fmeca`. Deferred
follow-on; the capability (P2) is the atomic unit.

---

## What must be built before HOQ can run (gating summary)

| Prereq | Where | Blocking for v1? |
|---|---|---|
| E1 model behind `Arc<Mutex>` | crossmatrix-mcp | **YES** |
| E2 import branch persists | crossmatrix-mcp | **YES** |
| E3 `analyze.marginalize` wired | crossmatrix-mcp | **YES** (the per-HOW floor) |
| E4 round-trip test | crossmatrix-mcp | proof, not a blocker |
| E5 `analyze.priority` | crossmatrix-mcp | no (cap can rank marginalize output) |
| E6 durable store + env load | crossmatrix-mcp | no (single-session suffices) |
| P1 skill, P2 cap, P3 conn | this pack | authored now, inert until E1-E3 |
| Roof scale/relation | already in fixture | **none — already present** |

## Gateway edits + restart (USER — not done here)

- **None required to wire HOQ**: the `crossmatrix` connection is already live
  (`gateway.yaml:169-175`).
- **Only if E6 lands**: add `env: { CROSSMATRIX_STORE_ROOT: . }` to the
  `crossmatrix` connection + restart the MCP. Proposed diff, USER applies.

Nothing in this plan touches `~/.config/praxec/gateway.yaml`, `../execution-policy`,
or praxec model-resolution code.
