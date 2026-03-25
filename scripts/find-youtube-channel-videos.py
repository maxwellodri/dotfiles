#!/usr/bin/env python3
"""
Queue videos from a YouTube channel that aren't already downloaded locally.
Outputs URLs to a file for later use with tsp_ytdlp.
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


def get_video_url_from_file(filepath: Path) -> str | None:
    """Extract video URL from file's comment metadata using ffprobe."""
    try:
        result = subprocess.run(
            [
                "ffprobe",
                "-v",
                "quiet",
                "-print_format",
                "json",
                "-show_format",
                str(filepath),
            ],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode != 0:
            return None
        data = json.loads(result.stdout)
        comment = data.get("format", {}).get("tags", {}).get("comment", "")
        if comment and ("youtube.com" in comment or "youtu.be" in comment):
            return comment.strip()
    except Exception:
        pass
    return None


def extract_video_id(url: str) -> str | None:
    """Extract YouTube video ID from URL."""
    patterns = [
        r"(?:v=|youtu\.be/)([a-zA-Z0-9_-]{11})",
        r"youtube\.com/embed/([a-zA-Z0-9_-]{11})",
        r"youtube\.com/shorts/([a-zA-Z0-9_-]{11})",
    ]
    for pattern in patterns:
        match = re.search(pattern, url)
        if match:
            return match.group(1)
    return None


def get_channel_id_from_video_url(video_url: str) -> str | None:
    """Get channel_id from a YouTube video URL using yt-dlp."""
    try:
        result = subprocess.run(
            ["yt-dlp", "--print", "%(channel_id)s", video_url],
            capture_output=True,
            text=True,
            timeout=60,
        )
        channel_id = result.stdout.strip()
        if channel_id and result.returncode == 0:
            return channel_id
    except Exception as e:
        print(f"Error fetching channel_id for video {video_url}: {e}", file=sys.stderr)
    return None


def get_channel_video_ids(channel_id: str) -> set[str]:
    """Fetch all video IDs from a YouTube channel."""
    channel_url = f"https://www.youtube.com/channel/{channel_id}/videos"
    try:
        result = subprocess.run(
            [
                "yt-dlp",
                "--simulate",
                "--flat-playlist",
                "--lazy-playlist",
                "--print",
                "%(id)s",
                channel_url,
            ],
            capture_output=True,
            text=True,
            timeout=300,
        )
        if result.returncode == 0:
            ids = set()
            for line in result.stdout.strip().split("\n"):
                line = line.strip()
                if line:
                    ids.add(line)
            return ids
        else:
            print(f"Error fetching channel videos: {result.stderr}", file=sys.stderr)
    except Exception as e:
        print(f"Error fetching channel videos: {e}", file=sys.stderr)
    return set()


def find_video_files(directory: Path) -> list[Path]:
    """Recursively find all video files in directory."""
    video_extensions = {".mp4", ".mkv", ".webm", ".avi", ".mov", ".ogg", ".mp3", ".m4a"}
    video_files = []
    for path in directory.rglob("*"):
        if path.is_file() and path.suffix.lower() in video_extensions:
            video_files.append(path)
    return video_files


def get_local_video_ids(directory: Path) -> set[str]:
    """Get set of video IDs for all YouTube videos in directory."""
    video_files = find_video_files(directory)
    local_ids = set()
    for filepath in video_files:
        url = get_video_url_from_file(filepath)
        if url:
            video_id = extract_video_id(url)
            if video_id:
                local_ids.add(video_id)
    return local_ids


def main():
    parser = argparse.ArgumentParser(
        description="Queue videos from a YouTube channel not already downloaded locally"
    )
    parser.add_argument(
        "--example-video",
        required=True,
        help="Example video file to extract channel from",
    )
    parser.add_argument(
        "--dir",
        required=True,
        dest="directory",
        help="Directory to check for existing videos",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Output file for missing video URLs",
    )
    args = parser.parse_args()

    example_video = Path(args.example_video).expanduser()
    if not example_video.is_file():
        print(f"Example video not found: {example_video}", file=sys.stderr)
        sys.exit(1)

    example_url = get_video_url_from_file(example_video)
    if not example_url:
        print(f"No YouTube URL found in metadata of {example_video}", file=sys.stderr)
        sys.exit(1)

    channel_id = get_channel_id_from_video_url(example_url)
    if not channel_id:
        print(f"Failed to get channel_id from {example_url}", file=sys.stderr)
        sys.exit(1)

    print(f"Channel ID: {channel_id}", file=sys.stderr)

    search_dir = Path(args.directory).expanduser()
    if not search_dir.is_dir():
        print(f"Directory not found: {search_dir}", file=sys.stderr)
        sys.exit(1)

    print("Fetching local video IDs...", file=sys.stderr)
    local_ids = get_local_video_ids(search_dir)
    print(f"Found {len(local_ids)} local videos", file=sys.stderr)

    print("Fetching channel video IDs...", file=sys.stderr)
    channel_ids = get_channel_video_ids(channel_id)
    print(f"Channel has {len(channel_ids)} videos", file=sys.stderr)

    missing_ids = channel_ids - local_ids
    print(f"Found {len(missing_ids)} videos not in directory", file=sys.stderr)

    output_path = Path(args.output).expanduser()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with output_path.open("w") as f:
        for video_id in sorted(missing_ids):
            f.write(f"https://www.youtube.com/watch?v={video_id}\n")

    print(f"Wrote {len(missing_ids)} URLs to {output_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
