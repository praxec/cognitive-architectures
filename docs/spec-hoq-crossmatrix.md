# Spec — House of Quality (QFD) capability over the `crossmatrix` matrix MCP

Status: DESIGN (not implemented). Date: 2026-07-17. Branch: `feat/hoq-matrix-mcp`.

Companion pattern specs: `docs/spec-fmeca-converge.md` (the deterministic-gate
convention this mirrors), ADR-0002/0003/0004 in the `crossmatrix` repo.

---

## 0. TL;DR — the two load-bearing findings

1. **The "matrix mcp" is real and already wired — but it is a spec-complete
   *stub*, not a working HOQ engine.** The binary is `crossmatrix-mcp`
   (`~/.cargo/bin/crossmatrix-mcp`), its repo is `/home/mc/working/crossmatrix`,
   and it is *already* declared as a live connection in the gateway
   (`~/.config/praxec/gateway.yaml:169`, key `crossmatrix`). It exposes exactly
   two tools — `crossmatrix.command` and `crossmatrix.query` — with a fully
   specified HOQ/QFD contract (schema + ADRs + example fixtures). **But the write
   path is a no-op stub and the query path is 90% stubbed** (evidence in §2). A
   HOQ capability *cannot run against it today*. The gateway description already
   flags this: *"query trace/coverage/gaps kinds still stubbed upstream (build
   candidate)"* (`gateway.yaml:175`).

2. **Because the connection already exists, no `gateway.yaml` edit is needed to
   wire HOQ.** The blocker is *building the crossmatrix engine's write-API +
   model persistence + the analyze query*, not the pack wiring. This spec
   provides (a) the ready-to-drop pack capability YAML and (b) the exact
   crossmatrix-mcp tool surface that must be built first.

---

## 1. What the matrix MCP actually is (grounded)

### 1.1 It exists and is wired

- Binary present: `~/.cargo/bin/crossmatrix-mcp`.
- Repo: `/home/mc/working/crossmatrix` — Rust workspace `crossmatrix` (engine
  crate) + `crossmatrix-mcp` (MCP stdio server). `README.md`: *"Multidimensional
  **House of Quality (QFD)** — cross-dimensional relationship matrices for
  structured trade-off and requirement analysis."*
- Live gateway connection, `~/.config/praxec/gateway.yaml:169-175`:
  ```yaml
  crossmatrix:
    kind: mcp
    command: crossmatrix-mcp
    description: >
      QFD House-of-Quality relationship matrices (crossmatrix.command /
      crossmatrix.query) for requirement/design/test trade-off + traceability.
      NOTE: query trace/coverage/gaps kinds still stubbed upstream (build candidate).
  ```

This is the same class of deterministic engine-MCP as `cpm-planner`,
`fmeca-mcp`, and `elicitation-mcp` (`gateway.yaml:129-143`) — the pack's
"deterministic tool over LLM math" pattern. HOQ's relationship matrix, the roof
correlation matrix, and the weighted technical-importance rollup are exactly the
deterministic linear-algebra the pack refuses to trust an LLM to do.

### 1.2 Its intended tool surface (from the schema — this is the *contract*)

Two tools, mutation-first envelope, observation-only boundary. Source:
`/home/mc/working/crossmatrix/schemas/crossmatrix-mcp.schema.json` and the
registration in `crates/crossmatrix-mcp/src/main.rs:38-58`.

- **`crossmatrix.command`** — input `{ "request": { envelope } }` where the
  envelope is `{ schemaVersion, requestId, modelId, expectedVersion?,
  actor{actorType,persona}, op{kind,...} }`. Write ops (`op.kind`):
  `model.open`, `dimension.register`, `scale.declare`, `relation.declare`,
  `contraction.declare`, `members.sync`, `observe`, `member.propose`,
  `evidence.attach`, `deprecate`. **Observation-only:** cells carry a *token*
  from the relation's scale (e.g. `strong`/`moderate`/`weak`), never a raw
  number — numeric weights without a `sourceRef.system` are rejected
  (`main.rs:75-99`). This is the poka-yoke that stops an LLM inventing a score.
- **`crossmatrix.query`** — input `{ "request": { schemaVersion, modelId,
  query{kind,...} } }`. Read/analysis kinds: `slice`, `describe`, `trace`,
  `explain`, `gaps.next`, `gaps.orphans`, `coverage`, `stale`, `conflicts`,
  `analyze` (`marginalize|contract|findings|priority|compare`), `validate`,
  `export`. Never mutates; engine-computed.

The model is **stateful and durable** — a repo-resident analysis artifact keyed
by `modelId`, with three-layer persistence (Configuration / Dimensions / State)
per ADR-0004 (`/home/mc/working/crossmatrix/adr/0004-*.md`). HOQ is therefore a
*session* (open → register dims → declare relations → observe cells → analyze),
like `elicitation` / `science`, **not** a single call like `fmeca-mcp analyze`.

### 1.3 The stub reality (CRITICAL — this is why HOQ can't run yet)

Evidence in `crates/crossmatrix-mcp/src/main.rs`:

- **All write ops are deferred no-ops.** `crossmatrix.command` handles the
  numeric-weight rejection and a full-`model` *import-validate* branch, then for
  every real op returns (`main.rs:106-110`):
  ```
  { "ok": true, "op": <kind>, "note": "op not supported in this build
    (mutation ops deferred — see ADR-0004; needs a core write-API)", "links": ["query"] }
  ```
  `model.open`, `dimension.register`, `relation.declare`, `observe`, etc. do
  **not** persist anything.
- **The query path implements only 3 of 12 kinds.** `analyze.contract`,
  `analyze.findings`, `validate` are real (`main.rs:127-183`); everything else
  falls through to (`main.rs:184-188`):
  ```
  { "ok": true, "query": <kind>, "note": "query not supported in this build
    (slice/describe/trace/gaps deferred)", "links": [...] }
  ```
  Note `analyze` sub-ops `marginalize`, `priority`, `compare` are *unimplemented*
  even though the schema advertises them.
- **The production server starts empty.** `main()` is
  `S::default().serve(stdio())` (`main.rs:231-237`); `S::default()` →
  `model: None`, and `main` never loads a model from the store (`store.rs` exists
  — `ConfigStore`/`DimensionsStore`/`StateStore` — but `main` never wires it).
  So the real `analyze.contract` immediately errors `"no model loaded"`
  (`main.rs:130-131`). The working query path only exists inside unit tests that
  preload a model via `S::new(model)`.

**Conclusion:** crossmatrix-mcp today is a schema-complete, ADR-vetted, but
**functionally hollow** engine — writes deferred, queries mostly stubbed, no
production model-loading path. The HOQ *contract* is trustworthy and stable; the
*implementation* is a build candidate. This is the single decision that gates the
whole feature (§7).

---

## 2. HOQ / QFD → crossmatrix model mapping (grounded in the fixtures)

The crossmatrix example split (`/home/mc/working/crossmatrix/examples/split/`)
*is* a House of Quality. The mapping is 1:1 and needs no new concepts:

| HOQ / QFD element | crossmatrix construct | Evidence |
|---|---|---|
| WHATs (customer requirements) | a `dimension` of `kind: customer_requirement` | `qfd-fmeca.dimensions.json` `dim_req` |
| WHAT importance weights | member `weightObservation` on the `importance` scale (`low/medium/high` = 1/3/9) | `dimensions.json` members; `hoq.config.json` scale `importance` |
| HOWs (engineering characteristics) | a `dimension` of `kind: engineering_characteristic` | `dimensions.json` `dim_char` |
| WHAT×HOW relationship matrix | a `relation` `rel_req_char` (from `dim_req` to `dim_char`) scored on the `qfd` scale (`weak/moderate/strong` = 1/3/9) | `hoq.config.json` scale `qfd`; `demo.state.json` cells |
| relationship cell (strong/moderate/weak) | an `observe` op / `cell.observations[]` carrying a scale *token* + `provenanceClass` (normative/observed/inferred) | `demo.state.json` cells |
| HOW×HOW correlation "roof" | a second `relation` from `dim_char` to `dim_char` (self-relation) on a bipolar correlation scale | supported by relation model; roof scale must be authored (see §6.2) |
| technical importance per HOW | a `contraction` (chain `dim_req → rel_req_char → dim_char`, `weightCombination: qfd_propagate`) → `query analyze.contract` findings | `contraction.declare` op; `main.rs:127-145` |
| competitive benchmarking (optional) | additional dimension(s) + relation, or member metadata | ADR-0004 federated dimensions |
| FMECA cross-link (bonus) | a third dimension `kind: failure_mode` (`dim_fail`) already in the fixture | `dimensions.json` `dim_fail` |

The weighted-column rollup (importance × relationship-strength, summed per HOW)
is exactly `qfd_propagate` contraction math — deterministic, code-computed,
returned by `analyze.contract`. This is the "don't trust the prompt for the
arithmetic" property the pack requires.

---

## 3. The pack capability — `cap.plan.house-of-quality`

### 3.1 Naming + placement in the flow set

- **Verb / name:** `cap.plan.house-of-quality` (verb `plan`). HOQ is a
  design-time translation of prioritized WHATs into ranked HOWs — a planning
  activity, alongside `cap.plan.technical-design` and `cap.plan.elicit-spec`
  (`capabilities/`).
- **Where it sits in the SDLC flow:** between **elicitation** and
  **design/FMECA**:
  `elicit (WHATs+weights)` → **`cap.plan.house-of-quality` (→ ranked HOWs +
  trade-off roof)** → `cap.plan.technical-design` (HOWs become the design's
  characteristics) → `flow.harden.fmeca-converge` (FMECA the design; the
  fixture already cross-links failure modes as a third axis). It can consume an
  elicitation session's readiness output (WHATs) directly, closing the
  elicit→HOQ→design→FMECA chain the pack already runs deterministically.
- **File:** `capabilities/cap.plan.house-of-quality.yaml`.

### 3.2 Executor convention this follows (verified against live caps)

`kind: mcp` leaf = `{ connection: <gateway key>, tool: <tool name>, map: {<arg>:
<$-path>} }`. The `map:` (NOT `arguments:`) is resolved by McpExecutor against
run scopes. Verified in `capabilities/cap.review.fmeca.yaml` (fmeca-mcp,
tools `scoring.catalog` + `analyze`) and `capabilities/cap.verify.spec-readiness.yaml`
(elicitation, tool `readiness.assess`). Agent leaves stay `kind: noop` and hand
work forward via `inputSchema` + `output:` (`cap.review.fmeca.yaml` `enumerating`
state). HOQ keeps the same split: LLM does the *fuzzy* half (pick relationship
tokens), the engine does the *math* (weighted rollup).

Because crossmatrix's tool input schema is `{ "request": <envelope> }`, the
`map:` binds a single `request` key to a pre-assembled envelope object (unlike
fmeca-mcp's flat arg maps). The agent state assembles the envelope; the mcp state
maps it in. This is the one shape difference from the fmeca cap and is called out
inline in the YAML.

### 3.3 Capability YAML (PROPOSED — runnable once §6 engine work lands)

Structure mirrors `cap.review.fmeca.yaml`: a deterministic setup, an agent
"observe the fuzzy cells" state, and a deterministic "compute the verdict" state.

```yaml
# capabilities/cap.plan.house-of-quality.yaml
#
# House of Quality (QFD) matrix, computed not generated. Separation of concerns:
#   1. opening (deterministic mcp)  — open a crossmatrix model + register the
#      QFD scales/relations (methodology config) and the WHAT/HOW dimensions
#      (from upstream elicitation + design inputs).
#   2. relating (agent)             — the LLM does the FUZZY half: for each
#      WHAT×HOW cell pick a relationship TOKEN (strong|moderate|weak|none) and
#      for the roof pick a correlation TOKEN. It picks tokens, never numbers.
#   3. rolling-up (deterministic mcp) — analyze.contract computes the
#      qfd_propagate technical-importance per HOW. The RANKING is code-computed.
#
# Requires the `crossmatrix` connection (already in gateway.yaml). BLOCKED until
# crossmatrix-mcp implements the write-API + model persistence + analyze
# (see docs/spec-hoq-crossmatrix.md §6).
workflows:
  cap.plan.house-of-quality:
    verb: plan
    lifecycle: experimental
    description: >
      Deterministic House-of-Quality (QFD) over prioritized WHATs + candidate
      HOWs. The LLM picks relationship/roof tokens; crossmatrix computes the
      weighted technical-importance ranking + trade-off (roof) findings. Emits a
      typed HOQ result — a ranked HOW list a design step can consume directly.
    snippet:
      inputs:
        model_id:   { type: string, required: true }   # durable HOQ artifact id
        whats:      { type: array,  required: true }    # [{id,label,importance:low|medium|high}]
        hows:       { type: array,  required: true }    # [{id,label}]
        context:    { type: string, default: "" }       # elicitation/design grounding
      outputs:
        ranked_hows:   { type: array }   # HOWs by descending technical importance
        roof_findings: { type: array }   # HOW×HOW correlations (synergies/conflicts)
        report:        { type: object }  # full analyze.contract payload
    initialState: opening
    states:

      # 1. Deterministic: open the model + register QFD scales, WHAT/HOW
      #    dimensions, the WHAT×HOW relation, the roof relation, and the
      #    qfd_propagate contraction. (One or more command envelopes; shown as a
      #    single build op — see §6.1 for the batch/import alternative.)
      opening:
        transitions:
          open:
            target: relating
            actor: deterministic
            executor:
              kind: mcp
              connection: crossmatrix
              tool: crossmatrix.command
              # crossmatrix takes {request:<envelope>}; assemble it from inputs.
              map:
                request:
                  schemaVersion: "0.2.0"
                  requestId:     "$.workflow.id"        # idempotency key
                  modelId:       "$.workflow.input.model_id"
                  actor:         { actorType: llm, persona: analyst }
                  op:
                    kind: model.open
                    title: "HOQ"
                    # dimensions/relations/contraction seeded from whats/hows;
                    # see §6.1 — engine must accept the composed build payload.
            output:
              hoq_opened: "$.output"

      # 2. Agent (fuzzy): observe each WHAT×HOW cell + roof cell with a TOKEN.
      relating:
        goal: >
          Read $.context and the opened model ($.context.hoq_opened). For every
          WHAT×HOW pair choose a relationship token (strong|moderate|weak|none)
          from the `qfd` scale, and for every HOW×HOW pair choose a roof
          correlation token. Emit `observations` — token ids only, never a score
          — each with a provenanceClass (normative|observed|inferred).
        skills: [plan.hoq.relate]     # PROPOSED skill (see §5)
        transitions:
          relate:
            target: rolling_up
            actor: agent
            inputSchema:
              type: object
              required: [observations]
              properties:
                observations: { type: array }   # [{relationId,from,to,observation,provenanceClass}]
            executor: { kind: noop }
            output:
              hoq_cells: "$.arguments.observations"

      # 3. Deterministic: the tool computes the ranking + roof findings.
      #    (Observations submitted via command `observe`; then analyze.contract.)
      rolling_up:
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
                  query: { kind: analyze.contract }
            output:
              ranked_hows:   "$.output.findings"     # qfd_propagate rollup
              roof_findings: "$.output.findings"     # correlation findings subset
              report:        "$.output"
      done: { terminal: true }
```

> **Wiring note (V6/V-verb):** verb `plan` is cognitive and permits `kind: mcp`
> leaves (same class as `review`/`verify` used by the fmeca and spec-readiness
> caps), so the mcp + agent split is valid. Fail-fast, no fallback: if the engine
> rejects an unknown token or a numeric weight, the run fails and returns legal
> links — matching crossmatrix's observation-only boundary (`main.rs:75-99`).

### 3.4 Optional orchestrator flow

If HOQ should *drive* into design/FMECA, add
`orchestrators/flow.plan.hoq-to-design.yaml` that nests
`cap.plan.house-of-quality` then feeds `ranked_hows` into
`cap.plan.technical-design` and the FMECA converge loop — mirroring how
`flow.harden.fmeca-converge.yaml` nests `cap.review.fmeca`. Deferred as a
follow-on; the capability above is the atomic unit.

---

## 4. Connection config (gateway wiring)

### 4.1 The connection already exists — no gateway edit required for wiring

`~/.config/praxec/gateway.yaml:169-175` already declares the `crossmatrix`
connection (§1.1). The capability's `connection: crossmatrix` binds to it
directly. **No `connections:` diff is needed to make HOQ discoverable.**

### 4.2 Pack reference-connection file (PROPOSED — matches pack convention)

The pack ships a REFERENCE connection file per engine-MCP (operators copy into
their gateway), e.g. `connections/fmeca-mcp.yaml`,
`connections/elicitation-mcp.yaml`. Add the matching one:

```yaml
# connections/crossmatrix.yaml — REFERENCE connection (operators copy into their
# gateway config). MCP connection to crossmatrix — the deterministic,
# multidimensional House-of-Quality (QFD) engine: WHAT/HOW dimensions, weighted
# relationship + roof matrices, and code-computed technical-importance rollups.
# Backs cap.plan.house-of-quality the way fmeca-mcp backs cap.review.fmeca.
# Install: `cargo install --path crates/crossmatrix-mcp` (crossmatrix repo);
# binary `crossmatrix-mcp`, MCP/stdio. Tools (two, command/query split):
#   crossmatrix.command (model.open, dimension.register, scale.declare,
#     relation.declare, contraction.declare, members.sync, observe, ...),
#   crossmatrix.query   (analyze.contract|findings, validate, slice, describe, ...).
connections:
  crossmatrix:
    kind: mcp
    command: crossmatrix-mcp
    description: >
      Deterministic QFD/House-of-Quality engine: register WHAT/HOW dimensions +
      weighted relationship/roof matrices; get code-computed technical-importance
      ranking + trade-off findings (observation-only boundary; no LLM-invented
      scores).
```

> Naming note: the pack's reference file for elicitation names the connection
> `elicitation` while the live gateway key is `elicitation-mcp`
> (`connections/elicitation-mcp.yaml` vs `gateway.yaml:141`) — a known drift.
> crossmatrix avoids it: both the live gateway key (`gateway.yaml:169`) and this
> reference file use the same key `crossmatrix`, so `connection: crossmatrix`
> resolves in both.

### 4.3 The ONE gateway edit HOQ will likely need (once the engine persists)

When crossmatrix-mcp gains model persistence (§6), the durable model store root
must be pinned so the HOQ artifact survives across runs (ADR-0004 makes the model
repo-resident). That is a small **env** addition on the existing connection —
still a `gateway.yaml` edit + MCP restart the USER performs:

```yaml
  crossmatrix:
    kind: mcp
    command: crossmatrix-mcp
    env:
      CROSSMATRIX_STORE_ROOT: .     # PROPOSED — needs the engine to read it
    description: >
      ...
```

`CROSSMATRIX_STORE_ROOT` does not exist yet (`main()` never reads env,
`main.rs:231-237`); it is proposed alongside the write-API build.

---

## 5. PROPOSED skill

`skills/plan.hoq.relate.yaml` — a static, hash-pinned instruction that tells the
agent to pick relationship/roof *tokens* from the model's scales (never numbers),
attach a provenanceClass, and submit `observations`. Mirrors
`skills/review.*` used by `cap.review.fmeca`. One-line: the fuzzy half of HOQ,
constrained to the engine's token vocabulary.

---

## 6. PROPOSED crossmatrix-mcp build (the real prerequisite)

The capability in §3 is inert until the engine implements the surface its own
schema already specifies. Three build items, in dependency order:

### 6.1 Write-API + model persistence (BLOCKING)

Today every `op` returns the "mutation ops deferred — needs a core write-API"
stub (`main.rs:106-110`) and `main()` holds no model. Required:

- A core write-API on `crossmatrix::Model` for: `model.open`,
  `dimension.register`, `scale.declare`, `relation.declare`,
  `contraction.declare`, `members.sync`, `observe` (at minimum — these are the
  HOQ-critical ops).
- Persist to the three-layer store already stubbed in `store.rs`
  (`ConfigStore`/`DimensionsStore`/`StateStore`), keyed by `modelId`, with the
  `expectedVersion` optimistic-CAS the envelope already carries.
- Load the model by `modelId` at query time (or hold it in `S` behind the
  `Arc<Mutex<..>>` already present) so `command` writes are visible to a later
  `query` in the same MCP session — the pack drives command→query across
  separate tool calls.
- **Design choice for the cap:** either (a) many `command` ops (one per
  dimension/relation/cell), or (b) a single composed *build* payload accepted by
  `model.open` (the §3.3 YAML assumes a composed open for brevity). Option (b) is
  fewer round-trips and matches the existing full-`model` import-validate branch
  (`main.rs:100-105`) — recommend the engine make that import branch *persist*
  (today it only validates), giving a one-call "load this whole HOQ" path.

Contract shapes are already fixed by
`schemas/crossmatrix-mcp.schema.json` — no new schema design, just
implementation.

### 6.2 Roof (HOW×HOW correlation) scale + a computed roof finding

The relationship matrix maps cleanly (§2). The **roof** needs a bipolar
correlation scale (`strong_positive`/`positive`/`negative`/`strong_negative`)
declared as a `scale.declare`, plus a self-`relation` `dim_char → dim_char`. The
example fixtures declare the WHAT×HOW relation but not the roof — the HOQ config
template (`connections`/an example) should add it. No engine change beyond §6.1
if scales are data-driven (they are — `hoq.config.json` scales).

### 6.3 `analyze.priority` (technical-importance ranking as a first-class query)

`analyze.contract` returns raw contraction findings (`main.rs:127-145`). A HOQ
consumer wants a *ranked* HOW list. The schema already reserves
`analyze` op `priority` (`crossmatrix-mcp.schema.json` QAnalyze enum) but it is
unimplemented. Either implement `analyze.priority` (sort + normalize the
qfd_propagate column sums) or have the capability rank `analyze.contract`
findings itself. Recommend implementing `analyze.priority` so the ranking is
code-computed (pack ethos), not LLM/JSONPath-sorted.

---

## 7. Open decisions (USER)

1. **Build crossmatrix-mcp, or not?** This is the gating call. The HOQ capability
   is written and ready, but the engine's write-API + persistence + analyze are
   stubs (§1.3). Options: (a) fund the §6 build (est. the bulk is §6.1 core
   write-API + store wiring; schema/ADRs are done); (b) shelve HOQ until
   crossmatrix is prioritized; (c) a thin interim — implement only the
   `model` import-persist + `analyze.contract` path (§6.1 option b) and ship a
   one-call HOQ that skips incremental `observe`. Recommend (c) as the minimum
   viable slice — it exercises the real deterministic rollup with the least
   engine work.
2. **Where does HOQ plug into the SDLC flows?** Proposed: elicit → HOQ →
   technical-design → FMECA (§3.1). Confirm HOQ is a `cap.plan.*` (design-time)
   vs a `cap.review.*` trade-off gate. Recommend `cap.plan.house-of-quality`.
3. **Composed-open vs incremental-observe** (§6.1a/b) — affects both the engine
   build and whether the agent submits one payload or many. Recommend composed
   open + single analyze for v1; incremental `observe` (with provenance/evidence
   per cell) as a follow-on that unlocks the roof + traceability queries.
4. **Roof + competitive benchmarking scope** — v1 could ship WHAT×HOW +
   technical importance only, deferring the roof (§6.2) and benchmarking. Confirm
   whether the first cut is the full house or just the body + weighted floor.

## 8. What needs a gateway edit / restart, and what needs a build

| Action | Who | Needed for HOQ v1? |
|---|---|---|
| `crossmatrix` connection in `gateway.yaml` | already present (`:169`) | already done — no edit |
| Add `CROSSMATRIX_STORE_ROOT` env to the connection | USER (gateway edit + MCP restart) | only once §6.1 persistence lands |
| Copy `connections/crossmatrix.yaml` reference into gateway | USER (optional; live conn already exists) | not required |
| Build crossmatrix-mcp write-API + model persistence (§6.1) | crossmatrix repo | **BLOCKING** |
| Build roof scale/relation (§6.2), `analyze.priority` (§6.3) | crossmatrix repo | roof/priority optional for v1 |
| Add `cap.plan.house-of-quality.yaml` + `skills/plan.hoq.relate.yaml` | this pack | ready to drop once engine works |

Nothing in this pack change touches `~/.config/praxec/gateway.yaml` or the
`../execution-policy` repo. The only gateway edits are the optional store-root env
(§4.3), performed by the USER after the engine build.
