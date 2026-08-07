# Northstar — Governed SDLC: the ticket pull system (v2, vetted)

**Status:** Northstar architecture · v2 (2026-08-07) · **Home:** cognitive-architectures (governance core)

> **v2 folds two vettings into the chart** — an FMECA/architecture simplification and a
> developer-experience bar. The governing principle changed from *"design the full
> governance apparatus"* to **"ship the simple proven core; add governance by
> evidence."** Every deferred component below carries an explicit **trigger** — the
> measurement that justifies building it. Nothing speculative is built ahead of its trigger.

---

## 0. What changed from v1, and why

- **FMECA vet:** most of v1's apparatus — a 7-level vetting battery, INCOSE/TRIZ MCP
  tools, a versioned contract + `provides:`/`dependencies:` dependency system, a
  pluggable tracker adapter, a burn-down store — is **speculative infrastructure ahead
  of demand** (≈0 live tickets, 1 executor domain). The *core* (FSM + lease + dispatch +
  one executor + audit) is **simple and proven**. v1 even scheduled the most speculative
  piece — the dependency seam — as Inc 0. Corrected here.
- **DX vet:** every speculative component is also a **friction tax**, and praxec's
  *authoring* and *operating* surfaces are already the pain (four-file config assembly,
  mandatory manifests, V-rule landmines, cryptic run-kills — all hit repeatedly while
  building this). **DX is now a first-class acceptance bar on every increment.**
- **Result:** a lean core, evidence-triggered increments, explicit DX criteria.

## 1. Thesis (unchanged in spirit)

A unit of work: **idea → vetted → pulled (under a lease) → dispatched by type → run (with
HITL gates) → verified**, governed and auditable, generic across codebases. But the
vetting starts **minimal**, the dispatch uses **direct references**, and the elaborate
seams appear **only when evidence demands** them.

## 2. The lean core — the foundation (build this first, Inc 0)

The only Essential + Proven/Adapted components:

- **Lane FSM (declarative):** `Request → Backlog → In-Progress → Completed → Verified`
  (+ `Rejected`). Promotion = **human sign-off + a minimal machine check (duplication +
  conflict)** — *not* the 7-level battery.
- **Exclusive lease** (concurrency) + **TTL/human reclaim** (both proven; process-death
  was observed this session — reclaim is required).
- **Dispatch by type → executor via direct `pack/flow` reference** (praxec already
  supports this). **No versioned-contract system.**
- **≥1 real executor:** `design/flow.design-pass` (the proven design suite).
- **Audit stream = the single source of truth;** status/burn-down = a **query projection**
  over it, never a separate store.
- **Governance metrics** instrumented from day one (§5).

## 3. The executor "contract" — a convention, not a schema (yet)

An executor honors an interface: **inputs** (ticket + a context bundle), **outputs**
(deliverable + evidence + close signal), **HITL gates** (where it parks). In the core
this is a **convention** enforced by a **lightweight runtime resolve-check** — every
dispatched type must resolve to a mounted flow, fail-fast with a clear message if not.
The **versioned `provides:`/`dependencies:` schema + cross-pack validator is deferred**
(§7): it serves *multiple executor packs + version skew* — neither exists yet — and the
engine's `RepoManifest` hard-rejects the schema today. Building it now is pure YAGNI *and*
pure DX tax.

## 4. DX acceptance criteria — first-class, a gate on every increment

An increment is **not done** until it meets the bar for the personas it touches. These
are enforced, not hoped.

| Persona | Bar | Enforcing metric |
|---|---|---|
| **Consumer** (uses the system) | idea → reviewing an executor's output in minutes, **zero YAML**, chat/CLI-native | % consumer actions needing YAML = **0**; time-to-review |
| **Author** (builds an executor) | `praxec new executor <type>` scaffolds a **V-rule-clean, contract-conforming skeleton**; `check` **teaches** (explains + offers the fix) | **author-error-rate** (failed `check`s before green) trending down; zero hand-authored machinery |
| **Operator** (runs praxec) | `praxec init` → one working config + bind models → go — **no four-file assembly** | **time-to-first-governed-run** (clone→run) in minutes |
| **Worktree / any checkout** | praxec is **worktree-native**: `repo_root` is auto-detected from the CWD's git root, all paths are repo-relative, config carries **no absolute paths** (poka-yoke: `check` refuses them), and run state is worktree-local while the governance store is repo-shared via the git common dir. `git worktree add …` **needs zero reconfiguration** (praxec/praxec#206) | config-edits-per-worktree = **0**; absolute paths in config/inputs = **0** |
| **Anyone** (a run dies) | termination reason surfaces **prominently** + `praxec why <run>` | MTTR on a dead run |

Rationale is grounded in lived friction: config sprawl (recreated the focused config
repeatedly), mandatory `praxec.repo.yaml` on plain repos (blocked config load twice),
V-rule landmines (V6/V12/V13/V30, parallel fan-in, `use:` vs `input:`, `missionDeadlineSecs`,
`max_turns` not YAML-configurable), and cryptic kills (30-min deadline surfaced only in
the log), and the worktree pain (absolute paths in config break every new worktree).
Simpler core + these bars = the whole DX story.

## 5. Governance observability — instrument from Inc 0

Without these the system is a black box (can't calibrate, can't improve):

- **decision-flip rate per vetting level** — does this level ever change the verdict? If ≈0, **delete it**.
- **executor rework/reopen + human-reject rate.**
- **lease-reclaim rate + stale-lease age.**
- **promote→verified cycle time.**
- **dispatch-failure count.**

**Calibration rule:** heuristic scores (FMECA RPN, `score.mjs` G/fit) are **advisory** —
never a hard gate — **until back-tested against outcomes.** A score is promoted to a gate
only once it demonstrably predicts.

## 6. Evidence-triggered increments (build order + triggers)

Reordered per the FMECA vet. Inc 0 is the **core**, not the contract seam. Each later
increment names the **trigger** that justifies it.

| Inc | What | Trigger to build |
|---|---|---|
| **0** | **Lean core + DX foundation** — FSM + lease + dispatch (direct refs) + design-pass executor + audit + 2-level human-gated vetting + governance metrics + `praxec init`/scaffold/`why`/validation-as-teacher. **DoD includes the §4 DX bar.** | — (the foundation) |
| **1** | `flow.design-pass` to production, dogfooded on a real preveti control | Inc 0 usable |
| **2** | Add a vetting level | data shows the current levels **miss a class of bad ticket** AND the new level's projected **decision-flip rate > ~0** |
| **3** | Second executor domain (e.g. `code-change`) | a real second ticket type in demand |
| **4** | **Versioned dependency seam** — `provides:`/`dependencies:` + engine `RepoManifest` schema + cross-pack validator (`PACK_DEPENDENCY_UNSATISFIED`) | Inc 3 exists → **2+ executor packs + real version skew** |
| **5** | Tracker adapter (Jira/Linear) | a real **second tracker** user |
| **6** | Burn-down / portfolio view + WSJF/cpm pull ordering | ticket volume high enough that manual `praxec.query` status is painful |

## 7. Deferred / removed — with explicit triggers

| Component (v1) | v2 status | Trigger to (re)build |
|---|---|---|
| 7-level FMECA vetting battery | **collapsed to 2** (dup + conflict) + human gate | each further level: decision-flip evidence (Inc 2) |
| INCOSE-MCP (#81), TRIZ+embeddings-MCP (#82) | **deferred** | the LLM-assisted version of that level proves it flips decisions |
| Versioned contract + `provides:`/`dependencies:` + cross-pack validator + engine schema | **deferred (out of the foundation)** | 2nd executor domain + version skew (Inc 4) |
| `currency: pull-latest` cross-pack resolution | **removed** | no cross-pack deps to resolve |
| Tracker adapter (pluggable) | **deferred** | a real second tracker (Inc 5) |
| Burn-down as a store | **never a store** — projection only; view deferred | ticket volume (Inc 6) |

The filed tickets (#80–#91, #83, #84) remain valid **as increments**, re-sequenced to
this order and gated on their triggers. #84 (lease) and the lane FSM are Inc 0; the
vetting/tools/dependency tickets move behind their evidence triggers.

## 8. Risk posture (from the FMECA vet)

- **No High risks** in the lean core.
- **Two accepted Medium residuals**, both constraint-bound (reducing them means re-adding
  the complexity we deliberately cut):
  1. **reduced-vetting miss** — bounded by the human promotion gate + the flip-rate
     observable that signals *exactly when* a heavier level is justified.
  2. **executor passes gates but deliverable is wrong** — bounded by the human executor
     gate + the rework observable.
- **Non-negotiable:** the **human gates at promotion and at the executor** stay while
  scores are uncalibrated; the **lease** (multi-actor safety); the **audit stream** (only
  source of truth).

## 9. How the design work maps in

The design suite — `flow.anneal.structure-first`, `flow.design.from-direction`,
`flow.design-system`, `flow.rollout`, and (Inc 1) `flow.design-pass` — is **already the
first executor column**, built + dogfooded. In the lean model it is **referenced directly
by `pack/flow`** and honors its contract **as a convention now**; it gains the versioned
`provides:` block at **Inc 4**, when the dependency seam is real.

## 10. Open decisions

- **Consumer-surface exposure** (MCP tool vs CLI vs chat) — decide **at Inc 0**; it *is*
  the DX bar.
- **Contract granularity** (per-type vs generic envelope) — decide **at Inc 4**, when the
  seam is real, not now.
- **Dispatch-table home** — core config (it is governance).
