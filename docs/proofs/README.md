# Proof Files

Checked-in proof files live here.

- `pr-to-test/test/`: local validation proofs for feature PRs targeting `test`.
- `promote-to-main/main/`: local validation proofs for promotion PRs targeting
  `main`.
- `trusted-signers/`: trusted GPG signer configuration for mandatory proof
  signature verification.

Do not store local command logs here. Local validation artifacts belong under
`artifacts/`, which is ignored.

Proof signatures are staged. Unsigned proofs can still pass while
`REQUIRE_PROOF_SIGNATURE` is `false`, but required-signature verification must
have at least one configured trusted fingerprint.
