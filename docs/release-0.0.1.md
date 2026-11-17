# Cognitive Architectures 0.0.1 release receipt

## Distribution

This is the first immutable, git-backed release of the `cognitive-architectures`
Praxec resource pack. Its manifest is `praxec.repo.yaml`, with pack version
`0.0.1`; it is not an npm package. Operators consume the exact release tag by
cloning the repository and pointing their gateway `repos` entry at that checkout.

## Verification

The release candidate must pass the repository's `praxec check (pack loads
clean)` GitHub Actions workflow at the tagged commit. Maintainers may reproduce
the pack validation locally with:

```bash
bash scripts/validate.sh
```

That command requires Praxec 0.0.22 or later, matching the manifest's stated
compatibility floor.

## Fuzz verification (#97)

`bash scripts/fuzz.sh` (the behavioural fuzz that `validate.sh` runs) is clean on this release: all 13 example configs exit 0, with 0 transition-coverage failures and every smoke definition ok (126 definitions for the full-pack configs). This was measured on 2026-11-17 with Praxec built from staging at `b3a613d`, which carries praxec/praxec#310 (deterministic chained output contracts, and repo-lock plus exclusive-pool wiring in the fuzz harness).

Praxec 0.0.53 lacks #310. With it, the same fuzz reports harness findings that are not pack defects: `POOL_LEASE_UNAVAILABLE` for the browser-exclusive definitions, and mock-seeding `INPUT_SCHEMA_VIOLATION` and `GUARD_UNSET_SLOT` errors. `validate.sh` treats fuzz as informational, so it still exits 0 on 0.0.53. A clean fuzz needs the first Praxec release that contains #310.

## Rollback

Because this is the first public pack release, there is no earlier public tag
to downgrade to. To roll back an installation of 0.0.1, restore the gateway
configuration that omitted the pack, remove its `repos` entry, and restart the
gateway. Future releases must retain this tag so operators can instead check
out `v0.0.1` and restart. The GitHub release records the exact commit and
validation workflow URL used for this receipt.

## Issue disposition gate

No ticket is represented as shipped solely by this release note. Before the
release is published, each of #80 through #91 must either link acceptance
evidence and close, or carry a dated defer/reject disposition naming its owner
and next review date. This keeps deferred INCOSE and TRIZ contract work visible
instead of implying that it was delivered by the existing workflow pack.
