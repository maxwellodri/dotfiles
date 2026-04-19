use std::fs;
use std::io::{self, Read, Write};
use std::path::Path;
use std::sync::{Arc, Mutex};

use clap::{Parser, Subcommand};
use chrono::{Local, TimeZone};
use indexmap::IndexMap;
use serde::{Deserialize, Serialize};
use tracing::{error, info};
use tracing_subscriber::EnvFilter;

const SOCKET_PATH: &str = "/tmp/herald.sock";
const TMUX_SESSION: &str = "herald_daemon";

// ── Wire protocol ────────────────────────────────────────────

/// Messages sent over the unix socket (JSON-encoded)
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
enum Message {
    #[serde(rename = "notification")]
    Notification {
        body: String,
        /// Header for notify-send. None = skip notify-send.
        notify_send: Option<String>,
        /// If true, call paplay after notification.
        paplay: bool,
        /// If true, persist to store.
        store: bool,
        /// If true, use a fixed notify-send hint so pings replace each other.
        ping: bool,
    },
    #[serde(rename = "remove")]
    Remove { id: Option<u64> },
    #[serde(rename = "clear")]
    Clear {},
    #[serde(rename = "kill")]
    Kill { sender_pid: u32 },
    #[serde(rename = "get_messages")]
    GetMessages {},
    #[serde(rename = "get_count")]
    GetCount {},
}

/// Responses sent back from the daemon over the socket
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
enum Response {
    #[serde(rename = "ok")]
    Ok { msg: String },
    #[serde(rename = "messages")]
    Messages { messages: Vec<StoredMessage> },
    #[serde(rename = "count")]
    Count { count: usize },
}

/// A message stored in the daemon's memory, with metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
struct StoredMessage {
    id: u64,
    message: Message,
    received_at: String,
}

/// Persistent store serialized to messages.json
#[derive(Debug, Clone, Serialize, Deserialize)]
struct StoreFile {
    messages: Vec<StoredMessage>,
}

/// Simplified message for eww widget consumption
#[derive(Debug, Clone, Serialize)]
struct EwwMessage {
    id: u64,
    title: Option<String>,
    body: String,
    full_body: String,
    time: String,
}

/// Full eww response including daemon status
#[derive(Debug, Clone, Serialize)]
struct EwwResponse {
    alive: bool,
    messages: Vec<EwwMessage>,
}

struct Store {
    next_id: u64,
    messages: IndexMap<u64, StoredMessage>,
}

impl Store {
    fn load() -> Self {
        let path = data_dir().join("messages.json");
        if path.exists() {
            match fs::read_to_string(&path) {
                Ok(s) => match serde_json::from_str::<StoreFile>(&s) {
                    Ok(file) => {
                        let mut max_id = 0u64;
                        let mut messages = IndexMap::new();
                        for msg in file.messages {
                            max_id = max_id.max(msg.id + 1);
                            messages.insert(msg.id, msg);
                        }
                        info!(count = messages.len(), "loaded store from disk");
                        return Self { next_id: max_id, messages };
                    }
                    Err(e) => error!(%e, "failed to parse store, starting fresh"),
                },
                Err(e) => error!(%e, "failed to read store, starting fresh"),
            }
        }
        Self {
            next_id: 0,
            messages: IndexMap::new(),
        }
    }

    fn save(&self) {
        let dir = data_dir();
        let path = dir.join("messages.json");
        if let Err(e) = fs::create_dir_all(&dir) {
            error!(%e, "failed to create data dir");
            return;
        }
        let file = StoreFile {
            messages: self.messages.values().cloned().collect(),
        };
        match serde_json::to_string_pretty(&file) {
            Ok(json) => {
                if let Err(e) = fs::write(&path, json) {
                    error!(%e, "failed to write store");
                }
            }
            Err(e) => error!(%e, "failed to serialize store"),
        }
    }

    fn insert(&mut self, mut msg: StoredMessage) -> u64 {
        msg.id = self.next_id;
        self.next_id += 1;
        let id = msg.id;
        self.messages.insert(id, msg);
        // Cap at 100 messages — remove oldest entries
        while self.messages.len() > 100 {
            self.messages.shift_remove_index(0);
        }
        self.save();
        id
    }

    fn remove(&mut self, id: u64) -> bool {
        if self.messages.shift_remove(&id).is_some() {
            self.save();
            true
        } else {
            false
        }
    }

    fn clear(&mut self) -> usize {
        let count = self.messages.len();
        self.messages.clear();
        self.save();
        count
    }
}

fn data_dir() -> std::path::PathBuf {
    let dirs = directories::ProjectDirs::from("", "", "herald")
        .expect("failed to determine data directory");
    dirs.data_dir().to_path_buf()
}

fn format_time(epoch: &str) -> String {
    let secs: i64 = epoch.parse().unwrap_or(0);
    let dt = Local.timestamp_opt(secs, 0).single().unwrap_or_else(Local::now);
    let now = Local::now();
    let time = dt.format("%-I:%M%P").to_string(); // e.g. 5:03pm

    let today = now.date_naive();
    let msg_day = dt.date_naive();

    if today == msg_day {
        format!("Today at {time}")
    } else if today - chrono::Duration::days(1) == msg_day {
        format!("Yesterday at {time}")
    } else if (today - msg_day).num_days() < 7 {
        let weekday = dt.format("%A");
        format!("{weekday} at {time}")
    } else {
        dt.format("%b %-d, %Y at %-I:%M%P").to_string()
    }
}

fn epoch_now() -> String {
    let d = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    format!("{}", d.as_secs())
}

// ── CLI ──────────────────────────────────────────────────────

#[derive(Parser)]
#[command(name = "herald", about = "Notification daemon")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Start the daemon
    Daemon {
        /// Launch in a detached tmux session
        #[arg(long)]
        tmux: bool,
    },
    /// Send a notification message to the daemon
    Message {
        /// Header for notify-send (omit to skip notify-send)
        #[arg(short, long)]
        title: Option<String>,
        /// Play a sound via paplay
        #[arg(long)]
        sound: bool,
        /// Ping: play sound, notify with tmux session name, don't store
        #[arg(long, conflicts_with = "body", conflicts_with = "title")]
        ping: bool,
        /// Don't persist to store
        #[arg(long)]
        no_store: bool,
        /// The message body
        body: Vec<String>,
    },
    /// List stored messages
    Messages {
        /// Output raw JSON
        #[arg(long)]
        json: bool,
    },
    /// Remove a stored message by id, or all messages
    Remove {
        /// Remove message by id
        id: Option<u64>,
        /// Remove all messages
        #[arg(long, conflicts_with = "id")]
        all: bool,
    },
    /// Kill the running daemon
    Kill,
    /// Output messages as JSON array for eww widgets
    Eww,
    /// Print notification count
    Count,
}

// ── Entry ────────────────────────────────────────────────────

fn main() -> io::Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Daemon { tmux } => {
            if tmux {
                launch_tmux()?;
                return Ok(());
            }
            // Only the daemon path needs tokio
            tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()?
                .block_on(run_daemon())
        }
        Commands::Message { title, sound, ping, no_store, body } => {
            if ping {
                let body = std::env::var("TMUX")
                    .ok()
                    .and_then(|v| {
                        // TMUX=/tmp/tmux-1000/default,1234 — extract session from tmux list-sessions
                        v.split(',').next().map(|s| s.to_string())
                    })
                    .map(|_| {
                        // We have TMUX, get the session name
                        std::process::Command::new("tmux")
                            .args(["display-message", "-p", "#S"])
                            .output()
                            .ok()
                            .and_then(|o| String::from_utf8(o.stdout).ok())
                            .map(|s| format!("{} has finished.", s.trim()))
                            .unwrap_or_else(|| "Ping!".to_string())
                    })
                    .unwrap_or_else(|| "Ping!".to_string());
                send_message(Message::Notification {
                    body,
                    notify_send: None,
                    paplay: true,
                    store: false,
                    ping: true,
                })
            } else {
                if title.is_none() && !sound && body.is_empty() {
                    eprintln!("error: message requires at least one of --title, --sound, --ping, or a body");
                    std::process::exit(1);
                }
                let body = body.join(" ");
                let has_content = title.is_some() || !body.is_empty();
                send_message(Message::Notification {
                    body,
                    notify_send: title,
                    paplay: sound,
                    store: has_content && !no_store,
                    ping: false,
                })
            }
        }
        Commands::Remove { id, all } => {
            if all {
                send_message(Message::Clear {})
            } else {
                let id = id.ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "provide an id or --all"))?;
                send_message(Message::Remove { id: Some(id) })
            }
        }
        Commands::Kill => send_message(Message::Kill {
            sender_pid: std::process::id(),
        }),
        Commands::Messages { json } => {
            let raw = send_and_recv(Message::GetMessages {})?;
            if json {
                println!("{raw}");
            } else {
                let resp: Response = serde_json::from_str(&raw)
                    .expect("failed to parse daemon response");
                match resp {
                    Response::Messages { messages } => {
                        if messages.is_empty() {
                            println!("No messages.");
                        } else {
                            for m in &messages {
                                let title = match &m.message {
                                    Message::Notification { notify_send, .. } => {
                                        notify_send.as_deref().unwrap_or("-")
                                    }
                                    _ => "-",
                                };
                                let body = match &m.message {
                                    Message::Notification { body, .. } => body.as_str(),
                                    _ => "-",
                                };
                                println!("{}\t{}\t{}\t{}", m.id, format_time(&m.received_at), title, body);
                            }
                        }
                    }
                    Response::Ok { msg } => println!("{msg}"),
                    Response::Count { count } => println!("{count}"),
                }
            }
            Ok(())
        }
        Commands::Count => {
            let raw = send_and_recv(Message::GetCount {})?;
            let resp: Response = serde_json::from_str(&raw)
                .expect("failed to parse daemon response");
            match resp {
                Response::Count { count } => println!("{count}"),
                Response::Ok { msg } => println!("{msg}"),
                _ => println!("unexpected response"),
            }
            Ok(())
        }
        Commands::Eww => {
            let alive = std::os::unix::net::UnixStream::connect(SOCKET_PATH).is_ok();
            let store = Store::load();
            let eww_msgs: Vec<EwwMessage> = store.messages.values().map(|m| {
                let (body, title) = match &m.message {
                    Message::Notification { body, notify_send, .. } => {
                        (body.clone(), notify_send.clone())
                    }
                    _ => ("-".to_string(), None),
                };
                let truncated = if body.len() > 30 {
                    format!("{}...", &body[..30])
                } else {
                    body.clone()
                };
                let truncated_title = title.map(|t| {
                    if t.len() > 15 {
                        format!("{}...", &t[..15])
                    } else {
                        t
                    }
                });
                EwwMessage {
                    id: m.id,
                    title: truncated_title,
                    body: truncated,
                    full_body: body,
                    time: format_time(&m.received_at),
                }
            }).collect();
            let resp = EwwResponse { alive, messages: eww_msgs };
            println!("{}", serde_json::to_string(&resp).unwrap());
            Ok(())
        }
    }
}

// ── Daemon (async) ───────────────────────────────────────────

async fn run_daemon() -> io::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    let path = Path::new(SOCKET_PATH);
    if path.exists() {
        fs::remove_file(path)?;
    }

    let listener = tokio::net::UnixListener::bind(SOCKET_PATH)?;
    info!("listening on {SOCKET_PATH}");

    let store = Arc::new(Mutex::new(Store::load()));

    loop {
        tokio::select! {
            accept = listener.accept() => {
                let (stream, _addr) = match accept {
                    Ok(s) => s,
                    Err(e) => {
                        error!(%e, "accept error");
                        continue;
                    }
                };
                let store = store.clone();
                tokio::spawn(async move {
                    if let Err(e) = handle_client(stream, store).await {
                        error!(%e, "client error");
                    }
                });
            }
        }
    }
}

async fn handle_client(
    stream: tokio::net::UnixStream,
    store: Arc<Mutex<Store>>,
) -> io::Result<()> {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    let mut buf = String::new();
    let (mut reader, mut writer) = stream.into_split();
    reader.read_to_string(&mut buf).await?;

    let trimmed = buf.trim();
    if trimmed.is_empty() {
        return Ok(());
    }

    let msg: Message = match serde_json::from_str(trimmed) {
        Ok(m) => m,
        Err(e) => {
            error!(%e, raw = trimmed, "failed to deserialize message");
            return Ok(());
        }
    };

    let resp = match &msg {
        Message::Kill { sender_pid } => {
            info!(sender_pid, "received kill, shutting down");
            let _ = fs::remove_file(SOCKET_PATH);
            // TODO: graceful shutdown via tokio::sync::Notify or similar
            std::process::exit(0);
        }
        Message::Notification {
            body,
            notify_send,
            paplay,
            store: should_store,
            ping,
        } => {
            let id = if *should_store {
                let stored = StoredMessage {
                    id: 0,
                    message: msg.clone(),
                    received_at: epoch_now(),
                };
                store.lock().unwrap().insert(stored)
            } else {
                // Don't persist, use a dummy id for notify-send hint
                0
            };

            info!(id, body, notify_send = ?notify_send, paplay, ping, "received notification");

            // Pings always get a notify-send with body as header, fixed hint
            // Regular notifications use title as header, per-id hint
            let (header, hint_id) = if *ping {
                (Some(body.clone()), "ping".to_string())
            } else {
                (notify_send.clone(), format!("{id}"))
            };

            if let Some(header) = header {
                let body_for_notify = if *ping { "".to_string() } else { body.clone() };
                tokio::spawn(async move {
                    match tokio::process::Command::new("notify-send")
                        .arg("--hint")
                        .arg(format!(
                            "string:x-canonical-private-synchronous:herald-{hint_id}"
                        ))
                        .arg(&header)
                        .arg(&body_for_notify)
                        .status()
                        .await
                    {
                        Ok(s) => info!(header, exit = s.code(), "notify-send"),
                        Err(e) => error!(%e, "notify-send failed"),
                    }
                });
            }
            if *paplay {
                tokio::spawn(async move {
                    match tokio::process::Command::new("sh")
                        .arg("-c")
                        .arg(
                            "ffmpeg -f lavfi -i 'sine=frequency=400:duration=0.2' \
                             -f lavfi -i 'sine=frequency=800:duration=0.2' \
                             -f lavfi -i 'sine=frequency=400:duration=0.2' \
                             -f lavfi -i 'sine=frequency=800:duration=0.2' \
                             -f lavfi -i 'sine=frequency=400:duration=0.2' \
                             -f lavfi -i 'sine=frequency=800:duration=0.2' \
                             -f lavfi -i 'sine=frequency=400:duration=0.2' \
                             -f lavfi -i 'sine=frequency=800:duration=0.2' \
                             -f lavfi -i 'sine=frequency=400:duration=0.2' \
                             -f lavfi -i 'sine=frequency=800:duration=0.2' \
                             -f lavfi -i 'sine=frequency=400:duration=0.2' \
                             -f lavfi -i 'sine=frequency=800:duration=0.2' \
                             -f lavfi -i 'sine=frequency=400:duration=0.2' \
                             -f lavfi -i 'sine=frequency=800:duration=0.2' \
                             -f lavfi -i 'sine=frequency=400:duration=0.2' \
                             -filter_complex '[0:a][1:a][2:a][3:a][4:a][5:a][6:a][7:a][8:a][9:a][10:a][11:a][12:a][13:a][14:a]concat=n=15:v=0:a=1[out]' \
                             -map '[out]' -f s16le -ar 44100 -ac 1 - 2>/dev/null \
                             | paplay --raw --rate=44100 --channels=1 --format=s16le --volume=131070"
                        )
                        .status()
                        .await
                    {
                        Ok(s) => info!(exit = s.code(), "paplay"),
                        Err(e) => error!(%e, "paplay failed"),
                    }
                });
            }

            Response::Ok {
                msg: format!("notification {id} stored"),
            }
        }
        Message::Remove { id } => {
            if let Some(id) = id {
                if store.lock().unwrap().remove(*id) {
                    info!(id, "removed message");
                    Response::Ok {
                        msg: format!("message {id} removed"),
                    }
                } else {
                    Response::Ok {
                        msg: format!("message {id} not found"),
                    }
                }
            } else {
                Response::Ok {
                    msg: "no id provided".to_string(),
                }
            }
        }
        Message::Clear {} => {
            let count = store.lock().unwrap().clear();
            info!(count, "cleared all messages");
            Response::Ok {
                msg: format!("cleared {count} messages"),
            }
        }
        Message::GetCount {} => {
            let count = store.lock().unwrap().messages.len();
            info!(count, "sending count");
            Response::Count { count }
        }
        Message::GetMessages {} => {
            let messages: Vec<StoredMessage> =
                store.lock().unwrap().messages.values().cloned().collect();
            info!(count = messages.len(), "sending stored messages");
            Response::Messages { messages }
        }
    };

    let json = serde_json::to_string(&resp).unwrap();
    writer.write_all(json.as_bytes()).await?;
    Ok(())
}

// ── Client helpers (sync) ────────────────────────────────────

fn send_message(msg: Message) -> io::Result<()> {
    use std::os::unix::net::UnixStream;

    let json = serde_json::to_string(&msg).unwrap();
    let mut stream = UnixStream::connect(SOCKET_PATH)?;
    stream.write_all(json.as_bytes())?;
    Ok(())
}

fn send_and_recv(msg: Message) -> io::Result<String> {
    use std::os::unix::net::UnixStream;

    let json = serde_json::to_string(&msg).unwrap();
    let mut stream = UnixStream::connect(SOCKET_PATH)?;
    stream.write_all(json.as_bytes())?;
    // Shut down write side so daemon sees EOF
    stream.shutdown(std::net::Shutdown::Write)?;

    let mut resp = String::new();
    stream.read_to_string(&mut resp)?;
    Ok(resp.trim().to_string())
}

// ── Tmux ─────────────────────────────────────────────────────

fn launch_tmux() -> io::Result<()> {
    use std::os::unix::process::CommandExt;
    use std::process::Command;

    let check = Command::new("tmux")
        .args(["has-session", "-t", &format!("={TMUX_SESSION}")])
        .stderr(std::process::Stdio::null())
        .status();

    match check {
        Ok(s) if s.success() => {
            eprintln!("herald: tmux session '{TMUX_SESSION}' already exists");
            eprintln!("Attach with: tmux attach -t {TMUX_SESSION}");
            std::process::exit(1);
        }
        Ok(_) => {
            println!("herald: launching daemon in tmux session '{TMUX_SESSION}'");
            let binary = std::env::current_exe().expect("failed to get current executable path");

            let filtered_args: Vec<String> = std::env::args()
                .skip(1)
                .filter(|arg| arg != "--tmux")
                .collect();

            let mut cmd = Command::new("tmux");
            cmd.args([
                "new-session",
                "-d",
                "-s",
                TMUX_SESSION,
                "-n",
                "herald",
                "--",
            ]);
            cmd.arg(binary);
            cmd.args(&filtered_args);

            let err = cmd.exec();
            eprintln!("herald: failed to exec tmux: {err}");
            std::process::exit(1);
        }
        Err(e) => {
            eprintln!("herald: failed to check tmux session: {e}");
            eprintln!("Is tmux installed?");
            std::process::exit(1);
        }
    }
}
