use std::io::{self, Read, Write};
use std::net::{SocketAddr, TcpListener, TcpStream};
use std::time::Duration;

use dino_protocol::{
    encode_server_message, parse_client_line, AvatarSnapshot, ClientCommandPayload, ServerMessage,
    ServerMessagePayload, WorldSnapshot,
};
use dino_sim::{tick_world, PlayerCommand, PlayerId, WorldConfig, WorldState};

pub const DEFAULT_BIND_ADDR: &str = "127.0.0.1:7007";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ServerConfig {
    pub bind_addr: SocketAddr,
    pub tick_duration: Duration,
    pub max_ticks: Option<u64>,
}

impl ServerConfig {
    pub const fn new(bind_addr: SocketAddr) -> Self {
        Self {
            bind_addr,
            tick_duration: Duration::from_millis(33),
            max_ticks: None,
        }
    }
}

#[derive(Debug)]
struct ConnectedClient {
    stream: TcpStream,
    read_buffer: String,
    player_ids: Vec<PlayerId>,
}

pub fn run_server(config: ServerConfig) -> io::Result<()> {
    let listener = TcpListener::bind(config.bind_addr)?;
    listener.set_nonblocking(true)?;

    let mut world = WorldState::new(WorldConfig::new(1_000_001));
    let mut clients = Vec::<ConnectedClient>::new();
    let mut pending_commands = Vec::<PlayerCommand>::new();

    println!("dino_server listening on {}", config.bind_addr);

    loop {
        accept_pending_clients(&listener, &mut clients)?;

        let mut commands = std::mem::take(&mut pending_commands);
        read_client_commands(&mut world, &mut clients, &mut commands);
        tick_world(&mut world, &commands);
        pending_commands.extend(broadcast_snapshot(&mut clients, &world));

        if config
            .max_ticks
            .is_some_and(|max_ticks| world.time().tick() >= max_ticks)
        {
            break;
        }

        std::thread::sleep(config.tick_duration);
    }

    Ok(())
}

pub fn smoke_snapshot() -> WorldSnapshot {
    let mut world = WorldState::new(WorldConfig::new(1_000_001));
    let player_id = world.allocate_player_id();
    tick_world(&mut world, &[PlayerCommand::JoinPlayer { player_id }]);
    tick_world(
        &mut world,
        &[PlayerCommand::MovePlayer {
            player_id,
            x_axis: 1,
            y_axis: 0,
            facing_yaw_degrees: 0,
        }],
    );

    snapshot_from_world(&world)
}

fn accept_pending_clients(
    listener: &TcpListener,
    clients: &mut Vec<ConnectedClient>,
) -> io::Result<()> {
    loop {
        match listener.accept() {
            Ok((stream, remote_addr)) => {
                stream.set_nonblocking(true)?;
                println!("client connected: {remote_addr}");
                clients.push(ConnectedClient {
                    stream,
                    read_buffer: String::new(),
                    player_ids: Vec::new(),
                });
            }
            Err(error) if error.kind() == io::ErrorKind::WouldBlock => return Ok(()),
            Err(error) => return Err(error),
        }
    }
}

fn read_client_commands(
    world: &mut WorldState,
    clients: &mut Vec<ConnectedClient>,
    commands: &mut Vec<PlayerCommand>,
) {
    let mut index = 0;
    while index < clients.len() {
        match read_one_client(world, &mut clients[index], commands) {
            Ok(()) => index += 1,
            Err(error)
                if matches!(
                    error.kind(),
                    io::ErrorKind::ConnectionReset
                        | io::ErrorKind::ConnectionAborted
                        | io::ErrorKind::BrokenPipe
                        | io::ErrorKind::UnexpectedEof
                ) =>
            {
                queue_leave_commands(&clients[index], commands);
                clients.swap_remove(index);
            }
            Err(error) => {
                eprintln!("client read error: {error}");
                queue_leave_commands(&clients[index], commands);
                clients.swap_remove(index);
            }
        }
    }
}

fn read_one_client(
    world: &mut WorldState,
    client: &mut ConnectedClient,
    commands: &mut Vec<PlayerCommand>,
) -> io::Result<()> {
    let mut buffer = [0_u8; 1024];
    loop {
        match client.stream.read(&mut buffer) {
            Ok(0) => return Err(io::Error::from(io::ErrorKind::UnexpectedEof)),
            Ok(bytes_read) => {
                client
                    .read_buffer
                    .push_str(&String::from_utf8_lossy(&buffer[..bytes_read]));
                while let Some(newline_index) = client.read_buffer.find('\n') {
                    let line = client.read_buffer[..newline_index].to_owned();
                    client.read_buffer.drain(..=newline_index);
                    handle_client_line(world, client, &line, commands)?;
                }
            }
            Err(error) if error.kind() == io::ErrorKind::WouldBlock => return Ok(()),
            Err(error) => return Err(error),
        }
    }
}

fn handle_client_line(
    world: &mut WorldState,
    client: &mut ConnectedClient,
    line: &str,
    commands: &mut Vec<PlayerCommand>,
) -> io::Result<()> {
    let command = match parse_client_line(line) {
        Ok(command) => command,
        Err(message) => {
            send_message(
                &mut client.stream,
                &ServerMessage::new(ServerMessagePayload::Error { message }),
            )?;
            return Ok(());
        }
    };

    match command.payload {
        ClientCommandPayload::Ping => {
            send_message(
                &mut client.stream,
                &ServerMessage::new(ServerMessagePayload::Pong),
            )?;
        }
        ClientCommandPayload::Join { name } => {
            let player_id = world.allocate_player_id();
            println!("player joined: {name} -> {}", player_id.get());
            client.player_ids.push(player_id);
            commands.push(PlayerCommand::JoinPlayer { player_id });
            send_message(
                &mut client.stream,
                &ServerMessage::new(ServerMessagePayload::Joined {
                    player_id: player_id.get(),
                }),
            )?;
        }
        ClientCommandPayload::MoveAvatar {
            player_id,
            x_axis,
            y_axis,
            facing_yaw_degrees,
        } => {
            if client
                .player_ids
                .iter()
                .any(|owned_player_id| owned_player_id.get() == player_id)
            {
                commands.push(PlayerCommand::MovePlayer {
                    player_id: PlayerId::new(player_id),
                    x_axis,
                    y_axis,
                    facing_yaw_degrees,
                });
            } else {
                send_message(
                    &mut client.stream,
                    &ServerMessage::new(ServerMessagePayload::Error {
                        message: "move rejected for unjoined player".to_owned(),
                    }),
                )?;
            }
        }
        ClientCommandPayload::BuildPrototype { prototype_id: _ } => {
            send_message(
                &mut client.stream,
                &ServerMessage::new(ServerMessagePayload::Error {
                    message: "build commands are not enabled in this slice".to_owned(),
                }),
            )?;
        }
    }

    Ok(())
}

fn broadcast_snapshot(
    clients: &mut Vec<ConnectedClient>,
    world: &WorldState,
) -> Vec<PlayerCommand> {
    let message = ServerMessage::new(ServerMessagePayload::Snapshot(snapshot_from_world(world)));
    let mut leave_commands = Vec::new();
    let mut index = 0;
    while index < clients.len() {
        match send_message(&mut clients[index].stream, &message) {
            Ok(()) => index += 1,
            Err(error)
                if matches!(
                    error.kind(),
                    io::ErrorKind::ConnectionReset
                        | io::ErrorKind::ConnectionAborted
                        | io::ErrorKind::BrokenPipe
                        | io::ErrorKind::UnexpectedEof
                ) =>
            {
                queue_leave_commands(&clients[index], &mut leave_commands);
                clients.swap_remove(index);
            }
            Err(error) => {
                eprintln!("client write error: {error}");
                queue_leave_commands(&clients[index], &mut leave_commands);
                clients.swap_remove(index);
            }
        }
    }

    leave_commands
}

fn send_message(stream: &mut TcpStream, message: &ServerMessage) -> io::Result<()> {
    stream.write_all(encode_server_message(message).as_bytes())
}

fn queue_leave_commands(client: &ConnectedClient, commands: &mut Vec<PlayerCommand>) {
    queue_leave_commands_for_player_ids(&client.player_ids, commands);
}

fn queue_leave_commands_for_player_ids(player_ids: &[PlayerId], commands: &mut Vec<PlayerCommand>) {
    commands.extend(
        player_ids
            .iter()
            .copied()
            .map(|player_id| PlayerCommand::LeavePlayer { player_id }),
    );
}

fn snapshot_from_world(world: &WorldState) -> WorldSnapshot {
    let avatars = world
        .avatars()
        .iter()
        .map(|avatar| {
            AvatarSnapshot::new(
                avatar.player_id().get(),
                avatar.position().x(),
                avatar.position().y(),
                avatar.position().z(),
                avatar.facing_yaw_degrees(),
                avatar.is_moving(),
            )
        })
        .collect();

    WorldSnapshot::new(
        world.seed(),
        world.time().tick(),
        world.entities().len() as u32,
        world.state_hash(),
        avatars,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn queue_leave_commands_enqueues_all_owned_players() {
        let mut commands = Vec::new();

        queue_leave_commands_for_player_ids(&[PlayerId::new(7), PlayerId::new(9)], &mut commands);

        assert_eq!(
            commands,
            vec![
                PlayerCommand::LeavePlayer {
                    player_id: PlayerId::new(7),
                },
                PlayerCommand::LeavePlayer {
                    player_id: PlayerId::new(9),
                },
            ]
        );
    }
}
