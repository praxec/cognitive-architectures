# Pattern: grill-and-extend-lexicon

The EXTENSION half of the ubiquitous-language loop. Socratic
questioning by an agent, human approval gate, commit to praxec's
lexicon via `gateway.lexicon.define`.

The REUSE half is built into every workflow that calls
`gateway.lexicon.search` at planning time (see `vet-plan` workflow).
Together they make the system **accumulate** ubiquitous language
across runs — the extracted vocabulary persists beyond a single session.

## What it does

| Phase | What happens | Actor |
|---|---|---|
| `grilling` | grill-agent asks Socratic questions until a precise definition emerges; uses the auto-injected `ask_human` transition (SPEC §29.3) for each question | agent + ad-hoc human |
| `human_approval` | operator reviews proposed term + definition; approve → commit; reject → back to grilling | human |
| `writing` | runtime calls `gateway.lexicon.define` to commit the term | deterministic |
| `done` | term is in the lexicon overlay; operator persists by editing `praxec.yaml` | terminal |

## Design notes

This pattern produces a PERSISTENT artifact:

- The term lives in `praxec.yaml`'s `lexicon:` block
- Every subsequent workflow run that calls `gateway.lexicon.search`
  finds it
- The vet-plan skill grounds its CPM-plan artifacts in already-extracted
  vocabulary
- Audit records (`lexicon.defined` event) preserve who defined what when

Across many runs, the lexicon becomes the **ubiquitous language** for
the operator's domain — exactly what Eric Evans / DDD prescribes.

For comparison with prompt-style skills, see
[mattpocock/skills](https://github.com/mattpocock/skills).

## Governance

The pattern routes through an `actor: human` transition before commit
(SPEC §30.6). This means:

- Agents can PROPOSE (grilling phase)
- Humans must APPROVE (`approve` transition)
- The commit (`writing` state's `gateway.lexicon.define` call) carries
  the human's principal through

If you want agents to commit directly (less discipline, faster iteration),
declare the term's `governance: agent-may-propose` in
`praxec.yaml` before running the grill — the lexicon.define handler
will accept the agent call.

## Composes with

- `vet-plan` — consumes lexicon terms via `gateway.lexicon.search`
- any workflow needing typed vocabulary

## Connection contract

The workflow's `writing` state calls `gateway.lexicon.define` via an
MCP connection named `praxec`. The host config must declare:

```yaml
connections:
  praxec:
    kind: mcp
    command: praxec
    args: []
    env:
      PRAXEC_CONFIG: ./praxec.yaml
```

This is the gateway calling itself through MCP — a child-process loop
that surfaces lexicon writes through the same governance path as any
other agent tool call. The `LEXICON_DEFINE_REQUIRES_HUMAN` rejection
fires here if the principal-passthrough fails.

## Validation

```bash
praxec check --config pattern.yaml
```

Validates the workflow shape. Runtime validation requires the
`praxec` connection wired in the host config.

## Future improvements

- Multi-term grilling (extract several related terms in one session) —
  current pattern is single-term per workflow
- Definition-quality scoring (length, ref-density, anti-vague-phrases) —
  could be a slot constraint
- Auto-cross-link: when proposing term X with definition mentioning
  term Y already in the lexicon, suggest `refs: [Y]`

These are operator-extensions; the base pattern is minimal by design.
