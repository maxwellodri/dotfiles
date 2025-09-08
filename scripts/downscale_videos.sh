#!/bin/bash

#set -euo pipefail

# Global variables (defined early for shellcheck)
TEMP_DIR="/tmp/transcode_$$"
CACHE_DIR="$HOME/.cache/dotfiles"
TEMP_OUTPUT="$CACHE_DIR/transcoding.mp4"

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Supported video extensions
VIDEO_EXTENSIONS=("avi" "m4v" "mkv" "mp4" "wmv" "mov" "ts" "mts" "m2ts")

# Results tracking arrays and counters
declare -a SUCCESSFUL_FILES=()
declare -a FAILED_FILES=()
declare -a ORIGINAL_SIZES=()
declare -a NEW_SIZES=()
declare -a REDUCTION_PERCENTAGES=()
declare -a TRANSCODE_FILES=()
SUCCESS_COUNT=0
FAILURE_COUNT=0
TOTAL_ORIGINAL_SIZE=0
TOTAL_NEW_SIZE=0

# Create temp directory
mkdir -p "$TEMP_DIR"
mkdir -p "$CACHE_DIR"

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
    rm -f "$TEMP_OUTPUT"
    exit 1
}

# Set up cleanup trap
trap cleanup EXIT

# Function to check if file has video extension
is_video_file() {
    local file="$1"
    local ext="${file##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    
    for valid_ext in "${VIDEO_EXTENSIONS[@]}"; do
        if [[ "$ext" == "$valid_ext" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to get video resolution using ffprobe
get_resolution() {
    local file="$1"
    local resolution
    
    resolution=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$file" 2>/dev/null || echo "")
    
    if [[ -n "$resolution" && "$resolution" =~ ^[0-9]+x[0-9]+$ ]]; then
        echo "$resolution"
    else
        echo ""
    fi
}

# Function to get file size in bytes
get_file_size() {
    local file="$1"
    if [[ -f "$file" ]]; then
        stat -c%s "$file" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Function to format bytes to human readable
format_bytes() {
    local bytes="$1"
    if (( bytes >= 1073741824 )); then
        printf "%.1fGB" "$(echo "scale=1; $bytes / 1073741824" | bc)"
    elif (( bytes >= 1048576 )); then
        printf "%.1fMB" "$(echo "scale=1; $bytes / 1048576" | bc)"
    else
        printf "%.1fKB" "$(echo "scale=1; $bytes / 1024" | bc)"
    fi
}

# Function to get video duration in seconds with decimal precision
get_duration() {
    local file="$1"
    ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "0"
}

# Function to record successful transcode
record_success() {
    local file="$1"
    local original_size="$2"
    local new_size="$3"
    local reduction_percent="$4"
    
    SUCCESSFUL_FILES+=("$file")
    ORIGINAL_SIZES+=("$original_size")
    NEW_SIZES+=("$new_size")
    REDUCTION_PERCENTAGES+=("$reduction_percent")
    ((SUCCESS_COUNT++))
    TOTAL_ORIGINAL_SIZE=$((TOTAL_ORIGINAL_SIZE + original_size))
    TOTAL_NEW_SIZE=$((TOTAL_NEW_SIZE + new_size))
}

# Function to record failed transcode
record_failure() {
    local file="$1"
    
    FAILED_FILES+=("$file")
    ((FAILURE_COUNT++))
}

# Function to transcode a single file
transcode_file() {
    local input_file="$1"
    local original_size original_duration
    
    original_size=$(get_file_size "$input_file")
    original_duration=$(get_duration "$input_file")
    
    echo "Transcoding: $(basename "$input_file")"
    
    # Remove existing temp file if it exists (HandBrake behavior with existing files is unclear)
    rm -f "$TEMP_OUTPUT"
    
    # Run HandBrake directly (no command substitution to avoid buffering)
    ffmpeg -i "$input_file" -c:v libx264 -crf 22 -vf scale=-2:720 -c:a aac -b:a 128k -ac 2 "$TEMP_OUTPUT" -y
    #HandBrakeCLI --input "$input_file" --output "$TEMP_OUTPUT" --encoder x264 --quality 22 --maxHeight 720 --loose-anamorphic --audio 1 --aencoder av_aac --ab 128 --mixdown stereo --verbose 2
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        echo -e "${RED}ERROR: HandBrake failed for $input_file${NC}"
        rm -f "$TEMP_OUTPUT"
        record_failure "$input_file"
        return 0  # Continue to next file instead of exiting loop
    fi
    
    # Validate the transcoded file BEFORE replacing original
    local new_size new_duration
    new_size=$(get_file_size "$TEMP_OUTPUT")
    new_duration=$(get_duration "$TEMP_OUTPUT")
    
    # Check if file exists and has reasonable size
    if [[ ! -f "$TEMP_OUTPUT" || $new_size -eq 0 ]]; then
        echo -e "${RED}ERROR: Output file is missing or empty for $input_file${NC}"
        rm -f "$TEMP_OUTPUT"
        record_failure "$input_file"
        return 0  # Continue to next file instead of exiting loop
    fi
    
    # Check duration within 1% tolerance BEFORE overwriting
    local duration_diff_percent
    duration_diff_percent=$(echo "scale=2; (($new_duration - $original_duration) * 100) / $original_duration" | bc)
    duration_diff_percent=${duration_diff_percent#-}  # Remove negative sign for absolute value
    
    if (( $(echo "$duration_diff_percent > 1.0" | bc -l) )); then
        echo -e "${RED}ERROR: Duration difference exceeds 1% for $input_file (original: ${original_duration}s, new: ${new_duration}s, diff: ${duration_diff_percent}%)${NC}"
        rm -f "$TEMP_OUTPUT"
        record_failure "$input_file"
        return 0  # Continue to next file instead of exiting loop
    fi
    
    # Check for excessive size reduction (>90%) BEFORE overwriting
    local size_reduction_percent
    size_reduction_percent=$(echo "scale=0; (($original_size - $new_size) * 100) / $original_size" | bc)
    if [[ $size_reduction_percent -gt 90 ]]; then
        echo -e "${RED}ERROR: Excessive size reduction (${size_reduction_percent}%) for $input_file${NC}"
        rm -f "$TEMP_OUTPUT"
        record_failure "$input_file"
        return 0  # Continue to next file instead of exiting loop
    fi
    
    # All sanity checks passed - safe to replace original file
    mv "$TEMP_OUTPUT" "$input_file"
    
    # Show result
    local formatted_original formatted_new
    formatted_original=$(format_bytes "$original_size")
    formatted_new=$(format_bytes "$new_size")
    
    echo -e "${YELLOW}Transcoded $(basename "$input_file") $formatted_original -> $formatted_new (${size_reduction_percent}% reduction)${NC}"
    
    # Record success
    record_success "$input_file" "$original_size" "$new_size" "$size_reduction_percent"
    
    return 0
}

# Check dependencies
if ! command -v ffprobe >/dev/null 2>&1; then
    echo -e "${RED}ERROR: ffprobe not found. Please install FFmpeg.${NC}"
    exit 1
fi

if ! command -v HandBrakeCLI >/dev/null 2>&1; then
    echo -e "${RED}ERROR: HandBrakeCLI not found. Please install HandBrake CLI.${NC}"
    exit 1
fi

if ! command -v bc >/dev/null 2>&1; then
    echo -e "${RED}ERROR: bc calculator not found. Please install bc.${NC}"
    exit 1
fi

# Find video files - inlined from find_video_files function
paths=("$@")
all_video_files=()

# Default to current directory if no arguments
if [[ ${#paths[@]} -eq 0 ]]; then
    paths=(".")
fi

for path in "${paths[@]}"; do
    if [[ -f "$path" ]]; then
        if is_video_file "$path"; then
            all_video_files+=("$(realpath "$path")")
        fi
    elif [[ -d "$path" ]]; then
        while IFS= read -r -d '' file; do
            if is_video_file "$file"; then
                all_video_files+=("$(realpath "$file")")
            fi
        done < <(find "$path" -type f -print0)
    fi
done

# Remove duplicates and sort
readarray -t all_video_files < <(printf '%s\n' "${all_video_files[@]}" | sort -u)

echo "DEBUG: Found ${#all_video_files[@]} total video files"

# Analyze files and build transcode list - inlined from analyze_files
count=1
echo "=== FILES ==="

for file in "${all_video_files[@]}"; do
    echo "DEBUG: Processing file: $file"
    resolution=$(get_resolution "$file")
    echo "DEBUG: Resolution for $file: $resolution"
    
    if [[ -z "$resolution" ]]; then
        echo "$count. $file [unable to read resolution]"
    else
        IFS='x' read -r width height <<< "$resolution"
        echo "DEBUG: Width=$width, Height=$height"
        
        if (( height > width )); then
            echo "$count. $file [$resolution vertical video]"
        elif (( height <= 720 )); then
            echo "$count. $file [$resolution already ≤720p]"
        else
            echo -e "$count. ${GREEN}$file${NC} [$resolution needs transcoding]"
            TRANSCODE_FILES+=("$file")
            echo "DEBUG: Added to transcode list: $file"
        fi
    fi
    ((count++))
done

echo
echo "Found ${#all_video_files[@]} video files [${#TRANSCODE_FILES[@]} videos need transcoding]:"
echo

# Save transcode files list for debugging
printf '%s\n' "${TRANSCODE_FILES[@]}" > "$TEMP_DIR/transcode_list.txt"
echo "DEBUG: Saved ${#TRANSCODE_FILES[@]} files to transcode list"

# Confirm transcoding - inlined from confirm_transcoding
if [[ ${#TRANSCODE_FILES[@]} -eq 0 ]]; then
    echo "No files need transcoding."
    exit 0
fi

count=1
echo "Files to be transcoded:"
for file in "${TRANSCODE_FILES[@]}"; do
    echo "$count. $file"
    ((count++))
done
echo

read -p "Proceed with transcoding? [Y/n]: " -r response
case "$response" in
    [nN]|[nN][oO])
        echo "Transcoding cancelled."
        exit 0
        ;;
    *)
        ;;
esac

# Process files
for file in "${TRANSCODE_FILES[@]}"; do
    transcode_file "$file"
done

# Show summary - inlined from show_summary
total_attempts=$((SUCCESS_COUNT + FAILURE_COUNT))

if [[ $total_attempts -eq 0 ]]; then
    echo "No transcoding attempts made."
    exit 0
fi

# Add separator before summary
echo
echo "=== SUMMARY ==="

# Show individual file results
if [[ $SUCCESS_COUNT -gt 0 ]]; then
    for i in "${!SUCCESSFUL_FILES[@]}"; do
        file="${SUCCESSFUL_FILES[i]}"
        orig_size="${ORIGINAL_SIZES[i]}"
        new_size="${NEW_SIZES[i]}"
        reduction="${REDUCTION_PERCENTAGES[i]}"
        
        formatted_orig=$(format_bytes "$orig_size")
        formatted_new=$(format_bytes "$new_size")
        
        echo -e "${YELLOW}Transcoded $(basename "$file") $formatted_orig -> $formatted_new (${reduction}% reduction)${NC}"
    done
    echo
fi

# Show totals
formatted_original=$(format_bytes "$TOTAL_ORIGINAL_SIZE")
formatted_new=$(format_bytes "$TOTAL_NEW_SIZE")

if [[ $TOTAL_ORIGINAL_SIZE -gt 0 ]]; then
    total_saved=$((TOTAL_ORIGINAL_SIZE - TOTAL_NEW_SIZE))
    savings_percent=$(echo "scale=0; ($total_saved * 100) / $TOTAL_ORIGINAL_SIZE" | bc)
    
    echo -e "${YELLOW}Successfully transcoded $SUCCESS_COUNT of $total_attempts videos. $formatted_original -> $formatted_new (${savings_percent}% reduction)${NC}"
else
    echo -e "${YELLOW}Successfully transcoded $SUCCESS_COUNT of $total_attempts videos.${NC}"
fi

if [[ $FAILURE_COUNT -gt 0 ]]; then
    echo -e "${RED}$FAILURE_COUNT files failed to transcode:${NC}"
    for failed_file in "${FAILED_FILES[@]}"; do
        echo "  - $(basename "$failed_file")"
    done
fi

# Manual cleanup
cleanup
