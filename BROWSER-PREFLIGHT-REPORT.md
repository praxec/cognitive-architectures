# Browser preflight gate + portable provisioning — finalization report

Branch: `feat/portable-browser-provisioning` (worktree `/home/mc/working/cog-arch-browser`)

## Task 1 — portable browser provisioning (finalized)

Reviewed and finalized the prior agent's uncommitted work:

- `scripts/browser-mcp.sh` — bootstraps Playwright's managed Chromium
  (`npx playwright install chromium`), resolves it OS-agnostically via
  `chromium.executablePath()`, fails loud if the resolved path isn't an
  executable file, then execs `@playwright/mcp --isolated --headless
  --executable-path <chromium>`. Made executable + git-tracked (not
  git-ignored, no `-f` needed).
- **Real bug found + fixed during verification**: the resolution step only
  tried the `npx -p playwright` temp-package PATH-derivation trick. This
  repo doubles as its own qa-target fixture (`package.json` /
  `package-lock.json`, also finalized here) and has `playwright` already
  resolvable locally — in that case `npx` never fabricates a temp package,
  PATH never gets an `_npx` entry, and the old code failed with "could not
  locate the npx temp package dir in PATH" even though a browser was
  trivially launchable. Fixed with two-tier resolution: try plain
  `require("playwright")` first (covers a target app that already has it
  installed/hoisted), fall back to the PATH-derivation trick only if that
  throws (covers a genuinely bare box). Verified both tiers directly
  (tier 1 in this repo, tier 2 from a clean directory with no ancestor
  `node_modules`).
- `connections/browser-playwright.yaml` defaults to the portable wrapper
  (`sh scripts/browser-mcp.sh`), no hardcoded Windows IP; split-host
  `--cdp-endpoint` kept as an opt-in comment + `BROWSER_MCP_SKIP_LOCAL=1`.
  `connections/browser-chrome-devtools.yaml`, `examples/praxec-browser.yaml`,
  `examples/qa-explore-run.yaml`, `.gitignore` all reviewed and finalized
  as the prior agent left them (consistent, no further changes needed).
- Also deleted scratch debris the prior agent left behind (not committed):
  `_dir_list.txt`, `_find.sh`, `_find_src.sh`, `_grep_target.txt`,
  `_list.sh`, `_list_all.sh`, `_probe_.txt`, `capabilities/plan/` (a stray
  `test-charter.yaml` containing literally "test").

## Task 2 — the browser preflight gate

**Naming deviation from the task's suggested names, on purpose**: built as
`cap.verify.browser-preflight` / `verify.browser.preflight`, not
`cap.diagnose.browser-preflight`. This pack's own V6 convention reserves
`diagnose` for agent-judged caps (`kind: noop`) and `verify` for
deterministic ones (`kind: script`) — see `cap.diagnose.browser-probe`
(agent) vs `cap.verify.repro-rate` (script) in this same family. This gate
is pure script, no agent, no judgment call, so it takes `verify` to match
the established split. Documented explicitly in the cap's header.

- `scripts-library/verify.browser.preflight.yaml` — bash script:
  1. **`@playwright/test` presence** — stats
     `<repo_root>/node_modules/@playwright/test/package.json` directly
     (not `npx --no-install playwright --version`, which turned out to be
     unreliable: npx's own cache from prior invocations can make it report
     "present" even in a directory that never had it installed). Absent →
     `PLAYWRIGHT_TEST_MISSING: install @playwright/test`, instant.
  2. **Browser launch/navigate probe** — resolves Playwright's managed
     Chromium (same two-tier logic as the fixed `browser-mcp.sh`), then a
     real `chromium.launch({headless:true}) → newPage() → goto("about:blank")
     → evaluate(() => 1+1)` round-trip via Node, launched inline through
     `npx --yes -p playwright -c 'node -e "..."'`.
  3. **Bounded timeout mechanism** — NOT a plain `timeout N cmd` (tried
     first, rejected: see below). Instead: `setsid` puts the whole
     npx→node→chromium tree in one new process group; the command's own
     stdout/stderr are redirected to files (never a captured pipe); a
     background watchdog subshell sleeps `TIMEOUT_S` then sends
     `SIGTERM`/`SIGKILL` to the **negative PID** (the whole group); the
     main script `wait`s on the tracked child PID specifically (returns
     the instant that PID dies, never on pipe EOF). Always exits 0; the
     verdict (`status`/`code`/`reason`) is JSON on stdout, matching this
     family's `verify.browser.repro-rate` convention.
- `capabilities/cap.verify.browser-preflight.yaml` — thin wrapper cap
  (inputs `repo_root`, `timeout_s`; outputs `preflight_status` /
  `preflight_code` / `preflight_reason`), same shape as `cap.verify.repro-rate`.

### Two real bugs found and fixed while proving this out (not just designed — verified)

1. **`browser-mcp.sh` resolution bug** (Task 1, described above).
2. **Watchdog-orphan pipe-hold bug** (this gate's own mechanism). First
   implementation used a bare `timeout N cmd` — dev testing showed it can
   block **well past its own deadline** (~15s wall against a 5s bound) when
   a captured-via-pipe caller (`$(...)`, or praxec's own script executor,
   which pipes stdout/stderr) waits for EOF from *every* holder of the
   write end, and Chromium's forked process tree doesn't all die
   synchronously with the parent's SIGTERM. Rewrote to the
   `setsid`-group + files + tracked-PID-`wait` design above. That
   redesign had its **own** instance of the same class of bug: the
   watchdog subshell itself didn't redirect its own stdio, so if its
   `sleep` had already forked as a real child by the time we cancelled it,
   the killed subshell left an **orphaned `sleep`** still holding the
   caller's original stdout/stderr pipe open for the rest of its duration
   — reproduced in a minimal isolated repro (real work finishes in 0.3s;
   buggy: `$(...)` blocks the full 15s watchdog duration anyway; fixed:
   returns in 0.317s) and confirmed via the real engine (executor
   `durationMs` dropped from 20011ms to 3653ms for the identical
   dead-browser case, once fixed). Fix: redirect the watchdog subshell's
   own stdio to `/dev/null` so an orphan can only ever hold `/dev/null`
   open.

## Task 3 — wired as the first gate

- **`flow.qa.explore`**: `initialState` changed from `chartering` to a new
  `preflight` state (→ `cognitive/cap.verify.browser-preflight`, inputs
  `repo_root: $.run.repo_root`, `timeout_s: $.workflow.input.preflight_timeout_s`
  [new input, default 20]) → `preflight_gate` (3-arm split gate, same
  shape as the existing `auth_gate`/`probe_gate`/`repro_gate`: `ok` →
  `chartering`; `unavailable` → `failed` explicitly; unguarded default →
  `failed`). New outputs `preflight_code`/`preflight_reason` (null unless
  the run aborted here) and matching `initialContext` seeds (V24: every
  output seeded, "" for `preflight_status` so the gate's unguarded default
  catches a broken cap contract). No browser-dependent state (surveying,
  probing, evidencing, verifying) is reachable without this gate passing.
- **`flow.qa.program`**: not re-wired — it transitively inherits the gate
  because its own `initialState` (`exploring`) calls `flow.qa.explore` as
  its very first transition, whose own `initialState` is now `preflight`.
  Added a comment documenting this inheritance so it's discoverable rather
  than looking like an oversight.
- **`flow.qa.promote-finding`**: out of scope, confirmed via the pack's own
  existing header comment — it does not lease a browser pool at all; its
  `cap.verify.test-red` / `cap.verify.repro-rate` calls run `playwright
  test` directly (their own browser spawn per test invocation, not the
  MCP-leased interactive browser), so it doesn't have the failure mode
  this gate exists to catch. No change made.

## `praxec check`

```
praxec check --config examples/qa-explore-run.yaml   → validation: 0 error(s), 3 warning(s), 0 soft warning(s)
praxec check --config examples/praxec-browser.yaml   → validation: 0 error(s), 1 warning(s), 0 soft warning(s)
```

All warnings are pre-existing (elicitation gate + ephemeral-storage dev
warnings on `serve`), unrelated to this change — identical before and
after.

## Fail-fast proof (standalone + through the real engine)

All three scenarios verified twice: directly (`bash` standalone) and
through `praxec orchestrate` against a throwaway isolated config driving
`cognitive/cap.verify.browser-preflight` directly (no browser connections
declared, so the measurement isolates the cap/script wiring from the
separate MCP-connection-spawn timeout).

| Scenario | Standalone | Engine (`durationMs`) |
|---|---|---|
| Happy path (real managed Chromium) | ok, 1–9s (machine was under heavy contention — load avg ~70–75 from other unrelated concurrent agent work on this shared box, swap exhausted; never hung) | ok, ~9s |
| Absent browser (`PLAYWRIGHT_BROWSERS_PATH` → nonexistent dir) | `BROWSER_UNAVAILABLE`, <1–7s | `BROWSER_UNAVAILABLE`, `durationMs: 3653` |
| **Genuinely hung browser** (fake `chrome` binary that `exec sleep 3600` — the exact original incident shape: process starts, never responds) | `BROWSER_UNAVAILABLE` in **6.148s** against a 6s bound; confirmed **no orphaned process** left running | `BROWSER_UNAVAILABLE`, `durationMs: 6787` / `6857` against a 6s bound |
| Missing `@playwright/test` in target repo | `PLAYWRIGHT_TEST_MISSING: install @playwright/test`, instant (stat-based check) | (covered by the same script path; not re-run through the engine separately) |

The hung-browser case is the direct proof requested: a browser process
that launches but never becomes responsive is killed and reported within
the bound, not hung — matching the actual dogfood incident this gate
exists to prevent.

## Known limitations / concerns

- The preflight proves the **default portable path** (local managed
  Chromium). It does not preflight the opt-in split-host `--cdp-endpoint`
  override, and does not guard against the MCP **connection's own**
  spawn/handshake hanging (that's bounded separately by
  `startupTimeoutMs`) — only against "the server started and accepted the
  lease but can't actually navigate," which is the failure mode that
  actually occurred.
- This dev box is currently under heavy load from unrelated concurrent
  agent work (other worktrees' eslint runs; load average ~70+, swap
  exhausted at time of testing), which made some timing numbers slower
  than a quiet box would show. This doesn't affect correctness — the
  bounded-timeout mechanism was verified in isolation independent of real
  Chromium timing (see the watchdog-orphan repro above) and via a
  deliberately-hung fake browser binary, both confirming the bound holds
  regardless of load.

## Verify

```
cd /home/mc/working/cog-arch-browser
/home/mc/working/mcp-flowgate/target/debug/praxec check --config examples/qa-explore-run.yaml
```
