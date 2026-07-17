# React anti-pattern suite — review, plan, fix

- Status: Proposed
- Date: 2026-07-17
- Scope: three new capabilities (`cap.review.react-antipatterns`,
  `cap.plan.react-feature`, `cap.plan.diff-proposal`), one new orchestrator
  (`flow.fix.react-antipatterns`), their deterministic scripts and skills, and
  a Claude Code skill wrapper (`/react-review`, `/react-plan`).
- Supersedes nothing. Generic addition to the library — zero coupling to any
  consuming repo's architecture (e.g. Autopilot's ADR-048).

## Context — what this closes

The library ships review/plan/fix machinery for generic SWE (`cap.review.*`,
`cap.plan.*`, `flow.safe-refactor`, `flow.bugfix-from-error-log`) but nothing
that understands **React's own failure modes**: synchronization-via-Effect,
copied-props-into-state, unstable keys, mutated state, missing cleanup,
uncontrolled/controlled input drift, legacy escape hatches, and the
performance smells that get over-prioritized ahead of correctness bugs. These
are well-documented (react.dev: render purity, "You Might Not Need an
Effect," Rules of Hooks, keeping components pure, stable keys) but nothing in
this pack encodes them as a reusable cognitive architecture.

A single "senior React reviewer" prompt could encode the catalog, but bolted
on raw it inherits this pack's oldest known failure mode (see
`praxec-verify-can-fake-success` in the operator's own notes): an LLM
asserting "no more `console.error` warnings" or "runtime-confirmed" when
nothing runtime-ish ever ran. **THE LAW this suite is built to respect:
verification is EARNED from evidence, never ASSERTED by the thing being
verified.** That forces a layered design, not a single prompt.

## Decision — the model

### 1. Mental model: candidates → judgment → runtime corroboration → adversarial fold

One capability, `cap.review.react-antipatterns`, internally runs four layers
at increasing cost and decreasing volume, mirroring the pack's existing
producer/adjudicator split (`cap.review.fmeca`, `cap.review.doc-drift`,
`cap.review.use-case-falsification`): a **fuzzy producer** (LLM) supplies raw
observations; a **deterministic adjudicator** (script) computes the verdict.
The model is never allowed to self-certify.

| Layer | Kind | Always runs? | Produces |
|---|---|---|---|
| A — static scan | deterministic script | always | cheap, high-recall **candidates** (rules-of-hooks/exhaustive-deps via ESLint if present, plus grep/AST-ish heuristics for keys, controlled-input drift, render-impure calls, mutable state ops, effect bodies missing cleanup) |
| B — LLM evidence-check | agent, file-read tools, the owner's senior-React-engineer persona + full catalog | always | evidence-backed **raw findings**, `file:line` cited, classified correctness/reliability \| maintainability/design \| performance-only; sweeps for what static analysis structurally cannot see (Effects-as-derived-state, copied-props-into-state, impossible/contradictory state, Effect chains) |
| C — runtime oracle | deterministic script, **pluggable + auto-detected** | only if a real oracle exists in the target repo | actual React console warnings from a real run (vitest/jest+RTL, Storybook test-runner, or "none" — an honest degrade, never fabricated) |
| D — adversarial fold | agent (skeptic votes, fuzzy) + deterministic script (majority fold, computed) | always | final verdict per finding: **CONFIRMED** (survived skeptics AND runtime-corroborated), **PLAUSIBLE** (survived skeptics, no runtime corroboration), or **killed** (majority of skeptic votes refuted it) |

Layer A is the always-on floor (matches this pack's existing
`cap.verify.stub-scan` + `cap.review.completeness` split — a deterministic
scan first, a judgment critic second). Layer C is pure enhancement: it
upgrades a survivor's verdict from PLAUSIBLE to CONFIRMED when a real runtime
signal corroborates it, and is entirely optional — Layers A/B/D alone are a
complete, honest capability.

### 2. The pluggable-oracle degradation contract (Layer C)

`verify.react.runtime-oracle` auto-detects, in order: (1) vitest or jest
configured with `@testing-library/react` present — run it, scrape captured
stdout/stderr for known React runtime-warning signatures ("Warning: Each
child in a list should have a unique \"key\" prop", "Cannot update a
component while rendering a different component", "Maximum update depth
exceeded", uncontrolled→controlled input warnings, etc.); (2) a Storybook
test-runner script (`test-storybook` in `package.json`) — run it, same
scrape; (3) neither present — emit `{oracle: "none", ran: false, warnings:
[], degrade_reason: "..."}, and **stop there**. There is no fourth "assume
clean" branch. The adjudicator (Layer D) reads `ran` before it will ever emit
CONFIRMED — a finding can only be PLAUSIBLE when the oracle did not run, no
matter how confident Layer B sounds. This is the same discipline
`verify.ts.green` already uses for a missing `tsconfig.json` (skip
honestly, met=true evidence says so — never invent a failure OR a pass for a
thing that didn't run).

### 3. Report-vs-fix config (the fix flow)

`flow.fix.react-antipatterns` takes one config input, `mode: report | fix`
(default `report` — safety-over-completeness, matching the owner prompt's own
constraint), and does:

```
reviewing (cap.review.react-antipatterns)
  -> mode_gate
       report -> reporting (terminal; findings only, nothing touched)
       fix    -> classifying (deterministic: mechanical vs judgment split)
                   -> autonomy_gate (branches on Layer C's oracle_status.ran)
                        oracle present -> applying_mechanical (cap.implement.scope-bounded, REUSED)
                                            -> verifying_regression (re-run oracle + tests)
                                                 -> pass -> fixed_done
                                                 -> fail -> needs_human (diff left uncommitted, reason attached)
                        no oracle      -> proposing_diffs (cap.plan.diff-proposal, NEW — agent drafts
                                            unified-diff-shaped proposals with NO file-write tool; nothing
                                            is applied) -> proposed_done
```

**Split by class**, not by finding-count: mechanical findings (stable keys,
`value`/`checked` without `onChange`, missing Effect cleanup, mutable→
immutable state ops) are candidates for autonomous apply because a correct
fix is close to mechanical and low-risk to get "safely wrong." Judgment
findings (Effects-that-are-really-derived-state, state-model refactors) are
**never** auto-applied — a wrong "safe" fix changes behavior, which violates
the prime directive. They always come back as findings-only, in both modes.

**The regression gate is the sole permission to keep an autonomous edit**:
oracle green (Layer C re-run, post-edit) AND the repo's test command still
exits 0 AND the warning-scrape count is 0. **No oracle ⇒ no gate ⇒ no
autonomous apply**, full stop — `cap.plan.diff-proposal` produces the same
remediation content as data instead of writing it, so the operator loses
nothing but the auto-apply.

### 4. Generic core + optional repo profile

Zero-config = generic React only; nothing in the core capabilities imports or
assumes any consuming repo's architecture. A repo attaches its own rules by
pointing the review at a **profile file** (`react_profile_path`, an optional
input on `cap.review.react-antipatterns` and `flow.fix.react-antipatterns`):

```jsonc
// e.g. react-antipatterns.profile.json in the target repo
{
  "extra_rules": [
    // repo-specific detection rules, same shape as an Layer-A candidate but
    // authored by the repo owner (e.g. "no `any`", "hooks named useXQuery")
    { "id": "no-generic-view-model", "pattern": "...", "category": "design", "message": "..." }
  ],
  "suppressions": [
    // finding ids or file globs the repo has consciously accepted
    { "match": "src/generated/**", "reason": "codegen output, never hand-edited" }
  ],
  "oracle_command": "npm run test:unit -- --run"
  // overrides Layer C's auto-detection when the repo's real test invocation
  // differs from the generic vitest/jest/storybook heuristics
}
```

`verify.react.static-scan` merges `extra_rules` into its candidate emission
(still just candidates — Layer B still adjudicates); `verify.react.runtime-
oracle` prefers `oracle_command` over auto-detection when present;
suppressions are applied by the Layer D adjudicator before a finding is
counted. **This PR ships the hook and documents it; it does not ship a
profile** — the profile is something each consuming repo authors and points
at, keeping the core suite genuinely repo-agnostic.

### 5. `cap.plan.react-feature` — the same catalog, inverted

Detection (review) and prevention (plan) share one catalog but need
opposite framing: a reviewer looks for evidence a pattern already happened; a
planner states the constraint before code exists ("this feature's step-N
state must not duplicate step-(N-1)'s props," "the polling interval effect
owns its own cleanup," "list items get a stable domain key, never the array
index"). `cap.plan.react-feature` is a single-state agent capability (same
shape as `cap.plan.ux-design` / `cap.plan.technical-design`) that emits
`{ constraints: [...], guidance: string }` from a feature/change description.
It is usable two ways: (a) fed into `cap.plan.build-graph`'s deliverable
authoring as `metadata.react_constraints` on the relevant deliverable node —
consumed downstream the same way `metadata.scope` already threads through the
Develop-vs-Execute plan split (`docs/plan-types.develop-vs-execute.md`,
currently on `docs/plan-types-develop-vs-execute`, PR #29); (b) standalone,
called directly for a design conversation with no plan graph in play.

### 6. Findings shape

Every surviving finding, from either capability, is emitted in one shape so
downstream tooling (and the requesting harness) can consume it uniformly
without re-parsing prose:

```jsonc
{
  "verdict": "confirmed | plausible",       // never "confirmed" without Layer C corroboration
  "category": "correctness | maintainability | performance",
  "file": "src/components/Foo.tsx",
  "line": 42,
  "failure_scenario": "one sentence: what breaks, for whom, when",
  "summary": "one-line finding title",
  "evidence": "verbatim file:line quote(s)",
  "confidence": "high | medium | low",
  "root_cause": "...",
  "remediation": "scoped, behavior-preserving fix description",
  "fix_class": "mechanical | judgment"       // read by flow.fix.react-antipatterns' classifier
}
```

## Consequences

- (+) No layer can lie about what ran — the oracle_status + verdict split
  makes "I didn't actually run anything" structurally visible instead of
  something the model can talk past.
- (+) Reuses `cap.implement.scope-bounded`, `cap.gate.human-signoff`-style
  terminal-with-artifact patterns, and the fmeca/doc-drift producer/adjudicator
  idiom verbatim — no parallel machinery invented for things this pack
  already solved well.
- (+) The profile hook keeps the core suite honestly generic; a consuming
  repo's own conventions never leak into the shipped catalog.
- (−) Six states inside `cap.review.react-antipatterns` is the most complex
  capability this PR adds (still far short of `cap.implement.build-loop`'s
  648 lines) — justified by the four-layer requirement; a future revision
  could hoist Layers C/D into their own reusable caps if another suite wants
  the same shape.
- (−) Layer C's runtime-warning scrape is a text-grep over captured test
  output, not a structured console-warning channel — good enough for the
  known React warning strings, but a repo with a custom test reporter that
  swallows console output will legitimately degrade to "oracle ran but
  produced no readable warnings," which Layer D treats as PLAUSIBLE, not a
  false CONFIRMED.

## Implementation

1. **Scripts** (`scripts-library/verify.react.*`) — Layer A static scan,
   Layer C oracle probe+run, Layer D majority-fold adjudicator, plus the fix
   flow's classifier and post-fix regression gate.
2. **Skills** (`skills/review.react.antipatterns*`, `skills/plan.react.*`,
   `skills/plan.diff-proposal.yaml`) — the persona/catalog spine (Layer B),
   the skeptic pass (Layer D fuzzy half), the feature-planning inversion, and
   the no-write diff-proposal drafting guidance.
3. **Capabilities** (`capabilities/cap.review.react-antipatterns.yaml`,
   `capabilities/cap.plan.react-feature.yaml`,
   `capabilities/cap.plan.diff-proposal.yaml`).
4. **Orchestrator** (`orchestrators/flow.fix.react-antipatterns.yaml`).
5. **Example config** (`examples/react-antipatterns.yaml`) so
   `scripts/validate.sh` actually exercises the new graph.
6. **Claude Code skill wrapper** (`.claude/skills/react-review/SKILL.md`,
   `.claude/skills/react-plan/SKILL.md`) — `/react-review <path>` and
   `/react-plan <feature>`, both delegating to the capabilities/flow above via
   the `praxec.command` MCP contract (SPEC §32).

## Where this bends the requested shape (flagged, not papered over)

The request describes the fix workflow as four visible stages: `review (cap.1)
-> adversarial-verify -> {report|fix} -> gate`. This design folds
"adversarial-verify" **into** `cap.review.react-antipatterns` as its internal
Layer D, rather than exposing it as a second top-level orchestrator state. The
request's own capability-1 description independently lists "Layer D —
adversarial verify" as one of `cap.review.react-antipatterns`'s four internal
layers, so the two readings collide; I took the capability's own layer list as
authoritative and kept the capability self-contained, on the precedent of
every existing multi-layer gate in this pack (`cap.review.fmeca`,
`cap.review.doc-drift`, `cap.review.use-case-falsification`) — none of them
split their producer/adjudicator halves across the orchestrator boundary, and
capabilities in this pack are documented as composition **leaves** (never
invoking another capability), so a second orchestrator-level "adversarial
verify" state calling back into review internals would not have a clean
capability to call without duplicating Layer D's contract. `flow.fix.react-
antipatterns` therefore has one `reviewing` state that already carries all
four layers, then branches on `mode`.
