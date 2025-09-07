#!/bin/bash

# Finds videos >720p and downscales them to 720p using VA-API

# Default settings
DRY_RUN=0
SEARCH_DIR=""
ACCEPT_ALL=0

# Arrays to track file size info
ORIGINAL_SIZES=()
FINAL_SIZES=()
TRANSCODED_FILES=()

# Video extensions found in your media directory
VIDEO_EXTENSIONS=("avi" "m4v" "mkv" "mp4" "wmv")

# Function to check if file is a video
is_video_file() {
    local file="$1"
    local ext="${file##*.}"
    ext="${ext,,}" # Convert to lowercase
    
    for valid_ext in "${VIDEO_EXTENSIONS[@]}"; do
        if [[ "$ext" == "$valid_ext" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to get video resolution
get_resolution() {
    local file="$1"
    ffprobe -v quiet -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$file" 2>/dev/null
}

# Function to check if resolution > 720p
needs_downscale() {
    local resolution="$1"
    if [[ -z "$resolution" || "$resolution" == "x" ]]; then
        return 1
    fi
    
    local height
    height=$(echo "$resolution" | cut -d'x' -f2)
    
    # Check if height > 720 (720p is 1280x720)
    if [[ "$height" -gt 720 ]]; then
        return 0
    fi
    return 1
}

# Function to test VA-API support
test_vaapi() {
    echo "=== Testing VA-API Hardware Encoding ==="
    
    # Check vainfo
    if command -v vainfo >/dev/null 2>&1; then
        echo "✓ vainfo found, checking HEVC encoding support:"
        if vainfo 2>/dev/null | grep -E "(HEVC|H265).*Enc" >/dev/null; then
            echo "✓ HEVC encoding supported"
        else
            echo "⚠ HEVC encoding not found in vainfo output"
        fi
    else
        echo "⚠ vainfo not found (install libva-utils)"
    fi
    
    # Test the actual encoder using working syntax from Test 4
    echo "Testing hevc_vaapi encoder..."
    local test_temp="$HOME/.cache/dotfiles/transcode/test_encoder.mp4"
    mkdir -p "$(dirname "$test_temp")"
    
    if ffmpeg -f lavfi -i "testsrc=duration=1:size=320x240:rate=1" \
        -vaapi_device /dev/dri/renderD128 \
        -vf "format=nv12,hwupload" \
        -c:v hevc_vaapi -frames:v 1 \
        -y "$test_temp" >/dev/null 2>&1; then
        echo "✓ hevc_vaapi encoder works"
        rm -f "$test_temp"
        return 0
    else
        echo "✗ hevc_vaapi encoder failed"
        rm -f "$test_temp"
        return 1
    fi
}

# Function to format file size in human readable format
format_size() {
    local size=$1
    if [[ $size -ge 1073741824 ]]; then
        awk "BEGIN {printf \"%.2f GB\", $size/1073741824}"
    elif [[ $size -ge 1048576 ]]; then
        awk "BEGIN {printf \"%.2f MB\", $size/1048576}"
    elif [[ $size -ge 1024 ]]; then
        awk "BEGIN {printf \"%.2f KB\", $size/1024}"
    else
        echo "${size} B"
    fi
}

# Function to transcode video using the working command format
transcode_video() {
    local input_file
    input_file="$(realpath "$1")"
    local temp_dir="$HOME/.cache/dotfiles/transcode"
    local temp_file="$temp_dir/transcoding.mp4"
    
    echo "=== Transcoding: $(basename "$input_file") ==="
    echo "Input: $input_file"
    echo "Temp: $temp_file"
    
    # Get original file size
    local original_size
    original_size=$(stat -c%s "$input_file" 2>/dev/null || echo "0")
    echo "Original size: $(format_size "$original_size")"
    
    # Create temp directory
    if ! mkdir -p "$temp_dir"; then
        echo "✗ Failed to create temp directory: $temp_dir"
        return 1
    fi
    
    # Remove any existing temp file
    rm -f "$temp_file"
    
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[DRY RUN] Would execute:"
        echo "ffmpeg -hwaccel vaapi -i \"$input_file\" -vf \"format=nv12,hwupload,scale_vaapi=-2:720\" -c:v hevc_vaapi -qp 28 -c:a copy \"$temp_file\""
        echo "[DRY RUN] Would replace original file"
        return 0
    fi
    
    # Execute the exact working command format
    echo "Executing ffmpeg command..."
    if ffmpeg -hwaccel vaapi \
        -i "$input_file" \
        -vf "format=nv12,hwupload,scale_vaapi=-2:720" \
        -c:v hevc_vaapi \
        -qp 28 \
        -c:a copy \
        "$temp_file" 2>&1 | tee "/tmp/ffmpeg_$(basename "$input_file").log"; then
        
        # Check if temp file was created and has content
        if [[ ! -f "$temp_file" ]]; then
            echo "✗ Temp file was not created"
            return 1
        fi
        
        local temp_size
        temp_size=$(stat -c%s "$temp_file" 2>/dev/null || echo "0")
        if [[ "$temp_size" -eq 0 ]]; then
            echo "✗ Temp file is empty"
            rm -f "$temp_file"
            return 1
        fi
        
        echo "✓ Temp file created ($(format_size "$temp_size"))"
        
        # Verify it's a valid video
        if ! ffprobe -v quiet "$temp_file" >/dev/null 2>&1; then
            echo "✗ Temp file is not a valid video"
            rm -f "$temp_file"
            return 1
        fi
        
        echo "✓ Temp file is valid video"
        
        # Replace original with transcoded version
        if cp "$temp_file" "$input_file"; then
            rm -f "$temp_file"
            local final_size
            final_size=$(stat -c%s "$input_file" 2>/dev/null || echo "0")
            local size_reduction=$((original_size - final_size))
            
            echo "✓ Successfully transcoded: $(basename "$input_file")"
            echo "  Original: $(format_size "$original_size")"
            echo "  Final: $(format_size "$final_size")"
            if [[ $size_reduction -gt 0 ]]; then
                echo "  Saved: $(format_size $size_reduction) ($(awk "BEGIN {printf \"%.1f%%\", ($size_reduction*100)/$original_size}"))"
            else
                echo "  Size increased by: $(format_size $((final_size - original_size)))"
            fi
            
            # Store size info for summary (using global arrays)
            ORIGINAL_SIZES+=("$original_size")
            FINAL_SIZES+=("$final_size")
            TRANSCODED_FILES+=("$(basename "$input_file")")
            
            return 0
        else
            echo "✗ Failed to copy temp file to original location"
            rm -f "$temp_file"
            return 1
        fi
    else
        echo "✗ FFmpeg failed"
        echo "Log saved to: /tmp/ffmpeg_$(basename "$input_file").log"
        rm -f "$temp_file"
        return 1
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dryrun|--dry-run|-n)
                DRY_RUN=1
                shift
                ;;
            --accept|-y)
                ACCEPT_ALL=1
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS] [DIRECTORY]"
                echo ""
                echo "Options:"
                echo "  --dryrun, -n     Show what would be done without modifying files"
                echo "  --accept, -y     Skip confirmation prompt and proceed automatically"
                echo "  --help, -h       Show this help message"
                echo ""
                echo "Arguments:"
                echo "  DIRECTORY        Directory to search (default: current directory)"
                echo ""
                echo "This script finds videos larger than 720p and downscales them using VA-API."
                exit 0
                ;;
            -*)
                echo "Unknown option: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
            *)
                # This is the directory argument
                SEARCH_DIR="$1"
                shift
                ;;
        esac
    done
}

# Main function
main() {
    local search_dir="${SEARCH_DIR:-.}"
    local start_time
    start_time=$(date +%s)
    
    if [[ ! -d "$search_dir" ]]; then
        echo "Error: Directory '$search_dir' does not exist."
        exit 1
    fi
    
    # Test VA-API support
    if ! test_vaapi; then
        echo "Error: VA-API HEVC encoding not available. Please check your drivers."
        exit 1
    fi
    
    echo ""
    echo "Searching for video files in: $(realpath "$search_dir")"
    echo "Video extensions: ${VIDEO_EXTENSIONS[*]}"
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "*** DRY RUN MODE - No files will be modified ***"
    fi
    echo ""
    
    # Find all video files
    local video_files=()
    while IFS= read -r -d '' file; do
        if is_video_file "$file"; then
            video_files+=("$file")
        fi
    done < <(find "$search_dir" -type f -print0)
    
    if [[ ${#video_files[@]} -eq 0 ]]; then
        echo "No video files found."
        exit 0
    fi
    
    echo "Found ${#video_files[@]} video files."
    echo ""
    
    # Check which files need downscaling
    local files_to_process=()
    local skipped_count=0
    
    for file in "${video_files[@]}"; do
        echo -n "Checking: $(basename "$file")... "
        
        resolution=$(get_resolution "$file")
        if [[ -z "$resolution" || "$resolution" == "x" ]]; then
            echo "SKIP (unable to get resolution)"
            ((skipped_count++))
            continue
        fi
        
        if needs_downscale "$resolution"; then
            echo -e "PROCESS (\e[32m${resolution} > 720p\e[0m)"
            files_to_process+=("$file")
            echo -e "  → \e[32m$(realpath "$file")\e[0m"
        else
            echo "SKIP (${resolution} ≤ 720p)"
            ((skipped_count++))
        fi
    done
    
    echo ""
    echo "Summary:"
    echo "  Files to process: ${#files_to_process[@]}"
    echo "  Files to skip: $skipped_count"
    echo ""
    
    if [[ ${#files_to_process[@]} -eq 0 ]]; then
        echo "No files need processing."
        exit 0
    fi
    
    # User confirmation
    echo "Files that will be transcoded:"
    for file in "${files_to_process[@]}"; do
        echo "  $(realpath "$file")"
    done
    echo ""
    
    if [[ $ACCEPT_ALL -eq 1 ]]; then
        echo "Auto-accepting due to --accept flag"
    else
        read -p "Proceed with transcoding? [Y/n]: " -n 1 -r
        echo ""
        
        if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ -n $REPLY ]]; then
            echo "Cancelled."
            exit 0
        fi
    fi
    
    # Process files
    echo ""
    echo "Starting transcoding..."
    local success_count=0
    local fail_count=0
    
    for file in "${files_to_process[@]}"; do
        echo ""
        echo "=== Processing file $((success_count + fail_count + 1)) of ${#files_to_process[@]} ==="
        if transcode_video "$file"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done
    
    # Calculate total time
    local end_time
    end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    local hours=$((total_time / 3600))
    local minutes=$(((total_time % 3600) / 60))
    local seconds=$((total_time % 60))
    
    local time_str=""
    if [[ $hours -gt 0 ]]; then
        time_str="${hours}h ${minutes}m ${seconds}s"
    elif [[ $minutes -gt 0 ]]; then
        time_str="${minutes}m ${seconds}s"
    else
        time_str="${seconds}s"
    fi
    
    echo ""
    echo "Transcoding complete!"
    echo "  Successful: $success_count"
    echo "  Failed: $fail_count"
    echo "  Total time: $time_str"
    
    # Calculate total size reduction
    local total_original=0
    local total_final=0
    
    for size in "${ORIGINAL_SIZES[@]}"; do
        total_original=$((total_original + size))
    done
    
    for size in "${FINAL_SIZES[@]}"; do
        total_final=$((total_final + size))
    done
    
    local total_reduction=$((total_original - total_final))
    
    # Show detailed file size summary
    if [[ ${#TRANSCODED_FILES[@]} -gt 0 ]]; then
        echo ""
        echo "=== File Size Summary ==="
        for i in "${!TRANSCODED_FILES[@]}"; do
            local orig=${ORIGINAL_SIZES[$i]}
            local final=${FINAL_SIZES[$i]}
            local reduction=$((orig - final))
            local filename="${TRANSCODED_FILES[$i]}"
            
            echo "  $filename:"
            echo "    Before: $(format_size "$orig")"
            echo "    After:  $(format_size "$final")"
            if [[ $reduction -gt 0 ]]; then
                echo "    Saved:  $(format_size $reduction) ($(awk "BEGIN {printf \"%.1f%%\", ($reduction*100)/$orig}"))"
            else
                echo "    Increased: $(format_size $((final - orig)))"
            fi
        done
        
        echo ""
        echo "=== Total Summary ==="
        echo "  Total original size: $(format_size $total_original)"
        echo "  Total final size:    $(format_size $total_final)"
        if [[ $total_reduction -gt 0 ]]; then
            echo "  Total space saved:   $(format_size $total_reduction) ($(awk "BEGIN {printf \"%.1f%%\", ($total_reduction*100)/$total_original}"))"
        else
            echo "  Total size increase: $(format_size $((total_final - total_original)))"
        fi
    fi
    
    # Send desktop notification (only if not dry run)
    if [[ $DRY_RUN -eq 0 ]] && command -v notify-send >/dev/null 2>&1; then
        local total_files=$((success_count + fail_count))
        local notification_title="Video Transcoding Complete"
        local notification_message="Processed $total_files files in $time_str
✓ Successful: $success_count
✗ Failed: $fail_count"
        
        if [[ $total_reduction -gt 0 ]]; then
            notification_message="$notification_message
💾 Space saved: $(format_size $total_reduction)"
        fi
        
        notify-send -t 0 "$notification_title" "$notification_message"
    fi
}

# Check dependencies
if ! command -v ffmpeg &> /dev/null; then
    echo "Error: ffmpeg is not installed or not in PATH."
    exit 1
fi

if ! command -v ffprobe &> /dev/null; then
    echo "Error: ffprobe is not installed or not in PATH."
    exit 1
fi

# Parse command line arguments and run
parse_args "$@"
main
