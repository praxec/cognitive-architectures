# Pattern: plan-vet-execute

Flagship coding pattern. Plan (vet-plan) → human approve → scope-bounded execute → parallel critic review → merge gate. Use for: any non-trivial code change you want governed.

## Composition contract

This pattern references skills / connections that the host config must supply via `include:`. Standalone `praxec check pattern.yaml` will report "skills entry X not declared" — that's expected; compose via:

```yaml
# host config (examples/your-host.yaml)
version: "1.0.0"
include:
  - ../patterns/plan-vet-execute/pattern.yaml
  - ../skills/<whatever-skill-this-pattern-references>.yaml
  - ../connections/<whatever-connection-this-pattern-references>.yaml
```

Then `praxec check --config examples/your-host.yaml` validates the composed config.

## v0.4 primitives used

Specific primitives per pattern (see `pattern.yaml` for inline comments referencing SPEC §s):
- `enable_human_ask: true` (SPEC §29.3) — ad-hoc human clarification
- Per-pattern: parallel + aggregator (§24), pipeline (§25), while (§26), state-local slots (§27), slot constraint (§28), max_fires_per_visit (§29.6)

## What praxec adds over a free-form prompt skill

- Typed governance (slot schemas, guards, input/output schemas)
- Audit per transition with correlation_id
- Real parallelism / sequencing (not "the model decides to do things one at a time")
- HITL injection without per-state authoring
- Resource bounds (`max_iterations`, `max_concurrency`, `max_fires_per_visit`)

## Composes with

See `../COMPOSITION.md` for the full compatibility matrix.
