# Ticket-Lifecycle Workflows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add a GitHub Projects-v2 ticket lifecycle to the praxec pack — research flows file/dedup tickets, handling flows fix them (red→green → chunky PR), a cleanup flow evidence-gates closes — as all-YAML pack definitions.

**Architecture:** `scripts-library/*` bash bodies wrap `gh api graphql` (the Projects-v2 substrate); `capabilities/cap.*` compose those scripts (deterministic) or adjudicate (agent); `orchestrators/flow.*` sequence caps into the lifecycle. Reuses the Finding schema (`cap.diagnose.finding`) and the TDD/fix machinery (`cap.implement.regression-test` / `fix-under-scope` / `cap.verify.*` / `cap.coordinate.pr-open`).

**Tech Stack:** praxec.repo/v1 pack YAML · `gh api graphql` · `jq` · bash · `praxec check` / `px` validators · GitHub GraphQL (ProjectV2 API).

## Global Constraints

- **All-YAML, zero engine change.** Only `flow.*` / `cap.*` / `scripts-library/*` `.yaml` files; GraphQL is bash embedded in `body:`.
- **Namespace `cognitive/`.** Every definitionId is namespace-prefixed by the manifest.
- **Substrate = `gh api graphql`** only for Projects-v2 (item-add + single-select fields + dedup search). Never hard-code the board.
- **Configurable:** `project = {owner,number}` default `{outboundlabs,3}`; `repo = {owner,name}` default `{outboundlabs,autopilot-beta}` — flow inputs.
- **Script contract:** positional argv (no env slots); JSON envelope on stdout; roots at `$.run.repo_root` where a repo is needed.
- **Validation gate:** every new/edited definition passes `praxec check` (0 diagnostics) before commit.
- **Poka-yokes:** (1) dedup fingerprint `sha256(repo|area|route|normalized-symptom)` in body marker `<!-- qa-fingerprint: <hash> -->`; (2) `close_fixed` unrepresentable without `evidence.kind ∈ {merged_pr, code_ref}` + reference.
- **Commits:** small + atomic; end with the Co-Authored-By trailer.
- **"Cleared" = closed on the board.** An item is not done until its **issue is closed AND its project Status = Killed/Done**. The board is the single common work list; a merged fix PR that leaves the ticket open/In-Review is NOT cleared. The verify pass reconciles merged fixes → closed+Killed and reopens (Status back to Hunting) anything that regressed.

---

### Task 1: GraphQL substrate spike — `resolve-project` + `project-enumerate`

Proves auth + the ProjectV2 GraphQL shape against the live board before anything depends on it.

**Files:**
- Create: `scripts-library/coordinate.github.resolve-project.yaml`
- Create: `scripts-library/coordinate.github.project-enumerate.yaml`

**Interfaces:**
- Produces: `resolve-project(owner, number)` → `{projectId, fields:{Status:{fieldId,options:{name→optionId}}, Priority:{…}, Size:{…}}}`
- Produces: `project-enumerate(owner, number)` → `{items:[{number,title,state,status,repo,ageDays,linkedPRs:[int]}]}`

- [ ] **Step 1:** Write `resolve-project` body: `gh api graphql -f query='query($o:String!,$n:Int!){organization(login:$o){projectV2(number:$n){id fields(first:30){nodes{... on ProjectV2SingleSelectField{id name options{id name}}}}}}}' -f o="$1" -F n="$2"` then `jq` reshape to the interface envelope. argv `$1=owner $2=number`.
- [ ] **Step 2:** Run live: `bash <(yq '.scripts[].body' resolve-project.yaml) outboundlabs 3` → expect `projectId=PVT_kwDOB8Crxs4BVRQh` + Status options `{Found,Hunting,Killed,...}`.
- [ ] **Step 3:** Write `project-enumerate` body: query `items(first:50){nodes{content{... on Issue{number title state url createdAt repository{nameWithOwner} timelineItems(itemTypes:[CROSS_REFERENCED_EVENT],last:20){...}}} fieldValues…}}`; `jq` compute `ageDays` from `createdAt`, `status` from the Status single-select value, `linkedPRs` from closing PR refs.
- [ ] **Step 4:** Run live against Project 3 → expect the 12 items with real `status` (Found/Hunting/Killed), `repo=outboundlabs/autopilot-beta`.
- [ ] **Step 5:** `praxec check` both files (via `meta/verify.praxec.check` or `praxec check --config <gw>`); 0 diagnostics.
- [ ] **Step 6:** Commit `feat(coordinate): github projectv2 resolve + enumerate scripts`.

---

### Task 2: `issue-search` (dedup) + `issue-upsert`

**Files:**
- Create: `scripts-library/coordinate.github.issue-search.yaml`
- Create: `scripts-library/coordinate.github.issue-upsert.yaml`

**Interfaces:**
- Produces: `issue-search(repoOwner, repoName, fingerprint)` → `{match:{number,state,url}|null}`
- Consumes: `resolve-project` output (Task 1)
- Produces: `issue-upsert(repoOwner, repoName, projectId, title, body, labelsCsv, statusOptionId, priorityOptionId, sizeOptionId)` → `{number,url,itemId,action}`

- [ ] **Step 1:** `issue-search` body: `gh api graphql` search `search(query:"repo:$O/$N in:body \"qa-fingerprint: $FP\"", type:ISSUE, first:1){nodes{... on Issue{number state url}}}`; `jq` → `{match: (.[0] // null)}`.
- [ ] **Step 2:** Live test: search a fingerprint known-absent → `match:null`. (Create a throwaway issue with a marker, re-search → match; then close it.)
- [ ] **Step 3:** `issue-upsert` body: if `issue-search` matches open → `updateIssue`/`addComment` (append re-occurrence), reuse number, `action=updated`; matches closed → `reopenIssue` + comment, `action=reopened`; no match → `createIssue`, `action=created`. Then `addProjectV2ItemById(projectId,contentId)` → itemId; `updateProjectV2ItemFieldValue` for Status/Priority/Size (skip nulls). Labels via `gh issue edit --add-label`.
- [ ] **Step 4:** Live test on a throwaway finding: run once → `action=created` + appears in Project 3 with Status set; run again same fingerprint → `action=updated`, still ONE issue. Clean up (close throwaway).
- [ ] **Step 5:** `praxec check`; 0 diagnostics.
- [ ] **Step 6:** Commit `feat(coordinate): github issue-search + idempotent issue-upsert (fingerprint dedup)`.

---

### Task 3: `cap.coordinate.ticket-upsert` (body template + fingerprint)

**Files:**
- Create: `capabilities/cap.coordinate.ticket-upsert.yaml`
- Create: `scripts-library/coordinate.ticket.render-body.yaml` (renders the schema body + computes fingerprint)

**Interfaces:**
- Consumes: Finding (`cap.diagnose.finding` shape) + `enrichment {area,persona,route,assertionSketch,affectedFiles,layer,suggestedFix}` + `project` + `repo`
- Produces: `cap.coordinate.ticket-upsert` → `{number,url,action}`
- Pattern to copy: `capabilities/cap.coordinate.pr-open.yaml` (state-machine shape) + `kind: script` wiring from `capabilities/cap.verify.repro-rate.yaml`

- [ ] **Step 1:** `render-body` script: argv = finding JSON + enrichment JSON + repo; emit `{title, body, labelsCsv, fingerprint, severity}`. Body = the schema table (design §"Ticket body schema"), fingerprint `= printf '%s' "$repo|$area|$route|$(normalize symptom)" | sha256sum`.
- [ ] **Step 2:** Unit-test `render-body` with a sample finding fixture → body contains the assertion sketch, layer, and `<!-- qa-fingerprint: <64hex> -->`.
- [ ] **Step 3:** Author `cap.coordinate.ticket-upsert`: states `rendering` (`kind: script` render-body) → `resolving` (resolve-project) → `filing` (issue-upsert with severity→Priority + default Status=Found). Map severity→Priority/Size via a small `jq` in a `mapping` step.
- [ ] **Step 4:** Live test end-to-end on one throwaway finding → creates a well-formed ticket in Project 3; re-run → updated. Clean up.
- [ ] **Step 5:** `praxec check`; commit `feat(coordinate): cap.coordinate.ticket-upsert with fix-context body + dedup`.

---

### Task 4: `flow.tickets-triage-cleanup` + `cap.diagnose.ticket-disposition` + `issue-close`

Highest immediate value — proves against the real 12.

**Files:**
- Create: `capabilities/cap.diagnose.ticket-disposition.yaml`
- Create: `scripts-library/coordinate.github.issue-close.yaml`
- Create: `orchestrators/flow.tickets-triage-cleanup.yaml`

**Interfaces:**
- Consumes: `project-enumerate` item (Task 1)
- Produces: `ticket-disposition(item)` → `{disposition: keep|close_fixed|close_stale|needs_human, evidence:{kind,reference}|null}`
- Produces: `issue-close(number, comment, statusOptionId)` → `{closed:bool}`
- Pattern to copy: `capabilities/cap.diagnose.finding.yaml` (the `affinity: review` + inputSchema poka-yoke), `orchestrators/flow.triage-issue.yaml` (state machine)

- [ ] **Step 1:** `issue-close` script: `gh issue close $N --repo $O/$NAME --comment "$C"` + `updateProjectV2ItemFieldValue` Status=Killed. Live-test on a throwaway.
- [ ] **Step 2:** Author `cap.diagnose.ticket-disposition` — `affinity: review`, tools `file:{{ $.run.repo_root }}` + `gh` read. `inputSchema` REQUIRES for `close_fixed` an `evidence` object with `kind ∈ {merged_pr, code_ref}` + `reference` (minLength 1); other dispositions allow `evidence:null`. Goal text: cite a merged PR / file:line proving the fix, else `needs_human`.
- [ ] **Step 3:** Author `flow.tickets-triage-cleanup` — `enumerating` (project-enumerate) → per-item `disposing` (ticket-disposition) → `applying` (deterministic: only `close_fixed`+evidence → issue-close; else collect) → `reporting` → terminal `{closed[],needs_human[],kept[]}`.
- [ ] **Step 4:** DRY-RUN live against Project 3 (add a `dry_run` input default true → applying step logs instead of closes). Verify: "Killed"-status items with a real merged PR classify `close_fixed`+evidence; unverifiable ones → `needs_human`.
- [ ] **Step 5:** Real run (`dry_run:false`) — closes only evidence-backed, reports the rest. `praxec check`; commit.

---

### Task 5: `flow.findings-to-tickets` + back-fill

**Files:**
- Create: `orchestrators/flow.findings-to-tickets.yaml`
- Create: `examples/backfill-session-findings.yaml` (the run config + the session findings as Finding-shaped input)

**Interfaces:**
- Consumes: `findings[]` (Finding + enrichment) + `project` + `repo`
- Produces: `{filed[],updated[],rollup:{created,updated,reopened}}`

- [ ] **Step 1:** Author `flow.findings-to-tickets` — iterate findings (deterministic fan over the array) → `cap.coordinate.ticket-upsert` each → aggregate rollup.
- [ ] **Step 2:** Convert a SMALL slice (3 findings) from the autopilot-beta deep-QA doc into Finding+enrichment shape in the example; run → 3 tickets in Project 3, correct bodies.
- [ ] **Step 3:** Re-run same slice → all `updated`, no duplicates (dedup proof).
- [ ] **Step 4:** `praxec check`; commit `feat(qa): flow.findings-to-tickets + session back-fill example`.

---

### Task 6: `cap.coordinate.ticket-read` + `flow.fix-from-ticket` + `flow.fix-ticket-batch`

**Files:**
- Create: `capabilities/cap.coordinate.ticket-read.yaml`
- Create: `scripts-library/coordinate.github.issue-read.yaml`
- Create: `orchestrators/flow.fix-from-ticket.yaml`
- Create: `orchestrators/flow.fix-ticket-batch.yaml`

**Interfaces:**
- Produces: `ticket-read(number)` → `{title, area, assertionSketch, affectedFiles, layer, severity, body}`
- Pattern to copy: `orchestrators/flow.qa.promote-finding.yaml` (regression-test → test-red → fix-under-scope → verify), `orchestrators/flow.bugfix-from-error-log.yaml`, `capabilities/cap.coordinate.pr-open.yaml`

- [ ] **Step 1:** `issue-read` script: `gh issue view $N --json title,body,labels` + parse the schema sections (assertion sketch, layer, affected files) from the body. Live-test on a back-filled ticket.
- [ ] **Step 2:** Author `cap.coordinate.ticket-read` wrapping it.
- [ ] **Step 3:** Author `flow.fix-from-ticket`: `reading` → Status=In-Progress → `writing_red` (regression-test from assertionSketch) → `proving_red` (verify.test-red) → `fixing` (fix-under-scope) → `verifying` (repro/build-green) → `pr` (pr-open, body `Fixes #N`) → Status=In-Review. Target repo = ticket's repo, worktree-isolated.
- [ ] **Step 4:** Author `flow.fix-ticket-batch`: query open tickets by `{label|priority|area, size}` → one branch → per-ticket fix as atomic commits → ONE pr-open `Fixes #a,#b,…` → each Status=In-Review.
- [ ] **Step 5:** Live-prove `flow.fix-from-ticket` on ONE small back-filled ticket end-to-end → `Fixes #N` PR opens (do NOT merge). `praxec check`; commit.

---

### Task 7: `flow.qa.explore-and-file` retrofit + manifest wiring

**Files:**
- Create: `orchestrators/flow.qa.explore-and-file.yaml`
- Modify: `README.md` (flow catalog section — add the new flows)
- Verify: `praxec.repo.yaml` layout already exposes `orchestrators/`,`capabilities/`,`scripts-library/` (no change needed)

**Interfaces:**
- Consumes: `flow.qa.explore` outputs (`findings`) + `project` + `repo`
- Produces: filed/updated ticket refs

- [ ] **Step 1:** Author `flow.qa.explore-and-file` — sub-workflow call `flow.qa.explore` → pipe `$.context.findings` into sub-workflow `flow.findings-to-tickets`. `qa.explore` unchanged.
- [ ] **Step 2:** Validate the whole pack loads: `praxec check --config <gateway-with-this-repo>`; 0 diagnostics across ALL new definitions.
- [ ] **Step 3:** Add the flow catalog rows to `README.md`.
- [ ] **Step 4:** Commit `feat(qa): flow.qa.explore-and-file + docs`.

---

### Task 8: End-to-end proof + PR

- [ ] **Step 1:** Full dogfood pass on Project 3: cleanup (Task 4) → back-fill remaining session findings (Task 5) → one batch fix (Task 6) → re-run cleanup to verify. **Every cleared item must end issue-closed + Status=Killed on the board** (the verify pass asserts this; a merged-but-open ticket fails the pass). Capture the board state.
- [ ] **Step 2:** Confirm 0 `praxec check` diagnostics for the whole pack; confirm no duplicate issues (dedup held).
- [ ] **Step 3:** Open PR into `praxec/cognitive-architectures` (base `dev`), body summarising the flow family + the dogfood evidence. Parked for owner merge.

## Self-Review

- **Spec coverage:** substrate (T1–2) ✓ · ticket-upsert + body schema (T3) ✓ · cleanup + evidence-gate (T4) ✓ · findings-to-tickets + back-fill (T5) ✓ · fix-from-ticket + batch (T6) ✓ · explore-and-file retrofit (T7) ✓ · dogfood loop + PR (T8) ✓. Configurability threaded as `project`/`repo` inputs on every flow. Both poka-yokes have a task (T2/T3 dedup, T4 evidence-gate).
- **Type consistency:** `resolve-project` field/option maps consumed by `issue-upsert` (T2) and `ticket-upsert` (T3); `project-enumerate` item shape consumed by `ticket-disposition` (T4); Finding+enrichment shape consumed by `ticket-upsert` (T3) and produced by `findings-to-tickets` (T5); `ticket-read` output consumed by `fix-from-ticket` (T6). Names aligned across tasks.
- **Placeholders:** none — each task names exact files, the GraphQL query shapes, the pattern file to copy, and a live-verification step.
