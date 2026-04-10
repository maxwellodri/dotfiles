use anyhow::{Context, Result, bail};
use clap::{Parser, Subcommand};
use regex::Regex;
use serde::Deserialize;
use std::collections::HashMap;
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
    Switch {
        #[arg(short, long, help = "Output path only, no tmux")]
        path: bool,
    },
    #[command(visible_alias = "f")]
    Find {
        #[arg(short, long, help = "Output path only")]
        path: bool,
    },
    #[command(visible_alias = "se")]
    Sessions,
    #[command(visible_alias = "l")]
    List,
}

#[derive(Debug, Deserialize)]
struct Config {
    projects: HashMap<String, Project>,
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
    tmux_windows: HashMap<String, Window>,
}

#[derive(Debug, Deserialize)]
struct Window {
    #[serde(default)]
    layout: Option<String>,
    #[serde(default)]
    panes: Vec<Option<String>>,
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

fn cmd_switch(gui: bool, path_only: bool) -> Result<()> {
    let config = load_config()?;
    let projects: Vec<(&String, &Project)> = config
        .projects
        .iter()
        .filter(|(_, p)| expand_path(&p.path).is_dir() && p.tmux_windows.is_empty())
        .collect();

    if projects.is_empty() {
        bail!("No projects found");
    }

    let input = projects
        .iter()
        .map(|(name, _)| name.as_str())
        .collect::<Vec<_>>()
        .join("\n");

    let selected = if gui {
        run_dmenu(&input, "Project")
    } else {
        let mut args: Vec<&str> = Vec::new();
        args.push("--border=rounded");
        args.extend(FZF_COLORS);
        args.extend(FZF_BINDS);
        run_fzf(&input, &args)
    };

    if let Some(name) = selected {
        if let Some(project) = config.projects.get(&name) {
            let dir = expand_path(&project.path);
            if path_only || project.tmux_windows.is_empty() {
                println!("cd '{}'", dir.display());
                if let Some(on_enter) = &project.on_enter {
                    println!("{}", on_enter);
                }
            } else {
                if !tmux_session_exists(&name) {
                    tmux_create_session(&name, project)?;
                }
                if env::var("TMUX").is_ok() {
                    println!("tmux detach-client");
                }
                println!("tmux attach-session -t '{}'", name);
            }
        }
    }

    Ok(())
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

    let search_dir = if let Some((_, proj)) = &project {
        expand_path(&proj.path)
    } else {
        cwd
    };

    let mut fd_args: Vec<String> = vec![
        "--base-directory".into(),
        search_dir.to_string_lossy().into(),
        "--type".into(),
        "f".into(),
        "--hidden".into(),
        "--follow".into(),
        "--exclude".into(),
        ".git".into(),
        "--color=always".into(),
    ];

    if let Some((_, proj)) = &project {
        if let Some(opts) = &proj.filter_opts {
            if let Some(depth) = opts.max_depth {
                fd_args.push("--max-depth".into());
                fd_args.push(depth.to_string());
            }
        }
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
        let mut args: Vec<&str> = Vec::new();
        args.push("--ansi");
        args.push("--preview");
        args.push(&preview_arg);
        args.push("--preview-window=right:50%:border-left:noinfo");
        args.push("--border=rounded");
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

fn cmd_sessions(gui: bool) -> Result<()> {
    let config = load_config().ok();

    let tmux_list = Command::new("tmux").args(["list-sessions"]).output().ok();

    let active_sessions: Vec<String> = tmux_list
        .as_ref()
        .map(|o| {
            String::from_utf8_lossy(&o.stdout)
                .lines()
                .filter_map(|line| line.split(':').next().map(String::from))
                .collect()
        })
        .unwrap_or_default();

    let mut entries: Vec<String> = vec!["+ Create new session".into()];

    for session in &active_sessions {
        entries.push(session.clone());
    }

    if let Some(config) = &config {
        for (name, project) in &config.projects {
            if !project.tmux_windows.is_empty() && !active_sessions.contains(name) {
                entries.push(format!("[layout] {}", name));
            }
        }
    }

    let input = entries.join("\n");

    let selected = if gui {
        run_dmenu(&input, "Session")
    } else {
        let mut args: Vec<&str> = Vec::new();
        args.push("--ansi");
        args.push("--border=rounded");
        args.push("--algo=v2");
        args.extend(FZF_COLORS);
        args.extend(FZF_BINDS);
        run_fzf(&input, &args)
    };

    if let Some(sel) = selected {
        if sel == "+ Create new session" {
            let name_input = if gui {
                run_dmenu("", "Session name")
            } else {
                let tmp_args: Vec<&str> = vec!["--prompt=Session name: ", "--border=rounded"];
                run_fzf("\n", &tmp_args)
            };
            if let Some(name) = name_input {
                let name = name.trim().to_string();
                if !name.is_empty() {
                    println!("tmux new-session -s '{}'", name);
                }
            }
        } else if let Some(layout_name) = sel.strip_prefix("[layout] ") {
            if let Some(config) = &config {
                if let Some(project) = config.projects.get(layout_name) {
                    tmux_create_session(layout_name, project)?;
                    if env::var("TMUX").is_ok() {
                        println!("tmux detach-client");
                    }
                    println!("tmux attach-session -t '{}'", layout_name);
                }
            }
        } else {
            if env::var("TMUX").is_ok() {
                println!("tmux detach-client");
            }
            println!("tmux attach-session -t '{}'", sel);
        }
    }

    Ok(())
}

fn cmd_list() -> Result<()> {
    let config = load_config()?;
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
    Ok(())
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command.unwrap_or(Commands::Switch { path: false }) {
        Commands::Switch { path } => cmd_switch(cli.gui, path)?,
        Commands::Find { path } => cmd_find(cli.gui, path)?,
        Commands::Sessions => cmd_sessions(cli.gui)?,
        Commands::List => cmd_list()?,
    }

    Ok(())
}
