#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub struct EntityId(u64);

impl EntityId {
    pub const fn new(value: u64) -> Self {
        Self(value)
    }

    pub const fn get(self) -> u64 {
        self.0
    }
}

#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub struct PlayerId(u64);

impl PlayerId {
    pub const fn new(value: u64) -> Self {
        Self(value)
    }

    pub const fn get(self) -> u64 {
        self.0
    }
}

#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub struct PrototypeId(u16);

impl PrototypeId {
    pub const fn new(value: u16) -> Self {
        Self(value)
    }

    pub const fn get(self) -> u16 {
        self.0
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct SimulationTime {
    tick: u64,
}

impl SimulationTime {
    pub const fn at_tick(tick: u64) -> Self {
        Self { tick }
    }

    pub const fn tick(self) -> u64 {
        self.tick
    }

    fn advance(&mut self) {
        self.tick = self.tick.saturating_add(1);
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct WorldConfig {
    seed: u64,
    max_commands_per_tick: usize,
    avatar_speed_units_per_tick: i32,
    avatar_collision_radius_units: i32,
    avatar_push_units_per_tick: i32,
}

impl WorldConfig {
    pub const fn new(seed: u64) -> Self {
        Self {
            seed,
            max_commands_per_tick: 256,
            avatar_speed_units_per_tick: 8,
            avatar_collision_radius_units: 42,
            avatar_push_units_per_tick: 4,
        }
    }

    pub const fn seed(self) -> u64 {
        self.seed
    }

    pub const fn max_commands_per_tick(self) -> usize {
        self.max_commands_per_tick
    }

    pub const fn avatar_speed_units_per_tick(self) -> i32 {
        self.avatar_speed_units_per_tick
    }

    pub const fn avatar_collision_radius_units(self) -> i32 {
        self.avatar_collision_radius_units
    }

    pub const fn avatar_push_units_per_tick(self) -> i32 {
        self.avatar_push_units_per_tick
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct TickContext {
    time: SimulationTime,
    accepted_commands: usize,
}

impl TickContext {
    pub const fn new(time: SimulationTime, accepted_commands: usize) -> Self {
        Self {
            time,
            accepted_commands,
        }
    }

    pub const fn time(self) -> SimulationTime {
        self.time
    }

    pub const fn accepted_commands(self) -> usize {
        self.accepted_commands
    }
}

pub trait SeedableRng {
    fn from_seed(seed: u64) -> Self;
    fn next_u64(&mut self) -> u64;
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct DeterministicRng {
    state: u64,
}

impl DeterministicRng {
    pub const fn state(self) -> u64 {
        self.state
    }
}

impl SeedableRng for DeterministicRng {
    fn from_seed(seed: u64) -> Self {
        Self {
            state: seed ^ 0x9e37_79b9_7f4a_7c15,
        }
    }

    fn next_u64(&mut self) -> u64 {
        self.state = self.state.wrapping_add(0x9e37_79b9_7f4a_7c15);
        let mut value = self.state;
        value = (value ^ (value >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
        value = (value ^ (value >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
        value ^ (value >> 31)
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PlayerCommand {
    Noop,
    BuildPrototype {
        prototype: PrototypeId,
    },
    JoinPlayer {
        player_id: PlayerId,
    },
    MovePlayer {
        player_id: PlayerId,
        x_axis: i8,
        y_axis: i8,
        facing_yaw_degrees: i16,
    },
    LeavePlayer {
        player_id: PlayerId,
    },
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SimEntity {
    id: EntityId,
    prototype: PrototypeId,
    created_tick: u64,
    spawn_nonce: u64,
}

impl SimEntity {
    pub const fn id(&self) -> EntityId {
        self.id
    }

    pub const fn prototype(&self) -> PrototypeId {
        self.prototype
    }

    pub const fn created_tick(&self) -> u64 {
        self.created_tick
    }

    pub const fn spawn_nonce(&self) -> u64 {
        self.spawn_nonce
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct AvatarPosition {
    x: i32,
    y: i32,
    z: i32,
}

impl AvatarPosition {
    pub const fn new(x: i32, y: i32, z: i32) -> Self {
        Self { x, y, z }
    }

    pub const fn x(self) -> i32 {
        self.x
    }

    pub const fn y(self) -> i32 {
        self.y
    }

    pub const fn z(self) -> i32 {
        self.z
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PlayerAvatar {
    player_id: PlayerId,
    position: AvatarPosition,
    facing_yaw_degrees: i16,
    is_moving: bool,
    joined_tick: u64,
}

impl PlayerAvatar {
    pub const fn player_id(&self) -> PlayerId {
        self.player_id
    }

    pub const fn position(&self) -> AvatarPosition {
        self.position
    }

    pub const fn facing_yaw_degrees(&self) -> i16 {
        self.facing_yaw_degrees
    }

    pub const fn is_moving(&self) -> bool {
        self.is_moving
    }

    pub const fn joined_tick(&self) -> u64 {
        self.joined_tick
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct MoveIntent {
    player_id: PlayerId,
    x_axis: i8,
    y_axis: i8,
    facing_yaw_degrees: i16,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct WorldState {
    config: WorldConfig,
    seed: u64,
    time: SimulationTime,
    rng: DeterministicRng,
    next_entity_id: u64,
    next_player_id: u64,
    accepted_command_count: u64,
    entities: Vec<SimEntity>,
    avatars: Vec<PlayerAvatar>,
}

impl WorldState {
    pub fn new(config: WorldConfig) -> Self {
        Self {
            config,
            seed: config.seed(),
            time: SimulationTime::at_tick(0),
            rng: DeterministicRng::from_seed(config.seed()),
            next_entity_id: 1,
            next_player_id: 1,
            accepted_command_count: 0,
            entities: Vec::new(),
            avatars: Vec::new(),
        }
    }

    pub const fn seed(&self) -> u64 {
        self.seed
    }

    pub const fn time(&self) -> SimulationTime {
        self.time
    }

    pub fn entities(&self) -> &[SimEntity] {
        &self.entities
    }

    pub fn avatars(&self) -> &[PlayerAvatar] {
        &self.avatars
    }

    pub fn avatar(&self, player_id: PlayerId) -> Option<&PlayerAvatar> {
        self.avatars
            .iter()
            .find(|avatar| avatar.player_id() == player_id)
    }

    pub const fn accepted_command_count(&self) -> u64 {
        self.accepted_command_count
    }

    pub fn allocate_player_id(&mut self) -> PlayerId {
        let id = PlayerId::new(self.next_player_id);
        self.next_player_id = self.next_player_id.saturating_add(1);
        id
    }

    pub fn state_hash(&self) -> u64 {
        let mut hash = StableHasher::new();
        hash.write_u64(self.seed);
        hash.write_u64(self.time.tick());
        hash.write_u64(self.rng.state());
        hash.write_u64(self.next_entity_id);
        hash.write_u64(self.next_player_id);
        hash.write_u64(self.accepted_command_count);
        hash.write_u64(self.entities.len() as u64);
        for entity in &self.entities {
            hash.write_u64(entity.id().get());
            hash.write_u64(u64::from(entity.prototype().get()));
            hash.write_u64(entity.created_tick());
            hash.write_u64(entity.spawn_nonce());
        }
        hash.write_u64(self.avatars.len() as u64);
        for avatar in &self.avatars {
            hash.write_u64(avatar.player_id().get());
            hash.write_i32(avatar.position().x());
            hash.write_i32(avatar.position().y());
            hash.write_i32(avatar.position().z());
            hash.write_i16(avatar.facing_yaw_degrees());
            hash.write_bool(avatar.is_moving());
            hash.write_u64(avatar.joined_tick());
        }
        hash.finish()
    }

    fn allocate_entity_id(&mut self) -> EntityId {
        let id = EntityId::new(self.next_entity_id);
        self.next_entity_id = self.next_entity_id.saturating_add(1);
        id
    }
}

pub fn tick_world(world: &mut WorldState, commands: &[PlayerCommand]) -> TickContext {
    let accepted_commands = commands.len();
    let mut move_intents = Vec::new();
    for command in commands {
        world.accepted_command_count = world.accepted_command_count.saturating_add(1);
        match *command {
            PlayerCommand::MovePlayer {
                player_id,
                x_axis,
                y_axis,
                facing_yaw_degrees,
            } => upsert_move_intent(
                &mut move_intents,
                MoveIntent {
                    player_id,
                    x_axis,
                    y_axis,
                    facing_yaw_degrees,
                },
            ),
            command => apply_non_movement_command(world, command),
        }
    }

    for avatar in &mut world.avatars {
        avatar.is_moving = false;
    }
    move_intents.sort_by_key(|intent| intent.player_id.get());
    apply_move_intents(world, &move_intents);
    resolve_avatar_collisions(world);

    world.time.advance();
    TickContext::new(world.time(), accepted_commands)
}

fn upsert_move_intent(move_intents: &mut Vec<MoveIntent>, next_intent: MoveIntent) {
    if let Some(existing_intent) = move_intents
        .iter_mut()
        .find(|intent| intent.player_id == next_intent.player_id)
    {
        *existing_intent = next_intent;
    } else {
        move_intents.push(next_intent);
    }
}

fn apply_non_movement_command(world: &mut WorldState, command: PlayerCommand) {
    match command {
        PlayerCommand::Noop => {}
        PlayerCommand::BuildPrototype { prototype } => {
            let entity = SimEntity {
                id: world.allocate_entity_id(),
                prototype,
                created_tick: world.time().tick(),
                spawn_nonce: world.rng.next_u64(),
            };
            world.entities.push(entity);
        }
        PlayerCommand::JoinPlayer { player_id } => {
            if world.avatar(player_id).is_none() {
                let position = spawn_position_for_join(world);
                world.avatars.push(PlayerAvatar {
                    player_id,
                    position,
                    facing_yaw_degrees: 0,
                    is_moving: false,
                    joined_tick: world.time().tick(),
                });
            }
        }
        PlayerCommand::LeavePlayer { player_id } => {
            world
                .avatars
                .retain(|avatar| avatar.player_id() != player_id);
        }
        PlayerCommand::MovePlayer {
            player_id: _,
            x_axis: _,
            y_axis: _,
            facing_yaw_degrees: _,
        } => unreachable!("movement commands are collected before non-movement application"),
    }
}

fn spawn_position_for_join(world: &WorldState) -> AvatarPosition {
    let spacing = world
        .config
        .avatar_collision_radius_units()
        .saturating_mul(2)
        .saturating_add(20);
    AvatarPosition::new((world.avatars.len() as i32).saturating_mul(spacing), 0, 0)
}

fn apply_move_intents(world: &mut WorldState, move_intents: &[MoveIntent]) {
    let speed = world.config.avatar_speed_units_per_tick();
    for intent in move_intents {
        if let Some(avatar) = world
            .avatars
            .iter_mut()
            .find(|avatar| avatar.player_id() == intent.player_id)
        {
            let x_axis = clamp_axis(intent.x_axis);
            let y_axis = clamp_axis(intent.y_axis);
            avatar.facing_yaw_degrees = normalize_yaw_degrees(intent.facing_yaw_degrees);
            avatar.is_moving = x_axis != 0 || y_axis != 0;
            if avatar.is_moving {
                let (x_delta, y_delta) = movement_delta(x_axis, y_axis, speed);
                avatar.position.x = avatar.position.x.saturating_add(x_delta);
                avatar.position.y = avatar.position.y.saturating_add(y_delta);
            }
        }
    }
}

fn movement_delta(x_axis: i8, y_axis: i8, speed: i32) -> (i32, i32) {
    if x_axis != 0 && y_axis != 0 {
        let diagonal_speed = ((speed.saturating_mul(707) + 500) / 1000).max(1);
        (
            i32::from(x_axis).saturating_mul(diagonal_speed),
            i32::from(y_axis).saturating_mul(diagonal_speed),
        )
    } else {
        (
            i32::from(x_axis).saturating_mul(speed),
            i32::from(y_axis).saturating_mul(speed),
        )
    }
}

fn resolve_avatar_collisions(world: &mut WorldState) {
    const COLLISION_PASSES: usize = 4;

    let minimum_separation = world
        .config
        .avatar_collision_radius_units()
        .saturating_mul(2);
    if minimum_separation <= 0 {
        return;
    }

    let maximum_push = world.config.avatar_push_units_per_tick().max(1);
    for _ in 0..COLLISION_PASSES {
        let mut separated_any_pair = false;
        for left_index in 0..world.avatars.len() {
            for right_index in (left_index + 1)..world.avatars.len() {
                let (left_slice, right_slice) = world.avatars.split_at_mut(right_index);
                let left_avatar = &mut left_slice[left_index];
                let right_avatar = &mut right_slice[0];

                let x_delta = right_avatar.position.x - left_avatar.position.x;
                let y_delta = right_avatar.position.y - left_avatar.position.y;
                let distance_squared = i64::from(x_delta) * i64::from(x_delta)
                    + i64::from(y_delta) * i64::from(y_delta);
                let minimum_squared = i64::from(minimum_separation) * i64::from(minimum_separation);
                if distance_squared >= minimum_squared {
                    continue;
                }

                let (unit_x, unit_y, distance) = if distance_squared == 0 {
                    let (fallback_x, fallback_y) =
                        fallback_collision_axis(left_avatar.player_id, right_avatar.player_id);
                    (fallback_x, fallback_y, 0.0)
                } else {
                    let distance = (distance_squared as f64).sqrt();
                    (
                        f64::from(x_delta) / distance,
                        f64::from(y_delta) / distance,
                        distance,
                    )
                };

                let overlap = (f64::from(minimum_separation) - distance).max(1.0);
                let shift = (overlap * 0.5).ceil().min(f64::from(maximum_push));
                let mut shift_x = (unit_x * shift).round() as i32;
                let shift_y = (unit_y * shift).round() as i32;
                if shift_x == 0 && shift_y == 0 {
                    shift_x = if unit_x >= 0.0 { 1 } else { -1 };
                }

                left_avatar.position.x = left_avatar.position.x.saturating_sub(shift_x);
                left_avatar.position.y = left_avatar.position.y.saturating_sub(shift_y);
                right_avatar.position.x = right_avatar.position.x.saturating_add(shift_x);
                right_avatar.position.y = right_avatar.position.y.saturating_add(shift_y);
                separated_any_pair = true;
            }
        }

        if !separated_any_pair {
            break;
        }
    }
}

fn fallback_collision_axis(left_player_id: PlayerId, right_player_id: PlayerId) -> (f64, f64) {
    match (left_player_id.get().wrapping_mul(31) ^ right_player_id.get()) % 4 {
        0 => (1.0, 0.0),
        1 => (0.0, 1.0),
        2 => (-1.0, 0.0),
        _ => (0.0, -1.0),
    }
}

fn clamp_axis(axis: i8) -> i8 {
    axis.clamp(-1, 1)
}

fn normalize_yaw_degrees(yaw_degrees: i16) -> i16 {
    let mut normalized = i32::from(yaw_degrees) % 360;
    if normalized > 180 {
        normalized -= 360;
    } else if normalized < -180 {
        normalized += 360;
    }

    normalized as i16
}

struct StableHasher {
    hash: u64,
}

impl StableHasher {
    const fn new() -> Self {
        Self {
            hash: 0xcbf2_9ce4_8422_2325,
        }
    }

    fn write_u64(&mut self, value: u64) {
        for byte in value.to_le_bytes() {
            self.hash ^= u64::from(byte);
            self.hash = self.hash.wrapping_mul(0x0000_0100_0000_01b3);
        }
    }

    fn write_i32(&mut self, value: i32) {
        for byte in value.to_le_bytes() {
            self.hash ^= u64::from(byte);
            self.hash = self.hash.wrapping_mul(0x0000_0100_0000_01b3);
        }
    }

    fn write_i16(&mut self, value: i16) {
        for byte in value.to_le_bytes() {
            self.hash ^= u64::from(byte);
            self.hash = self.hash.wrapping_mul(0x0000_0100_0000_01b3);
        }
    }

    fn write_bool(&mut self, value: bool) {
        self.hash ^= u64::from(value);
        self.hash = self.hash.wrapping_mul(0x0000_0100_0000_01b3);
    }

    const fn finish(self) -> u64 {
        self.hash
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run_commands(seed: u64, commands: &[PlayerCommand], ticks: usize) -> WorldState {
        let mut world = WorldState::new(WorldConfig::new(seed));
        for _ in 0..ticks {
            tick_world(&mut world, commands);
        }
        world
    }

    #[test]
    fn same_seed_and_commands_produce_same_state_hash() {
        let commands = [
            PlayerCommand::BuildPrototype {
                prototype: PrototypeId::new(7),
            },
            PlayerCommand::Noop,
        ];

        let first = run_commands(42, &commands, 3);
        let second = run_commands(42, &commands, 3);

        assert_eq!(first.state_hash(), second.state_hash());
        assert_eq!(first, second);
    }

    #[test]
    fn different_commands_produce_different_state_hash() {
        let first = run_commands(
            42,
            &[PlayerCommand::BuildPrototype {
                prototype: PrototypeId::new(7),
            }],
            1,
        );
        let second = run_commands(
            42,
            &[PlayerCommand::BuildPrototype {
                prototype: PrototypeId::new(8),
            }],
            1,
        );

        assert_ne!(first.state_hash(), second.state_hash());
    }

    #[test]
    fn tick_count_advances_predictably() {
        let mut world = WorldState::new(WorldConfig::new(99));

        let first_context = tick_world(&mut world, &[]);
        let second_context = tick_world(&mut world, &[PlayerCommand::Noop]);

        assert_eq!(first_context.time().tick(), 1);
        assert_eq!(second_context.time().tick(), 2);
        assert_eq!(second_context.accepted_commands(), 1);
        assert_eq!(world.time().tick(), 2);
    }

    #[test]
    fn joined_avatar_moves_with_clamped_axes() {
        let mut world = WorldState::new(WorldConfig::new(123));
        let player_id = world.allocate_player_id();

        tick_world(&mut world, &[PlayerCommand::JoinPlayer { player_id }]);
        tick_world(
            &mut world,
            &[PlayerCommand::MovePlayer {
                player_id,
                x_axis: 7,
                y_axis: -2,
                facing_yaw_degrees: 91,
            }],
        );

        let avatar = world.avatar(player_id).expect("avatar should exist");
        assert_eq!(avatar.position(), AvatarPosition::new(6, -6, 0));
        assert_eq!(avatar.facing_yaw_degrees(), 91);
        assert!(avatar.is_moving());
    }

    #[test]
    fn repeated_movement_commands_apply_latest_intent_once_per_tick() {
        let mut world = WorldState::new(WorldConfig::new(123));
        let player_id = world.allocate_player_id();

        tick_world(&mut world, &[PlayerCommand::JoinPlayer { player_id }]);
        tick_world(
            &mut world,
            &[
                PlayerCommand::MovePlayer {
                    player_id,
                    x_axis: 1,
                    y_axis: 0,
                    facing_yaw_degrees: 0,
                },
                PlayerCommand::MovePlayer {
                    player_id,
                    x_axis: 0,
                    y_axis: 1,
                    facing_yaw_degrees: 90,
                },
            ],
        );

        let avatar = world.avatar(player_id).expect("avatar should exist");
        assert_eq!(avatar.position(), AvatarPosition::new(0, 8, 0));
        assert_eq!(avatar.facing_yaw_degrees(), 90);
        assert!(avatar.is_moving());
    }

    #[test]
    fn leaving_player_removes_avatar() {
        let mut world = WorldState::new(WorldConfig::new(123));
        let player_id = world.allocate_player_id();

        tick_world(&mut world, &[PlayerCommand::JoinPlayer { player_id }]);
        tick_world(&mut world, &[PlayerCommand::LeavePlayer { player_id }]);

        assert!(world.avatar(player_id).is_none());
        assert!(world.avatars().is_empty());
    }

    #[test]
    fn avatar_collision_blocks_overlap_and_allows_slow_push() {
        let mut world = WorldState::new(WorldConfig::new(123));
        let first_player_id = world.allocate_player_id();
        let second_player_id = world.allocate_player_id();

        tick_world(
            &mut world,
            &[
                PlayerCommand::JoinPlayer {
                    player_id: first_player_id,
                },
                PlayerCommand::JoinPlayer {
                    player_id: second_player_id,
                },
            ],
        );

        const MINIMUM_SEPARATION: i32 = 84;
        world.avatars[0].position = AvatarPosition::new(0, 0, 0);
        world.avatars[1].position = AvatarPosition::new(MINIMUM_SEPARATION, 0, 0);

        tick_world(
            &mut world,
            &[PlayerCommand::MovePlayer {
                player_id: first_player_id,
                x_axis: 1,
                y_axis: 0,
                facing_yaw_degrees: 0,
            }],
        );

        let first_avatar = world
            .avatar(first_player_id)
            .expect("first avatar should exist");
        let second_avatar = world
            .avatar(second_player_id)
            .expect("second avatar should exist");
        assert_eq!(
            second_avatar.position().x() - first_avatar.position().x(),
            MINIMUM_SEPARATION
        );
        assert_eq!(first_avatar.position().x(), 4);
        assert_eq!(second_avatar.position().x(), 88);
    }
}
