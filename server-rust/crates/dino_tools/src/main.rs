use std::io::{self, BufRead, BufReader, Write};
use std::net::{SocketAddr, TcpStream};
use std::time::Duration;

use dino_protocol::{
    encode_client_command, parse_server_line, ClientCommand, ClientCommandPayload,
    ServerMessagePayload, WorldSnapshot,
};
use dino_sim::{tick_world, PlayerCommand, PrototypeId, WorldConfig, WorldState};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.iter().any(|arg| arg == "--help" || arg == "-h") {
        print_help();
        return;
    }

    match parse_mode(&args).unwrap_or_else(|message| {
        eprintln!("{message}");
        std::process::exit(2);
    }) {
        ToolMode::DeterministicSmoke => {
            let snapshot = run_deterministic_smoke();
            println!(
                "dino_tools deterministic smoke: seed={} tick={} entities={} hash={:016x}",
                snapshot.world_seed,
                snapshot.world_tick,
                snapshot.entity_count,
                snapshot.state_hash,
            );
        }
        ToolMode::ConnectSmoke { addr } => match run_connect_smoke(addr) {
            Ok(snapshot) => {
                let avatar = snapshot
                    .avatars
                    .first()
                    .expect("connect smoke should return an avatar");
                println!(
                    "dino_tools connect smoke: player={} tick={} pos=({}, {}, {}) hash={:016x}",
                    avatar.player_id,
                    snapshot.world_tick,
                    avatar.x,
                    avatar.y,
                    avatar.z,
                    snapshot.state_hash,
                );
            }
            Err(error) => {
                eprintln!("dino_tools connect smoke failed: {error}");
                std::process::exit(1);
            }
        },
        ToolMode::CircleClients {
            addr,
            player_count,
            ticks,
        } => match run_circle_clients(addr, player_count, ticks) {
            Ok(snapshot) => {
                println!(
                    "dino_tools circle clients: players={} ticks={} server_tick={} avatars={} hash={:016x}",
                    player_count,
                    ticks,
                    snapshot.world_tick,
                    snapshot.avatars.len(),
                    snapshot.state_hash,
                );
            }
            Err(error) => {
                eprintln!("dino_tools circle clients failed: {error}");
                std::process::exit(1);
            }
        },
    }
}

fn print_help() {
    println!(
        "dino_tools\n\nUSAGE:\n    dino_tools [--help]\n    dino_tools --connect 127.0.0.1:7007\n    dino_tools --circle-clients 127.0.0.1:7007 [--players 4] [--ticks 240]\n\nRuns a deterministic local smoke, connects to a dino_server and verifies join plus movement, or controls several joined bot players in looping movement."
    );
}

enum ToolMode {
    DeterministicSmoke,
    ConnectSmoke {
        addr: SocketAddr,
    },
    CircleClients {
        addr: SocketAddr,
        player_count: usize,
        ticks: u64,
    },
}

fn run_deterministic_smoke() -> WorldSnapshot {
    let mut world = WorldState::new(WorldConfig::new(7));
    tick_world(
        &mut world,
        &[PlayerCommand::BuildPrototype {
            prototype: PrototypeId::new(2),
        }],
    );

    WorldSnapshot::new(
        world.seed(),
        world.time().tick(),
        world.entities().len() as u32,
        world.state_hash(),
        Vec::new(),
    )
}

fn parse_mode(args: &[String]) -> Result<ToolMode, String> {
    let connect_addr = parse_socket_arg(args, "--connect")?;
    let circle_addr = parse_socket_arg(args, "--circle-clients")?;
    match (connect_addr, circle_addr) {
        (Some(_), Some(_)) => Err("--connect and --circle-clients cannot be combined".to_owned()),
        (Some(addr), None) => Ok(ToolMode::ConnectSmoke { addr }),
        (None, Some(addr)) => Ok(ToolMode::CircleClients {
            addr,
            player_count: parse_usize_arg(args, "--players", 4)?,
            ticks: parse_u64_arg(args, "--ticks", 240)?,
        }),
        (None, None) => Ok(ToolMode::DeterministicSmoke),
    }
}

fn parse_socket_arg(args: &[String], flag: &str) -> Result<Option<SocketAddr>, String> {
    let mut index = 0;
    while index < args.len() {
        if args[index] == flag {
            let value = args
                .get(index + 1)
                .ok_or_else(|| format!("{flag} requires a socket address"))?;
            return value
                .parse::<SocketAddr>()
                .map(Some)
                .map_err(|_| format!("invalid {flag} value: {value}"));
        }
        index += 1;
    }

    Ok(None)
}

fn parse_usize_arg(args: &[String], flag: &str, default_value: usize) -> Result<usize, String> {
    let value = parse_optional_arg(args, flag)?
        .map(|value| {
            value
                .parse::<usize>()
                .map_err(|_| format!("{flag} must be a positive integer"))
        })
        .transpose()?
        .unwrap_or(default_value);
    if value == 0 {
        return Err(format!("{flag} must be greater than zero"));
    }
    Ok(value)
}

fn parse_u64_arg(args: &[String], flag: &str, default_value: u64) -> Result<u64, String> {
    let value = parse_optional_arg(args, flag)?
        .map(|value| {
            value
                .parse::<u64>()
                .map_err(|_| format!("{flag} must be a positive integer"))
        })
        .transpose()?
        .unwrap_or(default_value);
    if value == 0 {
        return Err(format!("{flag} must be greater than zero"));
    }
    Ok(value)
}

fn parse_optional_arg<'a>(args: &'a [String], flag: &str) -> Result<Option<&'a str>, String> {
    let mut index = 0;
    while index < args.len() {
        if args[index] == flag {
            return args
                .get(index + 1)
                .map(String::as_str)
                .ok_or_else(|| format!("{flag} requires a value"))
                .map(Some);
        }
        index += 1;
    }
    Ok(None)
}

fn run_connect_smoke(addr: SocketAddr) -> io::Result<WorldSnapshot> {
    let mut stream = TcpStream::connect(addr)?;
    stream.set_read_timeout(Some(Duration::from_secs(3)))?;
    stream.set_write_timeout(Some(Duration::from_secs(3)))?;

    send_command(
        &mut stream,
        &ClientCommand::new(ClientCommandPayload::Join {
            name: "dino_tools".to_owned(),
        }),
    )?;

    let mut reader = BufReader::new(stream.try_clone()?);
    let player_id = read_joined_player_id(&mut reader)?;

    send_command(
        &mut stream,
        &ClientCommand::new(ClientCommandPayload::MoveAvatar {
            player_id,
            x_axis: 1,
            y_axis: 0,
            facing_yaw_degrees: 0,
        }),
    )?;

    read_moved_snapshot(&mut reader, player_id)
}

fn run_circle_clients(
    addr: SocketAddr,
    player_count: usize,
    ticks: u64,
) -> io::Result<WorldSnapshot> {
    let mut stream = TcpStream::connect(addr)?;
    stream.set_read_timeout(Some(Duration::from_secs(5)))?;
    stream.set_write_timeout(Some(Duration::from_secs(3)))?;
    let mut reader = BufReader::new(stream.try_clone()?);

    let mut player_ids = Vec::with_capacity(player_count);
    for player_index in 0..player_count {
        send_command(
            &mut stream,
            &ClientCommand::new(ClientCommandPayload::Join {
                name: format!("circle_bot_{}", player_index + 1),
            }),
        )?;
        player_ids.push(read_joined_player_id(&mut reader)?);
    }

    let mut latest_snapshot = None;
    for tick in 0..ticks {
        for (player_index, player_id) in player_ids.iter().copied().enumerate() {
            let (x_axis, y_axis) = circle_axis(tick, player_index);
            send_command(
                &mut stream,
                &ClientCommand::new(ClientCommandPayload::MoveAvatar {
                    player_id,
                    x_axis,
                    y_axis,
                    facing_yaw_degrees: axis_yaw_degrees(x_axis, y_axis),
                }),
            )?;
        }
        latest_snapshot = Some(read_next_snapshot(&mut reader)?);
    }

    let snapshot = latest_snapshot.ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "ticks must be greater than zero",
        )
    })?;
    let moved_players = player_ids
        .iter()
        .filter(|player_id| {
            snapshot
                .avatars
                .iter()
                .any(|avatar| avatar.player_id == **player_id && avatar.is_moving)
        })
        .count();

    if moved_players != player_ids.len() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!(
                "expected {} moved bot players, saw {moved_players}",
                player_ids.len()
            ),
        ));
    }

    Ok(snapshot)
}

fn circle_axis(tick: u64, player_index: usize) -> (i8, i8) {
    const DIRECTION_TICKS: u64 = 12;
    const DIRECTIONS: [(i8, i8); 8] = [
        (1, 0),
        (1, 1),
        (0, 1),
        (-1, 1),
        (-1, 0),
        (-1, -1),
        (0, -1),
        (1, -1),
    ];

    let direction_index = ((tick / DIRECTION_TICKS) as usize + player_index) % DIRECTIONS.len();
    DIRECTIONS[direction_index]
}

fn axis_yaw_degrees(x_axis: i8, y_axis: i8) -> i16 {
    match (x_axis.signum(), y_axis.signum()) {
        (1, 0) => 0,
        (1, 1) => 45,
        (0, 1) => 90,
        (-1, 1) => 135,
        (-1, 0) => 180,
        (-1, -1) => -135,
        (0, -1) => -90,
        (1, -1) => -45,
        _ => 0,
    }
}

fn send_command(stream: &mut TcpStream, command: &ClientCommand) -> io::Result<()> {
    stream.write_all(encode_client_command(command).as_bytes())
}

fn read_joined_player_id(reader: &mut BufReader<TcpStream>) -> io::Result<u64> {
    loop {
        let line = read_line(reader)?;
        let message = parse_server_line(&line).map_err(invalid_data)?;
        if let ServerMessagePayload::Joined { player_id } = message.payload {
            return Ok(player_id);
        }
    }
}

fn read_moved_snapshot(
    reader: &mut BufReader<TcpStream>,
    player_id: u64,
) -> io::Result<WorldSnapshot> {
    loop {
        let snapshot = read_next_snapshot(reader)?;
        {
            let moved = snapshot
                .avatars
                .iter()
                .any(|avatar| avatar.player_id == player_id && avatar.x > 0);
            if moved {
                return Ok(snapshot);
            }
        }
    }
}

fn read_next_snapshot(reader: &mut BufReader<TcpStream>) -> io::Result<WorldSnapshot> {
    loop {
        let line = read_line(reader)?;
        let message = parse_server_line(&line).map_err(invalid_data)?;
        if let ServerMessagePayload::Snapshot(snapshot) = message.payload {
            return Ok(snapshot);
        }
    }
}

fn read_line(reader: &mut BufReader<TcpStream>) -> io::Result<String> {
    let mut line = String::new();
    let bytes_read = reader.read_line(&mut line)?;
    if bytes_read == 0 {
        return Err(io::Error::from(io::ErrorKind::UnexpectedEof));
    }
    Ok(line)
}

fn invalid_data(message: String) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn circle_axis_cycles_through_octants() {
        assert_eq!(circle_axis(0, 0), (1, 0));
        assert_eq!(circle_axis(12, 0), (1, 1));
        assert_eq!(circle_axis(24, 0), (0, 1));
        assert_eq!(circle_axis(96, 0), (1, 0));
    }

    #[test]
    fn circle_axis_offsets_each_player_phase() {
        assert_eq!(circle_axis(0, 0), (1, 0));
        assert_eq!(circle_axis(0, 1), (1, 1));
        assert_eq!(circle_axis(0, 2), (0, 1));
    }

    #[test]
    fn axis_yaw_matches_world_axes() {
        assert_eq!(axis_yaw_degrees(1, 0), 0);
        assert_eq!(axis_yaw_degrees(0, 1), 90);
        assert_eq!(axis_yaw_degrees(-1, 0), 180);
        assert_eq!(axis_yaw_degrees(0, -1), -90);
    }
}
