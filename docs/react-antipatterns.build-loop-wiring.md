# Wiring React anti-pattern PREVENT + CATCH into the build/verify loop

- Status: Proposed
- Date: 2026-07-28
- Scope: two mechanisms that move the React anti-pattern suite from a
  standalone `flow.fix.react-antipatterns` (run downstream, after the fact)
  into the cohort build/verify loop, so commodity FE build agents stop
  *creating* the antipatterns (derived-state-in-Effect / Effect-over-state-
  composition, wall-clock timers in mockable flows) that we then have to hunt
  and fix on a PR.
- Supersedes nothing. Builds on `docs/react-antipatterns.review-plan-fix.md`
  (the review/plan/fix suite) and `docs/plan-types.develop-vs-execute.md` (the
  scoped-per-slice vs barrier verify split).

## Trigger

A commodity-model cohort shipped four `useEffect`s syncing reducer state →
`sessionStorage` in `ContactsContext` (the Effect-over-composition
antipattern). It broke E2E on a real PR. The pack already HAS the React review
assets (`cap.review.react-antipatterns`, `cap.plan.react-feature`, the skills),
but nothing was wired into the build+verify loop the cohort actually runs
(`flow.execute-cohorts` → `flow.implement.deliverable` → `cap.implement.build-
loop`), so the antipattern was only catchable downstream. This closes that gap
with a PREVENT arm (guidance while writing) and a CATCH arm (a verify gate
before the deliverable is marked complete).

## Two insertion points

### 1. PREVENT — `cap.implement.build-loop` builder goals (FE-only, data-gated)

The builder agent leaves live in `cap.implement.build-loop` (`red_test`,
`green_code`). This capability is SHARED by rust/dotnet/ts deliverables and
runs BEFORE the parent flow detects the stack, so we cannot statically add a
React skill to its `skills:` list (that would pollute .NET/Rust prompts) and we
cannot branch on stack here (unknown yet).

Instead we surface the guidance **through data the builder already receives** —
option (a) in the task. The builder is given the whole deliverable as
`$.workflow.input.plan`. We append a **hard self-gated paragraph** to the
`red_test` and `green_code` goals that fires ONLY when the plan is a
React/TypeScript deliverable — keyed on `plan.stack` ∈ {ts,tsx,react,frontend}
OR the presence of `plan.metadata.react_constraints` — and instructs the
builder to honor any `plan.metadata.react_constraints` (populated upstream by
`cap.plan.react-feature`) plus the non-negotiable core invariants:

- derive from props/state **during render**, not via `useEffect`;
- **never** mirror/copy state or props into other state through an Effect
  (no derived-state-in-Effect — the exact ContactsContext failure);
- make time **injectable** (accept a clock/`now`; no wall-clock
  `setTimeout`/`setInterval`/`Date.now` in logic that must be deterministically
  testable);
- keep render pure; give lists stable domain-id keys.

Why this is FE-only and backward-compatible: the paragraph self-gates in its
own text ("deliverables in any other stack have none of these — ignore this
paragraph"), and for a rust/dotnet deliverable `plan.stack` is not a TS token
and `plan.metadata.react_constraints` is absent, so the instruction is inert.
No new capability input, no caller change, no state reorder — the only diff is
goal prose. If the planner has populated `react_constraints`, the builder gets
the feature-specific constraints too; if not, a stack-typed FE deliverable
still gets the core invariants. Prevention degrades to "core invariants only,"
never to "nothing," and the CATCH arm backs it up regardless.

### 2. CATCH — `cap.review.react-antipatterns` as a per-deliverable ts-arm gate

`flow.implement.deliverable` already detects the stack and routes ts →
`cap.verify.ts`. We add a React review **on the ts arm only**, after
`cap.verify.ts` passes and before `plan.mark_status`, so a NEW antipattern the
deliverable introduced fails the deliverable (it is not marked complete; it
reverts to ready and is re-driven) rather than riding a green `tsc`/build to a
false complete.

**Scoped to the deliverable's own diff (cost + actionability).** Running the
whole-repo `cap.review.react-antipatterns` per deliverable would (a) blow the
budget — it is a two-LLM-pass review — and (b) surface pre-existing repo debt,
spuriously failing unrelated deliverables (the pack's own baseline-debt
principle). Both are fatal. So the gate reviews ONLY the files this deliverable
changed. The scope rides inside the existing `react_profile` object (no new
capability input, so `flow.fix.react-antipatterns` and the example config are
untouched):

```
react_profile: { oracle_command: "none", scope_files: <deliverable's changed react files>, suppressions: [], extra_rules: [] }
```

- `verify.react.static-scan` reads `react_profile.scope_files`; when non-empty
  it scans exactly those files (empty = whole repo, the legacy path).
- `verify.react.runtime-oracle` honors `oracle_command: "none"` as an explicit
  honest skip (`ran:false`) — we do NOT run the whole vitest suite per
  deliverable. Findings stay PLAUSIBLE (never fabricated CONFIRMED), which is
  fine for a gate that keys on category, not on runtime corroboration.

**Honest skip (task requirement).** The deliverable's changed-file list and its
react-file subset are computed deterministically by `inspect.git.progress`
(MEASURE mode now also emits `files[]`, `react_files[]`, `react_files_count`).
The new `react_gate` runs the review ONLY when `stack == ts`, the caller opted
in (`react_review == true`), AND `react_files_count > 0`. A ts deliverable that
touched no React source skips cleanly to `marking_complete` — never a
fabricated pass or finding, mirroring `verify.ts.green`'s "no tsconfig →
skipped, met=true" discipline.

**Gate on error-severity adjudicated findings, not candidates.** A new
deterministic `verify.react.review-gate` folds the ADJUDICATED findings (post
Layer-D skeptic fold — not the high-recall Layer-A candidates) into a flat
`{ gate_pass, blocking_count, reason }`. Blocking = survivors of category
`correctness` (the reliability/bug bucket; maintainability/performance never
fail a build — performance is explicitly de-prioritized by the review skill).
`gate_pass` is a flat top-level scalar so the flow guards on it directly (the
pack's GUARD_UNSET_SLOT poka-yoke — never guard a nested field). Zero blocking
findings → `gate_pass:true`, reason states the count.

**Opt-in, default OFF (backward-compat).** `react_review` is a new FLOW input
on `flow.implement.deliverable` and `flow.execute-cohorts`, `type: boolean,
default: false`. Flow-input defaults DO apply (unlike capability snippet
inputs — see `verify_scope`'s own precedent), so every existing caller that
does not pass it gets `false` and byte-for-byte the old behavior: no react
gate, straight to `marking_complete`. The commodity cohort driver sets
`react_review: true`; it naturally pairs with the scoped-per-slice path
(`verify_scope`/`stack`) where fast per-deliverable checks belong.

## Why per-deliverable (not the per-cohort barrier alternative)

The task allowed a per-COHORT barrier gate as the fallback "if a full per-
deliverable review is too heavy." Once the review is **scoped to the
deliverable's own diff** the per-deliverable cost is small (a handful of files
→ few candidates → a cheap review, oracle disabled), so the heavier-cost
objection dissolves — and per-deliverable is strictly better on two axes: it
catches the antipattern earlier (the deliverable is not marked complete, so it
is re-driven immediately) and its findings are tightly attributable to one
deliverable's change. A whole-repo barrier review would instead re-flag pre-
existing debt and fail whole cohorts on findings no deliverable in the cohort
introduced. The diff-scoping is the enabler that makes the task's *preferred*
per-deliverable shape both affordable and actionable.

## Files

| File | Change |
|---|---|
| `capabilities/cap.implement.build-loop.yaml` | PREVENT: self-gated React paragraph appended to `red_test` + `green_code` goals. |
| `capabilities/cap.review.react-antipatterns.yaml` | `reviewing` goal: restrict the independent sweep to `react_profile.scope_files` when present. (No input change.) |
| `scripts-library/verify.react.static-scan.yaml` | Read `react_profile.scope_files`; scan exactly those files when non-empty (empty = whole repo). |
| `scripts-library/verify.react.runtime-oracle.yaml` | `oracle_command: none`/`off`/`-` → honest skip (`ran:false`). |
| `scripts-library/inspect.git.progress.yaml` | MEASURE mode also emits `files[]`, `react_files[]`, `react_files_count`. |
| `scripts-library/verify.react.review-gate.yaml` | NEW. Adjudicated findings → `{gate_pass, blocking_count, reason}` on `correctness` severity. |
| `orchestrators/flow.implement.deliverable.yaml` | `react_review` input; capture the diff file lists; ts-arm `react_gate` → scoped `cap.review.react-antipatterns` → `verify.react.review-gate` → pass=mark / block=failed. |
| `orchestrators/flow.execute-cohorts.yaml` | `react_review` passthrough input (default false). |

## Non-goals / complementary upstream work

Populating `deliverable.metadata.react_constraints` (running
`cap.plan.react-feature` during `cap.plan.build-graph` deliverable authoring)
is what makes PREVENT carry *feature-specific* constraints. That is an upstream
planning change, out of this minimal wiring; without it PREVENT still emits the
stack-gated core invariants and CATCH still gates. Wiring it in is the natural
next increment.
