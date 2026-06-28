# AGENTS.md

This repository is for a greenfield biopunk dinosaur factory-defense game:
a first-person Unreal client backed by a Rust authoritative world server.
The core fantasy and architecture are described in
`docs/dino_biopunk_factory_game_codex_handoff.md`. The development operating
model is described in `docs/ai-development-best-practices.md`.

Agents must treat those two documents and this file as the project contract.

## Prime Directive

Build in a way that leaves evidence.

Every meaningful change should be understandable, reviewable, testable, and
easy for the next contributor to continue. Prefer small, deterministic,
server-first milestones over broad feature work.

## Required Start Of Work

Before editing files:

- Read this file and the relevant sections of both docs.
- Check `git status --short`.
- Work on a feature branch. Do not develop directly on `main` or `test`.
- Identify the current task, expected done criteria, and risk areas.
- Preserve human work. Do not overwrite, revert, or reformat unrelated changes.
- For non-trivial work, create or update a short implementation spec before
  coding. Keep it near the work, usually under `docs/specs/`.

For non-trivial specs, include:

- Research: current behavior, constraints, files, risks, unknowns.
- Plan: ordered steps, boundaries, rollback notes, test strategy.
- Implement: changes made and deviations from the plan.
- Test: new/updated tests and relevant existing tests.
- Validate: commands run, environment, results, skipped checks, residual risks.

## Product And Architecture Guardrails

The primary architecture is:

```text
Rust = truth
Unreal = embodiment
Server = world brain
Client = senses and hands
```

The Rust server is authoritative over shared reality:

- world state
- placed buildings
- player inventories
- production state
- belts, pipes, and power networks
- farms and animal populations
- wetware systems
- dinosaur ecology
- combat outcomes
- research
- persistence
- permissions

The Unreal client owns presentation and feel:

- rendering, animation, audio, VFX, UI
- build previews
- local interpolation and temporary prediction
- graceful correction from server state

Do not make Unreal Actors authoritative. Do not model every belt item,
resource packet, farm animal, or machine inventory as a replicated Actor.
Server state should be compact and authoritative; clients reconstruct
convincing visuals locally.

## Milestone Discipline

Follow the milestone order in the handoff document unless the user explicitly
changes priority:

1. Server-first foundation.
2. Minimal factory loop.
3. Minimal defense loop.
4. Disruption and attack generation.
5. Dino farming.
6. Biopunk production.
7. Wetware automation.
8. Unreal thin client vertical slice.
9. Hosted multiplayer prototype.

Do not expand into later backlog work until the current vertical loop is
proven with tests and runtime evidence. Avoid adding many resources, species,
weapons, biomes, or UI surfaces before the server-authoritative
factory-defense loop works.

The first true slice is:

- one small map region
- one player
- resource node, miner, belt, assembler
- ammo, turret, wall
- simple raptor
- disruption value and raptor attack
- save/reload
- basic Unreal visualization

## Repository Shape

Use this target structure unless a later decision updates the contract:

```text
client-unreal/
server-rust/
  Cargo.toml
  crates/
    dino_sim/
    dino_protocol/
    dino_server/
    dino_persistence/
    dino_tools/
  tests/
docs/
tools/
```

Rust crate boundaries:

- `dino_sim`: pure deterministic simulation. No networking, persistence, or
  Unreal dependencies.
- `dino_protocol`: versioned commands, snapshots, deltas, events, IDs, and
  serialization helpers.
- `dino_server`: networking, sessions, scheduling, world loading, admin
  commands, logging, metrics.
- `dino_persistence`: save/load, save versions, migrations, durable storage
  adapters.
- `dino_tools`: headless test client, simulation debugger, world inspector,
  protocol debugger, load tests, deterministic replay tools.

## Rust Simulation Rules

Keep the simulation deterministic wherever practical:

- fixed-tick simulation
- seedable RNG abstraction
- stable entity IDs
- deterministic tests
- explicit simulation time separate from wall-clock time
- no wall-clock reads inside core sim logic
- no hidden global mutable state
- no engine dependency in sim crates

Use structured types and explicit state transitions. Prefer boring, typed Rust
over clever abstractions. Add abstractions only when they remove real
complexity, reduce meaningful duplication, or match an established local
pattern.

For belts and logistics, use compressed server data rather than per-item
physics or per-item networking. The client may render individual moving items
from compressed belt lane state.

## Networking And Protocol Rules

Use command-in, state-out architecture:

- Client sends commands such as build, deconstruct, interact, inventory move,
  weapon fire, movement, chat, and admin commands.
- Server validates commands, advances simulation, and emits snapshots, deltas,
  corrections, and events.

Early networking should favor developer speed and debuggability. A local TCP
or WebSocket dev protocol with simple JSON or binary messages is acceptable
for Milestone 0. Do not optimize transport before proving gameplay.

All protocol types must be versioned. Prefer explicit compatibility and
migration paths over silent shape changes.

## Persistence And Hosted World Rules

Design hosted worlds as one world per Rust server process/container.

Persistence should include:

- periodic snapshots
- important-event snapshots where appropriate
- save version
- world seed
- world tick
- a path for old-save migration

Default offline behavior should avoid punishing players for logging off.
Production, farms, research, pressure, and maintenance debt may advance in
abstract, but destructive attacks should wait until players are online unless
an explicit hardcore mode is implemented.

## Game Design Constraints

Keep the game identity intact:

- Automation is survival, not only convenience.
- Every combat problem should eventually become a logistics problem.
- Dinosaurs are ecosystem actors, threats, resources, farm animals, hazards,
  and biological industrial components.
- Use disruption channels, not one generic pollution value.
- Attacks should be explainable through ecology: nests, hunger, prey density,
  noise, heat, light, corpse scent, runoff, temporal anomalies, and related
  pressure.
- Do not create a modern semiconductor fabrication tech tree. The intended
  workaround is wetware and biopunk.
- Biotech should be efficient, renewable, adaptive, weird, and unstable.
- Wetware should provide adaptive automation, not only raw stat increases.

Build debug visibility for ecological events. For any attack, tools should
eventually answer why it happened, which disruption channels contributed, what
source generated it, and why it chose its target.

## Testing And Validation

Tests are risk control. Add focused tests with behavior changes and broaden
validation when touching shared contracts, determinism, persistence, protocol,
combat, ecology, or save formats.

Use the checked-in validation entrypoint when possible:

```powershell
./scripts/Invoke-LocalValidation.ps1
```

Once the Rust workspace exists, expected validation commands are:

```powershell
cd server-rust
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

When relevant, also run:

```powershell
cargo run -p dino_server
cargo run -p dino_tools -- --help
```

Add deterministic tests early:

- same seed plus same commands produces same state hash
- same seed plus different commands produces different state
- tick count advances predictably
- save/load round trip preserves version, seed, tick, and relevant state

Do not claim validation passed unless the command actually ran and passed.
Record skipped checks with reasons.

## Branch And Proof Workflow

Development flows through local proof, not expensive GitHub re-execution:

- Feature branch -> local validation proof -> PR to `test` -> proof gate -> merge to `test`.
- `test` branch -> local promotion proof -> PR to `main` -> proof gate -> explicit approval -> merge to `main`.
- GitHub Actions should only run proof verification gates.

Use:

```powershell
./scripts/Ensure-FeatureBranch.ps1
./scripts/Prepare-PrToTest.ps1
./scripts/Prepare-PromoteToMain.ps1
./scripts/Verify-Proof.ps1 -Kind pr-to-test -TargetBranch test
```

Proof files under `docs/proofs/` are intended to be committed. Local command
logs under `artifacts/` are not. A valid proof must match the current tracked
content digest for the PR head, excluding proof files themselves. The digest
is based on the Git index manifest so it is stable across Windows and Linux
line-ending checkouts.

The `test` branch is the integration branch. Because Git cannot create real
branch refs before the first commit, bootstrap it after the initial commit:

```powershell
./scripts/Bootstrap-TestBranch.ps1
```

## Debug Tools Are Not Optional

Build these early as first-class development aids:

- server tick profiler
- world inspector
- attack reason debugger
- protocol debugger
- deterministic replay from seed, save, and command log

Prefer checked-in scripts or tools for repeated workflows. Scripts should be
idempotent, explicit, safe to rerun, fail fast, and preserve exit codes.

## Security, Secrets, And Destructive Work

- Never commit secrets, tokens, private keys, or real credentials.
- Never log secrets.
- Validate untrusted inputs at system boundaries.
- Require explicit human approval for destructive actions, irreversible data
  changes, production-like environment changes, releases, and branch promotion.
- Treat shared staging, production, or operator-owned environments as read-only
  diagnostic surfaces unless explicitly doing operator recovery.

## Code Review And Handoff Expectations

Before reporting work complete:

- Review the diff for accidental churn.
- Confirm docs changed when commands, contracts, or workflows changed.
- Run the focused validation appropriate to the change.
- Summarize what changed, what passed, what was skipped, and remaining risks.

Pull requests or handoffs should include:

- behavior changes
- validation evidence
- risks and rollback notes
- linked spec or task record when one exists
- destructive or irreversible actions, if any

## Retrospectives And Remediation

After every PR, failed validation, incident, or promotion, capture lessons
using this structure:

1. Friction points that need to be addressed in `AGENTS.md`.
2. Common workflows that should be automated with scripts.
3. Gaps discovered that deserve remediation.

Create remediation records only for material follow-up work. Avoid duplicates.
Each material remediation should have an owner, status, and link to the issue,
spec, PR, or checked-in record where it will be closed. Keep open records in
`docs/remediation/open/` and move them to `docs/remediation/done/` when
implemented, cancelled with rationale, or transferred elsewhere.

## Agent Conduct

- Read before editing.
- Prefer project tools and local patterns.
- Keep progress updates concise and factual.
- Ask questions only when a reasonable assumption would be risky.
- If context may have drifted, re-open the relevant source file.
- If a command fails due to permissions, sandboxing, or environment access, use
  the approved escalation path rather than inventing an unsafe workaround.
- Do not continue long-running validation while editing files that validation
  snapshots.
- Before final reporting, sanity-check that the answer addresses the latest
  user request.
