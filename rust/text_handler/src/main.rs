use anyhow::Result;
use indexmap::IndexMap;
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::io::{stdin, IsTerminal, Read, Write};
use tracing::{debug, trace};

#[derive(Serialize, Deserialize)]
struct Scorer {
    regex: String,
    command_label: String,
    score_change: i32,
}

#[derive(Clone, Serialize, Deserialize)]
struct Command {
    display: String,
    command: String,
}
fn default_min_threshold() -> i32 {
    10
}
fn default_max_threshold() -> i32 {
    100
}

#[derive(Serialize, Deserialize)]
struct Config {
    commands: IndexMap<String, Command>,
    scorers: Vec<Scorer>,
    #[serde(default = "default_min_threshold")]
    auto_select_min_threshold: i32,
    #[serde(default = "default_max_threshold")]
    auto_select_max_threshold: i32,
}

fn validate_config(config: &Config) -> Result<()> {
    if config.auto_select_min_threshold >= config.auto_select_max_threshold {
        anyhow::bail!(
            "Bad auto select values: min ({}) >= max ({})",
            config.auto_select_min_threshold,
            config.auto_select_max_threshold
        );
    }
    let missing_commands: Vec<(String, String)> = config
        .scorers
        .iter()
        .filter(|scorer| !config.commands.contains_key(&scorer.command_label))
        .map(|scorer| (scorer.regex.clone(), scorer.command_label.clone()))
        .collect();
    if !missing_commands.is_empty() {
        let error_msg = missing_commands
            .iter()
            .map(|(regex, command)| format!("regex '{}' -> command '{}'", regex, command))
            .collect::<Vec<_>>()
            .join(", ");

        anyhow::bail!("Scorers reference non-existent commands: {}", error_msg);
    }
    Ok(())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::TRACE)
        .init();
    let config_path = dirs::config_dir()
        .ok_or_else(|| anyhow::anyhow!("Could not find config directory"))?
        .join("dotfiles")
        .join("text_handler.yaml");
    let config_content = std::fs::read_to_string(&config_path)?;
    let config: Config = serde_yaml::from_str(&config_content)?;
    validate_config(&config)?;

    debug!(
        "Loaded {} commands and {} scorers",
        config.commands.len(),
        config.scorers.len()
    );
    let args: Vec<String> = std::env::args().collect();
    let text_source: &str;
    let text: String = match args.len() {
        1 => {
            // Case 1: no args - check if stdin has data, otherwise read from clipboard
            if !stdin().is_terminal() {
                text_source = "stdin";
                let mut buffer = String::new();
                stdin().read_to_string(&mut buffer)?;
                buffer
            } else {
                text_source = "clipboard";
                String::from_utf8(
                    std::process::Command::new("sh")
                        .args(["-c", "xclip -selection clipboard -o"])
                        .output()?
                        .stdout,
                )?
            }
        }
        2 if args[1] == "sel" => {
            text_source = "selection";
            // Case 2: exactly "sel" - read from selection
            String::from_utf8(
                std::process::Command::new("sh")
                    .args(["-c", "xclip -selection primary -o"])
                    .output()?
                    .stdout,
            )?
        }
        _ => {
            text_source = "command line";
            // Case 3: regular cmdline args joined
            args[1..].join(" ")
        }
    };
    debug!("Text from {text_source} to be plumbed: '{text}'");
    let mut scored_commands: IndexMap<String, (Command, i32)> = config
        .commands
        .iter()
        .map(|(label, cmd)| (label.clone(), (cmd.clone(), 0)))
        .collect();
    config
        .scorers
        .iter()
        .filter_map(|scorer| {
            Regex::new(&scorer.regex)
                .ok()
                .map(|re| (re, scorer.command_label.clone(), scorer.score_change))
        })
        .filter(|(re, _, _)| re.is_match(&text))
        .for_each(|(_, command_label, score_change)| {
            if let Some((command, score)) = scored_commands.get_mut(&command_label) {
                trace!(
                    "Updating score for command '{}' ('{}'): {} -> {}",
                    command.display,
                    command.command,
                    *score,
                    *score + score_change
                );
                *score += score_change;
            }
        });
    let mut sorted_commands: Vec<_> = scored_commands
        .iter()
        .enumerate()
        .filter(|(_, (_, (_, score)))| *score > 0)
        .collect();
    sorted_commands.sort_by(|a, b| {
        b.1 .1
             .1
            .cmp(&a.1 .1 .1) // score descending
            .then_with(|| a.0.cmp(&b.0)) // yaml order ascending
    });
    match sorted_commands.len() {
        0 => {
            debug!("No scorers matched");
            return Ok(());
        }
        num_cmds
            if (num_cmds == 1 && sorted_commands[0].1 .1 .1 > config.auto_select_min_threshold)
                || (num_cmds >= 2
                    && sorted_commands[0].1 .1 .1
                        > config.auto_select_max_threshold + sorted_commands[1].1 .1 .1
                    && sorted_commands[0].1 .1 .1 > 10) =>
        {
            debug!(
                "Matched auto-select (max threshold: {}, min threshold: {}): {} with score of {}",
                config.auto_select_max_threshold,
                config.auto_select_min_threshold,
                sorted_commands[0].1 .0,
                sorted_commands[0].1 .1 .1
            );
            // Auto-select first cmd if there is exactly one cmd or if first command scores 100+ points higher than second
            let (_, (_label, (command, _))) = &sorted_commands[0];
            std::process::Command::new("sh")
                .args(["-c", &command.command])
                .env("TEXT", &text)
                .spawn()?;
        }
        _ => {
            // Show dmenu for user selection
            let labels: String = sorted_commands
                .iter()
                .map(|(_, (_, (cmd, _)))| cmd.display.as_str())
                .collect::<Vec<_>>()
                .join("\n");
            debug!("Concatenated labels to dmenu: {labels}");

            let mut child = std::process::Command::new("sh")
                .args(["-c", "dmenu -l 20 -c -i"])
                .stdin(std::process::Stdio::piped())
                .stdout(std::process::Stdio::piped())
                .spawn()?;

            child.stdin.as_mut().unwrap().write_all(labels.as_bytes())?;

            let output = child.wait_with_output()?; // This gives you the actual output
            let selected_label = String::from_utf8(output.stdout)?.trim().to_string();
            let selected_command = scored_commands
                .iter()
                .find(|(_, (cmd, _))| cmd.display == selected_label);

            if let Some((label, (command, _))) = selected_command {
                debug!("Selected command label: {label}");
                std::process::Command::new("sh")
                    .args(["-c", &command.command])
                    .env("TEXT", &text)
                    .spawn()?;
            } else {
                debug!("Didn't select a command in dmenu")
            }
        }
    }
    Ok(())
}
