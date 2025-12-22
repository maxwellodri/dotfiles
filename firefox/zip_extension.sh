#!/bin/bash

# Array of valid extensions to zip
VALID_EXTENSIONS=("copy-download-path@local")

# Get script directory (firefox/ directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTENSIONS_DIR="$SCRIPT_DIR/extensions"
OUTPUT_DIR="$SCRIPT_DIR/zipped_extensions"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Function to validate extension
validate_extension() {
    local ext_path="$1"
    local manifest="$ext_path/manifest.json"
    
    if [ ! -f "$manifest" ]; then
        echo "Error: manifest.json not found in $ext_path"
        return 1
    fi
    
    # Validate JSON format
    if ! jq empty "$manifest" 2>/dev/null; then
        echo "Error: Invalid JSON in manifest.json"
        return 1
    fi
    
    # Check for required version field
    if ! jq -e '.version' "$manifest" >/dev/null 2>&1; then
        echo "Error: version field missing from manifest.json"
        return 1
    fi
    
    return 0
}

# Function to extract version using jq
get_version() {
    local manifest="$1"
    jq -r '.version' "$manifest" 2>/dev/null || echo "unknown"
}

# Function to zip an extension
zip_extension() {
    local ext_name="$1"
    local ext_path="$EXTENSIONS_DIR/$ext_name"
    local manifest="$ext_path/manifest.json"
    
    # Validate extension
    if ! validate_extension "$ext_path"; then
        echo "Skipping $ext_name - validation failed"
        return 1
    fi
    
    # Extract version
    local version
    version=$(get_version "$manifest")
    if [ "$version" = "null" ] || [ -z "$version" ]; then
        echo "Warning: Could not extract version from $manifest, using 'unknown'"
        version="unknown"
    fi
    
    local output_filename="${ext_name}-${version}.zip"
    local output_path="$OUTPUT_DIR/$output_filename"
    
    # Change to extension directory
    cd "$ext_path" || {
        echo "Error: Cannot change to directory $ext_path"
        return 1
    }
    
    # Create zip file (overwrite if exists)
    echo "Creating zip for $ext_name (version $version)..."
    if zip -r "$output_path" . -x "*.git*" "*.DS_Store*" "*.swp" "*~"; then
        echo "✓ Created: $output_filename"
        return 0
    else
        echo "✗ Failed to create zip for $ext_name"
        return 1
    fi
}

# Process each valid extension
echo "Starting extension zip process..."
successful=0
total=0

for ext in "${VALID_EXTENSIONS[@]}"; do
    total=$((total + 1))
    if [ -d "$EXTENSIONS_DIR/$ext" ]; then
        if zip_extension "$ext"; then
            successful=$((successful + 1))
        fi
    else
        echo "Warning: Extension directory not found: $ext"
    fi
done

echo ""
echo "Zip creation complete!"
echo "Successful: $successful/$total extensions processed"
echo "Output directory: $OUTPUT_DIR"