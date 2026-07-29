# CAPMODES-REPORT.md — flow.change build_mode / verify_mode enum routing

## Scope

`orchestrators/flow.change.yaml` is the ONLY file touched. `flow.implement.deliverable.yaml`
and `flow.shared.mini-vee.yaml` were read but NOT modified — confirmed via
`git status --porcelain` (only `flow.change.yaml` shows modified) and `git diff --stat`.

## The exact diff to flow.change (states/guards added)

### New inputs (all additive, all default to today's behavior)

```yaml
build_mode:      { type: string, default: "" }   # "" = stack routing (unchanged); "tdd" = cap.implement.tdd-loop
verify_mode:     { type: string, default: "" }   # "" = stack routing (unchanged); "regression" = cap.verify.regression-tests
defect_location: { type: object, default: {} }   # decoupled optional input, only read when verify_mode=='regression'
repro_steps:     { type: array,  default: [] }   # decoupled optional input, only read when verify_mode=='regression'
```

### New initialContext seed

```yaml
regression_ok: false   # GUARD_UNSET_SLOT poka-yoke for verify_regression_decision's guard
```

### build_gate — guard order (build_mode checked FIRST, ahead of stack)

```yaml
build_gate:
  transitions:
    build_tdd:                     # NEW — guarded FIRST
      target: building_tdd
      guards: [ { kind: expr, expr: "$.workflow.input.build_mode == 'tdd'" } ]
    build_ts:                      # unchanged, now evaluated second
      target: building_ts
      guards: [ { kind: expr, expr: "$.context.stack == 'ts'" } ]
    build_default:                 # unchanged, unguarded default
      target: building
```

### New state: building_tdd (mirrors `building` / `building_ts`)

```yaml
building_tdd:
  transitions:
    build:
      target: measuring_impl
      executor:
        kind: workflow
        definitionId: cognitive/cap.implement.tdd-loop
        repoRoot: "$.workflow.input.backstop_cwd"   # same multi-repo re-root as building/building_ts
        use:
          inputs:
            plan:        "$.workflow.input.deliverable"
            scope_paths: "$.workflow.input.deliverable"   # same convention flow.add-feature (the cap's only existing consumer) uses
          outputs:
            "$.context.result": result    # same slot `building` uses (mutually exclusive arms)
```

### stack_gate — guard order (verify_mode checked FIRST, ahead of stack)

```yaml
stack_gate:
  transitions:
    regression:                    # NEW — guarded FIRST
      target: verify_regression
      guards: [ { kind: expr, expr: "$.workflow.input.verify_mode == 'regression'" } ]
    ts: ...       # unchanged
    rust: ...     # unchanged
    dotnet: ...   # unchanged
    unknown_stack: ...   # unchanged, unguarded default
```

### New states: verify_regression → verify_regression_decision → verified_decision

```yaml
verify_regression:
  transitions:
    verify:
      target: verify_regression_decision
      executor:
        kind: workflow
        definitionId: cognitive/cap.verify.regression-tests
        use:
          inputs:
            defect_location: "$.workflow.input.defect_location"
            repro_steps:     "$.workflow.input.repro_steps"
            scope:           "$.workflow.input.verify_scope"   # reuses the atom's existing narrowing input
          outputs:
            "$.context.regression_ok":          ok
            "$.context.regression_tests_added": tests_added

verify_regression_decision:      # {ok:bool} → {status} translation (use.outputs is a straight bind-by-name, no conditional operator)
  transitions:
    pass:
      target: verified_decision
      guards: [ { kind: expr, expr: "$.context.regression_ok == true" } ]
      executor: { kind: noop }
      output: { ws_verify: { set: { status: "pass" } } }
    fail:                        # unguarded default
      target: verified_decision
      executor: { kind: noop }
      output: { ws_verify: { set: { status: "fail" } } }
```

`verified_decision` (unchanged) then reads `$.context.ws_verify.status == 'pass'` exactly as before,
so the regression path re-enters the SAME downstream gate (react_gate → done, or failed) with no
further changes needed.

## Byte-identical default behavior — confirmed

- With `build_mode==""` and `verify_mode==""`: every new arm's guard is `false` (both are
  workflow-input path checks against the literal default value, never referencing an
  unset/null context slot), so control flow falls through to the EXACT pre-existing
  `build_ts`/`build_default` and `ts`/`rust`/`dotnet`/`unknown_stack` arms, unchanged.
- `flow.implement.deliverable.yaml` and `flow.shared.mini-vee.yaml` were NOT edited (see git
  status above) and neither passes `build_mode`/`verify_mode`/`defect_location`/`repro_steps` —
  they get the atom's `""`/`{}`/`[]` defaults, i.e. today's behavior verbatim.
- The new `regression_ok: false` initialContext seed and the four new inputs are pure
  additions; no existing key, state, transition, or comment was removed or altered.

## Real definitionIds + output-shape mappings used

- `cognitive/cap.implement.tdd-loop` — snippet inputs `plan: object (required)`,
  `scope_paths: array (default [])`; outputs `result: object`, `tests_added: integer`.
  Captured into `$.context.result` (same slot `building` uses for
  `cap.implement.build-loop`'s `result` — the two build arms are mutually exclusive per run).
- `cognitive/cap.verify.regression-tests` — snippet inputs `defect_location: object
  (required)`, `repro_steps: array (required)`, `scope: string (default "")`; outputs
  `ok: boolean`, `tests_added: integer`. **This does NOT emit the canonical verifyOut
  `{status, summary, criteria, findings, provenance}` shape** that `cap.verify.ts/rust/dotnet`
  emit (and that `ws_verify.status` / the top-level DoD outcome read). The `{ok}` boolean is
  captured into a new `$.context.regression_ok` slot, then explicitly mapped onto
  `$.context.ws_verify = {status: "pass"|"fail"}` via two guarded `kind: noop` transitions
  using the `set` output-mapping operator (`use.outputs` is a straight-copy bind-by-name with
  no conditional operator — confirmed by reading `crates/praxec-core/src/use_binding.rs`'s
  `project_use_outputs`, so the translation could not be done inline in `use.outputs` itself).

## praxec check result

```
$ praxec check --config examples/praxec-cognitive-only.yaml
validation: 0 error(s), 3 warning(s), 0 soft warning(s)
```

The 3 warnings (2× `ELICITATION_INCOMPATIBLE_GATE` on `cap.implement.build-loop[-pkg]`'s
`needs_human` gate, 1× `EPHEMERAL_STORAGE` for the memory/stderr dev config) are pre-existing
and unrelated to this change (neither file nor state touched by this task).

## Skills sub-question — investigate only, NOT built

**Finding: NEEDS-A-CAP-CHANGE.**

- `cap.implement.tdd-loop`'s only inputs today are `plan` (object) and `scope_paths` (array,
  default `[]`) — there is no input that carries free-text skill/instruction guidance.
- Its `iterating` state's `goal:` field is a plain static string
  (`"Pick the next plan slice; execute one red-green-refactor cycle."`) — it contains NO
  `{{ }}` template placeholders today, so it does not thread ANY workflow input into the
  agent's prompt currently.
- The templating mechanism itself, however, is already proven and available:
  `crates/praxec-core/src/templating.rs::render_template` resolves `{{ $.workflow.input.* }}`
  (and `$.context.*`, `$.run.*`) placeholders inside a state's `goal`/`guidance` string, and
  `crates/praxec-agents/src/executor.rs` builds the agent's user prompt as exactly
  `render_template(&cfg.goal, &request.workflow)` — confirmed by the engine's own test
  `goal_is_templated_against_the_blackboard`. `skills:` (the system-message list, e.g.
  `skills: [implement.tdd.discipline]` on this cap), by contrast, is resolved as a static list
  against the loaded `_skillsLibrary` at config-load time (`praxec_core::skills::
  assemble_system_message`, driven by `cap.implement.build-loop`'s own doc comment in
  `crates/praxec-agents/src/executor.rs`) — it is NOT rendered against workflow input, matching
  the prior spike's finding that `scope.skills` cannot resolve from an input-sourced list.
- Conclusion: the -max flows' build-time craft skills text CANNOT reach
  `cap.implement.tdd-loop`'s agent today (goal is static; no guidance input exists), but the
  fix is small and well-understood — add an optional input (e.g. `craft_guidance: {type:
  string, default: ""}`) to the cap's `snippet.inputs`, and reference
  `{{ $.workflow.input.craft_guidance }}` inside `iterating.goal` (or a new `guidance:` field).
  Wave 2 needs that cap change (plus a corresponding decoupled top-level input threaded through
  `flow.change`'s `building_tdd` arm, the same pattern used for `cargo_scope`/`defect_location`)
  before build-time craft-skill preservation is possible through the `build_mode=='tdd'` path.
