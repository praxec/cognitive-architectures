# Two plan types: DevelopmentPlan vs ExecutionPlan

Status: proposed (2026-07-17). Formalizes a distinction the repo already
embodies but never named, and adds one new convention (explicit fix nodes)
so the CPM schedule accounts for rework.

## The distinction

Program work decomposes into two plans that are *different in kind* and should
not be conflated on one graph edge:

- **DevelopmentPlan** — a DAG of code deliverables. Design-time. Edges are
  REAL code dependencies (contract → handler → BFF → FE; codegen is a hard sync
  barrier). Nodes are file-disjoint (`owned_files`), so they are
  parallel-leasable. This is what `cap.plan.build-graph` produces and what
  cpm-planner schedules/leases.
- **ExecutionPlan** — the build/test verification of a bounded scope. Run-time.
  It is a *convergence loop* (build → test → fix-to-green), not a dependency
  edge. This is what `flow.cohort.compiled-stack` runs: edit-only per
  deliverable → ONE codegen milestone → ONE build+test verify → attribution on
  failure (`cap.diagnose.attribute-cohort-failure`).

The governing rule both already encode: **build/codegen are SYNCHRONIZATION
POINTS, not per-slice steps.** Fan out development maximally; verify at barriers
per cohesive scope — never per-change, never one-global.

### How the two plans map to existing definitions

| Concept              | Definition today                                    |
|----------------------|-----------------------------------------------------|
| DevelopmentPlan (author) | `cap.plan.build-graph` (deliverables DAG)        |
| DevelopmentPlan (schedule/lease) | cpm-planner via `cap.coordinate.cpm-plan` / `cap.coordinate.cpm-acquire*` |
| ExecutionPlan (per scope) | `flow.cohort.compiled-stack` (1 codegen + 1 build+test over a warm shared tree) |
| ExecutionPlan (atom) | `flow.shared.mini-vee` (sketch → build-loop → verify → gate) |
| Failure attribution  | `cap.diagnose.attribute-cohort-failure` (map findings onto the `owned_files` partition) |

So the machinery is present. What is missing is (a) the *name* of the
distinction, and (b) making rework a first-class, scheduled thing.

## The gap this closes: rework is invisible to CPM

Today the loop-back on a failed build/test barrier is operator-driven:
`flow.cohort.compiled-stack` parks in `failed_attributed`, the driver marks the
implicated members failed and re-runs survivors. Correct for execution — but
the *schedule* never saw the rework. A critical path computed over the
DevelopmentPlan under-counts, because the expensive "make it compile / make it
pass again" work is not a node.

A cyclic edge (build → test → back-to-build) is not an option: CPM critical-path
and the planner's acyclic-prerequisite invariant both require a DAG.

## The convention: explicit fix nodes (a mini-waterfall per scope)

Give each bounded-context scope an explicit, **acyclic** mini-waterfall of real
deliverables, so budgeted rework lands on the critical path:

```
D1 … Dn  (parallel, file-disjoint)  →  B-<scope>  →  Fb-<scope>  →  T-<scope>  →  Ft-<scope>
   develop nodes                        build        build-fix       test         test-fix
```

- **B / T** (`kind: build|test`): the barriers. `owned_files` are unique marker
  paths (`.plan/build/<scope>`, `.plan/test/<scope>`) so they stay disjoint;
  `metadata` carries the `build_command` / `test_command` + CI filter.
- **Fb / Ft** (`kind: fix`, `phase: build|test`): ALWAYS present, with a
  **budgeted** `estimated_effort_hours` (expected rework, ~25–40% of the scope's
  dev hours). No-op at execution time if the barrier was already green.
- The loop lives **inside** each fix node — bounded internal iterations
  (`max_internal_iterations`, patch↔build or patch→build→test), escalate on cap.
  Opaque to the DAG, so the graph stays acyclic and CPM computes.
- **Two** fix nodes, not one: build-fix fails fast on compile before a test run,
  and it separates make-it-compile rework from make-it-pass rework (different
  work, different attribution).
- **Cross-scope dependencies key off `Ft-<scope>`** — a scope is "verified done"
  only after test-fix, so a downstream deliverable prereqs on the scope's
  TestFix node, never on a raw develop node.

This is the develop-plan / execution-plan split made concrete on ONE schedulable
graph: `D*` are the DevelopmentPlan; `B → Fb → T → Ft` is the ExecutionPlan for
that scope, unrolled just enough to be scheduled and no more.

## Implementation delta (small, additive)

1. **`cap.plan.build-graph`** — after emitting develop deliverables, group them
   by `metadata.scope` (bounded context) and append the four barrier nodes per
   scope with the wiring above. Disjointness holds automatically via the
   `.plan/*` marker paths. (The producer still never grades itself; cpm-planner
   validates disjoint + acyclic at schedule.)
2. **`flow.cohort.compiled-stack`** — its `verify` milestone becomes the `B`/`T`
   nodes and its `failed_attributed` parking becomes the `Fb`/`Ft` node bodies
   (the internal fix loop + escalate-on-cap already exists as attribution +
   operator re-run; here it is a leased Fix deliverable instead of a park).
3. **Handoff that closes the loop across the two plans:** a fix node that
   exhausts `max_internal_iterations` marks itself failed and (optionally) emits
   a follow-on develop deliverable scoped to the still-red `owned_files` — the
   only sanctioned way rework re-enters the DevelopmentPlan.

## Open nuances (decide per program)

- **Barrier granularity** — scope to a bounded context (assembly / tool /
  service). Too coarse ⇒ late, ambiguous failures; too fine ⇒ re-serialized
  builds (the exact cost `flow.cohort.compiled-stack` exists to avoid).
- **Attribution scoping** — a failed barrier scopes its fix to the suspect
  develop nodes via `owned_files` overlap; `cap.diagnose.attribute-cohort-failure`
  already produces the implicated/collateral/clear verdicts the fix node needs.
- **Budget calibration** — the fix-node hour budget is an estimate of *expected*
  rework; measure actuals (`cap.coordinate.cpm-mark` records attempts) and tune.
