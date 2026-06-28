# Trusted Proof Signers

`trusted-proof-signers.json` is the allowlist used when proof signatures are
required.

Stage A keeps the list empty so existing unsigned proof workflows can continue
while signer setup is documented. Stage B should add Joseph's trusted public
key material or fingerprint, then set `REQUIRE_PROOF_SIGNATURE` to `true` in
the GitHub proof-verification workflow.

Fingerprints must be full GPG fingerprints, without short key IDs.
