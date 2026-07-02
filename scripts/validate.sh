#!/usr/bin/env bash
# scripts/validate.sh — runs `praxec check` against every example.
#
# Requires `praxec` v0.2.0 or later on PATH (the expanded 13-root
# blessed subject namespace is required). Install with:
#   cargo install praxec
# or build from source at github.com/praxec/praxec.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

if ! command -v praxec >/dev/null 2>&1; then
  echo "error: praxec not found in PATH." >&2
  echo "  install with: cargo install praxec" >&2
  echo "  or build:     git clone github.com/praxec/praxec && cargo build --release -p praxec" >&2
  exit 1
fi

shopt -s nullglob
examples=(examples/*.yaml)
if [[ ${#examples[@]} -eq 0 ]]; then
  echo "warning: no examples/*.yaml found." >&2
  exit 0
fi

failed=0
for f in "${examples[@]}"; do
  echo "-> checking $f"
  if ! praxec check --config "$f"; then
    failed=$((failed + 1))
  fi
done

if [[ $failed -gt 0 ]]; then
  echo
  echo "validate.sh: $failed example(s) FAILED" >&2
  exit 1
fi

echo
echo "validate.sh: all ${#examples[@]} example(s) validate."

# SPEC §22 — also validate the scripts-library entries. Each file is a
# standalone v1.0.0 config carrying one scripts: entry, so `praxec
# check` runs the full validator stack against it.
script_files=(scripts-library/*.yaml)
if [[ ${#script_files[@]} -gt 0 ]]; then
  echo
  echo "-> Validating scripts library entries..."
  script_failed=0
  for f in "${script_files[@]}"; do
    echo "  -> checking $f"
    if ! praxec check --config "$f"; then
      script_failed=$((script_failed + 1))
    fi
  done
  if [[ $script_failed -gt 0 ]]; then
    echo
    echo "validate.sh: $script_failed scripts-library entry/entries FAILED" >&2
    exit 1
  fi
  echo "validate.sh: all ${#script_files[@]} script(s) validate."
fi

echo "=== behavioral fuzz (informational) ==="
FUZZ_ITERATIONS="${FUZZ_ITERATIONS:-2}" bash scripts/fuzz.sh || echo "(fuzz reported violations — informational; see praxec docs/FUZZ.md)"
