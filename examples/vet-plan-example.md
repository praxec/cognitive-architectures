# vet-plan worked example: "Add OAuth provider connector to the gateway"

End-to-end walkthrough of the `vet_plan` workflow driving a real
planning task with lexicon grounding + FMECA optimization.

## Setup

```bash
# Build the praxec binary (0.0.13+)
cd ~/working/praxec
cargo build --release -p praxec
export PATH="$(pwd)/target/release:$PATH"

# Validate the example loads
cd ../cognitive-architectures
praxec check --config examples/vet-plan-example.yaml
```

## Run

```bash
praxec-tui walk \
  --workflow vet_plan \
  --config examples/vet-plan-example.yaml \
  --input '{"task":"Add OAuth provider connector to the gateway"}' \
  --agent planner=anthropic/claude-sonnet-4-6 \
  --agent critic=anthropic/claude-haiku-4-5-20251001 \
  --max-sub-agent-seconds 120 \
  --max-sub-agent-steps 50
```

## Expected trace

### Phase 0 — Lexicon grounding (`planning` state, before drafting)

The planner-agent calls `gateway.lexicon.search` for each substantive
term it's about to use:

```
gateway.lexicon.search({"query":"connector"})
→ {hits: [{term:"connector", definition:"A unit of integration..."}]}

gateway.lexicon.search({"query":"capability"})
→ {hits: [{term:"capability", definition:"A typed surface..."}]}

gateway.lexicon.search({"query":"oauth"})
→ {hits: []}   # not in lexicon — will surface as proposed_lexicon_additions

gateway.lexicon.search({"query":"provider"})
→ {hits: []}   # same
```

### Phase 1-5 — Plan emission (planner output)

```json
{
  "plan_markdown": "## Summary\nAdd OAuth provider...\n\n## Critical Path\n1. oauth-provider-trait\n2. anthropic-oauth-impl\n3. token-refresh-test\n4. wire-into-config\n5. integration-smoke-test\n\n## Deliverable Artifacts\n...",
  "artifacts": [
    {
      "id": "oauth-provider-trait",
      "kind": "file",
      "path": "crates/praxec-core/src/oauth.rs",
      "depends_on": [],
      "lexicon_refs": ["connector", "capability"],
      "on_critical_path": true,
      "estimated_effort": "M"
    },
    {
      "id": "anthropic-oauth-impl",
      "kind": "function",
      "path": "crates/praxec-core/src/oauth.rs::AnthropicProvider",
      "depends_on": ["oauth-provider-trait"],
      "lexicon_refs": ["connector"],
      "on_critical_path": true,
      "estimated_effort": "L"
    },
    {
      "id": "token-refresh-test",
      "kind": "test",
      "path": "crates/praxec-core/tests/oauth_refresh.rs",
      "depends_on": ["anthropic-oauth-impl"],
      "lexicon_refs": [],
      "on_critical_path": true,
      "estimated_effort": "M"
    }
    /* ... more artifacts ... */
  ],
  "critical_path": [
    "oauth-provider-trait",
    "anthropic-oauth-impl",
    "token-refresh-test",
    "wire-into-config",
    "integration-smoke-test"
  ],
  "fmeca": [
    {
      "artifact": "anthropic-oauth-impl",
      "failure_mode": "Token refresh races between concurrent requests; both refresh, one wins, the other's request fails with stale-token",
      "severity": "H",
      "probability": "M",
      "mitigation": "Single-flight refresh guard via Mutex<TokenState>; all concurrent refresh requests await the same future",
      "mitigation_kind": "prevention"
    },
    {
      "artifact": "wire-into-config",
      "failure_mode": "Operator declares provider with no client_secret; runtime spawns + crashes mid-workflow",
      "severity": "M",
      "probability": "H",
      "mitigation": "Slot constraint on `oauth.client_secret` (min_length: 1) at config-load; fail fast in `praxec check`",
      "mitigation_kind": "prevention"
    }
  ],
  "trade_offs": [],
  "proposed_lexicon_additions": [
    {
      "term": "oauth-provider",
      "context_used": "gateway",
      "definition_hypothesis": "A connector specialization that handles OAuth 2.0 client-credentials or authorization-code flows against an external identity provider. Manages token lifecycle (acquire, refresh, revoke) on behalf of downstream calls."
    },
    {
      "term": "token-refresh",
      "context_used": "gateway",
      "definition_hypothesis": "The act of exchanging a near-expiry refresh_token for a new access_token. Single-flight at the runtime layer to avoid concurrent-refresh races."
    }
  ]
}
```

### `critiquing` state

Critic reviews. Likely flags:

- Missing FMECA entry for `oauth-provider-trait` (zero-row entries
  should be at-least-low severity, not absent)
- "wire-into-config" has effort L but only depends on 1 artifact —
  effort estimate likely too high; recheck

Verdict: `needs_revision`. Workflow loops back to `planning` (one
iteration). Planner refines; second submit lands `approved`.

### `human_approval` state

Operator reviews the final plan markdown. Approves. Workflow lands at
`done` with `$.context.committed_plan_markdown` populated.

### Follow-up

The `proposed_lexicon_additions` list has 2 entries. Operator runs
`grill_and_extend_lexicon` workflow once per term to extend the
lexicon. Subsequent vet-plan runs against related tasks now find
"oauth-provider" and "token-refresh" in the lexicon and ground in
them automatically.

This is the LOOP that accumulates ubiquitous language across runs —
exactly the DDD prescription, automated.

For comparison with prompt-style skills planning, see
[mattpocock/skills](https://github.com/mattpocock/skills).
