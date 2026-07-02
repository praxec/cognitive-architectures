# Reusable pattern — FMECA convergence loop (harden-until-low)

A reusable way to make any artifact-producing flow **converge its risk** instead
of one-shot aborting when an FMECA finds residual risk. While risk remains, the
loop applies **poka-yoke + TRIZ** mitigations and **re-scores the full FMECA**,
bounded by a round counter (the LoopGuard tenet), escalating to a human on
exhaustion.

## Why it's an inline pattern, not a sub-flow

The praxec engine forbids a flow from invoking another flow via
`kind: workflow` — **flows may only invoke capabilities** (SPEC §3, V11), and
flows cannot carry a `snippet:` block (V8). A convergence *loop* is inherently
multi-state, so it must be a flow; therefore it cannot be nested. The reuse is
carried by the **capabilities + skills + this documented state pattern**, which
each consuming flow inlines (≈3 states).

## Reusable units (compose these)

- `cognitive/cap.review.fmeca` — enumerates failure modes (agent) then **scores
  them deterministically** via fmeca-mcp; emits a CODE-COMPUTED `ready`
  (true iff no residual High/Medium, all scored) + `risk_ranking` + `blockers`.
- `cognitive/cap.refactor.mitigate-risks` — takes the artifact + `risk_ranking`
  + `blockers`, returns a REVISED artifact with the failure modes designed out.
- skills `refactor.poka-yoke` (make the failure impossible) + `refactor.triz`
  (resolve the contradiction so no new mode is introduced) — carried by the
  mitigate cap.

## The state pattern (inline into your flow)

Add a round counter to your flow `inputs:` (`fmeca_round: { type: integer,
default: 0 }`), then:

```yaml
  assess:                      # ASSESS — re-runs FULL FMECA on the CURRENT artifact
    # (optionally) scope.skills: [<your domain lens, e.g. review.fmeca.customer-alignment>]
    transitions:
      fmeca:
        target: gate
        actor: deterministic
        executor:
          kind: workflow
          definitionId: cognitive/cap.review.fmeca
          use:
            inputs:  { subject: "$.context.<artifact>", subject_kind: <kind>, matrix_strategy: qualitative3x3 }
            outputs:
              "$.context.fmeca_ready":        ready
              "$.context.fmeca_risk_ranking": risk_ranking
              "$.context.fmeca_blockers":     blockers

  gate:
    transitions:
      converged:               # all residual Low (code-computed) -> proceed
        target: <next>
        actor: deterministic
        guards: [ { kind: expr, expr: "$.context.fmeca_ready == true" } ]
      mitigate:                # risk remains, budget remains -> mitigate + count
        target: mitigate
        actor: deterministic
        guards:
          - { kind: expr, expr: "$.context.fmeca_ready == false" }
          - { kind: expr, expr: "$.context.fmeca_round < 3" }
        output: { fmeca_round: { add: ["$.context.fmeca_round", 1] } }
      escalate:                # bound hit -> human (never silent)
        target: <human_gate>
        actor: deterministic
        guards:
          - { kind: expr, expr: "$.context.fmeca_ready == false" }
          - { kind: expr, expr: "$.context.fmeca_round >= 3" }

  mitigate:                    # MITIGATE — poka-yoke + TRIZ, then re-assess
    transitions:
      remediate:
        target: assess         # guarded back-edge (bounded by fmeca_round)
        actor: deterministic
        executor:
          kind: workflow
          definitionId: cognitive/cap.refactor.mitigate-risks
          use:
            inputs:  { artifact: "$.context.<artifact>", risk_ranking: "$.context.fmeca_risk_ranking", blockers: "$.context.fmeca_blockers", subject_kind: <kind> }
            outputs: { "$.context.<artifact>": artifact }
```

## Invariants this preserves

- **Convergence is code-computed** (`cap.review.fmeca.ready`), never an LLM's
  say-so.
- **No new risks surface** is enforced for free: every pass re-scores the FULL
  FMECA on the revised artifact, so a regression keeps `ready: false`.
- **Bounded + never silent** (LoopGuard): the round guard caps iterations; on
  exhaustion control goes to a human gate with the residual `risk_ranking` — it
  never silently passes or silently fails.
- **Back-edge is guarded** (`mitigate -> assess` only under `fmeca_round < 3`):
  the engine rejects *unguarded* cycles; a guarded counter cycle is legitimate.

## First application

`cognitive-max/flow.ui.optimal` inlines this as `design_qa` / `design_qa_gate` /
`design_mitigate` (subject_kind `design`), with `review.fmeca.customer-alignment`
in scope on the assess state. Other targets: `flow.add-feature` (plan/spec),
the refactor flows (code).
