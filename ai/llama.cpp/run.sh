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
    docker logs "${CONTAINER_NAME}" 2>&1 | grep -o 'loading model from /models/[^ ]*' | head -1 | sed 's/loading model from \/models\///'
}

# Function to ensure server is running with the specified model
ensure_server() {
    local model_name="$1"
    shift
    # Use "$*" instead of $@ to properly handle all arguments as a single string
    local extra_args="$*"
    
    if is_server_running; then
        # Declare and assign separately to avoid masking return values
        local loaded_model
        loaded_model=$(get_loaded_model)
        
        if [[ "$loaded_model" == "$model_name" ]]; then
            echo "Server already running with model: $model_name"
        else
            echo "Server is running but with a different model: $loaded_model"
            echo "Stopping current server..."
            docker stop "${CONTAINER_NAME}" > /dev/null
            echo "Starting new server with model: $model_name"
            "${SCRIPT_DIR}/deploy.sh" "$model_name" "$extra_args"
            # Small delay to let the server initialize
            sleep 2
        fi
    else
        echo "Starting server with model: $model_name"
        "${SCRIPT_DIR}/deploy.sh" "$model_name" "$extra_args"
        # Small delay to let the server initialize
        sleep 2
    fi
}

# Check arguments
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <model_file> <prompt> [max_tokens] [temperature] [server_extra_args]"
    echo "Example: $0 llama-3-8b-instruct.Q4_K_M.gguf \"Tell me a short story about robots.\" 512 0.7"
    exit 1
fi

MODEL_FILE="$1"
PROMPT="$2"
MAX_TOKENS=${3:-512}  # Default to 512 if not specified
TEMPERATURE=${4:-0.7}  # Default to 0.7 if not specified
shift 4

# Ensure server is running with the requested model
# Double quote the array expansion to prevent re-splitting elements
ensure_server "$MODEL_FILE" --ctx-size 4096 "$@"

# Prepare the API request
JSON_DATA=$(cat <<EOF
{
  "prompt": "$PROMPT",
  "n_predict": $MAX_TOKENS,
  "temperature": $TEMPERATURE,
  "stop": ["\n\n"]
}
EOF
)

# Send request to server and display result
echo "Sending prompt to server:"
echo "\"$PROMPT\""
echo "---------------------------------------------"
curl -s -X POST "http://localhost:${SERVER_PORT}/completion" -d "$JSON_DATA" | jq -r '.content' 2>/dev/null || echo "Error: Failed to get response from server. Is it running correctly?"
echo ""
echo "---------------------------------------------"
echo "Model remains loaded in GPU memory for future queries."
echo "To stop the server: docker stop ${CONTAINER_NAME}"
