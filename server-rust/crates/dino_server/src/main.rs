use std::net::SocketAddr;

fn main() {
    if std::env::args().any(|arg| arg == "--help" || arg == "-h") {
        print_help();
        return;
    }

    if std::env::args().any(|arg| arg == "--smoke") {
        let snapshot = dino_server::smoke_snapshot();
        println!(
            "dino_server smoke: seed={} tick={} avatars={} hash={:016x}",
            snapshot.world_seed,
            snapshot.world_tick,
            snapshot.avatars.len(),
            snapshot.state_hash,
        );
        return;
    }

    let bind_addr = parse_bind_addr().unwrap_or_else(|message| {
        eprintln!("{message}");
        std::process::exit(2);
    });

    let config = dino_server::ServerConfig::new(bind_addr);
    if let Err(error) = dino_server::run_server(config) {
        eprintln!("dino_server failed: {error}");
        std::process::exit(1);
    }
}

fn parse_bind_addr() -> Result<SocketAddr, String> {
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        if arg == "--addr" {
            let value = args
                .next()
                .ok_or_else(|| "--addr requires a socket address".to_owned())?;
            return value
                .parse::<SocketAddr>()
                .map_err(|_| format!("invalid --addr value: {value}"));
        }
    }

    dino_server::DEFAULT_BIND_ADDR
        .parse::<SocketAddr>()
        .map_err(|_| "default bind address is invalid".to_owned())
}

fn print_help() {
    println!(
        "dino_server\n\nUSAGE:\n    dino_server [--addr 127.0.0.1:7007]\n    dino_server --smoke\n\nStarts the local authoritative TCP development server."
    );
}
