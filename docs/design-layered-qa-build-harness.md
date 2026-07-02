# Design — Deliverables + Milestones, CPM-scheduled, Layered QA (build-harness evolution)

- Status: Proposed
- Date: 2026-06-29
- Scope: `cap.implement.build-loop`, the plan schema it consumes, the cohort/CPM
  orchestration around it (`flow.loom` → `flow.execute-cohorts` →
  `flow.implement.deliverable`), and the `verify.test.tdd-verdict` /
  `format.cleanup` script layer.
- Supersedes nothing; refines the v2 structural-TDD build loop.

## Context — what we observed

Driving the `crossmatrix` core build through `cap.implement.build-loop` surfaced
a cluster of related problems, all instances of one root issue: **verification
was applied at the wrong altitude and the wrong cadence.**

1. **Non-convergence spin (the 30-min "freeze").** On a QA rejection the loop
   re-ran `green_code` at the **same model** with no escalation and no count
   breaker, so it cycled green↔review indefinitely (observed: 10 build iters, 0
   slices committed). The serve-path `auto_drive` loop has no wall-clock budget
   (only `max_depth=32` and a human-gate break), so it blocked the caller. FIXED
   already (see "Precursor fixes" below): feed findings forward, retry-then-
   escalate model ladder, circuit-break to a human.
2. **Mis-scoped QA.** The `reviewing` step judged **each incremental slice
   against the whole plan's `acceptance_criteria`** — so it rejected every slice
   because later deliverables (`contract()`/`findings()`) were still stubs. No
   model can satisfy a whole-plan criterion from a single minimal slice, so the
   escalation ladder burned tiers on an **unsatisfiable-for-now** criterion and
   parked at a human on *every* slice.
3. **Mechanical checks blocked on trivia.** A one-line `cargo fmt` nit looped
   `needs_cleanup` for several iterations because the agent hand-formatted
   instead of running the formatter. FIXED already: a language-agnostic
   `format.cleanup` step.
4. **Single-language assumption.** The verdict/cleanup logic baked in `cargo`,
   yet the harness must serve any language (and multi-language repos).
5. **Per-step cost.** Full compile + full test suite + clippy + fmt + a senior
   QA model run **per tiny behavior** is expensive and serial, and defeats the
   parallelism the cohort machinery already offers.

The through-line: **cheap, local checks should run often; expensive, global
checks should run once over a batch at an explicit synchronization point.**

## Decision — the model

### 1. A plan is a DAG of *deliverables* and *milestones*

- **Deliverable** — a fine-grained unit of work that carries its **own**
  acceptance (self-contained). Sized to one module/file's one behavior so that
  independent deliverables touch **different files** and can run in parallel
  (the repo write-lock serializes same-file writers, so granularity should
  follow module boundaries).
- **Milestone** — a zero-work **synchronization + verification gate** that
  depends on a set of deliverables. The milestone is **where the expensive,
  global checks run once over the batch**: full workspace compile, full test
  suite, lint, and an integration QA review.
- Dependencies between deliverables/milestones let `cpm-planner` compute the
  critical path and the **parallelizable cohorts**.

### 2. Layered QA — each layer scoped to its own altitude

| Layer | Runs | Scope (what it judges) | Cost |
|---|---|---|---|
| **L0 — deliverable** | per granule, before commit | *This deliverable's own* acceptance + that its single assertion pins the behavior + no local regression + idiomatic quality. **Never** the whole plan; other deliverables being stubbed is fine. | cheap — incremental compile + just this deliverable's tests |
| **L1 — milestone** | per cohort | The integrated batch compiles, full suite + clippy + fmt pass, and the batch is coherent together. | expensive, **batched** |
| **L2 — end-of-plan** | once, all deliverables done | The **whole-plan** `acceptance_criteria` (the end-to-end story: example loads → contracts → findings). | one-time |
| **L3 — completion audit (check-the-check)** | once, after L2 | Independent verification the plan was **fully** executed: review plan vs **all code on disk** + a stub-scan → enumerate **gaps** → if any, emit a **second (remediation) plan**. Bounded by a max-rounds breaker. | one-time, bounded |

### 3. Verification placement — resolving the TDD-vs-batch tension

Strict per-behavior TDD wants compile+test on *every* step (max correctness, but
serial + compile-heavy). Milestone batching wants make-all-changes →
compile-once (fast + parallel, but loses per-step proof). The resolution is
**placement, not either/or**:

- **Per-deliverable (L0):** keep the red→green proof, but use **incremental**
  compile + only *this deliverable's* tests. No fmt/clippy/whole-suite here.
- **Milestone (L1):** full workspace build + full suite + clippy + fmt +
  integration QA, **once** over the cohort's batch.

So compile/test exist at two altitudes by design; the cost is paid where it buys
something (tight local feedback OR global integration), never redundantly.

### 4. Language-agnostic operations

Compile / test / lint / format are **operations with per-language bindings**,
selected by repo detection — never hardcoded. `format.cleanup` already does this
(rust/python/javascript/go, multi-language, one `case` row per language). The
verdict (`verify.test.tdd-verdict`) must be refactored the same way: detect
language(s), dispatch the build/test/lint command set per language.

## Reuse vs. new work

**Already exists in praxec** (do not rebuild):
- CPM scheduling + parallel cohorts: `cpm-planner`, `flow.loom`,
  `flow.execute-cohorts`, `flow.implement.deliverable` (already wraps the
  build-loop + marks the deliverable complete in `cpm-planner`).
- Gap-detection ingredients: `cap.verify.stub-scan`, `cap.verify.workspace-green`.
- Global repo write-exclusion (`repo_locks`) for safe parallel writers.

**New work:**
1. **Deliverable-scoped L0 QA** (vs the current plan-scoped review). *[quick fix]*
2. **End-of-plan L2 QA** gating completion. *[quick fix]*
3. **Milestone nodes** that batch full compile/test/lint/integration-QA.
4. **L3 completion audit → remediation-plan loop** (reuse `stub-scan`; bound the
   recursion).
5. **Plan schema** carrying per-deliverable acceptance, milestone gates, and
   dependencies for CPM.
6. **Language-agnostic verdict** (mirror `format.cleanup`'s dispatch).

## Consequences

- (+) QA stops rejecting slices for work that isn't theirs; the escalation
  ladder only fires on genuinely-unsatisfied *slice* criteria.
- (+) Expensive checks run once per cohort, not per behavior → cheaper + enables
  real parallelism.
- (+) The L3 audit guarantees "the plan was actually, fully executed" and turns
  residual gaps into a governed second pass instead of silent incompleteness.
- (−) Plans must be authored at finer granularity with explicit acceptance +
  deps + milestones — more up-front design (mitigated by CPM tooling).
- (−) Two compile altitudes add modest bookkeeping; justified by the cost/
  parallelism win.

## Implementation phases

- **Phase 0 (quick fix, now):** L0 reviewer scoped to the slice; add an L2
  end-of-plan review before `done`. Unblocks the `crossmatrix` build immediately.
- **Phase 1:** language-agnostic verdict (detect → per-language build/test/lint).
- **Phase 2:** plan schema = deliverables + milestones + acceptance + deps;
  milestone nodes batch L1 checks.
- **Phase 3:** L3 completion audit → bounded remediation-plan loop.
- **Phase 4:** wire the finer-grained, milestone-bearing plans through
  `flow.loom`/`flow.execute-cohorts` for CPM-parallel execution.

## Precursor fixes already landed (2026-06-29)

These resolve the non-convergence/freeze and the mechanical-trivia stalls, and
are prerequisites this design builds on:
- **QA escalation ladder + circuit breaker** — `inspect.qa-ladder` (deterministic;
  feed findings forward → retry same model `qa_same_model_retries`× → climb
  `coding → coding-standard → coding-frontier`+`xhigh` → human). Validated live.
- **Language-agnostic `format.cleanup`** — auto-format before measuring; agent
  never hand-formats.
- **Diagnosis of the engine drive loop**: no loop deadline is correct (per-step
  `stall_timeout` already handles genuine hangs); non-convergence is a *count/
  progress* problem, solved by the ladder's breaker, not a timer.
