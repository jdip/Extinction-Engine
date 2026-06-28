# Local Proof Workflows

GitHub Actions should not repeat the expensive validation already run locally.
The repository uses local validation plus checked-in proof files. GitHub only
verifies that a proof matches the current PR content.

## Branch Model

- Feature branches are the only place normal work happens.
- `test` receives feature PRs after local validation proof is generated.
- `main` receives promotion PRs from `test` after promotion proof is generated.

The `test` branch cannot exist until the repository has at least one commit.
After the initial commit on `main`, run:

```powershell
./scripts/Bootstrap-TestBranch.ps1
```

## Proof Model

Proof files live under `docs/proofs/` and are intended to be committed.
Local command logs and validation JSON live under `artifacts/` and are ignored.

Each proof binds to:

- proof kind: `pr-to-test` or `promote-to-main`
- target branch: `test` or `main`
- source branch
- subject Git commit and tree
- SHA-256 digest of the tracked Git index manifest, excluding `docs/proofs/`
- local validation result and command evidence summary

The verifier recomputes the Git index manifest digest for the PR head,
excluding `docs/proofs/`, and accepts the proof only when the digest matches.
This keeps proof verification stable across Windows and Linux line-ending
checkouts, and lets proof files be committed after validation without
invalidating the content that was tested.

Detached GPG signatures are optional at first. Use `-Sign` when preparing a
proof. Once trusted public keys are documented, set
`REQUIRE_PROOF_SIGNATURE` to `true` in the GitHub verification workflow.

## Feature PR To Test

From a clean feature branch:

```powershell
./scripts/Prepare-PrToTest.ps1
```

This command runs local validation, creates or reuses a matching proof, commits
generated proof files when needed, pushes the feature branch, creates or
updates the PR to `test`, waits for GitHub proof verification, and merges the
PR into `test`.

The GitHub gate only runs:

```powershell
./scripts/Verify-Proof.ps1 -Kind pr-to-test -TargetBranch test
```

## Promote Test To Main

From a clean `test` branch:

```powershell
./scripts/Prepare-PromoteToMain.ps1
```

This command prepares the promotion PR but does not merge by default. To merge
to `main`, use the explicit approval phrase:

```powershell
./scripts/Prepare-PromoteToMain.ps1 -ConfirmPromotion "promote test to main"
```

The GitHub gate only runs:

```powershell
./scripts/Verify-Proof.ps1 -Kind promote-to-main -TargetBranch main
```

## Remediation Records

Open remediation records live in `docs/remediation/open/`. Closed,
cancelled, and transferred records live in `docs/remediation/done/`.

Use helpers instead of hand-writing records when possible:

```powershell
./scripts/New-RemediationRecord.ps1 -Title "Add deterministic replay smoke test" -Owner "Joseph" -Source "PR #12"
./scripts/Close-RemediationRecord.ps1 -Id "REM-20260628-add-deterministic-replay-smoke-test" -Resolution "Added smoke test." -Validation "cargo test --workspace"
```

Every validation run checks remediation record structure.
