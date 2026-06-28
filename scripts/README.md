# Local Workflow Scripts

These scripts keep expensive validation local and make GitHub do only cheap
proof verification.

## Branches

- `main`: release branch.
- `test`: integration branch for validated feature work.
- `codex/<task>` or another feature branch: all normal development work.

Use:

```powershell
./scripts/Ensure-FeatureBranch.ps1
```

The repository needs an initial commit before Git can create real branch refs.
After that first commit, create the integration branch with:

```powershell
./scripts/Bootstrap-TestBranch.ps1
```

## PR To Test

From a clean feature branch:

```powershell
./scripts/Prepare-PrToTest.ps1
```

This runs local validation, writes and verifies a proof under
`docs/proofs/pr-to-test/test/`, commits the proof when needed, pushes the
branch, creates or updates the PR to `test`, waits for GitHub proof
verification, and merges the PR into `test`. Local command evidence is written
under `artifacts/validation/`.

## Promote To Main

From a clean `test` branch:

```powershell
./scripts/Prepare-PromoteToMain.ps1
```

This runs local validation, writes a promotion proof under
`docs/proofs/promote-to-main/main/`, pushes `test`, and creates or updates the
promotion PR to `main`. It only merges when called with:

```powershell
./scripts/Prepare-PromoteToMain.ps1 -ConfirmPromotion "promote test to main"
```

## Signatures

Both proof preparation scripts accept `-Sign`, which creates a detached GPG
signature beside the proof. The GitHub verification workflow can require these
signatures later by setting `REQUIRE_PROOF_SIGNATURE` to `true`.

## Remediations

Create a tracked remediation:

```powershell
./scripts/New-RemediationRecord.ps1 -Title "Automate replay smoke test" -Owner "Joseph" -Source "PR #12"
```

Close one:

```powershell
./scripts/Close-RemediationRecord.ps1 -Id "REM-20260628-automate-replay-smoke-test" -Resolution "Added replay smoke test." -Validation "cargo test --workspace"
```

Validate all records:

```powershell
./scripts/Verify-RemediationRecords.ps1
```
