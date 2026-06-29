pub const PROTOCOL_VERSION: u16 = 2;

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

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ClientCommand {
    pub protocol_version: u16,
    pub payload: ClientCommandPayload,
}

impl ClientCommand {
    pub const fn new(payload: ClientCommandPayload) -> Self {
        Self {
            protocol_version: PROTOCOL_VERSION,
            payload,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ClientCommandPayload {
    Ping,
    Join {
        name: String,
    },
    MoveAvatar {
        player_id: u64,
        x_axis: i8,
        y_axis: i8,
        facing_yaw_degrees: i16,
    },
    BuildPrototype {
        prototype_id: u16,
    },
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ServerMessage {
    pub protocol_version: u16,
    pub payload: ServerMessagePayload,
}

impl ServerMessage {
    pub const fn new(payload: ServerMessagePayload) -> Self {
        Self {
            protocol_version: PROTOCOL_VERSION,
            payload,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ServerMessagePayload {
    Pong,
    Joined { player_id: u64 },
    Snapshot(WorldSnapshot),
    Event(ServerEvent),
    Error { message: String },
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ServerEvent {
    ServerStarted { world_seed: u64 },
    CommandAccepted { command_index: u64 },
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct WorldSnapshot {
    pub protocol_version: u16,
    pub world_seed: u64,
    pub world_tick: u64,
    pub entity_count: u32,
    pub state_hash: u64,
    pub avatars: Vec<AvatarSnapshot>,
}

impl WorldSnapshot {
    pub fn new(
        world_seed: u64,
        world_tick: u64,
        entity_count: u32,
        state_hash: u64,
        avatars: Vec<AvatarSnapshot>,
    ) -> Self {
        Self {
            protocol_version: PROTOCOL_VERSION,
            world_seed,
            world_tick,
            entity_count,
            state_hash,
            avatars,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct AvatarSnapshot {
    pub player_id: u64,
    pub x: i32,
    pub y: i32,
    pub z: i32,
    pub facing_yaw_degrees: i16,
    pub is_moving: bool,
}

impl AvatarSnapshot {
    pub const fn new(
        player_id: u64,
        x: i32,
        y: i32,
        z: i32,
        facing_yaw_degrees: i16,
        is_moving: bool,
    ) -> Self {
        Self {
            player_id,
            x,
            y,
            z,
            facing_yaw_degrees,
            is_moving,
        }
    }
}

pub fn parse_client_line(line: &str) -> Result<ClientCommand, String> {
    let trimmed = line.trim();
    if trimmed.is_empty() {
        return Err("empty command".to_owned());
    }

    if trimmed.eq_ignore_ascii_case("ping") {
        return Ok(ClientCommand::new(ClientCommandPayload::Ping));
    }

    if let Some(name) = trimmed.strip_prefix("join ") {
        let name = name.trim();
        if name.is_empty() {
            return Err("join requires a player name".to_owned());
        }

        return Ok(ClientCommand::new(ClientCommandPayload::Join {
            name: name.to_owned(),
        }));
    }

    let parts: Vec<&str> = trimmed.split_whitespace().collect();
    match parts.as_slice() {
        ["move", player_id, x_axis, y_axis, facing_yaw_degrees] => {
            Ok(ClientCommand::new(ClientCommandPayload::MoveAvatar {
                player_id: parse_u64(player_id, "player_id")?,
                x_axis: parse_i8(x_axis, "x_axis")?,
                y_axis: parse_i8(y_axis, "y_axis")?,
                facing_yaw_degrees: parse_i16(facing_yaw_degrees, "facing_yaw_degrees")?,
            }))
        }
        ["build", prototype_id] => Ok(ClientCommand::new(ClientCommandPayload::BuildPrototype {
            prototype_id: parse_u16(prototype_id, "prototype_id")?,
        })),
        _ => Err(format!("unknown command: {trimmed}")),
    }
}

pub fn parse_server_line(line: &str) -> Result<ServerMessage, String> {
    let trimmed = line.trim();
    if trimmed.is_empty() {
        return Err("empty message".to_owned());
    }

    if trimmed.eq_ignore_ascii_case("pong") {
        return Ok(ServerMessage::new(ServerMessagePayload::Pong));
    }

    if let Some(message) = trimmed.strip_prefix("error ") {
        return Ok(ServerMessage::new(ServerMessagePayload::Error {
            message: message.trim().to_owned(),
        }));
    }

    let parts: Vec<&str> = trimmed.split_whitespace().collect();
    match parts.as_slice() {
        ["joined", player_id] => Ok(ServerMessage::new(ServerMessagePayload::Joined {
            player_id: parse_u64(player_id, "player_id")?,
        })),
        ["state", world_tick, state_hash, avatar_count, remaining @ ..] => {
            let avatar_count = parse_usize(avatar_count, "avatar_count")?;
            let expected_values = avatar_count
                .checked_mul(6)
                .ok_or_else(|| "avatar_count is too large".to_owned())?;
            if remaining.len() != expected_values {
                return Err(format!(
                    "state expected {expected_values} avatar values, got {}",
                    remaining.len()
                ));
            }

            let mut avatars = Vec::with_capacity(avatar_count);
            for chunk in remaining.chunks_exact(6) {
                avatars.push(AvatarSnapshot::new(
                    parse_u64(chunk[0], "avatar_player_id")?,
                    parse_i32(chunk[1], "avatar_x")?,
                    parse_i32(chunk[2], "avatar_y")?,
                    parse_i32(chunk[3], "avatar_z")?,
                    parse_i16(chunk[4], "avatar_facing_yaw_degrees")?,
                    parse_bool_u8(chunk[5], "avatar_is_moving")?,
                ));
            }

            Ok(ServerMessage::new(ServerMessagePayload::Snapshot(
                WorldSnapshot::new(
                    0,
                    parse_u64(world_tick, "world_tick")?,
                    0,
                    parse_hex_u64(state_hash, "state_hash")?,
                    avatars,
                ),
            )))
        }
        _ => Err(format!("unknown message: {trimmed}")),
    }
}

pub fn encode_client_command(command: &ClientCommand) -> String {
    match &command.payload {
        ClientCommandPayload::Ping => "ping\n".to_owned(),
        ClientCommandPayload::Join { name } => format!("join {}\n", sanitize_line_token(name)),
        ClientCommandPayload::MoveAvatar {
            player_id,
            x_axis,
            y_axis,
            facing_yaw_degrees,
        } => {
            format!("move {player_id} {x_axis} {y_axis} {facing_yaw_degrees}\n")
        }
        ClientCommandPayload::BuildPrototype { prototype_id } => {
            format!("build {prototype_id}\n")
        }
    }
}

pub fn encode_server_message(message: &ServerMessage) -> String {
    match &message.payload {
        ServerMessagePayload::Pong => "pong\n".to_owned(),
        ServerMessagePayload::Joined { player_id } => format!("joined {player_id}\n"),
        ServerMessagePayload::Snapshot(snapshot) => {
            let mut line = format!(
                "state {} {:016x} {}",
                snapshot.world_tick,
                snapshot.state_hash,
                snapshot.avatars.len()
            );
            for avatar in &snapshot.avatars {
                line.push_str(&format!(
                    " {} {} {} {} {} {}",
                    avatar.player_id,
                    avatar.x,
                    avatar.y,
                    avatar.z,
                    avatar.facing_yaw_degrees,
                    u8::from(avatar.is_moving)
                ));
            }
            line.push('\n');
            line
        }
        ServerMessagePayload::Event(ServerEvent::ServerStarted { world_seed }) => {
            format!("event server_started {world_seed}\n")
        }
        ServerMessagePayload::Event(ServerEvent::CommandAccepted { command_index }) => {
            format!("event command_accepted {command_index}\n")
        }
        ServerMessagePayload::Error { message } => {
            format!("error {}\n", sanitize_line_message(message))
        }
    }
}

fn sanitize_line_token(value: &str) -> String {
    let sanitized: String = value
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || character == '_' || character == '-' {
                character
            } else {
                '_'
            }
        })
        .collect();

    if sanitized.is_empty() {
        "player".to_owned()
    } else {
        sanitized
    }
}

fn sanitize_line_message(value: &str) -> String {
    value.replace(['\r', '\n'], " ")
}

fn parse_u16(value: &str, name: &str) -> Result<u16, String> {
    value
        .parse::<u16>()
        .map_err(|_| format!("{name} must be a u16"))
}

fn parse_u64(value: &str, name: &str) -> Result<u64, String> {
    value
        .parse::<u64>()
        .map_err(|_| format!("{name} must be a u64"))
}

fn parse_hex_u64(value: &str, name: &str) -> Result<u64, String> {
    u64::from_str_radix(value, 16).map_err(|_| format!("{name} must be a hexadecimal u64"))
}

fn parse_i8(value: &str, name: &str) -> Result<i8, String> {
    value
        .parse::<i8>()
        .map_err(|_| format!("{name} must be an i8"))
}

fn parse_i16(value: &str, name: &str) -> Result<i16, String> {
    value
        .parse::<i16>()
        .map_err(|_| format!("{name} must be an i16"))
}

fn parse_i32(value: &str, name: &str) -> Result<i32, String> {
    value
        .parse::<i32>()
        .map_err(|_| format!("{name} must be an i32"))
}

fn parse_usize(value: &str, name: &str) -> Result<usize, String> {
    value
        .parse::<usize>()
        .map_err(|_| format!("{name} must be a usize"))
}

fn parse_bool_u8(value: &str, name: &str) -> Result<bool, String> {
    match value {
        "0" => Ok(false),
        "1" => Ok(true),
        _ => Err(format!("{name} must be 0 or 1")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn commands_default_to_current_protocol_version() {
        let command = ClientCommand::new(ClientCommandPayload::Ping);

        assert_eq!(command.protocol_version, PROTOCOL_VERSION);
    }

    #[test]
    fn snapshots_carry_current_protocol_version() {
        let snapshot = WorldSnapshot::new(42, 3, 1, 9, Vec::new());

        assert_eq!(snapshot.protocol_version, PROTOCOL_VERSION);
    }

    #[test]
    fn parses_join_and_move_client_lines() {
        let join = parse_client_line("join scout-one").expect("join should parse");
        let movement = parse_client_line("move 7 -1 1 135").expect("move should parse");

        assert_eq!(
            join.payload,
            ClientCommandPayload::Join {
                name: "scout-one".to_owned()
            }
        );
        assert_eq!(
            movement.payload,
            ClientCommandPayload::MoveAvatar {
                player_id: 7,
                x_axis: -1,
                y_axis: 1,
                facing_yaw_degrees: 135,
            }
        );
    }

    #[test]
    fn encodes_and_parses_authoritative_state_lines() {
        let snapshot = WorldSnapshot::new(
            42,
            3,
            1,
            0xabc,
            vec![AvatarSnapshot::new(9, 15, -5, 0, 90, true)],
        );
        let line = encode_server_message(&ServerMessage::new(ServerMessagePayload::Snapshot(
            snapshot,
        )));
        let parsed = parse_server_line(&line).expect("state line should parse");

        assert_eq!(
            parsed.payload,
            ServerMessagePayload::Snapshot(WorldSnapshot::new(
                0,
                3,
                0,
                0xabc,
                vec![AvatarSnapshot::new(9, 15, -5, 0, 90, true)]
            ))
        );
    }
}
