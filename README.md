# cognitive-architectures

> Structured cognitive architectures for governed LLM agents — a
> `skills` repo, but with runtime semantics.

A curated library of Praxec-native YAML — capabilities, orchestrators,
skills, scripts, workflows, agent configs, and connection definitions —
that operators load via a `repos:` block (or copy-paste) to compose their
own governed agent systems.

---

## The Thesis

> A cheap or open-weight model, directed by a precise cognitive
> architecture and governed by a deterministic harness, can match or beat
> a frontier model that operates without structure.

(From the `praxec` RESEARCH notes.)

Each architecture encodes **what to think about** (guidance scoped to
one of 10 cognitive verbs), **when to think it** (workflow states in
sequence), **how to enforce it** (guards + blackboard + deterministic
executors), and **how to audit it** (transition records).

> **Two-tier composition.** A layer
> on top of the per-skill primitives: **capabilities** (`cap.*`) are
> typed-contract sub-workflows, and **orchestrators** (`flow.*`) are
> the lifecycle workflows that compose them. The shipping
> orchestrators — `flow.add-feature`, `flow.bugfix-from-error-log`,
> `flow.safe-refactor`, `flow.triage-issue`, and
> `flow.evidence-driven-convergence` — cover the main inbound
> surfaces of an engineering team. The composition is the point: this
> is where the library claims **composable parity**, not just per-skill
> parity, with broader skills ecosystems.
>
> Capabilities live under `capabilities/`, orchestrators under
> `orchestrators/`, and the whole tree is exposed to a gateway via a
> top-level `praxec.repo.yaml` manifest (SPEC §9). See "Two-tier
> composition" below for the loading pattern.

---

For comparison with prompt-style skills libraries, see
[mattpocock/skills](https://github.com/mattpocock/skills).

---

## Anatomy of a cognitive architecture

Every architecture is a composition of these artifact kinds (with
**capabilities** and **orchestrators** layered on top — see the next
section):

- **Skill** (`skills/*.yaml`) — a reusable guidance fragment under a
  blessed subject namespace, tagged with one of 10 cognitive verbs
  (`triage`, `diagnose`, `plan`, `implement`, `review`, `refactor`,
  `explain`, `compose`, `research`, `summarize`). Each skill is a
  focused 100-400 word coaching note. One mental model per file.
- **Workflow** (`workflows/*.yaml`) — a state machine that sequences
  the verbs. Each state declares a `delegate` (which agent does the
  work), a `goal`, surfaced skills, and a transition table with guards
  and executors.
- **Agent** (`agents/*.toml`) — a provider/model binding for a named
  role with a scoped system prompt. Workflow authors name roles
  (`planning-agent`, `editing-agent`, etc.); operators bind those names
  to actual models.
- **Connection** (`connections/*.yaml`) — an executor definition for an
  external tool: an MCP server, a CLI, or a REST endpoint.
- **Script** (`scripts-library/*.yaml`) — a curated, hash-pinned script
  body invokable by a workflow's `script` executor. Distinct verb
  vocabulary from skills: `build` / `test` / `deploy` / `format` /
  `lint` / `install` / `verify` / `run` / `inspect` / `search` /
  `fetch` / `audit`. Where skills tell the LLM what to think, scripts
  tell the workflow what to do — deterministically, with no model
  involvement. See `praxec` SPEC §22 (and SPEC §23 for the
  intent-layer invariant — skills and scripts together are the
  indeterminate + determinate intent layer).

Architectures compose into a complete gateway config via Praxec's
`include:` mechanism. See `examples/full-swe-pipeline.yaml` for the
end-to-end shape.

---

## Two-tier composition

The new tier-shape on top of skills/workflows/scripts:

- **Capability** (`capabilities/*.yaml`) — a `cap.<verb>.<name>`
  workflow with a typed `snippet: { inputs, outputs }` contract. Used
  as a sub-workflow by orchestrators; never invokes another workflow
  itself (composition leaves only). The library ships a capability for
  every stage of the lifecycle (the latest addition is
  `cap.plan.brainstorm` — a divergent-thinking primitive that pairs with
  any picking cap downstream).
- **Orchestrator** (`orchestrators/*.yaml`) — a `flow.<name>` workflow
  with an `inputs:` block declaring its entry signature. Invokes
  capabilities via `kind: workflow` executors with `use:` bindings
  that project typed outputs back into host context slots (see the
  lifecycle table below).
- **Repo manifest** (`praxec.repo.yaml`) — declares the namespace
  (`cognitive`) every loaded id is prefixed with, so multi-repo
  setups can compose without id collisions.

Operators wire the whole library into their gateway with:

```yaml
# gateway.yaml
version: "1.0.0"
repos:
  - path: /path/to/cognitive-architectures
```

Loaded ids land under `cognitive/<id>` — e.g. `cognitive/flow.add-feature`,
`cognitive/cap.plan.vet`. Cross-orchestrator capability reuse (caps
shared between bugfix / safe-refactor / add-feature) is the mechanism
the two-tier model exists to enable.

### Shipping orchestrators

| Orchestrator | Lifecycle | Trigger |
|---|---|---|
| `flow.add-feature` | Plan-driven feature delivery | Feature brief |
| `flow.bugfix-from-error-log` | Incident response | Error log / stack trace |
| `flow.safe-refactor` | Code-health | Scope description (paths or component) |
| `flow.triage-issue` | Intake | New issue / ticket |
| `flow.evidence-driven-convergence` | Deterministic decision-gating | Most-fragile assumption + desk evidence |

The repo manifest exposes `capabilities/`, `orchestrators/`, `skills/`,
and `scripts-library/` — the gateway's capability, flow, skill, and
script registries. Reference `connections/` stay out of the manifest, so
operators wire their own. The demo content under `workflows/`, `agents/`,
`patterns/`, and `examples/` stays in place and loads via Praxec's
`include:` mechanism — operators upgrading don't need to migrate.

---

## Scripts: the deterministic peer to skills

The thesis applied to actions: instead of inlining brittle
`command: ["bash", "-c", "..."]` arrays across every workflow, curate
a script library. Operators replace the library wholesale per
environment; workflows reference subjects, not commands.

Each script is a YAML file declaring a `scripts:` block (the same
shape Praxec consumes at the top level of any gateway config). It
carries a `verb` from the closed twelve, a `lifecycle`, a `source`
provenance string, and either an inline `body:` literal OR an
external `uri + hash` pair (v1 supports `file://` only).

**The scripts shipped here** span the curated verb vocabulary —
build / test / lint / format / verify / deploy / inspect / search /
install:

| Subject | Verb | What it does |
|---|---|---|
| `build.cargo.release` | build | Release build of a Rust crate/workspace, `--locked` for reproducibility |
| `test.cargo.workspace` | test | Full workspace test sweep; emits JSON summary for clean output mapping |
| `test.baseline.snapshot` | test | Capture a behavior baseline before a refactor |
| `test.baseline.compare` | test | Compare post-change behavior against the captured baseline |
| `lint.rust.clippy-strict` | lint | Clippy with `-D warnings` (every warning is a hard fail) |
| `format.rust.check` | format | `cargo fmt --check` — read-only audit that fails on diff |
| `verify.workspace.green` | verify | Composed gate: format-check + clippy + test must all pass |
| `ci.full-sweep` | verify | Full CI gauntlet: install → format → lint → test → release build |
| `deploy.cargo-install` | deploy | `cargo install --path` + `--locked`; pairs with `script_acknowledged` |
| `inspect.cargo.dependency-tree` | inspect | Read-only `cargo tree` + structured JSON summary on stdout |
| `inspect.crate.source` | inspect | Fetch and inspect a dependency crate's source |
| `search.codebase.ripgrep` | search | Pattern search via `rg` + per-pattern match/file counts on stdout |
| `install.opensrc` | install | Fetch open-source dependency sources for inspection |

**Referencing a script from a workflow:**

```yaml
states:
  verifying:
    transitions:
      run_verifier:
        target: critiquing
        actor: deterministic
        executor:
          kind: script
          subject: verify.workspace.green
        output:
          verifierPassed: "$.output.success"
```

The `swe-agent` workflow uses exactly this — the `verifying` state
now invokes `verify.workspace.green` rather than calling out to an
external verifier MCP. Less external surface, same deterministic
guarantees, and the script body is content-pinned by hash on the
workflow's snapshot.

For destructive scripts (deploys, migrations), pair the `script`
executor with a `script_acknowledged` guard — Praxec refuses to run
until an operator has called `gateway.describe` on the current body
(review-before-execute, hash-flip-invalidated on edit).

---

## Parallel: fan-out / fan-in inside one transition

Some architectures want to run independent activities concurrently —
50 SCIP queries against a codebase, 20 validation scenarios against a
patch, multiple reviewers / critics fanning out across one diff.
Sequential execution wastes wall-clock; the `parallel` executor kind
(praxec SPEC §24) adds first-class fan-out **inside a single
transition**:

```yaml
executor:
  kind: parallel
  branches:
    - { kind: script,   subject: lint.rust.clippy-strict }
    - { kind: script,   subject: format.rust.check }
    - { kind: script,   subject: test.cargo.workspace }
    - { kind: workflow, definitionId: critique_aspect, input: { ... } }
  join: all                            # all | any | { at_least: K }
  max_concurrency: 4                   # required when branches.len() >= 10
  on_branch_failure: continue          # bail (default) | continue
```

Or dynamic per-element fan-out:

```yaml
branches:
  for_each: "$.context.queries"
  do:
    kind: mcp
    connection: scip
    tool: lookup
    args: { symbol: "$.branch.value" }
```

Constraint that makes it safe (SPEC §24.5): fan-out lives INSIDE one
executor invocation. One state, one transition, one version bump, one
transition record. Per-branch audit events link back via parent
correlation_id + a `branch_index` payload. Multi-active-state workflow
execution is explicitly out of scope.

**Two demos in this library:**

- `workflows/parallel-scan.yaml` — 4 inspections fanned out (deps tree
  + clippy + fmt-check + tests), `on_branch_failure: continue` for a
  graded report, array-expansion mapping (`branches[*].ok`) into
  context.
- `workflows/parallel-review.yaml` — dynamic `for_each` over a
  per-aspect critique sub-workflow (`kind: workflow` branches),
  `join: all`, every aspect must clean-bill for approval.

---

## Installation

```bash
git clone https://github.com/praxec/cognitive-architectures
cd cognitive-architectures

# Copy an example into your gateway config and adjust the include paths
# (or point your gateway directly at one of the bundled examples):
praxec serve --config examples/full-swe-pipeline.yaml
```

You'll need:

- `praxec` 0.0.13 or later
  (`cargo install praxec`). It provides the scripts surface
  (SPEC §22), the verb taxonomy (SPEC §5/§22), the intent-layer
  invariant (SPEC §23), and parallel execution (SPEC §24) — the last is
  required for the `workflows/parallel-*.yaml` demos.
- The external MCP servers / CLI tools referenced by the connections you
  enable (the `connections/*.yaml` files document each one's contract).

---

## Validation

```bash
./scripts/validate.sh
```

Runs `praxec check --config` against every `examples/*.yaml`. Use
this as your pre-commit check when authoring new architectures.

---

## Contributing

We accept new architectures by PR. To keep the library coherent:

1. **One architecture per PR.** A new workflow + the skills it
   introduces + the agents and connections it needs. Atomic units only.
2. **Stay inside the cognitive-verb vocabulary.** `triage`, `diagnose`,
   `plan`, `implement`, `review`, `refactor`, `explain`, `compose`,
   `research`, `summarize`. There is no escape hatch; if your guidance
   doesn't fit, the workflow shape probably needs to split.
3. **Use a blessed subject root.** `review.*`, `authoring.*`, `debug.*`,
   `deploy.*`, `import.*`, `lifecycle.*`, `plan.*`, plus one of the
   eight verb-mirror roots. Subjects outside these fail config-load.
4. **`lifecycle:` honestly.** New, unproven guidance ships as
   `experimental`. Promote to `stable` only when at least one operator
   has run it in production for a quarter.
5. **`./scripts/validate.sh` must pass** before you push.

Bug reports, content corrections, and operator notes welcome via
issues.

---

## License

Apache-2.0 — see [LICENSE](./LICENSE).

---

## Links

- [praxec/praxec](https://github.com/praxec/praxec) —
  the gateway that interprets these architectures.
- [praxec.dev](https://praxec.dev) — full docs, concepts, and
  guides ([reusable primitives](https://praxec.dev/guides/reusable-primitives/),
  [capabilities & orchestrators](https://praxec.dev/guides/capabilities-and-orchestrators/)).
- [SPEC §5 (skills)](https://github.com/praxec/praxec/blob/main/SPEC.md#5-guidance)
  and [SPEC §21 (delegate)](https://github.com/praxec/praxec/blob/main/SPEC.md#21-sub-agent-delegation-tui-pass-through)
  for the runtime semantics this library targets.
