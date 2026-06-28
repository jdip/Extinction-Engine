# Retrospective PR Lifecycle Fix

## Research

PR #4 exposed a workflow gap: a retrospective file existed before the PR was
merged, but it did not reflect the completed PR-to-test lifecycle or the
problems encountered during the PR process. The after-PR report also failed to
display the required three retrospective sections.

Current `Prepare-PrToTest.ps1` validates a pre-existing retrospective before PR
creation, which encourages draft records. `Verify-Retrospectives.ps1` validates
shape and proof-source coverage, but does not reject pending/draft
retrospective text.
`AGENTS.md` requires retrospectives after PRs but does not explicitly state
that pre-PR drafts are insufficient or that AGENTS edits must be reloaded.

Follow-up review found two related gaps. Documentation-only lifecycle PRs, such
as retrospective remediation, need an explicit validation escape hatch so they
do not pay for a full product validation suite when only `AGENTS.md` or `docs/`
changed. Durable retrospective documents should also be reserved for material
lessons. A no-op "everything good" reflection belongs in the handoff, not in a
committed file.

Risk areas are branch discipline around post-merge lifecycle records,
maintaining proof-only GitHub gates, and making the PR workflow idempotent after
the merge path writes retrospective evidence. The docs-only escape hatch must
fail closed if non-documentation paths change or if no explicit skip reason is
provided.

## Plan

- Update `AGENTS.md` to require immediate reload after editing AGENTS and to
  clarify post-PR retrospective expectations.
- Tighten retrospective validation so draft/pending records do not pass.
- Update `Prepare-PrToTest.ps1` to stop requiring a retrospective before PR
  creation and instead finalize one after successful merge and local sync.
- Have the PR-to-test script print the three required retrospective sections in
  the completion output.
- Add a docs-only validation profile with an explicit skip reason and path
  guard for `AGENTS.md`/`docs/` changes.
- Only write durable retrospective records when material notes are supplied;
  otherwise print no-op sections in the after-PR report.
- Update docs and helpers to match the new post-merge lifecycle.
- Commit and validate on a feature branch, generate a proof, then run PR-to-test.

Rollback is reverting this branch and restoring the prior retrospective
workflow. The existing PR #4 retrospective and remediation record are normal
documentation changes.

## Implement

Updated the PR-to-test path so retrospectives are not required before PR
creation. After a successful merge and local sync, the script now prints the
three retrospective sections. It writes, docs-only-validates, commits, and
pushes a durable retrospective only when at least one supplied retrospective
section contains material content.

Added `ValidationProfile`/`ValidationSkipReason` plumbing through
`Prepare-PrToTest.ps1`, `New-ValidationProof.ps1`, and
`Invoke-LocalValidation.ps1`. The `docs-only` profile requires an explicit
reason, rejects paths outside `AGENTS.md` and `docs/`, and records Rust checks
as skipped for the supplied reason.

Tightened retrospective validation to reject pending/draft records and no-op
durable retrospectives. `New-Retrospective.ps1` now refuses to create an
all-good record. Documentation now describes the post-PR, material-only
contract, and `AGENTS.md` now requires immediate reload after edits.

## Test

Focused checks:

- PowerShell parse check for edited scripts.
- `./scripts/Verify-Retrospectives.ps1`
- `./scripts/Verify-RemediationRecords.ps1`
- `./scripts/Invoke-LocalValidation.ps1`
- Docs-only positive and negative checks:
  `./scripts/Invoke-LocalValidation.ps1 -Profile docs-only ...` with missing
  skip reason and a non-doc path. The positive docs-only path is exercised by
  the post-merge retrospective finalization during PR-to-test.
- `./scripts/Verify-Proof.ps1 -Kind pr-to-test -TargetBranch test`
- PR-to-test workflow, including post-merge retrospective finalization and
  three-section output.

## Validate

- PowerShell parse check passed for all scripts under `scripts/` and
  `scripts/lib/`.
- `./scripts/Verify-Retrospectives.ps1` passed.
- `./scripts/Verify-RemediationRecords.ps1` passed.
- `./scripts/Verify-Specs.ps1` passed.
- Negative docs-only validation without `-SkipFullValidationReason` failed with
  the expected required-reason error.
- Negative docs-only validation on this branch failed at the docs-only scope
  guard because this branch intentionally changes script paths.
- Negative no-op retrospective creation failed with the expected materiality
  error.
- `./scripts/Invoke-LocalValidation.ps1` passed; Rust format, clippy, and tests
  were skipped because `server-rust/Cargo.toml` does not exist yet.
- The first PR-to-test attempt failed during proof generation because
  `New-ValidationProof.ps1` used array splatting for named PowerShell
  parameters. The script now uses hashtable splatting for
  `Invoke-LocalValidation.ps1`.
- Post-merge review of the PR #5 retrospective found that Markdown backticks
  inside the expandable PowerShell here-string were interpreted as escapes,
  producing tab characters and a literal `$mergedHead`. The generator now uses
  plain text for those generated lines, the retrospective validator rejects tab
  escape artifacts and unresolved merged-head placeholders, and the PR #5
  retrospective was corrected to include the actual merge SHA.
