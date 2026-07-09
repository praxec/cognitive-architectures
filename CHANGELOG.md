# Changelog

All notable changes to this repository are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
The library is pre-1.0 (`0.0.x`) and not yet publicly released.

## [Unreleased]

### Added

- **Two-tier composition** — typed `cap.*` capabilities composed by `flow.*`
  lifecycle orchestrators (`flow.add-feature`, `flow.bugfix-from-error-log`,
  `flow.safe-refactor`, `flow.triage-issue`, `flow.audit-codebase`),
  exposed through a top-level `praxec.repo.yaml` manifest under the
  `cognitive` namespace. A capability runs in its own scoped blackboard; only
  its declared outputs propagate back to the host orchestrator. Flows may now
  nest other flows via `kind: workflow` (V11 relaxed, depth-capped), so the
  reusable sub-flows (`flow.derisk`, `flow.harden.fmeca-converge`,
  `flow.implement.deliverable`, `flow.execute-cohorts`) compose into larger
  programs (`flow.loom`).
- **`flow.audit-docs`** — governed doc-vs-code drift audit over the `corpus`
  docs-RAG server: a freshness gate (`corpus_index`) + retrieval
  (`corpus_search`) feed a governed agent that emits typed per-claim drift
  findings, aggregated into a report whose blocking (wrong | superseded) count
  is the code-computed definition of done. Ships with `cap.fetch.doc-corpus`,
  `cap.inspect.repo-digest`, `cap.review.doc-drift`, the
  `audit.drift.aggregate` script, and the `connections/corpus.yaml` reference
  connection.
- **`cap.plan.brainstorm`** — divergent-thinking primitive that generates
  genuinely-different candidate options for any goal, each with explicit
  assumptions, tradeoffs (as an array, not a string — countable for downstream
  vetting), and a confidence rating. Outputs `divergence_notes` naming the axes
  the option space actually spans, so the downstream picking step can audit
  whether real divergence happened or just pseudo-fanout. Pair it with any
  picking cap (`cap.plan.vet`, `cap.gate.human-pick-shape`, …) downstream.
- **The per-skill foundation** — skill fragments across the ten cognitive verbs
  (`triage`, `diagnose`, `plan`, `implement`, `review`, `refactor`, `explain`,
  `compose`, `research`, `summarize`); a curated, hash-pinned script library;
  reference agent configs and connection definitions; demo workflows
  (`swe-agent`, `pr-review`, `deploy-pipeline`, `tdd`, `triage-router`,
  `content-publish`); and composed gateway examples (`full-swe-pipeline`,
  `review-only`, `deploy-with-governance`).
- `scripts/validate.sh` — runs `praxec check` against every example.

### Compatibility

- Requires **praxec 0.0.14 or later** (the capability/orchestrator
  composition model, the curated-script surface, parallel execution, and
  relaxed V11 flow-nesting).
