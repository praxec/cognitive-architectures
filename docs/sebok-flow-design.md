# SEBoK Flow — INCOSE-aligned SE meta+micro Vee workflow (design)

**Status:** design (P1 of the praxec v0.0.16 self-improvement program). Produced by
`cognitive/cap.plan.technical-design`, driven through praxec — the first proof that a
precise, standards-grounded brief lets a commodity model produce a sound SE design.

**Grounding:** ISO/IEC/IEEE **15288** (system life-cycle technical processes), **12207**
(software life-cycle), and the **Vee** model (SEBoK: *Software Engineering in the Systems
Engineering Life Cycle*). Sits **beside** the existing SDLC flow (`cognitive/flow.greenfield-mcp`),
not replacing it.

## Core hypothesis (the reason this flow exists)

> If a commodity model can't drive a step, the fix is **more granular decomposition** —
> split the step into clearer sub-steps / sub-workflows — **not** a more capable model.

Every stage below is designed to be drivable by a commodity model with one precise
instruction. The **micro-waterfall** (mini-Vee TDD) is the atomic unit of that decomposition.
A commodity-model stall on any stage is a signal to sub-divide that stage, and is the primary
tuning datum this program collects.

## The Vee — 9 stages (15288 technical processes)

Left leg decomposes; bottom implements; right leg recomposes. Verification and Validation
are **distinct** and trace to **different** left-leg artifacts.

| # | Stage | Leg | Produces | Traces FROM | Existing cap | Class |
|---|-------|-----|----------|-------------|--------------|-------|
| 1 | **Stakeholder Needs** | left | StakeholderNeedsArtifact | — (root) | **NEW** (gap #1) — back with **elicitation-mcp** | Essential |
| 2 | System/SW Requirements (EARS) | left | RequirementsArtifact | needs | `flow.greenfield-mcp:plan` (partial; no EARS/trace) | Essential |
| 3 | Architecture Definition | left | ArchitectureArtifact | requirements | `cap.plan.technical-design` (partial) | Essential |
| 4 | Design Definition | left | DesignArtifact | architecture | `cap.plan.technical-design` | Essential |
| 5 | Implementation | bottom | ImplementationArtifact | design | **`shared.mini-vee-tdd`** (micro-Vee, looped per increment) | Essential |
| 6 | Integration | right | IntegrationArtifact | architecture+design | — | Essential |
| 7 | **Verification** ("built it right") | right | VerificationReport | **requirements** | `cap.verify.*` (no trace enforcement) | Essential |
| 8 | Transition | right | TransitionArtifact | — | — | Useful → collapse to gate-marker |
| 9 | **Validation** ("built the RIGHT thing") | right | ValidationReport | **stakeholder needs** | `flow.greenfield-mcp:acceptance` (conflates V&V) | Essential (gap #2) |

**The two gaps this flow closes vs. the existing SDLC:** (1) first-class **Stakeholder Needs**
elicitation (the trace-source for validation); (2) **Validation distinct from Verification**
(the existing `acceptance` stage conflates them).

## Traceability — `artifact.trace-matrix` (Essential)

Single append-only writer; stages are readers. Enforces at gate exit:
- every **requirement** → ≥1 verification outcome (else `UnverifiedRequirement`, block)
- every **need** → ≥1 validation outcome (else `UnvalidatedNeed`, block)

This is what makes "traceability across the Vee" checkable rather than aspirational.

## Shared subworkflows (callable from BOTH sebok-flow and the existing flow)

- **`shared.mini-vee-tdd`** (Essential): requirement → design-sketch → failing test →
  minimal implementation → verify. This IS the micro-waterfall. Reused by stage 5 here and
  by `flow.greenfield-mcp:tdd_loop`. Single source → no drift.
- **`shared.derisk`** (Useful): elicit → design → fmeca → poka-yoke → review. Callable at any
  stage gate; advisory (a failed FMECA must be dispositioned, doesn't hard-block).

## Commodity-model drive contract (per stage)

`input = (stage_prompt_template, current_artifact, trace_matrix_slice)` →
`output = (draft_artifact, confidence)`. The stage validates schema + confidence, then accepts
or **re-prompts (max 3, escalating specificity)**; persistent low confidence = decompose the
stage (the hypothesis). Stateless model; stage owns the prompt cycle.

## Error strategy

- **detect early:** per-stage output schema + confidence check; EARS-form conformance at stage 2;
  dangling-interface detection at stage 3.
- **fail-fast:** `GateBlocked{stage, missing_artifact}` if a predecessor artifact isn't `accepted`;
  trace-completion blocks at stages 7 and 9; `SubflowFailed` propagates (no silent proceed).
- **recover:** re-prompt (≤3), mini-vee increment retry, derisk re-invocable at any gate.

## MCP connections this flow wires (`connections/`)

- **elicitation-mcp** → stage 1 (stakeholder needs; interactive, operator boundary).
- **cpm-planner** → decomposition/scheduling of stage-5 increments (already in the pack).
- **science-process-mcp** → optional research grounding when a stage needs cited external
  evidence (e.g. pinning exact ISO/SEBoK clauses).

## Naming / file layout (corrected to real pack layout — no `flows/` dir)

- `capabilities/sebok-flow.yaml` (meta-Vee flow)
- `capabilities/_shared.mini-vee.yaml`, `capabilities/_shared.derisk.yaml`
- `connections/elicitation-mcp.yaml`, `connections/science-process-mcp.yaml`
- doc: `docs/sebok-flow-design.md` (this file)

## Cut list (anti-gold-plating)

- `stage.transition` → **collapse to a lightweight gate-check** between verification and
  validation, not a full commodity-model-prompted stage. Everything else is Essential and earns
  its place; `shared.derisk` is Useful and gated behind explicit invocation.
