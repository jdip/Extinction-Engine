---
id: REM-20260628-return-to-test-after-pr-merge
status: done
owner: Joseph
created: 2026-06-28
source: PR 1 retrospective
closed: 2026-06-28

# Return To Test After PR Merge

## Context

After PR #1 merged to `test`, the local checkout remained on the feature branch,
which made the next development turn start from the wrong branch.

## Remediation

Update PR-to-test automation so a successful merge fetches `origin/test`,
switches to local `test`, and fast-forwards it.

## Validation

`./scripts/Prepare-PrToTest.ps1` leaves the checkout on synced `test` after a
successful merge.
## Closure

Prepare-PrToTest.ps1 now syncs and switches to local test after a successful merge.

## Closure Validation

PR #2 merged to test and the script finished with checkout synced on test.
