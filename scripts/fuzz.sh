#!/usr/bin/env bash
# Fuzz every composed example config with praxec's harness. Reports
# structural violations (livelock/wedge/engine-error) per workflow. SMOKE/REPORT
# step: human-gated flows may still report Livelock until the harness can satisfy
# evidence-gated approvals (see praxec docs/FUZZ.md). Run from repo root.
set -uo pipefail
FG="${PRAXEC_BIN:-praxec}"
ITER="${FUZZ_ITERATIONS:-3}"
status=0
for cfg in examples/*.yaml; do
  echo "=== fuzz: $cfg ==="
  "$FG" fuzz --config "$cfg" --iterations "$ITER" --report text || status=1
done
exit "$status"
