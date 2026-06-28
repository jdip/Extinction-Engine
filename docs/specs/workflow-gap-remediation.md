# Workflow Gap Remediation

## Research

Current workflow scaffolding already includes local validation, proof creation,
proof verification, remediation records, and PR preparation scripts. The review
found gaps where the AI development contract is documented but not fully
enforced:

- Proof files are accepted without trusted signer enforcement.
- PR retrospectives are required by `AGENTS.md` but not generated or validated.
- Start-of-work sync and merged-branch cleanup are not scripted.
- PR bodies are generic and omit required handoff fields.
- Spec validation only checks headings.
- Checked-in proof JSON includes local absolute repository paths.

Relevant files are `scripts/*.ps1`, `scripts/lib/WorkflowCommon.ps1`,
`.github/workflows/proof-verification.yml`, `AGENTS.md`, `scripts/README.md`,
`docs/workflows/local-proof-workflows.md`, `docs/proofs/`, and
`docs/retrospectives/`.

Risk areas are Git state mutation, proof trust semantics, GPG availability,
validation false positives, stale proof hashes, and accidentally making the
bootstrap workflow impossible before a trusted proof signer is configured.

## Plan

- Add shared helpers for trusted proof signer configuration, signature
  verification, validation result summaries, branch freshness checks, and
  neutral validation environment metadata.
- Add retrospective tooling and validation, then include it in local
  validation.
- Tighten spec validation without requiring heavyweight schema files.
- Add start-of-work and dry-run-first branch cleanup scripts.
- Update proof creation and verification for staged trusted-signature support.
- Update PR preparation scripts to require metadata and build richer PR bodies.
- Update docs and `AGENTS.md` to describe the stricter workflow.
- Scrub existing checked-in proof JSON paths and refresh proof hashes.
- Validate with local validation plus focused negative and signature checks.

Rollback is a normal revert of the branch. The proof-signature rollout remains
staged: GitHub still does not require signatures until trusted signer
fingerprints are committed and `REQUIRE_PROOF_SIGNATURE` is flipped.

## Implement

Implemented workflow remediation across scripts and docs:

- Added trusted proof signer configuration under
  `docs/proofs/trusted-signers/` and staged signature enforcement support in
  proof creation and verification.
- Added retrospective template, creation helper, validator, PR #3 retrospective,
  and metadata on existing retrospective records.
- Added feature-work start and merged-branch cleanup helpers.
- Updated PR preparation scripts to reject stale bases, preserve auto-created
  signatures, require PR metadata, and generate richer handoff bodies.
- Strengthened spec validation and added retrospective validation to local
  validation.
- Scrubbed absolute local paths from historical proof JSON and refreshed proof
  hash sidecars.
- Updated `AGENTS.md`, script docs, workflow docs, and proof docs.

## Test

Checks used:

- Aggregate local validation.
- Script parse pass for all checked-in PowerShell scripts.
- Focused negative checks for empty/template-guidance specs.
- Focused negative checks for malformed retrospectives.
- Unsigned proof verification in Stage A.
- Required-signature failure when no trusted signer is configured.
- Required-signature failure when trusted config exists but signatures are
  missing.
- Historical proof verification after proof JSON scrubbing.

## Validate

- `./scripts/Invoke-LocalValidation.ps1` passed; Rust checks were skipped
  because `server-rust/Cargo.toml` does not exist yet.
- PowerShell parse pass for `scripts/*.ps1` and `scripts/lib/*.ps1` passed
  after fixing a `$Base:` string interpolation issue in `Start-FeatureWork.ps1`.
- `./scripts/Verify-Proof.ps1 -Kind pr-to-test -TargetBranch test` passed after
  proof path scrubbing and hash refresh.
- Focused negative spec validation observed the expected unresolved-marker and
  template-guidance failure.
- Focused negative retrospective validation observed the expected missing
  front-matter failure.
- `./scripts/Verify-Proof.ps1 -Kind pr-to-test -TargetBranch test
  -RequireSignature` failed closed with the expected trusted-signer setup
  message.
- Required-signature verification with a temporary trusted config failed closed
  with the expected missing-signature result.
- Full signed-proof positive-path validation was skipped because `gpg` is not
  installed on PATH in this environment.
