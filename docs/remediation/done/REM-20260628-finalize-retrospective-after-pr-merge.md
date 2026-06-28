---
id: REM-20260628-finalize-retrospective-after-pr-merge
status: done
owner: Joseph
created: 2026-06-28
source: PR #4 retrospective
closed: 2026-06-28
---

# Finalize Retrospective After PR Merge

## Context

PR #4 exposed that the workflow could validate a pre-existing retrospective
before PR creation, but still fail to produce a true post-PR retrospective
after the merge and proof-check lifecycle was complete. The assistant also
failed to display the three retrospective sections in the after-PR report.

## Remediation

Update the PR-to-test workflow so a successful merge finalizes the
retrospective after the actual PR process. When material findings exist, the
record includes the PR URL, merge outcome, GitHub proof check result, local
sync result, skipped checks, accepted risks, and PR-process findings. When the
reflection is no-op, the after-PR report displays the three sections but the
workflow does not create a low-signal durable file.

## Validation

Run a PR-to-test workflow and confirm material retrospectives are finalized
after the merge, docs-only retrospective validation can skip the full suite
with an explicit reason, and the final report includes the required three
sections.

## Closure

`Prepare-PrToTest.ps1` now writes, validates, commits, pushes, and displays a
post-merge retrospective only when material notes are supplied. Otherwise, it
prints the three retrospective sections without creating a durable file.

## Closure Validation

Covered by `docs/specs/retrospective-pr-lifecycle.md`; final PR-to-test
validation will exercise the post-merge retrospective path.
