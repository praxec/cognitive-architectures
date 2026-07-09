# Pattern: output-mapping

Reference for set/add/concat/[*] mapping operators. Use as: read-only documentation of mapping syntax.

## Source
Promoted from `github.com/praxec/praxec/examples/` (see SOURCE-README.md if present for the original walkthrough). This copy is the CA-library reference; the upstream is the canonical test substrate.

## Validates with
`praxec` 0.0.14+ — `praxec check --config pattern.yaml`.

## Composition

See `../COMPOSITION.md` for slot collisions, guard interactions, and what composes cleanly.

## What praxec gives you (vs free-form prompt skills)

- Typed slot schemas + write-time validation
- Declarative guards (`expr`, `evidence`, `permission`, `guidance_acknowledged`, `script_acknowledged`)
- Structured audit per transition (correlation_id, principal, before/after, evidence, exec timing)
- Optional HITL injection via `enable_human_ask: true`
- Per-transition fire caps (`max_fires_per_visit`)
- Resource bounds (`max_concurrency`, `max_iterations`, `total_timeout_ms`)
