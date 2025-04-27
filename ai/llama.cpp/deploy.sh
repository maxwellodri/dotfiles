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
    GPU_FLAGS="--gpus all"
    SERVER_CMD="/bin/server"
    CLI_CMD="--run"
    CONVERT_CMD="--all-in-one"
    echo "Using NVIDIA GPU configuration"
elif [ "$AI_GPU" == "AMD" ]; then
    # Use Vulkan image instead of ROCm for AMD GPUs
    DOCKER_IMAGE="ghcr.io/ggml-org/llama.cpp:full-vulkan"
    GPU_FLAGS="--device=/dev/dri --group-add video"
    SERVER_CMD="--server"  # Vulkan image uses --server instead of /bin/server
    CLI_CMD="--run"
    CONVERT_CMD="--all-in-one"
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

# Check for existing container and handle accordingly for server mode
if [ "$MODE" == "server" ] && docker ps -q --filter "name=${CONTAINER_NAME}" | grep -q .; then
    echo "Warning: Server is already running with container name: ${CONTAINER_NAME}"
    echo "To check server logs: docker logs ${CONTAINER_NAME}"
    echo "To stop the server: docker stop ${CONTAINER_NAME}"
    exit 0
fi

# Check if we have the image locally
if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${DOCKER_IMAGE}$"; then
    echo "Pulling Docker image: $DOCKER_IMAGE"
    docker pull "$DOCKER_IMAGE"
fi

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
        
        # Verify the model file exists
        MODEL_PATH="${MODELS_DIR}/$1"
        if [ ! -f "$MODEL_PATH" ]; then
            echo "Error: Model file not found: $MODEL_PATH"
            exit 1
        fi
        
        echo "Model file found: $MODEL_PATH"
        echo "Mounting directory: $MODELS_DIR to /models"
        
        # We know this exact command works for Vulkan - run in detached mode
        if [ "$AI_GPU" == "AMD" ]; then
            docker run -d --rm \
                --device=/dev/dri --group-add video \
                -v "${MODELS_DIR}:/models" \
                -p "${SERVER_PORT}:${SERVER_PORT}" \
                --name "${CONTAINER_NAME}" \
                "$DOCKER_IMAGE" \
                --server -m "/models/$1" --port "${SERVER_PORT}" --host 0.0.0.0
        else
            # For other GPUs
            docker run -d --rm \
                "$GPU_FLAGS" \
                -v "${MODELS_DIR}:/models" \
                -p "${SERVER_PORT}:${SERVER_PORT}" \
                --name "${CONTAINER_NAME}" \
                "$DOCKER_IMAGE" \
                "$SERVER_CMD" -m "/models/$1" --port "${SERVER_PORT}" --host 0.0.0.0 "${@:2}"
        fi
        
        # Give the server a moment to start
        sleep 2
        
        # Check if container is running
        if docker ps -q --filter "name=${CONTAINER_NAME}" | grep -q .; then
            echo "Server started successfully in background. Container name: ${CONTAINER_NAME}"
            echo "To check server logs: docker logs ${CONTAINER_NAME}"
            echo "To stop the server: docker stop ${CONTAINER_NAME}"
        else
            echo "Error: Server failed to start. Checking logs:"
            docker logs "${CONTAINER_NAME}" 2>/dev/null || echo "No logs available"
            exit 1
        fi
        ;;
    convert)
        echo "Running model conversion"
        docker run -it --rm \
            "$GPU_FLAGS" \
            -v "${MODELS_DIR}:/models" \
            --name "${CONTAINER_NAME}-convert" \
            "$DOCKER_IMAGE" \
            "$CONVERT_CMD" "/models/" "$@"
        ;;
    cli)
        echo "Running interactive CLI mode"
        # Check if a model file was specified
        if [ "$#" -lt 2 ]; then
            echo "Error: Model file and prompt are required"
            echo "Usage: $0 cli [model_file] [prompt]"
            exit 1
        fi
        
        # Verify the model file exists
        MODEL_PATH="${MODELS_DIR}/$1"
        if [ ! -f "$MODEL_PATH" ]; then
            echo "Error: Model file not found: $MODEL_PATH"
            exit 1
        fi
        
        echo "Model file found: $MODEL_PATH"
        echo "Mounting directory: $MODELS_DIR to /models"
        
        # We know basic commands work
        if [ "$AI_GPU" == "AMD" ]; then
            docker run -it --rm \
                --device=/dev/dri --group-add video \
                -v "${MODELS_DIR}:/models" \
                --name "${CONTAINER_NAME}-cli" \
                "$DOCKER_IMAGE" \
                --run -m "/models/$1" -n 512 -p "$2"
        else
            docker run -it --rm \
                "$GPU_FLAGS" \
                -v "${MODELS_DIR}:/models" \
                --name "${CONTAINER_NAME}-cli" \
                "$DOCKER_IMAGE" \
                "$CLI_CMD" -m "/models/$1" --n-gpu-layers 35 "${@:2}"
        fi
        ;;
esac
