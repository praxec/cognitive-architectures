# Cargo verifier diagnostics contract

`verify.cargo.cwd` still reports completed checks as JSON with `passed`, `issues`
and `summary`. It now also reports `diagnostics_available`. A failed formatting
check can produce a diff instead of a compiler error; when the error filter finds
nothing, the verifier retains up to 16 KB of raw output. A failed process with no
output sets `diagnostics_available: false` and includes the three exit statuses.
Consumers should route such failures to investigation, rather than ask a coding
model to fix nonexistent diagnostics. A missing `jq` fails before checks run.

This is process evidence, not proof of behavioral correctness. The caller still
owns test relevance, scope, and acceptance. Existing consumers of the original
three fields remain compatible. Test with `python3 -m unittest discover -s tests`;
the suite controls actual cargo process outcomes without compiling projects.
