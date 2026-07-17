---
name: react-plan
description: Use when the user is about to build a React feature or change and wants render-purity/state-modeling/Effects-discipline/stable-identity guidance BEFORE writing code -- so the implementation is born clean instead of caught later by react-review. Invoked as `/react-plan <feature description>`. Delegates to the praxec cognitive-architectures suite (cap.plan.react-feature) -- this skill does not design the feature itself.
---

# React feature planning (anti-pattern prevention)

This skill is a thin front door onto `cap.plan.react-feature` in
`cognitive-architectures` (design:
`docs/react-antipatterns.review-plan-fix.md`), the PROACTIVE half of the
React anti-pattern suite: the same catalog `react-review` detects against,
inverted from "did this happen" to "make sure this doesn't." It drives the
capability via the `praxec` MCP tool (SPEC §32: `praxec.query` for reads,
`praxec.command` for start/submit).

**Announce at start:** "I'm using the react-plan skill to get React planning
constraints for this feature before we start building."

## Steps

1. **Parse the invocation.** `$ARGUMENTS` is the feature/change description
   (free text -- what is being built, not how). If it is too vague to act on
   (e.g. just "a form"), ask one clarifying question about what state/data the
   feature involves rather than guessing.

2. **Start the mission.** Call:
   ```
   praxec.command {
     "definitionId": "cognitive/cap.plan.react-feature",
     "input": { "feature": "<the description>", "context": "<any existing component/state context you already know>" }
   }
   ```

3. **Drive to resolution.** Follow the response's `links`/`_required` hints
   until `result.status` is `succeeded`. This capability has a single agent
   state -- no human gates -- so it should resolve in one hop.

4. **Surface the result to the user before any code is written:**
   - `constraints` -- the concrete, checkable, feature-specific statements
     (state modeling, Effects, stable keys, controlled-input wiring, etc.).
     Present these as the checklist to build against, not as prose to
     summarize away.
   - `guidance` -- the short prose brief.

5. **If the user is planning inside a larger plan graph** (a
   `cap.plan.build-graph` deliverables DAG), tell them these `constraints` are
   meant to be threaded onto the relevant deliverable's
   `metadata.react_constraints` field, per the design doc -- do not silently
   drop them if a plan-graph step is already in flight.

## What NOT to do

- Do not invent React best-practice advice yourself as a substitute for
  running the capability -- the catalog is deliberately grounded and scoped
  to react.dev guidance, not generic style opinions.
- Do not present `constraints` as optional suggestions if the user is about
  to hand this off to an implementer (human or agent) -- they are meant to be
  checkable gates, not vibes.
