# Extinction Engine Rust Server Workspace

This workspace is the server-authoritative foundation for the game.

## Crates

- `dino_sim`: pure deterministic simulation. It owns seedable world state,
  simulation time, stable entity IDs, command application, and deterministic
  tests. It must not depend on Unreal, networking, persistence, or wall-clock
  time.
- `dino_protocol`: versioned command, event, snapshot, and ID value types for
  command-in/state-out communication.
- `dino_server`: runtime server binary. This first scaffold starts a seeded
  world and emits a development snapshot; networking comes after the simulation
  and protocol contracts settle.
- `dino_persistence`: save-format metadata and persistence boundary types.
- `dino_tools`: developer tooling entrypoint for smoke tests, inspectors,
  protocol debugging, and future deterministic replay helpers.

## Local Validation

Run from this directory:

```powershell
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cargo run -p dino_server
cargo run -p dino_tools -- --help
```

The repository aggregate validation script runs the same Rust checks once this
workspace exists:

```powershell
../scripts/Invoke-LocalValidation.ps1
```

