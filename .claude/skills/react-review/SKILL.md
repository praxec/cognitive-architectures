---
name: react-review
description: Use when the user wants a React codebase (or a subset of it) reviewed for anti-patterns -- Effects/synchronization, state modeling, render purity, unstable keys/identity, forms, legacy escape hatches, and evidenced performance smells. Invoked as `/react-review <path> [mode]`. Delegates entirely to the praxec cognitive-architectures suite (cap.review.react-antipatterns / flow.fix.react-antipatterns) -- this skill does not review code itself.
---

# React anti-pattern review (report or fix)

This skill is a thin front door onto the generic React review/plan/fix suite
in `cognitive-architectures` (design:
`docs/react-antipatterns.review-plan-fix.md`). It does not review code
itself -- it drives the praxec `flow.fix.react-antipatterns` workflow via the
`praxec` MCP tool (SPEC §32 two-tool surface: `praxec.query` for reads,
`praxec.command` for start/submit) and reports back what the workflow found.

**Announce at start:** "I'm using the react-review skill to run the
cognitive-architectures React anti-pattern suite against `<path>`."

## What you get

A four-layer, evidence-gated review -- NOT a single LLM opinion:

1. A deterministic static scan (ESLint rules-of-hooks/exhaustive-deps when
   configured, plus heuristic candidates for unstable keys, controlled-input
   drift, mutable state ops, missing Effect cleanup).
2. A senior-React-engineer LLM pass that confirms/refutes those candidates
   with real file:line evidence and independently sweeps for what static
   analysis cannot see (Effects-as-derived-state, copied-props-into-state,
   impossible state).
3. An OPTIONAL runtime oracle (real React console warnings from the target
   repo's own vitest/jest+RTL or Storybook test-runner) -- auto-detected; if
   none exists, findings are honestly reported as PLAUSIBLE, never falsely
   claimed CONFIRMED.
4. An adversarial skeptic pass -- three independent votes per finding,
   default-to-refute, majority-refute kills a finding before it's reported.

## Steps

1. **Parse the invocation.** `$ARGUMENTS` is `<path> [report|fix]`. `path` is
   the target React repo (or a subdirectory within one) to review. `mode`
   defaults to `report` (nothing is ever changed without the user explicitly
   asking for `fix`). If `path` is missing, ask for it -- do not guess a repo.

2. **Discover the workflow surface.** Call `praxec.query {}` to get the
   HATEOAS discovery home if you have not already established this session's
   praxec surface. If you already know the gateway is wired to the
   `cognitive-architectures` pack (via `repos:` or an included example such as
   `examples/react-antipatterns.yaml`), skip straight to step 3.

3. **Start the mission.** Call:
   ```
   praxec.command {
     "definitionId": "cognitive/flow.fix.react-antipatterns",
     "input": { "mode": "<report|fix>" }
   }
   ```
   The target repo resolves via the run-ambient `$.run.repo_root` the gateway
   config threads through (e.g. an `--input repo_path=...` / `--repoRoot`
   flag on the driving `praxec orchestrate`/`praxec command` invocation, or
   however the connected gateway resolves it for this session). If the
   response's `_required` hints ask for a repo path explicitly, supply
   `path` there instead of guessing the field name.

4. **Drive to resolution.** The response carries `links` -- each is a legal
   next transition. This flow has no human-in-the-loop gates on the report
   path; on the fix path it will pause with `needs_human` if the post-fix
   regression gate fails (oracle warnings, or oracle absent so the mechanical
   fixes never applied autonomously -- see step 5). Keep following `links` /
   `_required` until `result.status` is `succeeded` or `failed`, or the
   mission parks waiting on you.

5. **Report back to the user, honestly:**
   - The `findings` array (verdict CONFIRMED or PLAUSIBLE, category, file,
     line, `failure_scenario`, summary, evidence, remediation). Never
     upgrade a PLAUSIBLE finding to "confirmed" in your own summary --
     that verdict is computed, not asserted, and misrepresenting it defeats
     the whole point of the pipeline.
   - In `fix` mode: which findings were mechanically auto-applied (only if
     the regression gate passed), which were left as diffs-only (no runtime
     oracle in this repo -- nothing was touched), and which are
     judgment-class findings-only regardless (state-model refactors, Effect-
     as-derived-state -- never auto-applied).
   - If the mission parked at `needs_human`, say so plainly and surface the
     gate failure reason -- do not silently retry or "fix it anyway."

## What NOT to do

- Do not review the code yourself as a substitute for running the pipeline --
  the whole point is the layered evidence discipline (deterministic floor +
  evidence-gated LLM pass + optional runtime corroboration + adversarial
  fold), which a single ad hoc pass does not have.
- Do not claim a finding is "runtime-confirmed" unless the workflow's own
  `oracle_status.ran` is `true` and the finding's `verdict` is `confirmed`.
- Do not apply any fix outside what `flow.fix.react-antipatterns` itself
  applied -- judgment-class findings are findings-only by design.
