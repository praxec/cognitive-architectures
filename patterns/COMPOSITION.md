# Pattern Composition Guide

How to combine patterns in one workflow without surprises.

## Composition mechanics

praxec's `include:` loads another YAML and merges its top-level keys
(`workflows:`, `skills:`, `scripts:`, `connections:`) into the host
config. Patterns include their entire workflow definition — the host
gets a complete workflow, not a fragment.

Combining multiple patterns in ONE workflow today requires manual
composition: copy the states / transitions you need from each pattern
into a host workflow. The patterns are the SHAPE; the host is the
glue. A first-class `extends:` mechanism is a praxec v0.5 gap (G1);
until it ships, copy-customize is canonical.

## Blackboard slot collisions

Patterns share a flat blackboard namespace. Mixing patterns means
checking their slot names don't collide. Quick reference:

| Pattern | Slots it writes |
|---|---|
| circuit-breaker | `result`, `retryCount` |
| recovery-escalation | `attempt_result`, `attempt_count` |
| dynamic-fanout | `items` (input), `results`, `ok_count` |
| parallel-join-conditions | `branch_results`, `ok_count`, `failed_count`, `all_passed`, `winner` |
| evidence-quorum | `report_a`, `report_b`, `report_c` |
| script-governance | `script_result` |
| guidance-templates | depends on the host's `guidance:` template variables |
| governed-change | `change_request`, `plan`, `risk_analysis`, `approval`, `execution_result` |
| deploy-pipeline | `lint_passed`, `tests_passed`, `build_artifact`, `deploy_result` |
| output-mapping | per-workflow demonstration; no fixed slots |

**Collision risk**: `ok_count` appears in dynamic-fanout AND
parallel-join-conditions. If you compose both in one workflow, rename
one of the slots.

## Guard interaction

Multiple patterns can declare guards on the same state. Guards compose
conjunctively (AND) within one transition; across transitions, the
first transition whose guards all pass wins (declaration order).

| Common guard | What it depends on |
|---|---|
| `evidence` quorum | Evidence records emitted from earlier states |
| `guidance_acknowledged` | Skill body fetched via `gateway.describe` |
| `script_acknowledged` | Script body fetched via `gateway.scripts.search` + acknowledged |
| `expr` over `$.context.*` | Slot value present + matches expression |

Composition risk: a `guidance_acknowledged` guard from
guidance-templates + an `evidence` guard from evidence-quorum require
the agent to do BOTH the acknowledgment AND the evidence emission
before the transition fires. Document this expectation in the host
workflow's `goal:` so the agent knows.

## Per-pattern observability

When multiple patterns fire in one workflow, the audit log carries
events from each. Filter by:

- `correlation_id` → all events for one transition's chain
- `transition` field in payload → which transition fired
- `purpose:` field (SPEC §29.5) → what kind of transition (`ask`,
  `approve`, `escalate`, custom)
- `parallel.fanout.*` / `pipeline.*` → which executor kind aggregated
  per-branch / per-step events

## Composition shortcuts that DO work today

These compose cleanly without G1 / G3:

1. **Pattern as starting shape**: copy a pattern's workflow YAML to
   your host config; rename `definitionId`; customize states.
2. **Pattern as nested workflow**: a pattern's workflow can be invoked
   as a `kind: workflow` branch inside the host's `parallel:` or
   `pipeline:`. The pattern keeps its own audit trail (linked to the
   host's correlation_id).
3. **Skills + connections from patterns**: a pattern's referenced
   skills / connections are independent of the workflow shape; host
   can `include:` just the skill / connection YAMLs without the
   workflow.

## Composition shortcuts that DON'T work today (G1, G3)

- **Parameterized pattern instantiation** — operators want to write
  `extends: circuit-breaker, with: { max_retries: 10 }` and have the
  host workflow inherit the pattern with overrides. Not in v0.4.
  Workaround: copy + edit.
- **Multiple instances of same pattern** — instantiating two circuit
  breakers in one workflow requires renaming all slots / states
  manually. v0.5 fix.

## Verification

For any composed workflow:

```bash
praxec check --config your-composed-workflow.yaml
# Validate semantics: walk it (with noop registry if you don't have
# real connections set up)
cargo test -p praxec-core --test walk_examples your_workflow
```
