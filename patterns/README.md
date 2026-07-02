# Cognitive Architecture Patterns

Ten battle-tested composable patterns promoted from
`github.com/praxec/praxec/examples/`. Each pattern is a
production-validated workflow YAML you can `include:` into a host
config, then customize. They cover the recurring shapes of governed
agent work: parallel fan-out, sequential chaining, looping, evidence
gating, human-in-the-loop, script invocation, output mapping.

## What's here

| Pattern | What it does | Composes with |
|---|---|---|
| **[parallel-join-conditions](parallel-join-conditions/)** | Reference: `all`, `any`, `at_least:K`, `percent:P`, expression / aggregator joins. Five workflows in one file. | dynamic-fanout, evidence-quorum |
| **[dynamic-fanout](dynamic-fanout/)** | `for_each` over a blackboard array + optional `where:` pre-fan-out filter. | parallel-join-conditions |
| **[output-mapping](output-mapping/)** | Reference for `set`/`add`/`concat`/`[*]` array-projection mapping operators. | every other pattern (every workflow uses output mapping) |
| **[circuit-breaker](circuit-breaker/)** | Self-loop with iteration cap + escalation. Closes via `result == 'ok'`; escalates after N failures. | recovery-escalation |
| **[recovery-escalation](recovery-escalation/)** | attempt → check → retry / escalate-to-human. Multi-state recovery topology. | circuit-breaker, deploy-pipeline |
| **[evidence-quorum](evidence-quorum/)** | Multi-collector with evidence guard requiring N records of kind K. | parallel-join-conditions, governed-change |
| **[script-governance](script-governance/)** | Hash-pinned script execution behind `script_acknowledged` review gate. | deploy-pipeline, any state firing a `kind: script` executor |
| **[guidance-templates](guidance-templates/)** | `{{ }}` interpolation reference + `guidance_acknowledged` guard pattern. | every workflow with `goal:` / `guidance:` blocks |
| **[governed-change](governed-change/)** | FMECA-shaped change-approval template: change → plan → risk → approval → execute. | evidence-quorum, deploy-pipeline, recovery-escalation |
| **[deploy-pipeline](deploy-pipeline/)** | Deterministic chain (lint → test → build) → human-approval gate → deploy → rollback handler. | governed-change, evidence-quorum, recovery-escalation |

## How patterns compose

praxec workflows compose via the `include:` mechanism: a host config
`include:`s the pattern YAML, then adds connections, skills, and any
override fields the host needs. Patterns are NOT parameterized YAML
templates today — operators currently treat the pattern as a starting
shape and customize per their context.

The `extends:` mechanism for first-class pattern parameterization is a
praxec v0.5 gap (G1 in the plan); for now, copy + customize is
canonical.

See [COMPOSITION.md](COMPOSITION.md) for compatibility rules — which
patterns share blackboard slots, which guards interact, what audit
events to expect when multiple patterns fire in one workflow.

## Why a pattern library beats a free-form prompt-skill library

Each pattern here gives you what a markdown prompt skill cannot:

- **Typed governance**: blackboard slots have JSON schemas; transitions
  have input/output contracts; guards are declarative and inspectable
- **Audit by default**: every transition emits a structured event with
  correlation_id, principal, before/after state, evidence, exec timing
- **Real parallelism**: `parallel` fans out with tokio JoinSets, bounded
  concurrency, per-branch + total timeouts — not "the model decides to
  do things one at a time"
- **HITL injection without authoring burden**: `enable_human_ask: true`
  auto-injects an `ask_human` self-loop into every non-terminal state
- **Slot constraints**: `path_allowlist`, `subset_of` reject violating
  writes at the transition boundary, not in a downstream review
- **Resource bounds**: `max_concurrency`, `max_fires_per_visit`,
  `max_iterations`, `max_recursion_depth` cap blast radius

A pattern is a CONTRACT the runtime enforces. A skill is a hope the
model will follow guidance. Both have a place; the pattern is the load
of governance, the skill is the load of cognitive coaching.

## Validation

```bash
cd ../cognitive-architectures
for d in patterns/*/; do
  praxec check --config "$d/pattern.yaml" || echo "FAILED: $d"
done
```

Every pattern validates against praxec 0.0.13 or later.
