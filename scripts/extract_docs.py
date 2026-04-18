#!/usr/bin/env python3
import sys
import os
import json
import re
import subprocess
import shutil
import signal
from urllib.parse import urljoin

try:
    import requests
except ImportError:
    print("Error: 'requests' is not installed.", file=sys.stderr)
    sys.exit(1)

try:
    from bs4 import BeautifulSoup
except ImportError:
    print("Error: 'beautifulsoup4' is not installed.", file=sys.stderr)
    sys.exit(1)

try:
    from bs4 import BeautifulSoup
except ImportError:
    print("Error: 'beautifulsoup4' is not installed.", file=sys.stderr)
    print(
        "Install it with: pip install beautifulsoup4  (or your system package manager)",
        file=sys.stderr,
    )
    sys.exit(1)

# --- Logging System ---
LOG_BUFFER = []


def log(msg):
    """Accumulate log messages silently."""
    LOG_BUFFER.append(str(msg))


def dump_log():
    """Prints the accumulated log to stderr."""
    sys.stderr.write("\n--- Execution Log ---\n")
    for line in LOG_BUFFER:
        sys.stderr.write(f"{line}\n")


def fail(msg):
    """Print error, dump the accumulated log, and exit."""
    sys.stderr.write(f"Error: {msg}\n")
    dump_log()
    sys.exit(1)


# --- Cross-Platform Helpers ---
def get_base_cache_dir():
    """Returns the platform-specific cache directory root."""
    if sys.platform == "darwin":
        return os.path.expanduser("~/Library/Caches")
    elif os.name == "nt":
        local_app_data = os.environ.get("LOCALAPPDATA")
        if local_app_data:
            return local_app_data
        return os.path.expanduser("~\\AppData\\Local")
    else:
        xdg_cache = os.environ.get("XDG_CACHE_HOME")
        if xdg_cache:
            return xdg_cache
        return os.path.expanduser("~/.cache")


def get_cache_path(crate_name):
    """Returns the full path to the JSON cache file for the crate."""
    base = get_base_cache_dir()
    cache_dir = os.path.join(base, "extract_docs")
    try:
        os.makedirs(cache_dir, exist_ok=True)
    except OSError as e:
        log(f"Warning: Could not create cache directory {cache_dir}: {e}")
    return os.path.join(cache_dir, f"{crate_name}.json")


def check_url(url):
    """Returns True if the URL exists (200 OK), False otherwise."""
    log(f"Checking URL: {url}")
    try:
        headers = {"User-Agent": "Mozilla/5.0 (compatible; RustDocTool/1.0)"}
        head = requests.head(url, allow_redirects=True, timeout=5, headers=headers)
        log(f"Status: {head.status_code}")
        return head.status_code == 200
    except Exception as e:
        log(f"HEAD request failed: {e}")
        return False


# --- Core Logic ---
def parse_input(user_input):
    parts = user_input.split("::")
    if not parts:
        fail("Invalid input")
    crate = parts[0]
    stripped_path = "::".join(parts[1:])
    return crate, stripped_path


def fetch_and_parse_crate_index(crate):
    all_html_url = f"https://docs.rs/{crate}/latest/{crate}/all.html"
    log(f"Fetching all.html from network: {all_html_url}")
    html = ""
    try:
        headers = {"User-Agent": "Mozilla/5.0 (compatible; RustDocTool/1.0)"}
        resp = requests.get(all_html_url, timeout=10, headers=headers)
        if resp.status_code != 200:
            fail(f"Could not fetch all.html. Status: {resp.status_code}")
        html = resp.text
    except Exception as e:
        log(f"Request Exception: {e}")
        fail("Network error fetching all.html")

    item_map = {}
    # Isolate main content
    start_marker = 'id="main-content"'
    idx = html.find(start_marker)
    if idx == -1:
        idx = html.find("<main")
    if idx != -1:
        html = html[idx:]

    pattern = re.compile(
        r'<a\s+[^>]*href="([^"]+)"[^>]*>\s*(.*?)\s*</a>', re.IGNORECASE | re.DOTALL
    )
    count = 0
    for match in pattern.finditer(html):
        href = match.group(1)
        text = re.sub(r"<[^>]+>", "", match.group(2)).strip()
        if not text:
            continue
        if text not in item_map:
            item_map[text] = []
        if href not in item_map[text]:
            item_map[text].append(href)
            count += 1

    log(f"Parsed {count} items into dictionary.")
    return item_map


def find_urls_in_map(cache_map, crate, stripped_path, original_input):
    base_url = f"https://docs.rs/{crate}/latest/{crate}/all.html"
    candidates = [stripped_path, original_input]

    # 1. Exact match
    for candidate in candidates:
        if candidate in cache_map:
            val = cache_map[candidate]
            if isinstance(val, list):
                log(f"Found exact match for key '{candidate}': {len(val)} links.")
                return [urljoin(base_url, u) for u in val]

    # 2. Module inference
    if stripped_path:
        module_prefix = stripped_path + "::"
        log(f"Checking for module prefix: '{module_prefix}'")
        found_child = None
        for key, val in cache_map.items():
            if not isinstance(val, list):
                continue
            if key.startswith(module_prefix):
                found_child = key
                break
        if found_child:
            log(f"Inferred module '{stripped_path}' due to child '{found_child}'")
            relative_module_path = stripped_path.replace("::", "/")
            module_url = f"https://docs.rs/{crate}/latest/{crate}/{relative_module_path}/index.html"
            if check_url(module_url):
                return [module_url]
            else:
                log(f"Inferred module URL {module_url} failed verification.")

    # 3. Leaf fallback
    leaf_name = original_input.split("::")[-1]
    log(f"Checking leaf name: '{leaf_name}'")
    if leaf_name in cache_map:
        val = cache_map[leaf_name]
        if isinstance(val, list):
            log(f"Found leaf match: {len(val)} links.")
            return [urljoin(base_url, u) for u in val]

    fail(f"Could not resolve '{original_input}' using cached map.")


# --- Content Extraction ---

# Sections to remove entirely by heading text
_SKIP_SECTIONS = {
    "Auto Trait Implementations",
    "Blanket Implementations",
    "Examples found in repository",
}


def _remove_section_by_heading(soup, heading_text, heading_tag="h2"):
    """Remove a heading and all following siblings until the next same-level heading."""
    heading = soup.find(heading_tag, string=re.compile(re.escape(heading_text)))
    if not heading:
        return
    tag = heading.next_sibling
    while tag and not (hasattr(tag, "name") and tag.name == heading_tag):
        nxt = tag.next_sibling
        tag.decompose()
        tag = nxt
    heading.decompose()


def extract_content(url):
    """Fetches URL, cleans HTML with BS4, then converts via pandoc."""
    log(f"Extracting content from: {url}")

    # 1. Fetch HTML
    try:
        headers = {"User-Agent": "Mozilla/5.0 (compatible; RustDocTool/1.0)"}
        resp = requests.get(url, timeout=10, headers=headers)
        resp.raise_for_status()
    except Exception as e:
        log(f"Download error for {url}: {e}")
        return f"[Error downloading {url}]"

    # 2. Parse with BS4, isolate <main>
    soup = BeautifulSoup(resp.text, "html.parser")
    main = soup.find("main") or soup.find(id="main-content")
    if not main:
        log("Warning: <main> not found, using full body.")
        main = soup

    # 3. Remove noisy elements before conversion
    for sel in [
        "#sidebar",
        ".sidebar",
        "nav",
        ".toggle-wrapper",
        ".src",
        ".rightside",
        ".out-of-band",
    ]:
        for el in main.select(sel):
            el.decompose()

    # Remove "§" anchor links and spans (section permalink icons)
    for el in main.find_all(["a", "span"], class_="anchor"):
        el.decompose()

    # Remove example file links e.g. examples/foo/bar.rs
    for a in main.find_all("a", href=re.compile(r"^examples/")):
        a.decompose()

    # Strip all remaining <a> tags but keep their inner text
    for a in main.find_all("a"):
        a.replace_with_children()

    # Remove entire noisy sections by heading
    for section_title in _SKIP_SECTIONS:
        for tag in ("h2", "h3", "h4", "h5"):
            _remove_section_by_heading(main, section_title, tag)

    # 4. Convert clean HTML via pandoc
    try:
        process = subprocess.Popen(
            ["pandoc", "-f", "html", "-t", "markdown", "--wrap=none"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        markdown, err = process.communicate(input=str(main))
        if process.returncode != 0:
            log(f"Pandoc error: {err}")
            return f"[Error running pandoc for {url}]"
    except OSError as e:
        log(f"OS Error running pandoc: {e}")
        return "[Error: Pandoc execution failed]"

    # 5. Minimal post-pandoc cleanup
    markdown = markdown.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")
    markdown = markdown.replace(r"\<", "<").replace(r"\>", ">")

    # Remove remaining pandoc attribute blocks: {.foo}, {#bar .baz}, possibly multiline
    markdown = re.sub(r"\s*\{[^}]+\}", "", markdown, flags=re.DOTALL)

    # Remove leftover empty link brackets []
    markdown = re.sub(r"\[\]", "", markdown)

    # Remove stray § symbols
    markdown = re.sub(r"§", "", markdown)

    # Collapse 3+ blank lines to 2
    markdown = re.sub(r"\n{3,}", "\n\n", markdown)

    return markdown.strip()


def generate_markdown(urls):
    outputs = []
    for url in urls:
        content = extract_content(url)
        outputs.append(f"# Source: {url}\n\n{content}")
    return "\n\n---\n\n".join(outputs)


# --- Commands ---


def query(user_input, debug_mode):
    if not shutil.which("pandoc"):
        print("Error: 'pandoc' is not installed or not in your PATH.")
        print("Please install pandoc: https://pandoc.org/installing.html")
        sys.exit(1)

    crate, stripped_path = parse_input(user_input)

    # Load cache
    cache_path = get_cache_path(crate)
    cache = {}
    if os.path.exists(cache_path):
        log(f"Loading cache from: {cache_path}")
        try:
            with open(cache_path, "r") as f:
                cache = json.load(f)
        except Exception as e:
            log(f"Error loading cache: {e}. Resetting.")
            cache = {}

    # Fast path: content already cached
    if user_input in cache and isinstance(cache[user_input], str):
        log(f"Cache HIT for content: '{user_input}'")
        print(cache[user_input])
        if debug_mode:
            dump_log()
        sys.exit(0)

    # Ensure index is loaded
    if "__index_parsed__" not in cache:
        log("Cache index missing. Parsing all.html...")
        index_map = fetch_and_parse_crate_index(crate)
        cache.update(index_map)
        cache["__index_parsed__"] = True

    # Resolve URLs
    if not stripped_path:
        root_url = f"https://docs.rs/{crate}/latest/{crate}/index.html"
        if check_url(root_url):
            urls = [root_url]
        else:
            fail(f"Crate root for '{crate}' not found.")
    else:
        urls = find_urls_in_map(cache, crate, stripped_path, user_input)

    # Generate and cache output
    markdown_output = generate_markdown(urls)
    cache[user_input] = markdown_output
    try:
        log(f"Saving updated cache to: {cache_path}")
        with open(cache_path, "w") as f:
            json.dump(cache, f)
    except Exception as e:
        log(f"Warning: Could not save cache: {e}")

    print(markdown_output)
    if debug_mode:
        dump_log()


def paths(crate_name, debug_mode):
    cache_path = get_cache_path(crate_name)
    cache = {}
    if os.path.exists(cache_path):
        log(f"Loading cache from: {cache_path}")
        try:
            with open(cache_path, "r") as f:
                cache = json.load(f)
        except Exception as e:
            log(f"Error loading cache: {e}. Resetting.")
            cache = {}

    if "__index_parsed__" not in cache:
        log("Cache index missing. Parsing all.html...")
        index_map = fetch_and_parse_crate_index(crate_name)
        cache.update(index_map)
        cache["__index_parsed__"] = True

    for key in sorted(cache.keys()):
        if key == "__index_parsed__":
            continue
        print(f"{crate_name}::{key}")

    if debug_mode:
        dump_log()


def purge_cache(crate_name, debug_mode):
    """Delete cache. If crate_name provided, delete only that crate's cache file."""
    if crate_name:
        cache_path = get_cache_path(crate_name)
        if os.path.exists(cache_path):
            try:
                os.remove(cache_path)
                print(f"Purged cache for crate: {crate_name}")
            except OSError as e:
                fail(f"Could not delete cache file {cache_path}: {e}")
        else:
            print(f"No cache found for crate: {crate_name}")
    else:
        base = get_base_cache_dir()
        cache_dir = os.path.join(base, "extract_docs")
        if os.path.exists(cache_dir):
            try:
                shutil.rmtree(cache_dir)
                print(f"Purged entire cache directory: {cache_dir}")
            except OSError as e:
                fail(f"Could not delete cache directory {cache_dir}: {e}")
        else:
            print("No cache directory found.")
    if debug_mode:
        dump_log()


def print_help():
    print("Usage: python extract_docs.py [OPTIONS] COMMAND")
    print("")
    print("Commands:")
    print("  <crate::path::Item>    Query documentation for a specific item")
    print("  --paths <crate>        List all available items/modules in a crate")
    print("  --purge [<crate>]      Purge cache (all, or for specific crate)")
    print("")
    print("Options:")
    print("  --debug                Show debug information")
    print("  --help                 Show this help message")
    print("")
    print("Examples:")
    print("  python extract_docs.py bevy::app::App")
    print("  python extract_docs.py --debug bevy::app::App")
    print("  python extract_docs.py --paths bevy")
    print("  python extract_docs.py --purge")
    print("  python extract_docs.py --purge bevy")


# --- Entry Point ---


def main():
    if len(sys.argv) == 1 or "--help" in sys.argv[1:]:
        print_help()
        sys.exit(0)

    debug_mode = False
    mode = "query"
    args = []

    for arg in sys.argv[1:]:
        if arg == "--debug":
            debug_mode = True
        elif arg == "--paths":
            mode = "paths"
        elif arg.startswith("--"):
            fail(f"Unknown argument: {arg}")
        else:
            args.append(arg)

    if mode == "paths":
        if len(args) != 1:
            fail("Usage: python extract_docs.py [--debug] --paths <crate>")
        paths(args[0], debug_mode)
    else:
        if len(args) != 1:
            fail("Usage: python extract_docs.py [--debug] <crate::path::Item>")
        query(args[0], debug_mode)


if __name__ == "__main__":
    try:
        signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    except AttributeError:
        pass
    try:
        main()
    except BrokenPipeError:
        devnull = os.open(os.devnull, os.O_WRONLY)
        os.dup2(devnull, sys.stdout.fileno())
        sys.exit(0)
