# Workflow Scaffolding Spec

## Research

The project is a greenfield repository for a server-authoritative Unreal and
Rust game. The development contract requires feature-branch work, validation
evidence, branch promotion discipline, and remediation tracking.

The user explicitly wants expensive test execution to stay local. GitHub should
not rerun full validation for PRs or promotions; it should only verify that a
checked-in cryptographic proof matches the PR content.

The repository now has an initial `.gitignore` commit, with `main`, `test`, and
`codex/workflow-scaffolding` branch refs created from that commit.

## Plan

- Add PowerShell scripts for feature-branch guards, local validation, proof
  creation, proof verification, and remediation records.
- Add documentation for the local proof workflow.
- Add remediation and proof directories with templates and README files.
- Add a minimal GitHub Actions workflow that verifies proofs only.
- Keep local validation artifacts ignored and proofs checked in.

## Implement

Implemented scripts under `scripts/`:

- `Ensure-FeatureBranch.ps1`
- `Bootstrap-TestBranch.ps1`
- `Invoke-LocalValidation.ps1`
- `New-ValidationProof.ps1`
- `Prepare-PrToTest.ps1`
- `Prepare-PromoteToMain.ps1`
- `Verify-Proof.ps1`
- remediation create, close, and verify helpers

Implemented docs under `docs/workflows/`, `docs/proofs/`, and
`docs/remediation/`.

Implemented a minimal proof-verification workflow at
`.github/workflows/proof-verification.yml`.

Updated `Prepare-PrToTest.ps1` so the script owns the full PR-to-test path:
validate, create or reuse proof, commit proof artifacts, push the branch, and
create or update the GitHub PR, wait for proof verification, and merge to
`test`.

Updated proof hashing to use the Git index manifest rather than working-tree
bytes, so proof verification is stable across Windows and Linux checkouts.

Updated `Prepare-PromoteToMain.ps1` to use the same proof and PR helpers while
requiring the explicit phrase `promote test to main` before merging.

## Test

Validation should cover:

- feature branch guard accepts `codex/workflow-scaffolding`
- remediation record validator passes
- aggregate local validation passes
- Rust checks are skipped until `server-rust/Cargo.toml` exists
- PR-to-test proof can be generated after the scaffolding commit
- proof verifier accepts the generated proof
- PR-to-test script can be re-run and complete the PR flow without manual
  proof commits or manual PR creation
- GitHub proof verification passes for the PR head
- PR-to-test script merges the PR into `origin/test`

## Validate

- `./scripts/Invoke-LocalValidation.ps1` passed before PR #1 proof generation;
  Rust checks were skipped because `server-rust/Cargo.toml` does not exist yet.
- `./scripts/Prepare-PrToTest.ps1` generated the local proof, pushed the
  feature branch, waited for GitHub proof verification, and merged PR #1 to
  `origin/test`.
- GitHub proof verification passed on PR #1.
- PR #1 merged into `test` as merge commit
  `a0629130920e16bcdf5c6a0cc2a759f15abe5995`.
- Follow-up lifecycle gaps are tracked in `docs/remediation/open/`.
