#!/bin/bash

# Define script directory and container name
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONTAINER_NAME="llama-cpp"
SERVER_PORT=42070

# Function to check if server is running
is_server_running() {
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        return 0  # Server is running
    else
        return 1  # Server is not running
    fi
}

# Function to get the model currently loaded in the server
get_loaded_model() {
    # For Vulkan image format
    local model
    model=$(docker logs "${CONTAINER_NAME}" 2>&1 | grep -o "load_model: loading model.*models/[^ ']*" | head -1)
    
    # Extract the model name
    if [ -n "$model" ]; then
        # Extract just the filename from the path
        model=${model##*/}
        echo "$model"
    else
        # Fallback to empty string if not found
        echo ""
    fi
}

# Check arguments
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <model_file> <prompt> [max_tokens] [temperature]"
    echo "Example: $0 llama-3-8b-instruct.Q4_K_M.gguf \"Tell me a short story about robots.\" 512 0.7"
    exit 1
fi

MODEL_FILE="$1"
PROMPT="$2"
MAX_TOKENS=${3:-512}  # Default to 512 if not specified
TEMPERATURE=${4:-0.7}  # Default to 0.7 if not specified

# Ensure server is running with the correct model
if is_server_running; then
    # Get the currently loaded model - simpler approach to avoid sed errors
    LOADED_MODEL=$(get_loaded_model)
    
    if [[ "$LOADED_MODEL" == "$MODEL_FILE" ]]; then
        echo "Server already running with model: $MODEL_FILE"
    else
        echo "Server is running but with a different model: $LOADED_MODEL"
        echo "Restarting with model: $MODEL_FILE"
        
        # Stop the current container
        docker stop "${CONTAINER_NAME}" > /dev/null
        
        # Start the server with the new model
        "${SCRIPT_DIR}/deploy.sh" "$MODEL_FILE"
    fi
else
    echo "Starting server with model: $MODEL_FILE"
    # Start the server
    "${SCRIPT_DIR}/deploy.sh" "$MODEL_FILE"
fi

# Format the prompt for TinyLlama
FORMATTED_PROMPT="<|im_start|>user\n${PROMPT}<|im_end|>\n<|im_start|>assistant\n"

# Prepare the API request
JSON_DATA=$(cat <<EOF
{
  "prompt": "$FORMATTED_PROMPT",
  "n_predict": $MAX_TOKENS,
  "temperature": $TEMPERATURE,
  "stop": ["<|im_end|>"]
}
EOF
)

# Wait a moment for server to be ready
sleep 2

# Send request to server and display result
echo "Sending prompt to server:"
echo "\"$PROMPT\""
echo "---------------------------------------------"

# Use jq if available, otherwise show full response
if command -v jq >/dev/null 2>&1; then
    RESULT=$(curl -s -X POST "http://localhost:${SERVER_PORT}/completion" -d "$JSON_DATA" | jq -r '.content' 2>/dev/null)
    if [ -z "$RESULT" ]; then
        echo "Warning: Empty response or content extraction failed. Full response:"
        curl -s -X POST "http://localhost:${SERVER_PORT}/completion" -d "$JSON_DATA"
    else
        echo "$RESULT"
    fi
else
    curl -s -X POST "http://localhost:${SERVER_PORT}/completion" -d "$JSON_DATA"
fi

echo ""
echo "---------------------------------------------"
echo "Model remains loaded in GPU memory for future queries."
echo "To stop the server: docker stop ${CONTAINER_NAME}"
