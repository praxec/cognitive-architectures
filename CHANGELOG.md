# Changelog

All notable changes to this repository are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
The library is pre-1.0 (`0.0.x`) and not yet publicly released.

## [Unreleased]

### Added

- **`flow.review.docs-fmeca` — cognitive-science pass + human-gated fixer.**
  Two additions to the docs × role-lens × FMECA review:
  1. A SECOND FMECA pass per doc (`reviewing_doc_cogsci`) evaluating
     structure/content against the information-processing evidence base —
     Sweller's Cognitive Load Theory (intrinsic/extraneous/germane,
     split-attention, redundancy, worked examples), Mayer's signaling/
     coherence/contiguity, Morville–Rosenfeld findability, Procida's
     Diátaxis type purity, Carroll's minimalism (action-first,
     error-recovery), Horn/Miller chunking, progressive disclosure, and
     Redish plain language. A deterministic per-doc metrics step
     (`inspect.docs-fmeca.cogsci-metrics`: Flesch–Kincaid grade, sentence
     stats, section/chunk sizes, heading-hierarchy violations, list runs,
     link density, worked-example presence) feeds the leaf as citable
     evidence; findings are tagged `evidence_basis: deterministic`
     (metric breach cited) vs `advisory` (LLM judgment). Both passes feed
     the SAME fmeca-mcp engine (LLM picks observation ids, code computes
     every criticality) and merge into one ranked checklist. A per-doc
     `principle_assessments` ledger makes silence visible: the aggregate
     enumerates every unassessed (doc, principle) pair as a blind spot
     (`cogsci_blindspot_count`, outcome-gated) plus the fixed
     `principles_out_of_scope` list, so a clean run can never masquerade
     as full-spectrum coverage.
  2. A human-gated fixer leg: the flow PARKS at `fix_approval_gating`
     (`actor: human` — the engine refuses non-human submitters with
     ACTOR_MISMATCH, live-verified) where a person approves WHICH
     checklist fix_ids apply ("fix-001,fix-004" / "all" / skip);
     `inspect.docs-fmeca.fix-scope` joins the approval deterministically
     (unknown id fails loud); the `fixing` leaf applies ONLY the approved
     edits on a `run.git.branch-ensure`d fix branch;
     `verify.docs-fmeca.fixes` verifies every claim against `git status`
     (a claimed-but-unchanged file halts the run) and builds a
     traceability PR body (fix → finding → lens/principle → computed
     criticality → probe evidence); `run.git.ensure-committed` +
     `run.git.push-pr` open the PR — the flow NEVER merges, and a second
     human gate (`pr_review_gating`) parks until the PR is dispositioned
     on the forge. All four agent leaves stay on the effort-safe
     commodity-led `review` chain (docs/docs-fmeca.models.yaml).
     `run.git.branch-ensure` (1.1.0) now also accepts positional args.

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
- **`flow.review.docs-fmeca`** — docs × role-lens × FMECA review composing
  three org MCP engines: `fmeca-mcp` (`scoring.catalog` + `analyze` — the
  reviewers pick observation ids, the engine computes criticality/residual/
  standing/risk_ranking), `structureos` (the scripts-organization evidence
  scan), and `markdown-administrator` (`outline` / `read_section` structured
  doc navigation). A deterministic inventory enumerates the docs + scripts
  (empty inventory fails loud), a per-item loop reviews each through every
  role lens (local-dev/new-hire, devops/deploy, on-call/SRE, security,
  contributor by default), and a RUNNABLE-VERIFICATION gate executes the
  safe-classified probes (behind a destructive-command denylist, timeout,
  and path jail — destructive probes are flagged, never run; a vetoed
  "safe" probe counts unevaluated, not passed). The rollup joins the
  computed risk ranking with the probe exit-code evidence into a ranked
  remediation checklist. Agent leaves bind `affinity: review` +
  `reasoning_effort: medium`; `docs/docs-fmeca.models.yaml` ships an
  effort-safe, commodity-led chain (every member advertises low AND
  medium) so no fallback depth can hit REASONING_EFFORT_UNSUPPORTED (the
  flow.qa.explore charter failure). Ships with the
  `inspect.docs-fmeca.inventory` / `inspect.docs-fmeca.next` /
  `verify.docs-fmeca.batch` / `run.docs-fmeca.probes` /
  `audit.docs-fmeca.aggregate` scripts, the `review.docs-fmeca.method`
  skill, the `connections/markdown-administrator.yaml` reference
  connection, and `examples/docs-fmeca-run.yaml`.
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
