use anyhow::{Context, Result, bail};
use clap::{Parser, Subcommand};
use indexmap::IndexMap;
use regex::Regex;
use serde::Deserialize;
use std::env;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

#[derive(Parser)]
#[command(
    author,
    version,
    about = "Unified project switcher and tmux session manager"
)]
struct Cli {
    #[arg(short, long, help = "Use dmenu instead of fzf")]
    gui: bool,

    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand)]
enum Commands {
    #[command(visible_alias = "s")]
    Switch,
    #[command(visible_alias = "f")]
    Find {
        #[arg(short, long, help = "Output path only")]
        path: bool,
    },
    #[command(visible_alias = "l")]
    List {
        #[arg(long, help = "Print absolute paths only, no formatting")]
        clean: bool,
        #[arg(long, help = "Only include tmux projects (requires --clean)")]
        tmux: bool,
        #[arg(long, help = "Exclude tmux projects (requires --clean)")]
        notmux: bool,
    },
}

#[derive(Debug, Deserialize)]
struct Config {
    projects: IndexMap<String, Project>,
}

#[derive(Debug, Default, Deserialize)]
struct FilterOpts {
    max_depth: Option<usize>,
}

#[derive(Debug, Deserialize)]
struct Project {
    path: String,
    #[serde(default)]
    filter_for: Option<String>,
    #[serde(default)]
    filter_out: Option<String>,
    #[serde(default)]
    filter_opts: Option<FilterOpts>,
    #[serde(default)]
    handler_pattern: Option<String>,
    #[serde(default)]
    handler_override: Option<String>,
    #[serde(default)]
    on_enter: Option<String>,
    #[serde(default)]
    find_override: Option<String>,
    #[serde(default)]
    tmux_windows: IndexMap<String, Window>,
}

#[derive(Debug, Deserialize)]
struct Window {
    #[serde(default)]
    layout: Option<String>,
    #[serde(default)]
    panes: Vec<Option<String>>,
}

const SOH: char = '\x01';

enum Action {
    Cd {
        path: PathBuf,
        on_enter: Option<String>,
    },
    Eval(Vec<String>),
    TmuxCreateAndAttach {
        name: String,
    },
    NewSession,
}

struct Entry {
    label: String,
    action: Action,
}

fn config_dir() -> PathBuf {
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("$HOME/.config"))
        .join("qz")
}

fn config_path() -> PathBuf {
    config_dir().join("config.yaml")
}

fn load_config() -> Result<Config> {
    let path = config_path();
    if !path.exists() {
        bail!("Config file not found at {}", path.display());
    }
    let contents = std::fs::read_to_string(&path)
        .with_context(|| format!("Reading config at {}", path.display()))?;
    let config: Config = serde_norway::from_str(&contents)
        .with_context(|| format!("Parsing YAML config at {}", path.display()))?;
    Ok(config)
}

fn expand_path(path: &str) -> PathBuf {
    let expanded = shellexpand::full(path).unwrap_or_else(|_| path.into());
    PathBuf::from(expanded.as_ref())
}

fn tmux_session_exists(name: &str) -> bool {
    Command::new("tmux")
        .args(["has-session", "-t", name])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn tmux_create_session(name: &str, project: &Project) -> Result<()> {
    let path = expand_path(&project.path);
    if !path.is_dir() {
        bail!("Directory {} does not exist", path.display());
    }

    if tmux_session_exists(name) {
        return Ok(());
    }

    if project.tmux_windows.is_empty() {
        Command::new("tmux")
            .args([
                "new-session",
                "-d",
                "-s",
                name,
                "-c",
                &path.to_string_lossy(),
            ])
            .status()
            .context("Creating tmux session")?;
        return Ok(());
    }

    let mut tmux_windows: Vec<(&String, &Window)> = project.tmux_windows.iter().collect();
    let first = tmux_windows.swap_remove(0);

    Command::new("tmux")
        .args([
            "new-session",
            "-d",
            "-s",
            name,
            "-n",
            first.0,
            "-c",
            &path.to_string_lossy(),
        ])
        .status()
        .context("Creating tmux session with first window")?;

    setup_window_panes(name, first.0, first.1, &path);

    for (win_name, win) in tmux_windows {
        Command::new("tmux")
            .args([
                "new-window",
                "-t",
                name,
                "-n",
                win_name,
                "-c",
                &path.to_string_lossy(),
            ])
            .status()
            .context("Creating tmux window")?;

        setup_window_panes(name, win_name, win, &path);
    }

    Command::new("tmux")
        .args(["select-window", "-t", &format!("{}:{}", name, first.0)])
        .status()
        .ok();

    Ok(())
}

fn setup_window_panes(session: &str, window: &str, win: &Window, path: &Path) {
    let target = format!("{}:{}", session, window);
    let panes: Vec<&str> = win.panes.iter().filter_map(|p| p.as_deref()).collect();

    if panes.is_empty() && win.panes.is_empty() {
        return;
    }

    for (i, cmd) in panes.iter().enumerate() {
        if i > 0 {
            Command::new("tmux")
                .args(["split-window", "-t", &target, "-c", &path.to_string_lossy()])
                .status()
                .ok();
        }
        Command::new("tmux")
            .args(["send-keys", "-t", &target, cmd, "C-m"])
            .status()
            .ok();
    }

    if let Some(layout) = &win.layout {
        Command::new("tmux")
            .args(["select-layout", "-t", &target, layout])
            .status()
            .ok();
    }
}

fn is_text_file(path: &Path) -> bool {
    std::fs::File::open(path)
        .map(|mut f| {
            let mut buf = [0u8; 8192];
            match std::io::Read::read(&mut f, &mut buf[..]) {
                Ok(n) => std::str::from_utf8(&buf[..n]).is_ok(),
                Err(_) => false,
            }
        })
        .unwrap_or(false)
}

fn run_fzf(input: &str, args: &[&str]) -> Option<String> {
    let mut child = Command::new("fzf")
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;

    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(input.as_bytes());
    }

    let output = child.wait_with_output().ok()?;
    if output.status.success() {
        let selected = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if !selected.is_empty() {
            return Some(selected);
        }
    }
    None
}

fn run_dmenu(input: &str, prompt: &str) -> Option<String> {
    let mut child = Command::new("dmenu")
        .args(["-l", "30", "-i", "-c", "--class", "sw", "-p", prompt])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;

    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(input.as_bytes());
    }

    let output = child.wait_with_output().ok()?;
    if output.status.success() {
        let selected = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if !selected.is_empty() {
            return Some(selected);
        }
    }
    None
}

const FZF_COLORS: &[&str] = &[
    "--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8",
    "--color=fg:#cdd6f4,header:#f38ba8,info:#cba6ac,pointer:#f5e0dc",
    "--color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6ac,hl+:#f38ba8",
];

const FZF_BINDS: &[&str] = &[
    "--bind=ctrl-u:preview-page-up,ctrl-d:preview-page-down",
    "--cycle",
];

fn cmd_switch(gui: bool) -> Result<()> {
    let config = load_config()?;
    let in_tmux = env::var("TMUX").is_ok();

    let active_sessions: Vec<String> = if !in_tmux {
        Command::new("tmux")
            .args(["list-sessions"])
            .output()
            .ok()
            .map(|o| {
                String::from_utf8_lossy(&o.stdout)
                    .lines()
                    .filter_map(|line| line.split(':').next().map(String::from))
                    .collect()
            })
            .unwrap_or_default()
    } else {
        vec![]
    };

    let mut entries: Vec<Entry> = Vec::new();

    if !in_tmux {
        let project_names: Vec<&String> = config.projects.keys().collect();
        let mut adhoc: Vec<&String> = active_sessions
            .iter()
            .filter(|s| !project_names.contains(s))
            .collect();
        adhoc.sort();
        for session in adhoc {
            entries.push(Entry {
                label: format!("{} 🖥👻", session),
                action: Action::Eval(vec![format!("tmux attach-session -t '{}'", session)]),
            });
        }
    }

    for (name, project) in &config.projects {
        let dir = expand_path(&project.path);
        if !dir.is_dir() {
            continue;
        }

        if !in_tmux && !project.tmux_windows.is_empty() {
            if active_sessions.contains(name) {
                entries.push(Entry {
                    label: format!("{} 🧐🤔", name),
                    action: Action::Eval(vec![format!("tmux attach-session -t '{}'", name)]),
                });
            } else {
                entries.push(Entry {
                    label: format!("{} 😠😇", name),
                    action: Action::TmuxCreateAndAttach { name: name.clone() },
                });
            }
        } else {
            entries.push(Entry {
                label: format!("{} 🖥📁", name),
                action: Action::Cd {
                    path: dir,
                    on_enter: project.on_enter.clone(),
                },
            });
        }
    }

    if !in_tmux {
        entries.push(Entry {
            label: "+ Create new session".into(),
            action: Action::NewSession,
        });
    }

    if entries.is_empty() {
        bail!("No projects found");
    }

    let input = entries
        .iter()
        .map(|e| e.label.as_str())
        .collect::<Vec<_>>()
        .join("\n");

    let selected = if gui {
        run_dmenu(&input, "Project")
    } else {
        let mut args: Vec<&str> = Vec::new();
        args.push("--no-sort");
        args.push("--border=rounded");
        args.extend(FZF_COLORS);
        args.extend(FZF_BINDS);
        run_fzf(&input, &args)
    };

    if let Some(label) = selected {
        if let Some(entry) = entries.iter().find(|e| e.label == label) {
            match &entry.action {
                Action::Cd { path, on_enter } => {
                    println!("{}cd '{}'", SOH, path.display());
                    if let Some(cmd) = on_enter {
                        println!("{}", cmd);
                    }
                }
                Action::Eval(commands) => {
                    for cmd in commands {
                        println!("{}", cmd);
                    }
                }
                Action::TmuxCreateAndAttach { name } => {
                    if let Some(project) = config.projects.get(name) {
                        tmux_create_session(name, project)?;
                    }
                    println!("tmux attach-session -t '{}'", name);
                }
                Action::NewSession => {
                    let name_input = if gui {
                        run_dmenu("", "Session name")
                    } else {
                        eprint!("Session name: ");
                        let mut buf = String::new();
                        std::io::stdin().read_line(&mut buf).ok().map(|_| buf)
                    };
                    if let Some(name) = name_input {
                        let name = name.trim().to_string();
                        if !name.is_empty() {
                            println!("tmux new-session -s '{}'", name);
                        }
                    }
                }
            }
        }
    }

    Ok(())
}

fn git_root(path: &Path) -> Option<PathBuf> {
    Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .current_dir(path)
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| {
            let s = String::from_utf8_lossy(&o.stdout).trim().to_string();
            PathBuf::from(s)
        })
}

fn cmd_find(gui: bool, path_only: bool) -> Result<()> {
    let cwd = env::current_dir().unwrap_or_default();
    let config = load_config().ok();
    let cfg_dir = config_dir();

    let project = config.as_ref().and_then(|c| {
        c.projects.iter().find(|(_, p)| {
            let ppath = expand_path(&p.path);
            cwd.starts_with(&ppath) || cwd == ppath
        })
    });

    if let Some((_, proj)) = &project {
        if let Some(cmd) = &proj.find_override {
            println!("{}", cmd);
            return Ok(());
        }
    }

    let (search_dir, fallback_max_depth) = if let Some((_, proj)) = &project {
        (expand_path(&proj.path), None)
    } else if let Some(root) = git_root(&cwd) {
        (root, None)
    } else {
        (cwd.clone(), Some(1))
    };

    let mut fd_args: Vec<String> = vec![
        "--base-directory".into(),
        search_dir.to_string_lossy().into(),
        "--hidden".into(),
        "--follow".into(),
        "--exclude".into(),
        ".git".into(),
        "--color=always".into(),
    ];

    if let Some((_, proj)) = &project {
        fd_args.push("--type".into());
        fd_args.push("f".into());
        if let Some(opts) = &proj.filter_opts {
            if let Some(depth) = opts.max_depth {
                fd_args.push("--max-depth".into());
                fd_args.push(depth.to_string());
            }
        }
    } else if fallback_max_depth.is_none() {
        fd_args.push("--type".into());
        fd_args.push("f".into());
    } else if let Some(depth) = fallback_max_depth {
        fd_args.push("--max-depth".into());
        fd_args.push(depth.to_string());
    }

    let fd_output = Command::new("fd")
        .args(&fd_args)
        .stdout(Stdio::piped())
        .output()
        .context("Running fd")?;

    let files = String::from_utf8_lossy(&fd_output.stdout).into_owned();
    if files.trim().is_empty() {
        return Ok(());
    }

    let files = if let Some((_, project)) = &project {
        files
            .lines()
            .filter(|line| {
                project
                    .filter_out
                    .as_ref()
                    .map(|pat| Regex::new(pat).map(|re| !re.is_match(line)).unwrap_or(true))
                    .unwrap_or(true)
            })
            .filter(|line| {
                project
                    .filter_for
                    .as_ref()
                    .map(|pat| Regex::new(pat).map(|re| re.is_match(line)).unwrap_or(true))
                    .unwrap_or(true)
            })
            .collect::<Vec<_>>()
            .join("\n")
    } else {
        files
    };

    let selected = if gui {
        run_dmenu(&files, "File")
    } else {
        let preview_arg = format!(
            "env PROJECT_PATH_ENV_VAR='{}' '{}' {{}}",
            search_dir.display(),
            cfg_dir.join("fzf_preview.sh").display()
        );
        let mut args: Vec<&str> = vec![
            "--ansi",
            "--preview",
            &preview_arg,
            "--preview-window=right:50%:border-left:noinfo",
            "--border=rounded",
        ];
        args.extend(FZF_COLORS);
        args.extend(FZF_BINDS);
        run_fzf(&files, &args)
    };

    if let Some(file) = selected {
        let file_path = search_dir.join(&file);
        if path_only {
            println!("{}", file_path.display());
            return Ok(());
        }

        if let Some((_, project)) = project {
            if let (Some(pattern), Some(handler)) =
                (&project.handler_pattern, &project.handler_override)
            {
                if let Ok(re) = Regex::new(pattern) {
                    if re.is_match(&file_path.to_string_lossy()) {
                        let handler_path = if Path::new(handler).is_absolute() {
                            PathBuf::from(handler)
                        } else {
                            cfg_dir.join(handler)
                        };
                        let _ = Command::new(&handler_path).arg(&file_path).status();
                        return Ok(());
                    }
                }
            }
        }

        if file_path.is_dir() {
            println!("cd '{}'", file_path.display());
        } else if is_text_file(&file_path) {
            let editor = env::var("EDITOR").unwrap_or_else(|_| "nvim".into());
            println!("{} '{}'", editor, file_path.display());
        } else {
            println!("xdg-open '{}'", file_path.display());
        }
    }

    Ok(())
}

fn cmd_list(clean: bool, tmux: bool, notmux: bool) -> Result<()> {
    if tmux && notmux {
        bail!("--tmux and --notmux are mutually exclusive");
    }
    if (tmux || notmux) && !clean {
        bail!("--tmux and --notmux require --clean");
    }

    let config = load_config()?;

    if clean {
        for (_, project) in &config.projects {
            let path = expand_path(&project.path);
            if !path.is_dir() {
                continue;
            }
            let has_tmux = !project.tmux_windows.is_empty();
            if tmux && !has_tmux {
                continue;
            }
            if notmux && has_tmux {
                continue;
            }
            println!("{}", path.display());
        }
    } else {
        println!("Projects:");
        for (name, project) in &config.projects {
            let path = expand_path(&project.path);
            if !path.is_dir() {
                continue;
            }
            if !project.tmux_windows.is_empty() {
                let status = if tmux_session_exists(name) {
                    "\u{2713}"
                } else {
                    "\u{2717}"
                };
                println!("  {} {}", status, name);
            } else {
                println!("  \u{1f4c1} {}", name);
            }
        }
    }

    Ok(())
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Some(Commands::Switch) => cmd_switch(cli.gui)?,
        Some(Commands::Find { path }) => cmd_find(cli.gui, path)?,
        Some(Commands::List {
            clean,
            tmux,
            notmux,
        }) => cmd_list(clean, tmux, notmux)?,
        None => {
            Cli::parse_from(["qz", "--help"]);
        }
    }

    Ok(())
}
