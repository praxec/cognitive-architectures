# Two plan types: DevelopmentPlan vs ExecutionPlan

Status: adopted (2026-07-18). Formalizes a distinction the repo already
embodies but never named, corrects a conflation this doc itself introduced in
its first revision, and adds the velocity principle that makes the
distinction matter in practice: scoped per-slice verify, ONE full barrier.

**Changelog note (read this first if you're diffing):** the 2026-07-17
revision of this doc introduced an "explicit fix nodes" convention that told
`cap.plan.build-graph` to append `B-<scope> → Fb-<scope> → T-<scope> →
Ft-<scope>` marker deliverables directly into `graph.deliverables[]` — i.e.
into the DevelopmentPlan cpm-planner schedules. That re-conflated the two
plans this doc exists to separate: a verification barrier was made a
scheduler-visible *code deliverable* with fake `owned_files`, even though it
edits nothing and has no developer. This revision reverses that: the
mini-waterfall is real, but it is owned and run by the **execution flows**
against the DevelopmentPlan `cap.plan.build-graph` already produces — never
authored as nodes on the graph itself. See "The convention" below.

## The distinction

Program work decomposes into two plans that are *different in kind* and should
not be conflated on one graph edge, and — as of this revision — not conflated
onto one *schema* either:

- **DevelopmentPlan** — a DAG of code deliverables. Design-time. Edges are
  REAL code dependencies (contract → handler → BFF → FE; codegen is a hard sync
  barrier). Nodes are file-disjoint (`owned_files`), so they are
  parallel-leasable. This is what `cap.plan.build-graph` produces and what
  cpm-planner schedules/leases. It contains ONLY things a developer/agent
  edits (plus, as the one sanctioned exception, an owner-decision *gate* — a
  real dependency on a human answer, not a build/test barrier).
- **ExecutionPlan** — the build/test verification of a bounded scope. Run-time.
  It is a *convergence loop* (build → test → fix-to-green), not a dependency
  edge, and it is not schedulable by cpm-planner because it isn't made of code
  deliverables. It is owned and driven entirely by the execution FLOWS:
  - `flow.cohort.compiled-stack` — a batched cohort (≤ 5 file-disjoint
    deliverables) in one shared warm tree: edit-only per deliverable → ONE
    codegen milestone → ONE build+test verify → attribution + ONE bounded
    recovery pass on failure (`cap.diagnose.attribute-cohort-failure` +
    `cap.run.fix-scope`).
  - `flow.execute-cohorts` — the serial, one-deliverable-at-a-time driver: each
    deliverable is built + marked complete on a SCOPED per-slice verify, then
    ONE full-suite barrier (`barrier_verifying`) runs once when the whole plan
    is exhausted.

The governing rule both already encode: **build/codegen/full-suite are
SYNCHRONIZATION POINTS, not per-slice steps.** Fan out development maximally;
verify at barriers per cohesive scope — never per-change, never never-at-all.

### How the two plans map to existing definitions

| Concept              | Definition today                                    |
|----------------------|-----------------------------------------------------|
| DevelopmentPlan (author) | `cap.plan.build-graph` (deliverables DAG — develop nodes + owner-decision gates ONLY; see the changelog note) |
| DevelopmentPlan (schedule/lease) | cpm-planner via `cap.coordinate.cpm-plan` / `cap.coordinate.cpm-acquire*` |
| ExecutionPlan (batched cohort) | `flow.cohort.compiled-stack` (1 codegen + 1 build+test over a warm shared tree, + 1 bounded recovery) |
| ExecutionPlan (serial driver) | `flow.execute-cohorts` (scoped per-deliverable verify, looped, + 1 closing barrier) |
| ExecutionPlan (single-increment atom) | `flow.shared.mini-vee` (sketch → build-loop → verify → gate) — invoked ONCE per increment by its callers today, so its own verify already plays a single-barrier role; it is not currently looped per-slice inside a larger cohort |
| Per-slice SCOPED verify | `cap.implement.build-loop`'s `cargo_scope` (rust, pre-existing); `cap.verify.ts` / `cap.verify.dotnet`'s `scope` input (added with this revision) |
| Failure attribution  | `cap.diagnose.attribute-cohort-failure` (map findings onto the `owned_files` partition) |

So the machinery is present. What was missing, closed by this revision, was
(a) the *name* of the distinction, (b) NOT conflating the two plans' schemas
(the changelog note), and (c) the actual per-slice/barrier verification
granularity in the execution flows — see the velocity principle below.

## The velocity principle: scoped per-slice verify, ONE full barrier

This is the core rule the rest of the doc exists to make schedulable. It was
diagnosed directly from an observed defect: agents were running the FULL test
suite / full `tsc` / full lint to verify EACH micro-change, which dominated
wall-clock time on every plan. The fix is not "verify less" — it is "verify
the right thing at the right granularity":

- **Per-deliverable / per-slice local verify = the NARROWEST thing that can
  prove THIS change**: the specific affected unit/story test file(s) the
  slice touches, plus lint scoped to the files it touched. Nothing more.
- **The full type-check + full test suite + full lint = ONE Build/Test
  BARRIER**, run ONCE at cohort/plan close (the mini-waterfall: `develop →
  Build → BuildFix → Test → TestFix`), never per slice.
- `tsc --noEmit` is **whole-program** — there is no cheap way to typecheck one
  file — so for TypeScript the per-slice check is *lint + the affected vitest
  test(s)*; typecheck (and the bundler build) is barrier-only. This is why
  `cap.verify.ts`'s scoped arm explicitly does NOT run `tsc`/`vite build` (see
  its header) — it would be dishonest to claim typecheck passed when it
  wasn't run, so the scoped verifyOut simply omits that criterion rather than
  faking it.
- The barrier still runs the FULL suite — this principle never weakens
  verification. It moves the full run from "once per slice" to "once per
  cohort/plan", and makes the per-slice check genuinely narrow instead of
  either (a) full-every-time (slow) or (b) skipped (unsafe).

### Where this lands in the pack, concretely

| Stack | Per-slice SCOPED check | Barrier (full, once) |
|-------|------------------------|------------------------|
| rust  | `cap.implement.build-loop`'s `cargo_scope` (`-p <crate>`), already existed — the RED/GREEN TDD loop tests only the touched crate | `cap.verify.rust` (`cargo fmt + clippy + test --workspace`), called once by `flow.cohort.compiled-stack`'s verify milestone; `flow.implement.deliverable`'s rust arm still calls it per-deliverable too (a known residual gap for the serial driver — see "Open nuances") |
| ts    | `cap.verify.ts` with `scope` set: eslint on touched files + `vitest run` on the affected test file(s) only | `cap.verify.ts` with `scope: ""` (default): `npm ci` + `tsc --noEmit` + `vite build` |
| dotnet| `cap.verify.dotnet` with `scope` set: narrows to a project path or an ANDed `--filter` fragment | `cap.verify.dotnet` with `scope: ""` (default): full `dotnet build` + `dotnet test` over `cwd` |
| (bugfix, single-change) | `cap.verify.regression-tests`'s `scope` (a crate name, optional) | same cap, `scope: ""` (default) = `cargo test --workspace` — for its sole current caller (`flow.bugfix-from-error-log`, exactly one fix per run) this full run already correctly plays the barrier role, since there is no per-slice repetition to amortize |

`flow.implement.deliverable`'s `verify_scope` input threads the SCOPED arm
through for ts/dotnet (default `""` = unchanged full backstop, so every
caller that predates this input keeps its exact old behavior).
`flow.execute-cohorts`'s `verify_scope` + `stack` inputs are how a caller
opts BOTH halves in together: `verify_scope` narrows every deliverable's
pre-mark check, and `stack` (non-`""`) enables the ONE `barrier_verifying`
pass that runs when the plan is exhausted. **Never set only one of the two**
— an unscoped per-deliverable check plus a closing barrier pays for the full
suite twice; a scoped per-deliverable check with no barrier never runs the
full suite at all, which silently drops the safety net the two-gate design
depends on.

## The convention: the mini-waterfall, owned by the execution flows

Give each bounded-context scope (or, for the serial driver, the whole plan) an
explicit, **acyclic** mini-waterfall so budgeted rework lands on the critical
path — but as **flow states**, not **graph deliverables**:

```
D1 … Dn  (parallel, file-disjoint, DevelopmentPlan)  ⇒  Build  →  BuildFix  →  Test  →  TestFix
   cap.plan.build-graph produces these                   the ExecutionPlan a FLOW runs, not the schedule
```

Two concrete implementations already exist in the pack; neither authors a
barrier node into `graph.deliverables[]`:

- **`flow.cohort.compiled-stack`** (batched cohort): `editing_0..4` (edit-only,
  no build/no git) → `generating` (codegen milestone, optional) →
  `verifying` (Build+Test COMBINED into one verify milestone call — the
  underlying `cap.verify.<stack>` already runs build then test in sequence) →
  on failure, `attributing_verify` → `deriving_fix_scope` →
  `recovering` (BuildFix+TestFix combined into ONE bounded fix pass, grounded
  in the verify findings) → `linting_recovery` → `reverifying` → `committing`.
  The loop is bounded BY CONSTRUCTION (straight-line, no back-edge — see that
  flow's own header) rather than by an `estimated_effort_hours` budget on a
  graph node.
- **`flow.execute-cohorts`** (serial driver): each deliverable is built +
  marked complete on scoped evidence, looped; `barrier_verifying` /
  `barrier_verify_gate` is the ONE Build+Test barrier at plan close (dispatch
  by `stack`); a failure lands in `barrier_failed` (terminal, `outcome:
  failure`) carrying `$.context.barrier_verify` for the operator — this flow
  does not yet implement a fix/recovery loop the way `flow.cohort
  .compiled-stack` does (see "Open nuances").

Cross-scope dependencies still key off a scope's Test/TestFix having gone
green — but that "having gone green" lives in the EXECUTION FLOW's own
context/state (e.g. a cohort's `commit_message`/`last_commit` or a plan's
`barrier_verify.status == 'pass'`), not as a graph node id a downstream
deliverable's `prerequisites[]` can reference. A downstream deliverable that
must not start before a scope is verified belongs in a LATER cpm-planner
schedule (or a later cohort acquire), scheduled after the operator/driver
observes that scope's barrier passed — not wired as a same-graph edge.

## Implementation delta (adopted this revision)

1. **`cap.plan.build-graph`** — REVERSED the 2026-07-17 "emit barrier nodes"
   instruction. It now authors develop deliverables (tagged
   `metadata:{kind:"develop", scope:"<bounded-context>"}`) and owner-decision
   gates ONLY; it explicitly tells the authoring agent not to inline
   Build/BuildFix/Test/TestFix nodes, and points at the execution flows
   instead.
2. **`cap.verify.ts` / `cap.verify.dotnet`** — gained an optional `scope`
   input (default `""` = the full barrier gate, byte-for-byte the prior
   behavior). Non-empty scope runs the narrow per-slice path described above.
3. **`cap.verify.regression-tests`** — gained an optional `scope` (crate name)
   threaded to `test.cargo.workspace`'s existing pass-through args; default
   `""` is unchanged (`--workspace`).
4. **`flow.implement.deliverable`** — gained `verify_scope` (default `""`,
   unchanged for existing callers), threaded into the ts/dotnet verify arms
   only (rust stays a full per-deliverable backstop — see "Open nuances").
5. **`flow.execute-cohorts`** — gained `verify_scope` (threaded to
   `flow.implement.deliverable`) and `stack` (dispatches the new
   `barrier_verifying` → `barrier_verify_gate` → `done` | `barrier_failed`
   sequence, run ONCE when the plan is exhausted). `stack == ""` (default)
   skips the barrier entirely — a caller that hasn't opted in (e.g.
   `flow.loom` today, which does not yet know a heterogeneous brief's stack
   ahead of scheduling) gets exactly its prior behavior.
6. **`flow.loom` / `flow.drive-program`** — updated their nested calls to
   explicitly pass the new inputs (`""` literals) rather than omit them: a
   nested `kind: workflow` invocation does not merge a callee's OWN declared
   default into `$.workflow.input` (the same rule documented on
   `flow.shared.mini-vee`'s `cargo_scope`), so omitting a newly-added input at
   a call site that references it is an unresolved-arg-path failure, not a
   silent default.

## Open nuances (decide per program)

- **`flow.execute-cohorts` has no fix/recovery loop yet** — unlike
  `flow.cohort.compiled-stack`'s bounded `recovering` pass, a
  `barrier_verifying` failure in the serial driver dead-ends at
  `barrier_failed` for the operator. Every deliverable is still individually
  marked complete by that point (on scoped evidence), so nothing is lost, but
  closing this gap the same way `flow.cohort.compiled-stack` does is a
  natural follow-up.
- **rust's per-deliverable path in `flow.execute-cohorts` is unchanged (full
  cross-crate backstop every deliverable)** — `cap.verify.rust` deliberately
  did not gain a `scope` input in this revision (`cap.implement.build-loop`'s
  existing `cargo_scope` already gives rust a fast per-slice inner loop; the
  outer full-workspace check plays the same "milestone" role this doc
  describes, just not yet hoisted to a plan-close barrier for the serial
  driver). rust cohorts that want the barrier-once-per-cohort model should use
  `flow.cohort.compiled-stack`, which already implements it.
- **Barrier granularity** — for `flow.cohort.compiled-stack`, scope to a
  bounded context (assembly / tool / service). Too coarse ⇒ late, ambiguous
  failures; too fine ⇒ re-serialized builds (the exact cost that flow exists
  to avoid).
- **Attribution scoping** — a failed barrier scopes its fix to the suspect
  develop nodes via `owned_files` overlap; `cap.diagnose.attribute-cohort-failure`
  already produces the implicated/collateral/clear verdicts the fix step needs.
- **`flow.loom` does not yet opt into the scoped/barrier path** — it passes
  `verify_scope: ""` / `stack: ""` literally, preserving its prior behavior.
  Threading a real per-scope `verify_scope` and a real `stack` through
  `cap.plan.build-graph`'s output into `flow.execute-cohorts` is the natural
  next step once the graph reliably carries that metadata.
