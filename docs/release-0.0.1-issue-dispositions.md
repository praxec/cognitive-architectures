# Cognitive Architectures 0.0.1 issue dispositions

**Decision date:** 2026-10-27  
**Accountable owner:** Praxec Cognitive Architectures maintainers  
**Review date:** 2027-01-26

## Decision rule

Version 0.0.1 releases the validated, git-backed pack foundation.  It does not
claim that an experimental workflow is production-ready merely because its YAML
loads.  Each issue below is therefore deferred, rather than represented as
implemented, until its stated evidence trigger is met.  The owner must either
open a bounded implementation plan or renew this disposition on the review
date, recording the evidence that supports the choice.

## Deferred increments

| Issue | Disposition | Evidence trigger before implementation |
| --- | --- | --- |
| #80 Governed ticket lifecycle | Deferred | A second real target needs the lifecycle and supplies a system-context pack, tracker adapter decision, and acceptance evidence. |
| #81 INCOSE requirements-quality MCP | Deferred | The current two-level vetting misses a requirements-quality decision that deterministic INCOSE checks demonstrably change. |
| #82 TRIZ plus embeddings contradiction MCP | Deferred | The current conflict/alternative review misses a decision that deterministic retrieval or TRIZ analysis demonstrably changes. |
| #83 Ticketing adapter and declarative swim lanes | Deferred | A second tracker or executor domain requires durable tracker synchronization and version-skew evidence. |
| #84 Ticket claim and lease concurrency | Deferred | Concurrent ticket execution is enabled against a tracker-backed lifecycle; the implementation must then prove atomic claim, TTL reclaim, and audit behavior. |
| #85 Incident response and on-call workflow | Deferred | A production incident or on-call operating model supplies a real escalation, ownership, and audit contract. |
| #86 Release, deploy, canary, rollback workflow | Deferred | A deployable target supplies a real canary, rollback, and operational SLO contract beyond this pack's git-release procedure. |
| #87 Resumable migration harness | Deferred | A migration with checkpoint/restart evidence requires worktree-isolated recovery. |
| #88 Unattended CVE and dependency remediation | Deferred | A supported dependency source and security-owner policy exist for automated remediation. |
| #89 Bug to repro to regression-lock workflow | Deferred | A target project provides a reproducible defect corpus and a regression artifact contract. |
| #90 Requirements-to-spec-to-build-to-verify traceability | Deferred | A target supplies stable requirement identifiers and independently auditable end-to-end trace links. |
| #91 LLM eval gate | Deferred | A released LLM-facing feature has representative evaluation data, quality thresholds, and a named decision owner. |

## Release guard

These deferrals do not waive runtime correctness of the pack itself.  Issue #97
tracks the fuzz execution regressions discovered during 0.0.1 preparation and
must be repaired and proven before an immutable 0.0.1 tag and GitHub release
are created.
