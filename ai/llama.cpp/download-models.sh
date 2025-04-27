#!/bin/bash

# Define script directory and models directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MODELS_DIR="${SCRIPT_DIR}/models"
CONTAINER_NAME="llama-cpp"
SERVER_PORT=42070

# Check if models directory exists
if [ ! -d "$MODELS_DIR" ]; then
    echo "Error: Models directory not found at $MODELS_DIR"
    echo "Creating models directory..."
    mkdir -p "$MODELS_DIR"
fi

# Check if AI_GPU is set correctly
if [ -z "$AI_GPU" ]; then
    echo "Error: AI_GPU environment variable not set. Please set it to either 'NVIDIA' or 'AMD'."
    echo "Example: export AI_GPU=AMD"
    exit 1
fi

if [ "$AI_GPU" != "NVIDIA" ] && [ "$AI_GPU" != "AMD" ]; then
    echo "Error: AI_GPU must be set to either 'NVIDIA' or 'AMD'. Current value: $AI_GPU"
    exit 1
fi

# Set Docker image and run parameters based on GPU type
if [ "$AI_GPU" == "NVIDIA" ]; then
    DOCKER_IMAGE="ghcr.io/ggml-org/llama.cpp:full-cuda"
    GPU_ARGS="--gpus all"
    echo "Using NVIDIA GPU configuration"
elif [ "$AI_GPU" == "AMD" ]; then
    # Use Vulkan image instead of ROCm for AMD GPUs
    DOCKER_IMAGE="ghcr.io/ggml-org/llama.cpp:full-vulkan"
    # Don't combine these flags - they need to be passed separately
    GPU_ARGS="--device=/dev/dri --group-add video"
    echo "Using AMD GPU with Vulkan configuration"
fi

# Determine run mode (default to server mode now)
MODE="server"
if [ "$1" == "cli" ]; then
    MODE="cli"
    shift
elif [ "$1" == "convert" ]; then
    MODE="convert"
    shift
fi

# Pull the Docker image
echo "Pulling Docker image: $DOCKER_IMAGE"
docker pull "$DOCKER_IMAGE"

# Run the Docker container based on mode
case "$MODE" in
    server)
        echo "Starting server mode on port $SERVER_PORT"
        # Check if a model file was specified
        if [ "$#" -eq 0 ]; then
            echo "Error: No model file specified"
            echo "Usage: $0 [model_file] [options]"
            echo "Or: $0 cli [model_file] [options]"
            echo "Or: $0 convert [model_size]"
            exit 1
        fi
        
        # Execute docker run with properly separated arguments
        docker run -d --rm \
            "$GPU_ARGS" \
            -v "${MODELS_DIR}:/models" \
            -p "${SERVER_PORT}:${SERVER_PORT}" \
            --name "${CONTAINER_NAME}" \
            "$DOCKER_IMAGE" \
            /bin/server -m "/models/$1" --port "$SERVER_PORT" --host 0.0.0.0 --n-gpu-layers 35 "${@:2}"
        
        echo "Server started in background. Container name: ${CONTAINER_NAME}"
        echo "To check server logs: docker logs ${CONTAINER_NAME}"
        echo "To stop the server: docker stop ${CONTAINER_NAME}"
        ;;
    convert)
        echo "Running model conversion"
        docker run -it --rm \
            "$GPU_ARGS" \
            -v "${MODELS_DIR}:/models" \
            --name "${CONTAINER_NAME}-convert" \
            "$DOCKER_IMAGE" \
            --all-in-one "/models/" "$@"
        ;;
    cli)
        echo "Running interactive CLI mode"
        # Check if a model file was specified
        if [ "$#" -eq 0 ]; then
            echo "Error: No model file specified"
            echo "Usage: $0 cli [model_file] [options]"
            echo "Or: $0 [model_file] [options] (server mode)"
            echo "Or: $0 convert [model_size]"
            exit 1
        fi
        
        docker run -it --rm \
            "$GPU_ARGS" \
            -v "${MODELS_DIR}:/models" \
            --name "${CONTAINER_NAME}-cli" \
            "$DOCKER_IMAGE" \
            --run -m "/models/$1" --n-gpu-layers 35 "${@:2}"
        ;;
esac

#download-models.sh
#!/bin/bash

# Define script directory and models directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MODELS_DIR="${SCRIPT_DIR}/models"

# Check if models directory exists
if [ ! -d "$MODELS_DIR" ]; then
    echo "Creating models directory at $MODELS_DIR"
    mkdir -p "$MODELS_DIR"
fi

# Function to download a model with confirmation
download_model() {
    local MODEL_NAME="$1"
    local MODEL_URL="$2"
    local MODEL_SIZE="$3"
    local OUTPUT_PATH="${MODELS_DIR}/${MODEL_NAME}"
    
    if [ -f "$OUTPUT_PATH" ]; then
        echo "Model $MODEL_NAME already exists. Skipping download."
        return 0
    fi
    
    echo "Model: $MODEL_NAME"
    echo "Size: $MODEL_SIZE"
    read -p "Do you want to download this model? (y/n): " -r confirm
    
    if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
        echo "Skipping download of $MODEL_NAME"
        return 1
    fi
    
    echo "Downloading $MODEL_NAME ($MODEL_SIZE)..."
    # Check exit code directly instead of using $?
    if wget -O "$OUTPUT_PATH" "$MODEL_URL"; then
        echo "Successfully downloaded $MODEL_NAME"
        return 0
    else
        echo "Failed to download $MODEL_NAME"
        rm -f "$OUTPUT_PATH"
        return 1
    fi
}

# Display menu for model selection
echo "Select models to download:"
echo "1) Llama-3-8B-Instruct (Q4_K_M) - Good for general usage (4.3GB)"
echo "2) Mistral-7B-Instruct-v0.2 (Q4_K_M) - Good alternative (4.1GB)"
echo "3) TinyLlama-1.1B-Chat (Q4_0) - Small model, lower quality (590MB)"
echo "4) All of the above"
echo "5) Exit"

read -p "Enter your choice (1-5): " -r choice

case $choice in
    1)
        download_model "llama-3-8b-instruct.Q4_K_M.gguf" "https://huggingface.co/TheBloke/Llama-3-8B-Instruct-GGUF/resolve/main/llama-3-8b-instruct.Q4_K_M.gguf" "4.3GB"
        ;;
    2)
        download_model "mistral-7b-instruct-v0.2.Q4_K_M.gguf" "https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.2-GGUF/resolve/main/mistral-7b-instruct-v0.2.Q4_K_M.gguf" "4.1GB"
        ;;
    3)
        download_model "tinyllama-1.1b-chat-v1.0.Q4_0.gguf" "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_0.gguf" "590MB"
        ;;
    4)
        echo "Downloading all models:"
        download_model "llama-3-8b-instruct.Q4_K_M.gguf" "https://huggingface.co/TheBloke/Llama-3-8B-Instruct-GGUF/resolve/main/llama-3-8b-instruct.Q4_K_M.gguf" "4.3GB"
        download_model "mistral-7b-instruct-v0.2.Q4_K_M.gguf" "https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.2-GGUF/resolve/main/mistral-7b-instruct-v0.2.Q4_K_M.gguf" "4.1GB"
        download_model "tinyllama-1.1b-chat-v1.0.Q4_0.gguf" "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_0.gguf" "590MB"
        ;;
    5)
        echo "Exiting without downloading any models."
        exit 0
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

echo "Download process complete. Models are stored in $MODELS_DIR"

#run.sh
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

