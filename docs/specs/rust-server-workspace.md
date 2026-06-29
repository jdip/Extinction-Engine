# Rust Server Workspace Spec

## Research

The repository is currently a greenfield contract, workflow scripts, and
documentation. `server-rust/Cargo.toml` does not exist, so the aggregate local
validation script skips Rust format, clippy, and tests.

The handoff document defines Milestone 0 as a server-first foundation and lists
the first implementation task as a Rust workspace with crates for simulation,
protocol, server runtime, persistence, and tools. `AGENTS.md` requires the Rust
simulation crate to stay pure, deterministic where practical, and free of
Unreal dependencies.

The user expanded the goal after the initial scaffold: keep going until there
is a server and client, and the client can join the server with a basic avatar
that can move around. Unreal Engine 5.8 is installed at
`C:\Program Files\Epic Games\UE_5.8`, with `Build.bat` available for C++
project validation.

Risk areas are workspace boundary drift, introducing unnecessary dependencies
before the local server loop needs them, and creating generated or binary
artifacts that should stay ignored.

During validation, the new Rust workspace exposed that the aggregate validation
helper treated successful native stderr output from Cargo as a failed PowerShell
exception. That workflow issue needed to be fixed for Rust checks to become
usable through the required repository entrypoint.

For the join-and-move slice, the safest minimum is a local TCP development
protocol with text lines: a client joins, receives a player ID, sends movement
intent, and receives authoritative avatar state. The Rust CLI tool can prove
the server loop in automation; the Unreal client can share the same line
protocol and provide the visible avatar.

After the first playable run, the avatar could connect and move, but the camera
and controls were still scaffold-quality: movement was world-axis based, the
camera was fixed in an angled third-person view, and there was no in-game
diagnostic overlay or escape menu. The next client pass needs to keep Rust
authoritative over position while making the Unreal client responsible for
presentation feel: camera-relative movement intent, mouse-controlled view, a
basic diagnostic HUD, and a quit menu.

The next requested slice replaces the sphere stand-in with a bundled Unreal
human avatar and proves that the server can host additional controllable
players. Unreal Engine 5.8 has default mannequin content in installed engine
plugins; `NetworkPredictionExtras` contains a compact UE mannequin mesh without
requiring the larger experimental Mover sample stack. The Unreal client must
render non-local avatars from authoritative snapshots, otherwise a Rust swarm
client can join and move other players but the world will not show them.

Follow-up interactive feedback exposed several presentation and protocol
problems in the multiplayer slice. The client currently sends movement every
render frame, while the server applies every movement command in the next
server tick; this makes player speed depend on client frame rate and feel far
too fast. Remote player facing is inferred from movement deltas in Unreal
instead of tracked as authoritative player state. Avatars also persist after a
client or bot disconnects, so stale disconnected players can remain visible as
standing mannequins. The bundled `NetworkPredictionExtras` content includes
UE4 mannequin idle and run animation clips that match the current mesh, so the
thin client can use those clips as a temporary single-node animation setup.
Player avatars also need basic server-side collision: players should not pass
through each other, but walking into another player should create a slow,
bounded nudge rather than a hard immovable wall.

## Plan

- Create `server-rust/` as a Cargo workspace with `dino_sim`,
  `dino_protocol`, `dino_persistence`, `dino_server`, and `dino_tools`.
- Keep the first pass dependency-light and server-first: pure sim types,
  versioned protocol value types, a tiny persistence metadata shape, and
  minimal runnable server/tool binaries.
- Add deterministic tests for seed stability, command divergence, and tick
  advancement in the simulation crate.
- Fix the validation helper if enabling Cargo checks exposes wrapper-level
  failures unrelated to the Rust commands themselves.
- Add README documentation that explains crate responsibilities and the
  validation commands.
- Rollback is a clean revert of the new `server-rust/` tree, this spec, and
  any validation helper adjustment made solely to support the Rust checks.
- Extend `dino_sim` with deterministic avatar/player state and movement
  commands.
- Extend `dino_protocol` with join/move text-line commands and authoritative
  avatar snapshots.
- Replace the `dino_server` smoke-only binary with a local TCP server that owns
  world state and broadcasts snapshots.
- Extend `dino_tools` with a connect-and-move smoke client for automated proof.
- Add a minimal `client-unreal/` C++ project pinned to Unreal 5.8, with a pawn
  that connects to the Rust server, sends input movement, and applies server
  avatar snapshots.
- Add Git LFS attributes for Unreal binary assets before any future `.uasset`
  or `.umap` files are tracked.
- Refine the Unreal pawn to use over-the-shoulder mouse-look camera controls.
- Convert WASD into server movement intent relative to the camera yaw so W is
  forward and S is backward from the current view.
- Add a lightweight C++ HUD for FPS, connection, player ID, server tick/hash,
  and authoritative avatar position.
- Add a player controller that toggles an Esc menu with a clickable Quit button.
- Validate with Unreal builds and the existing Rust/Unreal auto-smoke path;
  manually bring up the runtime for interactive confirmation after validation.
- Enable the bundled Unreal plugin content needed for a default mannequin mesh
  and replace the local sphere stand-in with a skeletal human avatar.
- Render remote snapshot players with the same mannequin mesh so bot players
  controlled by tools are visible in the thin client.
- Extend `dino_tools` with a swarm/circle client that joins multiple players on
  one test connection and continuously sends movement commands with phase
  offsets.
- Validate the swarm client against a local server and confirm Unreal still
  builds and auto-smokes with the new avatar code.
- Change movement from frame-rate-amplified command application to one
  authoritative movement intent per player per server tick.
- Add explicit facing yaw and moving state to avatar simulation and snapshots,
  and include facing yaw in movement commands.
- Remove a disconnected client's owned avatars from the authoritative world so
  stale players disappear from subsequent snapshots.
- Apply deterministic per-player colors in Unreal and drive idle/run mannequin
  animation from authoritative moving state.
- Cap the Unreal client frame rate at 144 FPS through runtime settings and
  config.
- Add deterministic avatar collision resolution in `dino_sim`: avatars have a
  collision radius, overlapping pairs are separated server-side, and the
  separation is capped per tick so pushing another player is slow and visible.

## Implement

Created `server-rust/` as a Cargo workspace with the five required crates.

`dino_sim` now provides a pure deterministic nucleus: seedable world creation,
simulation time, stable entity IDs, a seedable deterministic RNG abstraction,
minimal building commands, player/avatar state, fixed-tick movement command
application, and a stable state hash.

`dino_protocol` now provides versioned command, event, message, snapshot, and
ID value types plus the text-line development protocol for `ping`, `join`,
`move`, authoritative `joined`, and authoritative `state` messages.

`dino_persistence` now provides save metadata derived from a world state.
`dino_server` now runs a local TCP authoritative world server, accepts join and
movement commands, advances fixed ticks, and broadcasts compact avatar
snapshots. `dino_tools` now includes a connect-and-move smoke client that proves
the protocol loop without Unreal.

Created `client-unreal/` as a minimal Unreal 5.8 C++ project. The project has a
default game mode, a simple sphere avatar pawn with camera, a local TCP socket
client, WASD movement intent sent to the Rust server, and server-state
application back onto the avatar position. Added an `-ExtinctionAutoSmoke`
runtime mode for validation: it joins a Rust server, sends movement, waits for
authoritative movement, logs success, and exits.

Updated the Unreal client interaction pass after the first playable run:

- Replaced the fixed angled camera with an over-the-shoulder camera attached to
  the avatar.
- Added mouse-look yaw and pitch on the pawn, with camera-relative WASD
  movement intent converted back into the Rust server's compact integer
  movement axes.
- Added a C++ player controller for Esc menu toggling and click handling.
- Added a Canvas HUD with FPS, server endpoint/connection state, player ID,
  server tick/hash, avatar count, authoritative position, and view angles.
- Added an Esc menu overlay with a clickable Quit button.
- Kept the server authoritative over avatar position; the Unreal changes only
  affect presentation, input interpretation, and local UI.

Added Git LFS attributes for future Unreal binary assets. No `.uasset` or
`.umap` files were committed in this pass.

Updated the avatar and multi-player smoke slice:

- Enabled the bundled `NetworkPredictionExtras` Unreal plugin for access to
  the installed UE mannequin mesh without importing binary template assets into
  the project.
- Replaced the local sphere stand-in with a skeletal mannequin component while
  preserving the server-authoritative position and over-the-shoulder camera.
- Added remote avatar visualization: each non-local player in a server snapshot
  spawns or updates a lightweight mannequin actor, and stale remote actors are
  pruned when they disappear from snapshots.
- Allowed a single server connection to own multiple joined player IDs, while
  still rejecting movement for unowned IDs.
- Extended `dino_tools` with
  `--circle-clients <addr> [--players N] [--ticks N]`, which joins multiple bot
  players and drives them through phase-offset eight-direction loops.
- Added small Rust tests for the circle movement phase function and a runtime
  Unreal log line when remote avatars spawn.
- Tuned mouse-look after interactive feedback: the default sensitivity was
  increased and vertical mouse input was flipped so moving the mouse up looks
  up and moving it down looks down.
- Updated the multiplayer movement/presentation slice after interactive
  feedback:
  - `dino_sim` now stores avatar facing yaw and moving state, applies only the
    latest movement intent per player per server tick, lowers the per-tick
    movement speed, normalizes diagonal movement, and resolves player-player
    collision with a deterministic collision radius and capped slow push.
  - `dino_protocol` is now protocol version 2 for the text-line dev protocol:
    `move` carries facing yaw, and avatar snapshots carry facing yaw plus
    moving state.
  - `dino_server` now queues `LeavePlayer` commands for every player owned by
    a dropped client connection, so disconnected clients and completed bot
    tools stop leaving stale standing avatars in the world.
  - `dino_tools --circle-clients` now sends yaw with movement and validates
    bot movement through the authoritative moving flag.
  - The Unreal pawn sends camera yaw with movement, parses the richer snapshot
    shape, rotates remote avatars from server yaw, and switches local/remote
    mannequin single-node animation between bundled idle and run clips.
  - Unreal now applies deterministic per-player colors through dynamic
    material parameters and a small colored marker, and caps frame rate to 144
    FPS in runtime code plus `DefaultEngine.ini`.

Updated `scripts/lib/WorkflowCommon.ps1` so validation command capture preserves
the native command exit code while allowing successful native stderr output.
This prevents Cargo progress output from falsely failing aggregate validation.

## Test

Added Rust unit tests for:

- same seed plus same commands producing the same state hash
- same seed plus different commands producing a different state hash
- predictable tick advancement
- joined avatar movement with clamped axes
- protocol constructors carrying the current protocol version
- protocol text-line parsing and encoding for join, move, and state snapshots
- protocol version 2 parsing/encoding for movement yaw plus snapshot yaw and
  moving state
- one movement intent per player per tick, using the latest intent
- player leave removing the authoritative avatar
- player-player collision preventing overlap while allowing capped slow push
- server helper coverage for queuing leave commands for all players owned by a
  dropped connection
- circle-client yaw mapping for scripted bot movement
- persistence metadata preserving save version, seed, tick, and state hash

Existing repository validation continues to check specs, remediation records,
retrospectives, whitespace, and now the Rust workspace because
`server-rust/Cargo.toml` exists.

The aggregate validation run also covers the validation helper change by
running the previously failing Cargo clippy and test steps through the wrapper.

The join-and-move slice has two runtime smoke paths:

- `dino_tools --connect <addr>` connects to `dino_server`, joins, moves, and
  checks the authoritative avatar position.
- `dino_tools --circle-clients <addr> --players <n> --ticks <n>` connects to
  `dino_server`, joins multiple bot players through one owned test connection,
  sends repeated movement commands, and checks that all bot avatars moved.
- Unreal `-game -ExtinctionAutoSmoke -ExtinctionPort=<port>` loads the client
  pawn, joins the Rust server, sends movement, and checks the authoritative
  position from the server state line.
- Unreal build validation covers the HUD/player-controller integration and the
  over-the-shoulder camera code. The current auto-smoke covers runtime join and
  movement after those additions, and the bot-backed auto-smoke also exercises
  remote avatar spawn/update from server snapshots. It does not synthesize
  mouse motion or click the Esc menu.

## Validate

- `cd server-rust; cargo fmt --all --check` initially failed with formatting
  diffs only; `cargo fmt --all` was run to apply rustfmt.
- `cd server-rust; cargo fmt --all --check` passed after formatting.
- `cd server-rust; cargo clippy --workspace --all-targets -- -D warnings`
  passed.
- `cd server-rust; cargo test --workspace` passed: 9 unit tests passed.
- `cd server-rust; cargo run -p dino_server -- --smoke` passed and printed
  `dino_server smoke: seed=1000001 tick=2 avatars=1 hash=d6a0aac177021844`.
- `cd server-rust; cargo run -p dino_tools -- --help` passed and printed CLI
  help. It briefly waited on the Cargo build directory lock because the smoke
  binaries were run in parallel, then completed successfully.
- `cd server-rust; cargo run -p dino_tools` passed and printed a deterministic
  smoke snapshot at tick 1.
- Started `target\debug\dino_server.exe --addr 127.0.0.1:7907`, then ran
  `target\debug\dino_tools.exe --connect 127.0.0.1:7907`; passed with
  `dino_tools connect smoke: player=1 tick=4 pos=(15, 0, 0) hash=9d73f3945036d838`.
- Unreal editor build passed:
  `Build.bat ExtinctionEngineEditor Win64 Development -Project=client-unreal\ExtinctionEngine.uproject -WaitMutex -NoHotReloadFromIDE`.
- Unreal standalone client target build passed:
  `Build.bat ExtinctionEngine Win64 Development -Project=client-unreal\ExtinctionEngine.uproject -WaitMutex -NoHotReloadFromIDE`.
- Initial Unreal commandlet smoke attempts were rejected as proof. The editor
  commandlet path loaded editor modules before `Main` and hit Slate/GEditor
  assertions under `-nullrhi`. The standalone game commandlet path was also not
  counted because it hit uncooked asset-registry startup before the commandlet
  logic. The retained proof path is the editor-hosted game runtime smoke.
- Unreal runtime smoke passed with a Rust server on `127.0.0.1:7912` and:
  `UnrealEditor-Cmd.exe client-unreal\ExtinctionEngine.uproject -game -ExtinctionAutoSmoke -ExtinctionPort=7912 -unattended -nop4 -nosplash -nullrhi -nosound -stdout -FullStdOutLogOutput`.
  The Unreal log contained
  `Extinction auto smoke joined and moved player 1 to (15, 0, 0)`, and the Rust
  server log contained `player joined: unreal_auto_smoke -> 1`.
- After the camera/HUD/menu pass, Unreal editor build passed:
  `Build.bat ExtinctionEngineEditor Win64 Development -Project=client-unreal\ExtinctionEngine.uproject -WaitMutex -NoHotReloadFromIDE`.
- After the camera/HUD/menu pass, Unreal standalone client target build passed:
  `Build.bat ExtinctionEngine Win64 Development -Project=client-unreal\ExtinctionEngine.uproject -WaitMutex -NoHotReloadFromIDE`.
- After the camera/HUD/menu pass, Unreal runtime smoke passed with a Rust server
  on `127.0.0.1:7913`; the Unreal log contained
  `Extinction auto smoke joined and moved player 1 to (15, 0, 0)` and no
  critical errors.
- `./scripts/Invoke-LocalValidation.ps1` initially failed because the
  validation wrapper treated Cargo's successful stderr progress output as a
  PowerShell error.
- After updating `scripts/lib/WorkflowCommon.ps1`, `./scripts/Invoke-LocalValidation.ps1`
  passed, including Rust format, clippy, and tests.
- Final `./scripts/Invoke-LocalValidation.ps1` passed after the Unreal client
  and runtime smoke changes, including durable spec validation, Rust format,
  clippy, and tests.
- `cd server-rust; cargo fmt --all --check` passed after the bot-client and
  multi-owner server changes.
- `cd server-rust; cargo clippy --workspace --all-targets -- -D warnings`
  passed after the bot-client and multi-owner server changes.
- `cd server-rust; cargo test --workspace` passed after the bot-client changes:
  11 unit tests passed.
- `cd server-rust; cargo build -p dino_server -p dino_tools` passed and rebuilt
  the runnable development binaries.
- Started `target\debug\dino_server.exe --addr 127.0.0.1:7921`, then ran
  `target\debug\dino_tools.exe --circle-clients 127.0.0.1:7921 --players 4 --ticks 64`;
  passed with
  `dino_tools circle clients: players=4 ticks=64 server_tick=99 avatars=4 hash=8a52d98ded94f364`.
- After the mannequin and remote avatar pass, Unreal editor build passed:
  `Build.bat ExtinctionEngineEditor Win64 Development -Project=client-unreal\ExtinctionEngine.uproject -WaitMutex -NoHotReloadFromIDE`.
- After the mannequin and remote avatar pass, Unreal standalone client target
  build passed:
  `Build.bat ExtinctionEngine Win64 Development -Project=client-unreal\ExtinctionEngine.uproject -WaitMutex -NoHotReloadFromIDE`.
- Bot-backed Unreal runtime smoke passed with a Rust server on
  `127.0.0.1:7923`, three `dino_tools --circle-clients` bots, and:
  `UnrealEditor-Cmd.exe client-unreal\ExtinctionEngine.uproject -game -ExtinctionAutoSmoke -ExtinctionPort=7923 -unattended -nop4 -nosplash -nullrhi -nosound -stdout -FullStdOutLogOutput`.
  The Unreal log contained `Extinction spawned remote avatar 1`,
  `Extinction spawned remote avatar 2`, `Extinction spawned remote avatar 3`,
  and `Extinction auto smoke joined and moved player 4 to (15, 0, 0)`.
  The Rust server log contained joins for `circle_bot_1`, `circle_bot_2`,
  `circle_bot_3`, and `unreal_auto_smoke`.
- Residual risk: the bundled `NetworkPredictionExtras` mannequin loads and
  renders, but Unreal logs warnings that several plugin assets were saved with
  an empty engine version and that one optional Rig class is unavailable. This
  is acceptable for the current dev-only visual stand-in, but a later asset
  pass should replace it with project-owned mannequin assets or a purpose-built
  avatar package.
- Final `./scripts/Invoke-LocalValidation.ps1` passed after the mannequin,
  remote avatar, circle-client, and spec updates, including durable spec
  validation, Rust format, clippy, and tests.
- After mouse-look feedback, the Unreal input-only patch was validated with an
  editor target rebuild. Full Rust validation was not rerun because no Rust,
  protocol, persistence, or server-authoritative behavior changed.
- `cd server-rust; cargo fmt --all --check` passed after protocol v2, movement
  dedupe, leave cleanup, and collision changes.
- `cd server-rust; cargo clippy --workspace --all-targets -- -D warnings`
  passed after protocol v2, movement dedupe, leave cleanup, and collision
  changes.
- `cd server-rust; cargo test --workspace` passed after protocol v2 and
  collision changes: 16 unit tests passed.
- `cd server-rust; cargo build -p dino_server -p dino_tools` initially failed
  because the old live `dino_server.exe` and `dino_tools.exe` processes were
  still running and locking the target executables. After stopping the live
  session, the same build passed.
- After the protocol v2 and presentation pass, Unreal editor build passed:
  `Build.bat ExtinctionEngineEditor Win64 Development -Project=client-unreal\ExtinctionEngine.uproject -WaitMutex -NoHotReloadFromIDE`.
- After the protocol v2 and presentation pass, Unreal standalone client target
  build passed:
  `Build.bat ExtinctionEngine Win64 Development -Project=client-unreal\ExtinctionEngine.uproject -WaitMutex -NoHotReloadFromIDE`.
- Bot-backed Unreal runtime smoke passed with a Rust server on
  `127.0.0.1:7930`, three `dino_tools --circle-clients` bots, and:
  `UnrealEditor-Cmd.exe client-unreal\ExtinctionEngine.uproject -game -ExtinctionAutoSmoke -ExtinctionPort=7930 -unattended -nop4 -nosplash -nullrhi -nosound -stdout -FullStdOutLogOutput`.
  The Unreal log contained remote avatar spawns for players 1, 2, and 3, and
  `Extinction auto smoke joined and moved player 4 to (329, -3, 0)`.
- Started `target\debug\dino_server.exe --addr 127.0.0.1:7931`, then ran
  `target\debug\dino_tools.exe --circle-clients 127.0.0.1:7931 --players 4 --ticks 64`;
  passed with
  `dino_tools circle clients: players=4 ticks=64 server_tick=98 avatars=4 hash=a91443cae22004e5`.
- Attempted an ad hoc socket-level disconnect cleanup smoke, but the harness
  failed before producing useful output with Windows access denied while
  launching/opening local sockets from the sandbox. The disconnect cleanup is
  still covered by `dino_sim` leave removal tests and a `dino_server` unit test
  that dropped-client cleanup queues leave commands for all owned players.
- Final `./scripts/Invoke-LocalValidation.ps1` passed after the protocol v2,
  movement, collision, animation/color, FPS cap, and spec updates, including
  durable spec validation, Rust format, clippy, and tests.
