# Ticket-Lifecycle Workflows (GitHub Projects-v2)

Status: design → implementation · 2026-07-31 · namespace `cognitive/`

## Problem

Research/discovery flows (`flow.qa.explore`, `flow.audit-codebase`, `flow.audit-docs`,
`flow.review.docs-fmeca`) today emit **Findings** as run-local artifacts and aggregate a
code-computed report. There is no durable, shared, deduplicated backlog: findings do not survive the
run, cannot be triaged/prioritised across passes, and there is no clean hand-off from *finding a
defect* to *fixing it*.

We want a **ticket lifecycle** on top of a GitHub Projects-v2 board:

```
research flow → Finding[] → TICKET (issue + project item, deduped)
                                   │
                          triage / cleanup (close stale, verify-fixed)
                                   │
                     fix flow → red→green → PR (Fixes #N) → Status
```

so that *research just creates tickets* and *separate handling flows fix them*, with the board as the
single source of truth.

## Non-goals / constraints

- **All-YAML, zero engine change.** Every artifact is a `praxec.repo/v1` pack definition — `flow.*`
  orchestrators, `cap.*` capabilities, and `scripts-library/*` script bodies (bash/`gh`/`jq` embedded
  in the `body:` field). The gateway binary is untouched.
- **Integration substrate = GitHub GraphQL via `gh api graphql`** (operator-decided). It is the only
  API that fully covers Projects-v2: item-add + single-select field values + dedup search. The
  reference `connections/github-mcp.yaml` (issue/PR MCP) stays available but is NOT on the
  Projects-v2 path.
- **Configurable project**, defaulting to the operator's board. Default `project = { owner:
  "outboundlabs", number: 3 }` ("MVP Gremlin List"), default `repo = { owner: "outboundlabs", name:
  "autopilot-beta" }`. Both are flow inputs, never hard-coded in a script.
- **Reuse, don't fork.** The fix side reuses the existing TDD/fix machinery
  (`cap.implement.regression-test`, `cap.implement.fix-under-scope`, `cap.verify.*`,
  `cap.coordinate.pr-open`) and the Finding schema (`cap.diagnose.finding`). `flow.qa.explore` stays
  pure; ticketing is an opt-in tail.

## Two poka-yokes (in the pack's spirit)

1. **Dedup fingerprint.** `fingerprint = sha256(repo | area | route | normalized-symptom)`, embedded
   in the issue body as `<!-- qa-fingerprint: <hash> -->`. Re-running research **updates** the
   existing open ticket (append re-occurrence + refreshed evidence), **reopens** a closed one that
   recurred, and only **creates** when none matches. Ticketing is therefore idempotent across passes.
2. **Evidence-gated close.** In the cleanup flow, the `close_fixed` disposition is *unrepresentable*
   without a citable proof — a merged-PR number or a `file:line` reference demonstrating the fix.
   Anything the agent cannot prove routes to `needs_human`. This mirrors `cap.diagnose.finding`'s
   mandatory closed-enum `expectedSource`. Satisfies "close only verifiably-fixed."

## Ticket body schema (the "all context necessary for fixes" contract)

Every filed issue body is rendered from the Finding + a fix-context enrichment and MUST carry:

| Section | Source |
|---|---|
| Title | Finding.title |
| Area / tool · persona · route | enrichment |
| Observed vs Expected | Finding.observed / Finding.expected |
| **Red→green assertion sketch** (the exact test to write) | enrichment (derived from expectedSource) |
| expectedSource citation | Finding.expectedSource |
| Reproduction (probe_ref / steps) | Finding.reproduction / probe_ref |
| Evidence refs (trace/screenshot/console/network) | Finding.evidence |
| Affected files + layer (`fe` / `backend`) | enrichment |
| Severity → Priority, Size | Finding.severity → mapping |
| Suggested fix approach | enrichment |
| `<!-- qa-fingerprint: <hash> -->` | computed |

A ticket the fix flow cannot act on (no assertion sketch, no layer) is a defect in the upsert cap,
not a judgement call downstream.

## Components

### Substrate — `scripts-library/` (bash + `gh api graphql` + `jq`)

All parameterised by `project {owner, number}` and `repo {owner, name}`; positional argv (the script
executor injects no env slots); JSON envelope on stdout.

- `coordinate.github.resolve-project` — `project` → `{ projectId, fields: { Status, Priority, Size,
  Labels, Repository } with option-id maps }`. Run-cached; one GraphQL round-trip.
- `coordinate.github.issue-search` — `{repo, fingerprint}` → `{ match: {number, state, url} | null }`
  (searches open+closed by the fingerprint marker).
- `coordinate.github.issue-upsert` — `{repo, project, resolved, title, body, labels, fields}` →
  create-or-update issue, `addProjectV2ItemById`, `updateProjectV2ItemFieldValue` per field →
  `{ number, url, itemId, action: created|updated|reopened }`.
- `coordinate.github.issue-close` — `{number, comment, statusOption}` → close + comment + set Status.
- `coordinate.github.project-enumerate` — `project` → `[{number, title, state, status, repo,
  ageDays, linkedPRs}]`.

### Capabilities — `capabilities/`

- `cap.coordinate.ticket-upsert` (verb `coordinate`) — Finding + enrichment + project/repo → renders
  the body template, computes the fingerprint, calls `issue-search` then `issue-upsert`. Deterministic
  (`kind: script` chain). Output: `{number, url, action}`.
- `cap.coordinate.ticket-read` (verb `coordinate`) — issue number → parsed structured fix-context
  (area, assertion sketch, affected files, layer) for the fix flow.
- `cap.diagnose.ticket-disposition` (verb `diagnose`, `affinity: review`, SENIOR tier) — one project
  item → `{ disposition: keep|close_fixed|close_stale|needs_human, evidence }`. Schema poka-yoke:
  `close_fixed` REQUIRES `evidence.kind ∈ {merged_pr, code_ref}` + non-empty `reference`; the agent's
  tools are `file:{{ $.run.repo_root }}` + `gh` read so it can verify a PR/commit before citing it.

### Flows — `orchestrators/`

- `flow.findings-to-tickets` — `findings[]` + project/repo → per-finding `cap.coordinate.ticket-upsert`
  → `{ filed[], updated[], rollup }`. **Also the back-fill vehicle** (existing session findings convert
  to Finding shape and flow through unchanged).
- `flow.qa.explore-and-file` — run `flow.qa.explore`, pipe its `findings` into
  `flow.findings-to-tickets`. Keeps `qa.explore` pure; ticketing opt-in and reusable by any
  finding-emitting research flow.
- `flow.fix-from-ticket` — `issue_number` → `ticket-read` → Status=In-Progress → `regression-test`
  (RED, from the assertion sketch) → `verify.test-red` → `fix-under-scope` (GREEN) → `verify.repro`/
  build-green → `pr-open` (`Fixes #N`) → Status=In-Review. Reuses the promote-finding machinery.
- `flow.fix-ticket-batch` — `{filter (label/priority/area), size}` → query open tickets → coherent
  batch → per-ticket red→green as **small atomic commits on ONE branch** → **one** `pr-open` linking
  all (`Fixes #a, #b, …`) → each Status=In-Review. Realises the "20–30 fixes / chunky-CI PR,
  small-commits" operating rule.
- `flow.tickets-triage-cleanup` — `project` → `project-enumerate` → per-item
  `cap.diagnose.ticket-disposition` → deterministically close only evidence-backed `close_fixed`
  (comment the evidence, Status=Killed) → `{ closed[], needs_human[], kept[] }` report.

## Testing (against the real Project 3) → PR

Author on `feat/ticket-lifecycle-workflows` (worktree off `origin/dev`). Prove against the live board:

1. `resolve-project` + `project-enumerate` return the real 12 items and field/option IDs.
2. `flow.tickets-triage-cleanup` on the 12 closes ONLY evidence-backed items, lists the rest.
3. `cap.coordinate.ticket-upsert` run twice on one finding → second is `action: updated`, no duplicate.
4. `flow.findings-to-tickets` back-fills a small slice of the session findings.
5. `flow.fix-from-ticket` on one small ticket → opens a `Fixes #N` PR end-to-end.

Validate every definition with `praxec check` (via `meta/verify.praxec.check`) — 0 diagnostics — before
committing. Then open a PR into `praxec/cognitive-architectures` (the pack lives in `praxec/`, operates
on `outboundlabs/` targets — the dogfooding split).

## Build order (value + risk)

1. Substrate scripts + `resolve-project`/`project-enumerate` (proves the GraphQL + auth).
2. `cap.coordinate.ticket-upsert` + body template + dedup.
3. `flow.tickets-triage-cleanup` (prove on the 12 — lowest risk, highest immediate value).
4. `flow.findings-to-tickets` + back-fill the session findings.
5. `cap.coordinate.ticket-read` + `flow.fix-from-ticket` + `flow.fix-ticket-batch`.
6. `flow.qa.explore-and-file` retrofit.

The in-flight autopilot-beta fix batches (FE / Backend-A) finish undisturbed under the present approach.

## Operating loop (dogfood — the standing large-scale process)

Once implemented, this is the repeating program, run against the live board until it converges:

```
   ┌────────────────────────────────────────────────────────────┐
   │  SWEEP    research flows (qa.explore-and-file, audits) →    │
   │           file/dedup tickets into Project 3                 │
   │  CLEAR    flow.fix-ticket-batch drains the backlog →        │
   │           red→green → chunky PRs (Fixes #…)                 │
   │  VERIFY   flow.tickets-triage-cleanup confirms each fixed   │
   │           ticket is evidence-backed-closed; reopens any     │
   │           that regressed                                    │
   └───────────────────────────┬────────────────────────────────┘
                               │  repeat
                               ▼
        STOP when a full sweep produces zero NEW findings
        (loop-until-dry: dedup guarantees "new" is real, not re-filed)
```

**"Cleared" means closed on the board.** An item is done only when its issue is closed AND its
project Status = Killed/Done — the board is the common work list, so a merged fix PR that leaves the
ticket open is not yet cleared. The VERIFY pass reconciles merged fixes to closed+Killed and reopens
(Status→Hunting) anything that regressed.

First execution target: drive the **current backlog to 100% cleared + verified** — the 12 existing
items plus the back-filled session findings — then begin the sweep→clear→verify iteration. The dedup
fingerprint is what makes "sweeps stopped producing findings" a trustworthy convergence signal rather
than an artefact of re-reporting.
