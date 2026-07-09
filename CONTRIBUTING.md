# Contributing to cognitive-architectures

Thanks for considering a contribution. This repo ships YAML
artifacts — skills, scripts, capabilities, orchestrators — that
operators load into praxec. The shape conventions below are
what keep the library composable.

---

## What to contribute

| Layer | Lives in | Naming | Trigger to add |
|---|---|---|---|
| Skill | `skills/*.yaml` | `<verb>.<subject-root>.<name>` | A small, reusable coaching note for one cognitive verb |
| Script | `scripts-library/*.yaml` | `<verb>.<subject-root>.<name>` | A deterministic action (build/test/deploy/format/lint/install/verify/run) |
| Capability | `capabilities/cap.<verb>.<name>.yaml` | `cap.<verb>.<name>` (one segment after verb) | A typed-contract sub-workflow with `snippet: { inputs, outputs }`. Composition leaf — never invokes another workflow. |
| Orchestrator | `orchestrators/flow.<name>.yaml` | `flow.<name>` | A lifecycle workflow that composes capabilities via `kind: workflow` with `use:` bindings. |
| Workflow (legacy) | `workflows/*.yaml` | — | Demo workflows; new contributions should prefer capabilities + orchestrators. |

The skill, script, and workflow layers are not going away — they're
orthogonal authoring affordances, used by capabilities internally. The
manifest layout exposes `capabilities/`, `orchestrators/`, `skills/`, and
`scripts-library/`; the demo `workflows/` (and `agents/`, `patterns/`,
`examples/`) load via the `include:` path instead.

---

## Capability authoring style (SPEC §5.4)

The runtime enforces correctness rules (contract typing, slot
reachability, verb-subject consistency, no-nesting). The library
enforces **taste** — these guidelines are reviewed by hand and never
trip a load-time error.

### Keep snippets small — ≤5 inputs, ≤5 outputs

A capability with 6 inputs isn't broken, just smelly. Larger contracts
fragment composition: every consumer has to thread the extra slot
through, every cross-cap reference has to know about it, every
contract-hash diff churns when the input set shifts.

Above five, ask: is this one capability or two? Bundling related
inputs into a typed object (`config: { type: object, properties: {...} }`)
preserves the count while keeping structure.

### Pick the right verb (the 24-cloud)

Choose from the closed CapVerb set (SPEC §4):

- **Cognitive (LLM-driven):** `triage`, `diagnose`, `plan`,
  `implement`, `review`, `refactor`, `explain`, `compose`, `research`,
  `summarize`
- **Deterministic (tool/script):** `build`, `test`, `deploy`, `format`,
  `lint`, `install`, `verify`, `run`, `inspect`, `search`, `fetch`,
  `audit`
- **Coordination:** `gate` (HITL / quorum / ack), `coordinate`
  (external side effect like PR open)

The verb encodes both **who acts** and **what shape the primary
executor is** (V6). Picking the wrong verb means the runtime rejects
the cap at load. If the cap doesn't fit any of the 24, the contribution
probably belongs as a script or skill instead.

### Scope discipline

Caps invoking `implement.*` or `refactor.*` should declare
`scope_paths` as a required input. The underlying edit tool
(`constrained-edit`, etc.) enforces the path allowlist at write time;
the cap's input shape documents it for the orchestrator.

Coordination caps (`coordinate.*`) should be the LAST transition in
any orchestrator that invokes them — side effects are terminal. If
something needs to happen after a side effect, it belongs in the
external system's response loop, not in the orchestrator.

---

## Orchestrator authoring style (SPEC §7)

### Declare every host slot via `inputs:` or `use.outputs`

The slot-table validator (V13) refuses an orchestrator that reads
`$.context.X` via `use.inputs` without a write site for `X`. Practical
consequence: when you add a new capability invocation that needs an
input from a slot, you ALSO add the writer in an earlier state's
`use.outputs`. The validator turns this into a load-time error
rather than a runtime surprise.

### Guards CANNOT read the same transition's `use.outputs`

The runtime evaluates guards BEFORE the transition's executor fires
(`runtime_chain::select_deterministic_transition`). A common
authoring trap is putting `guards: [{ expr: "$.context.verdict == 'pass' }]`
on the same transition whose `use.outputs` writes `verdict`. The guard
never sees a written value.

Workaround: split execute-and-branch into two states. One state runs
the capability; the next state's transitions branch on its output.
The shipping orchestrators ship happy-path-only to dodge this trap;
branched lifecycles will return after the state-shape helper lands.

### Pin contract hashes on `stable`-lifecycle caps

Once a capability promotes to `lifecycle: stable`, every orchestrator
that invokes it MUST include `expects_contract_hash:` (V16). The
error message inlines the current hash; copy-paste it in. Pinning
gives the library version-safe composition: if a cap's snippet
changes after promotion, every dependent orchestrator surfaces a
load-time mismatch.

---

## Vendored fixture in praxec

The praxec repo vendors a copy of this library under
`crates/praxec-core/tests/fixtures/cognitive-architectures/`
for its M4 acceptance test. The vendored copy is a manual sync —
when this library cuts a release, the operator updating praxec
re-copies `praxec.repo.yaml` + `capabilities/` + `orchestrators/`.
Symlinks were considered and rejected as fragile across checkouts.

---

## Validating a contribution

```bash
bash scripts/validate.sh
```

This script (existing) runs lints across all artifact kinds.
Capability and orchestrator contributions are additionally checked by
praxec's `check` subcommand:

```bash
praxec check --config examples/praxec-cognitive-only.yaml
```

That surfaces every V1-V23 violation against the live tree.

---

## Versioning

Cognitive-architectures is pre-1.0 (`0.0.x`) and follows praxec's
spec. This library is only meaningful against **praxec 0.0.14 or
later** — the manifest schema, snippet contract, and slot-table machinery
all land together. CHANGELOG.md records the required praxec version.
