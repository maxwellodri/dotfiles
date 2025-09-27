use anyhow::{Context, Result};
use clap::Parser;
use colored::Colorize;
use indicatif::{ProgressBar, ProgressStyle};
use std::collections::HashMap;
use std::fs;
use std::io::{self, Write};
use std::path::PathBuf;
use strsim::levenshtein;

/// Command line arguments
#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// Directories to process
    #[arg(short, long, required = true)]
    path: Vec<PathBuf>,

    /// Maximum Levenshtein distance for grouping
    #[arg(short, long, default_value_t = 5)]
    dist: usize,
}

/// Group information
#[derive(Debug, Clone)]
struct Group {
    files: Vec<PathBuf>,
    name: String,
}

/// Find the longest common substring between two strings
fn longest_common_substring(s1: &str, s2: &str) -> String {
    let len1 = s1.len();
    let len2 = s2.len();
    let mut max_length = 0;
    let mut end_index = 0;

    // Create a table to store lengths of longest common suffixes
    let mut table = vec![vec![0; len2 + 1]; len1 + 1];

    for i in 1..=len1 {
        for j in 1..=len2 {
            if s1.chars().nth(i - 1) == s2.chars().nth(j - 1) {
                table[i][j] = table[i - 1][j - 1] + 1;
                if table[i][j] > max_length {
                    max_length = table[i][j];
                    end_index = i;
                }
            }
        }
    }

    if max_length == 0 {
        return String::new();
    }

    s1[(end_index - max_length)..end_index].to_string()
}
/// Find longest common substring for a group of filenames
fn find_lcs_for_group(files: &[PathBuf]) -> String {
    if files.is_empty() {
        return "group".to_string();
    }

    if files.len() == 1 {
        return files[0]
            .file_stem()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string();
    }

    // Extract base filenames (no extension)
    let base_names: Vec<String> = files
        .iter()
        .map(|path| {
            path.file_stem()
                .unwrap_or_default()
                .to_string_lossy()
                .to_string()
        })
        .collect();

    let mut lcs = base_names[0].clone();

    for name in &base_names[1..] {
        lcs = longest_common_substring(&lcs, name);
        if lcs.is_empty() {
            return "group".to_string();
        }
    }

    // Clean up the LCS
    let lcs = lcs.trim();
    if lcs.is_empty() {
        return "group".to_string();
    }

    // Remove trailing non-alphanumeric characters
    let lcs = lcs
        .trim_end_matches(|c: char| !c.is_alphanumeric())
        .to_string();

    // Replace spaces with underscores and remove special characters
    let lcs = lcs
        .chars()
        .map(|c| {
            if c.is_alphanumeric() || c == '_' || c == '-' {
                c
            } else {
                '_'
            }
        })
        .collect::<String>()
        .replace(' ', "_");

    if lcs.is_empty() {
        "group".to_string()
    } else {
        lcs
    }
}

/// Scan directory and collect files
fn collect_files(dirs: &[PathBuf]) -> Result<Vec<PathBuf>> {
    let mut all_files = Vec::new();

    for dir in dirs {
        let entries = fs::read_dir(dir)
            .with_context(|| format!("Failed to read directory: {}", dir.display()))?;

        for entry in entries {
            let entry = entry?;
            let path = entry.path();
            if path.is_file() {
                all_files.push(path);
            }
        }
    }

    Ok(all_files)
}

/// Asks for user confirmation
fn confirm(message: &str) -> Result<bool> {
    print!("{} [y/n]: ", message.green().bold());
    io::stdout().flush()?;

    let mut input = String::new();
    io::stdin().read_line(&mut input)?;
    Ok(input.trim().eq_ignore_ascii_case("y"))
}

fn main() -> Result<()> {
    // Initialize logger
    env_logger::init();

    // Parse command line arguments
    let args = Args::parse();

    // Collect all files from the specified directories
    println!("{}", "Collecting files...".cyan());
    let all_files = collect_files(&args.path)?;

    if all_files.is_empty() {
        println!("{}", "No files found in the specified directories.".red());
        return Ok(());
    }

    println!(
        "{} {} {}",
        "Found".green(),
        all_files.len().to_string().yellow(),
        "files to process".green()
    );
    println!(
        "{} {}",
        "Using maximum Levenshtein distance:".green(),
        args.dist.to_string().yellow()
    );

    // Calculate total comparisons
    let file_count = all_files.len();
    let total_comparisons = (file_count * (file_count - 1)) / 2;
    println!(
        "{} {}",
        "Analyzing similarity...".green(),
        format!("({} total comparisons)", total_comparisons).cyan()
    );

    // Setup progress bar
    let progress = ProgressBar::new(total_comparisons as u64);
    progress.set_style(
        ProgressStyle::default_bar()
            .template("{spinner:.green} [{elapsed_precise}] [{bar:40.cyan/blue}] {pos}/{len} ({percent}%) {msg}")
            .unwrap()
            .progress_chars("#>-"),
    );

    // Track processed files
    let mut processed = vec![false; file_count];
    let mut groups: Vec<Group> = Vec::new();
    let mut rejected_files: Vec<PathBuf> = Vec::new();
    let mut comparisons_done = 0;

    // Process files to form groups
    for i in 0..file_count {
        if processed[i] {
            continue;
        }

        processed[i] = true;
        let base_name_i = all_files[i]
            .file_stem()
            .unwrap_or_default()
            .to_string_lossy();

        let mut group_files = vec![all_files[i].clone()];

        for j in (i + 1)..file_count {
            if processed[j] {
                continue;
            }

            let base_name_j = all_files[j]
                .file_stem()
                .unwrap_or_default()
                .to_string_lossy();

            let distance = levenshtein(&base_name_i, &base_name_j);

            comparisons_done += 1;
            progress.set_position(comparisons_done);

            if distance <= args.dist {
                // Check if this file could belong to multiple groups
                let mut ambiguous = false;
                for group in &groups {
                    for group_file in &group.files {
                        let group_base_name =
                            group_file.file_stem().unwrap_or_default().to_string_lossy();

                        let group_distance = levenshtein(&base_name_j, &group_base_name);
                        if group_distance <= args.dist {
                            ambiguous = true;
                            break;
                        }
                    }
                    if ambiguous {
                        break;
                    }
                }

                if ambiguous {
                    rejected_files.push(all_files[j].clone());
                } else {
                    group_files.push(all_files[j].clone());
                    processed[j] = true;
                }
            }

            progress.set_message(format!("Creating groups: {} found", groups.len()));
        }

        // Only create groups with at least one file
        if !group_files.is_empty() {
            groups.push(Group {
                files: group_files,
                name: String::new(), // Will be set later
            });
        }
    }

    progress.finish_with_message("Analysis complete!");

    // Generate group names
    println!("\n{}", "Determining group names...".cyan());

    // First generate base names
    let mut base_names: HashMap<String, usize> = HashMap::new();
    for group in &mut groups {
        let base_name = find_lcs_for_group(&group.files);
        *base_names.entry(base_name.clone()).or_insert(0) += 1;
    }

    // Assign unique names
    let cloned_groups = groups.clone();
    for group in &mut groups {
        let mut base_name = find_lcs_for_group(&group.files);

        // If this base name is used multiple times, add a suffix
        if base_names.get(&base_name).unwrap_or(&0) > &1 {
            let mut counter = 1;
            let original_base = base_name.clone();

            while cloned_groups.iter().any(|g| g.name == base_name) {
                base_name = format!("{}_{}", original_base, counter);
                counter += 1;
            }
        }

        group.name = base_name;
    }

    // Display group information for confirmation
    println!("\n{}", "Analysis complete! Found groups:".cyan().bold());

    for (i, group) in groups.iter().enumerate() {
        println!(
            "\n{}. {} {} {} -> {}",
            (i + 1).to_string().yellow(),
            "Group".green(),
            group.name.cyan().bold(),
            format!("({} files)", group.files.len()).yellow(),
            format!("{}/{}", args.path[0].display(), group.name).blue()
        );

        group.files.iter().for_each(|file_path| {
            println!(
                "  - {}",
                file_path
                    .file_name()
                    .unwrap_or_default()
                    .to_string_lossy()
                    .cyan()
            );
        });
    }

    // Display rejected files
    if !rejected_files.is_empty() {
        println!(
            "\n{} {}",
            "Rejected files:".red().bold(),
            format!("({} files may match multiple groups)", rejected_files.len()).yellow()
        );

        let display_count = std::cmp::min(rejected_files.len(), 5);
        (0..display_count).for_each(|f| {
            println!(
                "  - {}",
                rejected_files[f]
                    .file_name()
                    .unwrap_or_default()
                    .to_string_lossy()
                    .red()
            );
        });

        if rejected_files.len() > 5 {
            println!(
                "  - {}",
                format!("... and {} more files", rejected_files.len() - 5).yellow()
            );
        }
    }

    // Ask for confirmation
    if !confirm(&format!(
        "\nConfirm creation of {} directories?",
        groups.len()
    ))? {
        println!(
            "{}",
            "Operation cancelled. No directories were created.".yellow()
        );
        return Ok(());
    }

    // Create directories and copy files
    println!("{}", "Creating directories and copying files...".cyan());

    let progress = ProgressBar::new(groups.len() as u64);
    progress.set_style(
        ProgressStyle::default_bar()
            .template("{spinner:.green} [{elapsed_precise}] [{bar:40.cyan/blue}] {pos}/{len} ({percent}%) {msg}")
            .unwrap()
            .progress_chars("#>-"),
    );

    for (i, group) in groups.iter().enumerate() {
        // Create target directory (use the first directory as the base)
        let target_dir = args.path[0].join(&group.name); //TODO fix - add .target() method on args
        fs::create_dir_all(&target_dir)?;

        // Copy files
        for file in &group.files {
            let target = target_dir.join(file.file_name().unwrap_or_default());
            fs::copy(file, target)?;
        }

        progress.set_position(i as u64 + 1);
        progress.set_message(format!("Created group '{}'", group.name));
    }

    progress.finish_with_message("Grouping complete!");

    println!(
        "\n{} {} {}",
        "Grouping complete!".green().bold(),
        "Created".green(),
        format!("{} groups", groups.len()).yellow().bold()
    );
    println!(
        "{}",
        "Original files remain in their original locations.".green()
    );
    println!(
        "{} {}",
        "Grouped copies are in:".green(),
        args.path[0].display().to_string().cyan()
    );

    Ok(())
}
