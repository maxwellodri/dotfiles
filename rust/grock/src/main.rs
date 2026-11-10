use std::fs;
use std::io::{self, Write};
use std::path::PathBuf;

use anyhow::{Context, Result};
use clap::Parser;
use ignore::WalkBuilder;
use proc_macro2::{LineColumn, Span};
use syn::spanned::Spanned;
use syn::{File, ImplItem, Item, TraitItem};

/// Print every .rs file under a path, with function bodies elided to `{ ... }`.
/// Structs, enums, signatures, constants, comments and formatting are kept.
/// Respects .gitignore, skips hidden dirs and `target/`.
#[derive(Parser)]
#[command(version, about)]
struct Args {
    /// Directories or single .rs files to walk (repeatable)
    #[arg(long, default_value = ".")]
    path: Vec<PathBuf>,

    /// Print token-savings estimates to stderr
    #[arg(long)]
    stats: bool,
}

fn main() -> Result<()> {
    let args = Args::parse();
    let files = collect_rs_files(&args.path);

    let mut total_raw_chars = 0usize;
    let mut total_out_chars = 0usize;
    let mut per_file_raw = Vec::new();

    for (file, display) in &files {
        let source = fs::read_to_string(file).with_context(|| format!("reading {display}"))?;
        total_raw_chars += source.chars().count();
        per_file_raw.push((source.chars().count(), display.clone()));

        let elided = match syn::parse_file(&source) {
            Ok(syntax) => elide_bodies(&source, &syntax),
            Err(err) => {
                eprintln!("grock: {display}: parse error, printing raw: {err}");
                source
            }
        };
        total_out_chars += elided.chars().count();

        // broken pipe (piped into head/less): stop quietly
        let mut stdout = io::stdout().lock();
        if writeln!(stdout, "// ===== {display} =====").is_err()
            || writeln!(stdout, "{elided}").is_err()
            || writeln!(stdout).is_err()
        {
            return Ok(());
        }
    }

    if args.stats {
        print_stats(files.len(), total_raw_chars, total_out_chars, &per_file_raw);
    }
    Ok(())
}

/// Returns (real path, path shown in headers relative to its root).
fn collect_rs_files(roots: &[PathBuf]) -> Vec<(PathBuf, String)> {
    let mut files: Vec<(PathBuf, String)> = Vec::new();
    for root in roots {
        if root.is_file() {
            files.push((root.clone(), root.display().to_string()));
            continue;
        }
        let mut builder = WalkBuilder::new(root);
        builder.sort_by_file_path(Ord::cmp);
        // target/ is skipped even when not gitignored
        builder.filter_entry(|e| e.depth() == 0 || !e.file_name().eq_ignore_ascii_case("target"));
        for entry in builder.build() {
            match entry {
                Ok(e)
                    if {
                        e.file_type().is_some_and(|t| t.is_file())
                            && e.file_name().to_string_lossy().ends_with(".rs")
                    } =>
                {
                    let path = e.into_path();
                    let display = path
                        .strip_prefix(root)
                        .map(|p| p.display().to_string())
                        .unwrap_or_else(|_| path.display().to_string());
                    files.push((path, display));
                }
                Err(err) => eprintln!("grock: walk error: {err}"),
                _ => {}
            }
        }
    }
    files.sort_by(|a, b| a.0.cmp(&b.0));
    files.dedup_by(|a, b| a.0 == b.0);
    files
}
fn elide_bodies(source: &str, syntax: &File) -> String {
    let mut spans = Vec::new();
    collect_body_spans(&syntax.items, &mut spans);

    let line_index = LineIndex::new(source);
    let mut byte_spans: Vec<(usize, usize)> = spans
        .iter()
        .map(|s| (line_index.offset(s.start), line_index.offset(s.end)))
        .collect();
    byte_spans.sort();

    let mut out = String::with_capacity(source.len() / 2);
    let mut cursor = 0;
    for (start, end) in byte_spans {
        out.push_str(&source[cursor..start]);
        out.push_str("{ ... }");
        cursor = end;
    }
    out.push_str(&source[cursor..]);
    out
}

fn collect_body_spans(items: &[Item], spans: &mut Vec<BodySpan>) {
    for item in items {
        match item {
            Item::Fn(f) => push_span(f.block.span(), spans),
            Item::Mod(m) => {
                if let Some((_, inner)) = &m.content {
                    collect_body_spans(inner, spans);
                }
            }
            Item::Trait(t) => {
                for member in &t.items {
                    if let TraitItem::Fn(f) = member {
                        if let Some(block) = &f.default {
                            push_span(block.span(), spans);
                        }
                    }
                }
            }
            Item::Impl(i) => {
                for member in &i.items {
                    if let ImplItem::Fn(f) = member {
                        push_span(f.block.span(), spans);
                    }
                }
            }
            _ => {}
        }
    }
}

struct BodySpan {
    start: LineColumn,
    end: LineColumn,
}

fn push_span(span: Span, spans: &mut Vec<BodySpan>) {
    spans.push(BodySpan {
        start: span.start(),
        end: span.end(),
    });
}

/// Converts 1-based line / char-column LineColumn into a byte offset.
struct LineIndex<'a> {
    text: &'a str,
    line_starts: Vec<usize>,
}

impl<'a> LineIndex<'a> {
    fn new(text: &'a str) -> Self {
        let mut line_starts = vec![0];
        for (i, b) in text.bytes().enumerate() {
            if b == b'\n' {
                line_starts.push(i + 1);
            }
        }
        LineIndex { text, line_starts }
    }

    fn offset(&self, lc: LineColumn) -> usize {
        let line = (lc.line - 1).min(self.line_starts.len() - 1);
        let line_start = self.line_starts[line];
        let line_end = self.line_end(line);
        for (i, (byte, _)) in self.text[line_start..line_end].char_indices().enumerate() {
            if i == lc.column {
                return line_start + byte;
            }
        }
        line_end
    }

    fn line_end(&self, line: usize) -> usize {
        self.line_starts
            .get(line + 1)
            .copied()
            .unwrap_or(self.text.len())
    }
}

/// ~4 chars per token is the standard rough estimate for code.
fn print_stats(
    file_count: usize,
    raw_chars: usize,
    out_chars: usize,
    per_file_raw: &[(usize, String)],
) {
    let raw_tok = raw_chars / 4;
    let out_tok = out_chars / 4;
    eprintln!("--- grock stats (stderr) ---");
    eprintln!(
        "{} files: raw {} chars ≈ {raw_tok} tok → grock {} chars ≈ {out_tok} tok ({}% saved)",
        file_count,
        raw_chars,
        out_chars,
        100usize.saturating_sub(out_tok * 100 / raw_tok.max(1)),
    );
    eprintln!("for comparison, raw tokens per file (largest first):");
    let mut sorted = per_file_raw.to_vec();
    sorted.sort_unstable_by(|a, b| b.0.cmp(&a.0));
    for (chars, name) in sorted.iter().take(5) {
        eprintln!("  {:>7} tok  {}", chars / 4, name);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn elide_src(source: &str) -> String {
        let syntax = syn::parse_file(source).unwrap();
        elide_bodies(source, &syntax)
    }

    #[test]
    fn free_fn_and_method_bodies_elided() {
        let out = elide_src(
            "struct S;\nimpl S {\n    fn m(&self) -> u8 {\n        7\n    }\n}\nfn main() {\n    let x = 1;\n}\n",
        );
        assert_eq!(
            out,
            "struct S;\nimpl S {\n    fn m(&self) -> u8 { ... }\n}\nfn main() { ... }\n"
        );
    }

    #[test]
    fn trait_default_and_decl_fns() {
        let out = elide_src(
            "trait T {\n    fn req(&self);\n    fn def(&self) -> u8 {\n        1\n    }\n}\nimpl T for S {\n    fn req(&self) { hi() }\n}\n",
        );
        assert_eq!(
            out,
            "trait T {\n    fn req(&self);\n    fn def(&self) -> u8 { ... }\n}\nimpl T for S {\n    fn req(&self) { ... }\n}\n"
        );
    }

    #[test]
    fn unicode_columns_stay_byte_correct() {
        let out = elide_src("fn ünïcödé(名: &str) -> String {\n    \"héllo\".into()\n}\n");
        assert_eq!(out, "fn ünïcödé(名: &str) -> String { ... }\n");
    }

    #[test]
    fn no_trailing_newline_clamps_to_eof() {
        let out = elide_src("fn a() {\n    todo!()\n}");
        assert_eq!(out, "fn a() { ... }");
    }

    #[test]
    fn inline_mod_recurses_and_comments_survive() {
        let out = elide_src("// top comment\nmod inner {\n    // inner comment\n    fn f() -> u8 {\n        1\n    }\n}\n");
        assert_eq!(
            out,
            "// top comment\nmod inner {\n    // inner comment\n    fn f() -> u8 { ... }\n}\n"
        );
    }
}
