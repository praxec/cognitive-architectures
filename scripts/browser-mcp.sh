#!/bin/sh
# scripts/browser-mcp.sh
#
# Portable @playwright/mcp launcher — starts a real, working browser MCP
# server on ANY OS (Linux/macOS/Windows/WSL/containers) with ZERO
# host-specific setup. This is what connections/browser-playwright.yaml's
# DEFAULT pool members `command` this script instead of `npx` directly.
#
# It replaces two host-specific assumptions that used to live in the
# connection YAML:
#   - `--browser chrome` (a CHANNEL name, not a path) hunting for a
#     system-installed Google Chrome that most Linux boxes/containers/WSL
#     don't have (and where a snap/apt chromium is often confinement-broken);
#   - a hardcoded remote Windows Chrome via --cdp-endpoint/--browser-url,
#     which only exists on one specific WSL box and is unreachable anywhere
#     else (CI runners, macOS, a teammate's Linux box, ...).
#
# Mechanism (see connections/browser-playwright.yaml for the fuller
# narrative):
#   1. bootstrap  — idempotently ensure Playwright's own managed Chromium is
#      installed (`npx playwright install chromium`; a fast no-op once it's
#      already downloaded).
#   2. resolve    — find that Chromium's executable path OS-agnostically via
#      Playwright's own `chromium.executablePath()` API (never a hand-glob'd
#      versioned cache directory, which drifts every Playwright release and
#      differs in shape per OS).
#   3. preflight  — fail LOUD if the resolved path is not an executable
#      file, so a mis-provisioned box errors out HERE rather than the MCP
#      server starting, accepting the run's lease, and then failing every
#      navigate silently — which is indistinguishable from "a survey that
#      maps nothing" instead of an honest launch error.
#   4. launch     — exec the real @playwright/mcp server pointed at that
#      Chromium via --executable-path (which, unlike --browser, takes any
#      literal binary path on any OS).
#
# Usage: this script IS the connection's `command`. Any extra args pass
# through to @playwright/mcp untouched (MCP transport flags, etc.):
#   sh scripts/browser-mcp.sh [extra @playwright/mcp args...]
#
# Split-host opt-in: to attach to a remote/system Chrome instead of a
# locally-managed one (see connections/browser-chrome-devtools.yaml for the
# rationale), pass `--cdp-endpoint http://<host-ip>:9222` as an extra arg.
# Set BROWSER_MCP_SKIP_LOCAL=1 to skip the bootstrap/resolve/preflight steps
# entirely in that case (no local Chromium needed when attaching remotely).

set -eu

# Scratch space for the launch probe's stderr, cleaned up on exit.
TMPDIR_LAUNCH=$(mktemp -d)
trap 'rm -rf "$TMPDIR_LAUNCH"' EXIT INT TERM

if [ "${BROWSER_MCP_SKIP_LOCAL:-0}" != "1" ]; then
  # ---------------------------------------------------------------------
  # Step 1 — bootstrap: idempotent install (fast no-op when present).
  # ---------------------------------------------------------------------
  echo "browser-mcp.sh: ensuring Playwright-managed Chromium is installed..." >&2
  if ! npx --yes playwright install chromium >&2; then
    echo "browser-mcp.sh: FATAL - 'npx playwright install chromium' failed." >&2
    echo "  Check network access (Playwright's CDN) and that node/npx work." >&2
    exit 1
  fi

  # ---------------------------------------------------------------------
  # Step 2 — resolve: OS-agnostic Chromium path via Playwright's own API.
  # ---------------------------------------------------------------------
  # TWO-TIER resolution, in order:
  #   Tier 1 — plain `require("playwright")`. This is the common case when
  #   the praxec process's cwd (or any ancestor node_modules) ALREADY has
  #   `playwright` on disk — e.g. a target app that lists @playwright/test
  #   as a devDependency typically hoists a real `playwright` package
  #   alongside it. Node's own resolution walks up from cwd and finds it
  #   directly; no npx temp-package involved at all.
  #   Tier 2 — only reached if tier 1 throws (nothing local anywhere in the
  #   ancestor chain): `npx --yes -p playwright ...` fabricates an EPHEMERAL
  #   temp install and prepends its node_modules/.bin to PATH, but does NOT
  #   add the sibling node_modules to Node's require() resolution (no
  #   NODE_PATH is set), so a plain `node -e` in that context throws
  #   MODULE_NOT_FOUND. We derive NODE_PATH from that same PATH entry so
  #   `require('playwright')` resolves — still fully OS-agnostic
  #   (path.delimiter/path.join handle the platform-specific separators)
  #   and needs no separate install step or version-numbered glob.
  # Skipping tier 1 and always forcing tier 2 was tried first and BROKE on
  # this very pack's own dev fixture (this repo doubles as its own
  # qa-target and has a local `playwright` package on disk from
  # @playwright/test) — npx then has nothing to fabricate, PATH never gets
  # an `_npx` entry, and tier-2-only resolution fails with "could not
  # locate the npx temp package dir in PATH" even though a browser is
  # trivially launchable. Tier 1 first covers exactly that case.
  CHROME="$(npx --yes -p playwright -c 'node -e "
    var pw;
    try {
      pw = require(\"playwright\");
    } catch (e1) {
      var path = require(\"path\");
      var bins = (process.env.PATH || \"\").split(path.delimiter);
      var npxBin = bins.find(function (p) {
        return /_npx[\\\\\/]/.test(p) && p.endsWith(path.join(\"node_modules\", \".bin\"));
      });
      if (!npxBin) {
        process.stderr.write(\"browser-mcp.sh: could not resolve playwright via require() and could not locate the npx temp package dir in PATH either\\n\");
        process.exit(1);
      }
      var nodeModules = path.dirname(npxBin);
      pw = require(path.join(nodeModules, \"playwright\"));
    }
    process.stdout.write(pw.chromium.executablePath());
  "' 2>&2)"

  # ---------------------------------------------------------------------
  # Step 3 — fail-fast preflight.
  # ---------------------------------------------------------------------
  if [ -z "$CHROME" ] || [ ! -x "$CHROME" ]; then
    echo "browser-mcp.sh: FATAL - resolved Chromium path is not an executable file: '${CHROME:-<empty>}'" >&2
    echo "  This means the box is mis-provisioned (network-blocked npx, a" >&2
    echo "  broken Playwright cache, or an unsupported OS/arch). Fix the" >&2
    echo "  underlying install rather than routing around this check — a" >&2
    echo "  browser MCP that starts anyway will accept the run's lease and" >&2
    echo "  then fail every navigate, which looks like 'a survey that maps" >&2
    echo "  nothing', not a launch error." >&2
    exit 1
  fi

  # A resolved, executable path is NOT a launchable browser. `playwright install
  # chromium` downloads the binary but NOT the OS packages it dynamically links
  # against, and a minimal Linux image (WSL's Ubuntu, most containers) ships none
  # of them. The binary is then present, 290 MB, and `-x` true — and dies
  # instantly:
  #
  #   error while loading shared libraries: libnspr4.so: cannot open shared
  #   object file   →   exitCode=127
  #
  # Observed cost of not checking: the bootstrap above reported success, the MCP
  # server started, it accepted the run'"'"'s browser lease, and the failure
  # surfaced ~900 SECONDS LATER inside an agent turn as
  # AGENT_STEP_BUDGET_EXHAUSTED — after two models had each burned a full-length
  # attempt trying to drive a browser that could never start. The engine'"'"'s own
  # note was "this step needs a human", which was true and unactionable.
  #
  # So: actually launch it. `--dump-dom about:blank` is the cheapest complete
  # round-trip — it loads a page and prints the DOM, exercising the dynamic
  # linker, the sandbox flags and the renderer, in well under a second.
  # An operator may point at a Chromium this script would not have resolved (a
  # system package, a pinned build). It is also what makes the FAILURE path
  # testable: a preflight whose error branch nobody can exercise is a preflight
  # nobody can trust.
  if [ -n "${BROWSER_MCP_CHROME:-}" ]; then
    echo "browser-mcp.sh: BROWSER_MCP_CHROME override -> $BROWSER_MCP_CHROME" >&2
    CHROME="$BROWSER_MCP_CHROME"
  fi

  echo "browser-mcp.sh: verifying Chromium can launch..." >&2
  if ! "$CHROME" --headless --disable-gpu --no-sandbox --dump-dom about:blank >/dev/null 2>"$TMPDIR_LAUNCH/err"; then
    echo "browser-mcp.sh: FATAL - Chromium is installed but CANNOT LAUNCH." >&2
    echo "  path: $CHROME" >&2
    sed "s/^/  | /" "$TMPDIR_LAUNCH/err" >&2 || true
    # The overwhelmingly common cause, and the one worth naming precisely.
    if command -v ldd >/dev/null 2>&1; then
      MISSING=$(ldd "$CHROME" 2>/dev/null | awk "/not found/ {print \$1}" | sort -u | tr "\n" " ")
      if [ -n "$MISSING" ]; then
        echo "  MISSING SHARED LIBRARIES: $MISSING" >&2
        echo "  Playwright downloads the browser, not the OS packages it links" >&2
        echo "  against. Install them:" >&2
        echo "    sudo npx playwright install-deps chromium" >&2
        echo "  or, on Debian/Ubuntu, the direct equivalent:" >&2
        echo "    sudo apt-get install -y libnspr4 libnss3 libasound2t64" >&2
        echo "  Without root, they can be fetched user-locally:" >&2
        echo "    apt-get download libnspr4 libnss3 libasound2t64" >&2
        echo "    dpkg -x <each>.deb ~/.local/chromium-deps" >&2
        echo "    export LD_LIBRARY_PATH=~/.local/chromium-deps/usr/lib/x86_64-linux-gnu" >&2
      fi
    fi
    echo "  Failing HERE, in one second, rather than 900 seconds into an agent" >&2
    echo "  turn that has already spent two model attempts on it." >&2
    exit 1
  fi
  echo "browser-mcp.sh: resolved Chromium -> $CHROME (launches OK)" >&2
fi

# ---------------------------------------------------------------------------
# Step 4 — launch the real MCP server.
# ---------------------------------------------------------------------------
if [ "${BROWSER_MCP_SKIP_LOCAL:-0}" = "1" ]; then
  exec npx --yes @playwright/mcp@latest --isolated --headless "$@"
else
  exec npx --yes @playwright/mcp@latest --isolated --headless --executable-path "$CHROME" "$@"
fi
