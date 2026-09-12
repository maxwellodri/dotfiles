use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::{self, Read, Write};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tokio::io::AsyncBufReadExt;

use chrono::{Local, TimeZone};
use clap::{Parser, Subcommand};
use indexmap::IndexMap;
use serde::{Deserialize, Serialize};
use tracing::{error, info};
use tracing_subscriber::EnvFilter;

const SOCKET_PATH: &str = "/tmp/herald.sock";
const TMUX_SESSION: &str = "herald_daemon";

/// Socket path; overridable via $HERALD_SOCKET (testing, secondary instances).
fn socket_path() -> PathBuf {
    std::env::var_os("HERALD_SOCKET").map_or_else(|| PathBuf::from(SOCKET_PATH), PathBuf::from)
}

// ── Wire protocol ────────────────────────────────────────────

/// Messages sent over the unix socket (JSON-encoded)
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
enum Message {
    #[serde(rename = "notification")]
    Notification {
        header: String,
        body: String,
        notify: bool,
        play_sound: bool,
        store: bool,
        ping: bool,
        /// Routing tags; at least one required for the daemon to display.
        /// Missing field = old sender, treated as untagged -> skipped.
        #[serde(default)]
        tags: Vec<String>,
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
                        return Self {
                            next_id: max_id,
                            messages,
                        };
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
    let dt = Local
        .timestamp_opt(secs, 0)
        .single()
        .unwrap_or_else(Local::now);
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

// ── Config ──────────────────────────────────────────────────

/// Daemon config, read once at startup from
/// $XDG_CONFIG_HOME/herald/config.toml (i.e. ~/.config/herald/config.toml).
#[derive(Debug, Default, Deserialize)]
struct Config {
    /// Tags this daemon displays/stores. Empty = accept all tagged messages.
    #[serde(default)]
    subscribe: Vec<String>,
    /// When set, the daemon joins the cross-machine bus (see NtfyConfig).
    #[serde(default)]
    ntfy: Option<NtfyConfig>,
}

/// [ntfy] — self-hosted ntfy server acting as the message bus. Absent = the
/// daemon stays local-only (no presence, no cross-machine routing).
#[derive(Debug, Clone, Deserialize)]
struct NtfyConfig {
    url: String,
    /// Bearer token, inline (tests only — don't put real tokens in dotfiles).
    #[serde(default)]
    token: Option<String>,
    /// Token file (default: $XDG_DATA_HOME/herald/ntfy_token, mode 600).
    /// Fill via `pass show <host>-ntfy-token > ~/.local/share/herald/ntfy_token`.
    #[serde(default)]
    token_file: Option<PathBuf>,
    #[serde(default = "default_desk_topic")]
    desk: String,
    #[serde(default = "default_phone_topic")]
    phone: String,
    #[serde(default = "default_presence_topic")]
    presence: String,
    #[serde(default = "default_interval_secs")]
    interval_secs: u64,
    /// Presence entries older than this are stale (3x interval by default).
    #[serde(default = "default_stale_secs")]
    stale_secs: u64,
    /// Machine idle below this counts as "in use".
    #[serde(default = "default_active_idle_ms")]
    active_idle_ms: u64,
}

fn default_desk_topic() -> String {
    "notify-desk".into()
}
fn default_phone_topic() -> String {
    "notify-phone".into()
}
fn default_presence_topic() -> String {
    "presence".into()
}
fn default_interval_secs() -> u64 {
    15
}
fn default_stale_secs() -> u64 {
    45
}
fn default_active_idle_ms() -> u64 {
    120_000
}

impl NtfyConfig {
    /// Inline token, else first line of `token_file` (default
    /// $XDG_DATA_HOME/herald/ntfy_token). None = bus misconfigured.
    fn resolve_token(&self) -> Option<String> {
        if let Some(t) = &self.token {
            return Some(t.trim().to_string());
        }
        let p = self
            .token_file
            .clone()
            .unwrap_or_else(|| data_dir().join("ntfy_token"));
        fs::read_to_string(p)
            .ok()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
    }
}

/// A notification is accepted iff it carries >=1 tag and (when `subscribe` is
/// non-empty) at least one of them intersects `subscribe`.
fn accepts(config: &Config, tags: &[String]) -> bool {
    !tags.is_empty()
        && (config.subscribe.is_empty() || tags.iter().any(|t| config.subscribe.contains(t)))
}

fn load_config() -> Config {
    let path = directories::ProjectDirs::from("", "", "herald")
        .expect("failed to determine config directory")
        .config_dir()
        .join("config.toml");
    match fs::read_to_string(&path) {
        Ok(s) => match toml::from_str::<Config>(&s) {
            Ok(c) => {
                info!(path = %path.display(), subscribe = ?c.subscribe, "loaded config");
                c
            }
            Err(e) => {
                error!(%e, path = %path.display(), "invalid config.toml; accepting all");
                Config::default()
            }
        },
        Err(_) => {
            info!("no config.toml; accepting all tagged notifications");
            Config::default()
        }
    }
}

// ── Bus (ntfy) ───────────────────────────────────────────────

/// Shared bus state. Every message carries a uuid + originating machine;
/// daemons skip their own echoes and uuids they've already displayed.
/// A machine is "active" when its presence beacon (idle ms from xidle) is
/// fresh and below `active_idle_ms`.
#[derive(Clone)]
struct Bus {
    cfg: NtfyConfig,
    token: String,
    machine: String,
    /// machine -> (idle_ms, received_at)
    presence: Arc<Mutex<HashMap<String, (u64, Instant)>>>,
    /// uuids already displayed/published (trim periodically, not LRU-precise)
    seen: Arc<Mutex<HashSet<String>>>,
}

impl Bus {
    fn new(cfg: NtfyConfig, token: String) -> Self {
        let machine = fs::read_to_string("/etc/hostname")
            .ok()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| "unknown".into());
        Self {
            cfg,
            token,
            machine,
            presence: Arc::new(Mutex::new(HashMap::new())),
            seen: Arc::new(Mutex::new(HashSet::new())),
        }
    }

    fn mark_seen(&self, uuid: &str) -> bool {
        let mut seen = self.seen.lock().unwrap();
        if seen.len() > 512 {
            seen.clear();
        }
        seen.insert(uuid.to_string())
    }

    fn fresh_idle(&self, machine: &str) -> Option<u64> {
        self.presence
            .lock()
            .unwrap()
            .get(machine)
            .filter(|(_, at)| at.elapsed() < Duration::from_secs(self.cfg.stale_secs))
            .map(|(idle, _)| *idle)
    }

    /// Own idle: fresh beacon value if available, else probe xidle now.
    async fn my_idle(&self) -> Option<u64> {
        if let Some(idle) = self.fresh_idle(&self.machine) {
            return Some(idle);
        }
        self.probe_idle().await
    }

    /// Probe xidle once; refreshes the presence map entry on success.
    async fn probe_idle(&self) -> Option<u64> {
        let out = tokio::process::Command::new("xidle").output().await.ok()?;
        let idle: u64 = String::from_utf8_lossy(&out.stdout).trim().parse().ok()?;
        self.presence
            .lock()
            .unwrap()
            .insert(self.machine.clone(), (idle, Instant::now()));
        Some(idle)
    }

    /// Is any machine (including this one) currently in use?
    fn any_machine_active(&self) -> bool {
        let stale = Duration::from_secs(self.cfg.stale_secs);
        self.presence
            .lock()
            .unwrap()
            .iter()
            .any(|(_, (idle, at))| at.elapsed() < stale && *idle < self.cfg.active_idle_ms)
    }

    /// Should this machine ring? Unknown idle fails open (ring).
    async fn i_am_active(&self) -> bool {
        match self.my_idle().await {
            Some(idle) => idle < self.cfg.active_idle_ms,
            None => true,
        }
    }

    /// POST a JSON publish body to the ntfy root endpoint. Best-effort.
    async fn publish(&self, body: serde_json::Value, cache_off: bool) {
        let mut cmd = tokio::process::Command::new("curl");
        cmd.args([
            "-sf",
            "--max-time",
            "10",
            "-H",
            &format!("Authorization: Bearer {}", self.token),
        ]);
        if cache_off {
            cmd.args(["-H", "Cache: no"]);
        }
        let status = cmd
            .arg("-d")
            .arg(body.to_string())
            .arg(&self.cfg.url)
            .status()
            .await;
        match status {
            Ok(s) if s.success() => {}
            Ok(s) => error!(
                exit = s.code(),
                topic = body["topic"].as_str().unwrap_or("?"),
                "ntfy publish failed"
            ),
            Err(e) => error!(%e, "curl spawn failed"),
        }
    }

    /// Fan out a socket-originated notification: envelope to the desk topic
    /// (other daemons), human-readable copy to the phone topic when no
    /// machine is in use.
    async fn publish_notification(&self, msg: &Message, uuid: &str, phone: bool) {
        let mut env = serde_json::to_value(msg).unwrap_or_default();
        env["uuid"] = serde_json::json!(uuid);
        env["machine"] = serde_json::json!(self.machine);
        self.publish(
            serde_json::json!({
                "topic": self.cfg.desk,
                "title": "herald",
                "message": env.to_string(),
            }),
            false,
        )
        .await;
        if phone
            && let Message::Notification {
                header, body, tags, ..
            } = msg
        {
            self.publish(
                serde_json::json!({
                    "topic": self.cfg.phone,
                    "title": header,
                    "message": body,
                    "tags": tags,
                }),
                false,
            )
            .await;
        }
    }

    async fn publish_beacon(&self, idle_ms: u64) {
        self.publish(
            serde_json::json!({
                "topic": self.cfg.presence,
                "message": format!("{} {idle_ms}", self.machine),
            }),
            true,
        )
        .await;
    }
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
        /// Play a sound
        #[arg(long)]
        sound: bool,
        /// Suppress sound (overrides --ping's implied sound)
        #[arg(long)]
        no_sound: bool,
        /// Ping: notify with tmux session name, don't store
        #[arg(long, conflicts_with = "title")]
        ping: bool,
        /// Persist to store
        #[arg(long, conflicts_with = "ping")]
        store: bool,
        /// Routing tag (repeatable); at least one required unless --ping
        #[arg(long)]
        tag: Vec<String>,
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
        Commands::Message {
            title,
            sound,
            no_sound,
            ping,
            store,
            mut tag,
            body,
        } => {
            let play_sound = if ping { !no_sound } else { sound };

            // --ping implies the work_done tag; explicit tags are kept too.
            if ping {
                tag.push("work_done".to_string());
            }
            if tag.is_empty() {
                eprintln!("error: message requires at least one --tag (e.g. --tag work_done)");
                std::process::exit(2);
            }

            if ping {
                let header = std::env::var("TMUX")
                    .ok()
                    .and_then(|v| v.split(',').next().map(|s| s.to_string()))
                    .map(|_| {
                        std::process::Command::new("tmux")
                            .args(["display-message", "-p", "#S"])
                            .output()
                            .ok()
                            .and_then(|o| String::from_utf8(o.stdout).ok())
                            .map(|s| format!("{} has finished.", s.trim()))
                            .unwrap_or_else(|| "Ping!".to_string())
                    })
                    .unwrap_or_else(|| "Ping!".to_string());

                let body = if body.is_empty() {
                    String::new()
                } else {
                    body.join(" ")
                };

                send_message(Message::Notification {
                    header,
                    body,
                    notify: true,
                    play_sound,
                    store: false,
                    ping: true,
                    tags: tag,
                })
            } else {
                if title.is_none() && !sound && body.is_empty() {
                    eprintln!(
                        "error: message requires at least one of --title, --sound, --ping, or a body"
                    );
                    std::process::exit(1);
                }
                let body = body.join(" ");
                let has_title = title.is_some();
                let has_content = has_title || !body.is_empty();
                send_message(Message::Notification {
                    header: title.unwrap_or_default(),
                    body,
                    notify: has_title,
                    play_sound,
                    store: store && has_content,
                    ping: false,
                    tags: tag,
                })
            }
        }
        Commands::Remove { id, all } => {
            if all {
                send_message(Message::Clear {})
            } else {
                let id = id.ok_or_else(|| {
                    io::Error::new(io::ErrorKind::InvalidInput, "provide an id or --all")
                })?;
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
                let resp: Response =
                    serde_json::from_str(&raw).expect("failed to parse daemon response");
                match resp {
                    Response::Messages { messages } => {
                        if messages.is_empty() {
                            println!("No messages.");
                        } else {
                            for m in &messages {
                                let title = match &m.message {
                                    Message::Notification { header, .. } => {
                                        if header.is_empty() {
                                            "-"
                                        } else {
                                            header.as_str()
                                        }
                                    }
                                    _ => "-",
                                };
                                let body = match &m.message {
                                    Message::Notification { body, .. } => body.as_str(),
                                    _ => "-",
                                };
                                println!(
                                    "{}\t{}\t{}\t{}",
                                    m.id,
                                    format_time(&m.received_at),
                                    title,
                                    body
                                );
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
            let resp: Response =
                serde_json::from_str(&raw).expect("failed to parse daemon response");
            match resp {
                Response::Count { count } => println!("{count}"),
                Response::Ok { msg } => println!("{msg}"),
                _ => println!("unexpected response"),
            }
            Ok(())
        }
        Commands::Eww => {
            let alive = std::os::unix::net::UnixStream::connect(socket_path()).is_ok();
            let store = Store::load();
            let eww_msgs: Vec<EwwMessage> = store
                .messages
                .values()
                .map(|m| {
                    let (body, title) = match &m.message {
                        Message::Notification { body, header, .. } => {
                            (body.clone(), header.clone())
                        }
                        _ => ("-".to_string(), String::new()),
                    };
                    let truncated = if body.len() > 30 {
                        format!("{}...", &body[..30])
                    } else {
                        body.clone()
                    };
                    let truncated_title = if title.is_empty() {
                        None
                    } else if title.len() > 15 {
                        Some(format!("{}...", &title[..15]))
                    } else {
                        Some(title)
                    };
                    EwwMessage {
                        id: m.id,
                        title: truncated_title,
                        body: truncated,
                        full_body: body,
                        time: format_time(&m.received_at),
                    }
                })
                .collect();
            let resp = EwwResponse {
                alive,
                messages: eww_msgs,
            };
            println!("{}", serde_json::to_string(&resp).unwrap());
            Ok(())
        }
    }
}

// ── Delivery ─────────────────────────────────────────────

fn gen_uuid() -> String {
    use std::os::unix::fs::FileExt;
    let mut buf = [0u8; 16];
    if let Ok(f) = fs::File::open("/dev/urandom")
        && f.read_exact_at(&mut buf, 0).is_ok()
    {
        return buf.iter().map(|b| format!("{b:02x}")).collect();
    }
    format!(
        "{}-{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0),
        std::process::id()
    )
}

/// Unified handling for socket- and bus-originated notifications: tag gate,
/// presence-gated ring, store, then fan out to the bus (socket origin only,
/// so bus messages can never loop).
async fn deliver(
    store: &Arc<Mutex<Store>>,
    config: &Config,
    bus: Option<&Bus>,
    msg: &Message,
) -> Response {
    let Message::Notification {
        header,
        body,
        notify,
        play_sound,
        store: should_store,
        ping,
        tags,
    } = msg
    else {
        unreachable!("deliver called on non-notification")
    };

    if !accepts(config, tags) {
        info!(?tags, "skipped notification: no subscribed tag");
        return Response::Ok {
            msg: "skipped: no subscribed tag".to_string(),
        };
    }

    // Ring only when this machine is the one in use; unknown idle fails open.
    let i_am_active = match bus {
        Some(b) => b.i_am_active().await,
        None => true,
    };

    let id = if *should_store {
        let stored = StoredMessage {
            id: 0,
            message: msg.clone(),
            received_at: epoch_now(),
        };
        store.lock().unwrap().insert(stored)
    } else {
        0
    };

    info!(
        id,
        header,
        body,
        notify,
        play_sound,
        ping,
        active = i_am_active,
        "received notification"
    );

    let hint_id = if *ping {
        "ping".to_string()
    } else {
        format!("{id}")
    };

    if *notify {
        if i_am_active {
            let header = header.clone();
            let body = body.clone();
            tokio::spawn(async move {
                match tokio::process::Command::new("notify-send")
                    .arg("--hint")
                    .arg(format!(
                        "string:x-canonical-private-synchronous:herald-{hint_id}"
                    ))
                    .arg(&header)
                    .arg(&body)
                    .status()
                    .await
                {
                    Ok(s) => info!(header, exit = s.code(), "notify-send"),
                    Err(e) => error!(%e, "notify-send failed"),
                }
            });
        } else {
            info!(id, "notify suppressed: machine not in use");
        }
    }
    if *play_sound && i_am_active {
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
                             -filter_complex '[0:a][1:a][2:a][3:a][4:a][5:a][6:a][7:a][8:a]concat=n=9:v=0:a=1[out]' \
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

    // Fan out to the bus (socket origin only). Phone copy goes out only when
    // no machine is in use (self included, via own beacon).
    let mut routed = String::new();
    if let Some(bus) = bus {
        let uuid = gen_uuid();
        bus.mark_seen(&uuid);
        let phone = !bus.any_machine_active();
        bus.publish_notification(msg, &uuid, phone).await;
        routed = format!(" -> bus {uuid}{}", if phone { " +phone" } else { "" });
    }

    Response::Ok {
        msg: format!("notification {id}{routed}"),
    }
}

/// Periodically publish own idle (xidle) as a cache-less presence beacon.
async fn beacon_task(bus: Bus) {
    let mut warned = false;
    loop {
        match bus.probe_idle().await {
            Some(idle) => bus.publish_beacon(idle).await,
            None => {
                if !warned {
                    error!("xidle unavailable; no self presence (display fails open)");
                    warned = true;
                }
            }
        }
        tokio::time::sleep(Duration::from_secs(bus.cfg.interval_secs)).await;
    }
}

/// Subscribe to the desk + presence topics; NDJSON stream, reconnect with
/// since=<last id> so restarts bridge the gap without replaying history.
async fn subscribe_task(bus: Bus, store: Arc<Mutex<Store>>, config: Arc<Config>) {
    let last_id_path = data_dir().join("ntfy_last_id");
    let mut since: Option<String> = fs::read_to_string(&last_id_path)
        .ok()
        .map(|s| s.trim().to_string());
    loop {
        let mut url = format!("{}/{},{}/json", bus.cfg.url, bus.cfg.desk, bus.cfg.presence);
        if let Some(id) = &since {
            url.push_str(&format!("?since={id}"));
        }

        let child = tokio::process::Command::new("curl")
            .args([
                "-sN",
                "-H",
                &format!("Authorization: Bearer {}", bus.token),
                &url,
            ])
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::null())
            .spawn();

        match child {
            Ok(mut child) => {
                if let Some(out) = child.stdout.take() {
                    let mut lines = tokio::io::BufReader::new(out).lines();
                    while let Ok(Some(line)) = lines.next_line().await {
                        let line = line.trim().to_string();
                        if line.is_empty() {
                            continue;
                        }
                        if let Err(e) = handle_stream_line(
                            &bus,
                            &store,
                            &config,
                            &line,
                            &last_id_path,
                            &mut since,
                        )
                        .await
                        {
                            error!(%e, raw = %line, "bad stream line");
                        }
                    }
                }
                info!("ntfy stream ended; reconnecting");
            }
            Err(e) => error!(%e, "curl spawn failed"),
        }
        tokio::time::sleep(Duration::from_secs(2)).await;
    }
}

async fn handle_stream_line(
    bus: &Bus,
    store: &Arc<Mutex<Store>>,
    config: &Config,
    line: &str,
    last_id_path: &std::path::Path,
    since: &mut Option<String>,
) -> Result<(), serde_json::Error> {
    let v: serde_json::Value = serde_json::from_str(line)?;
    if let Some(id) = v["id"].as_str() {
        *since = Some(id.to_string());
        let _ = fs::write(last_id_path, id);
    }
    if v["event"].as_str() != Some("message") {
        return Ok(());
    }
    match v["topic"].as_str().unwrap_or_default() {
        t if t == bus.cfg.presence => {
            // "machine idle_ms"
            let mut it = v["message"].as_str().unwrap_or_default().split_whitespace();
            if let (Some(m), Some(idle)) =
                (it.next(), it.next().and_then(|x| x.parse::<u64>().ok()))
            {
                bus.presence
                    .lock()
                    .unwrap()
                    .insert(m.to_string(), (idle, Instant::now()));
                info!(machine = m, idle, "presence");
            }
        }
        t if t == bus.cfg.desk => {
            let env: serde_json::Value =
                serde_json::from_str(v["message"].as_str().unwrap_or_default())?;
            let uuid = env["uuid"].as_str().unwrap_or_default().to_string();
            let machine = env["machine"].as_str().unwrap_or_default().to_string();
            if machine == bus.machine {
                return Ok(()); // own echo
            }
            if uuid.is_empty() || !bus.mark_seen(&uuid) {
                return Ok(()); // duplicate
            }
            let notif: Message = serde_json::from_value(env)?;
            deliver(store, config, Some(bus), &notif).await;
        }
        _ => {}
    }
    Ok(())
}

// ── Daemon (async) ───────────────────────────────────────────

async fn run_daemon() -> io::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    let path = socket_path();
    if path.exists() {
        fs::remove_file(&path)?;
    }

    let listener = tokio::net::UnixListener::bind(&path)?;
    info!(path = %path.display(), "listening");

    let store = Arc::new(Mutex::new(Store::load()));
    let config = Arc::new(load_config());
    let bus = config.ntfy.clone().and_then(|c| match c.resolve_token() {
        Some(token) => Some(Bus::new(c, token)),
        None => {
            error!("[ntfy] configured but no token (inline `token` or token file); bus disabled");
            None
        }
    });
    if let Some(b) = &bus {
        tokio::spawn(beacon_task(b.clone()));
        tokio::spawn(subscribe_task(b.clone(), store.clone(), config.clone()));
        info!(machine = %b.machine, "bus enabled");
    }

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
                let config = config.clone();
                let bus = bus.clone();
                tokio::spawn(async move {
                    if let Err(e) = handle_client(stream, store, config, bus).await {
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
    config: Arc<Config>,
    bus: Option<Bus>,
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
            let _ = fs::remove_file(socket_path());
            // TODO: graceful shutdown via tokio::sync::Notify or similar
            std::process::exit(0);
        }
        Message::Notification { .. } => deliver(&store, &config, bus.as_ref(), &msg).await,
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
    let mut stream = UnixStream::connect(socket_path())?;
    stream.write_all(json.as_bytes())?;
    Ok(())
}

fn send_and_recv(msg: Message) -> io::Result<String> {
    use std::os::unix::net::UnixStream;

    let json = serde_json::to_string(&msg).unwrap();
    let mut stream = UnixStream::connect(socket_path())?;
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
