#!/bin/bash

# Define script directory and models directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MODELS_DIR="${SCRIPT_DIR}/models"
CONTAINER_NAME="llama-cpp"
SERVER_PORT=42070  # Changed to 42070 as requested

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
    echo "Using NVIDIA GPU configuration"
elif [ "$AI_GPU" == "AMD" ]; then
    DOCKER_IMAGE="ghcr.io/ggml-org/llama.cpp:full-rocm"
    GPU_FLAGS="--device=/dev/kfd --device=/dev/dri --group-add=video"
    echo "Using AMD GPU configuration"
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
        
        docker run -d --rm \
            "$GPU_FLAGS" \
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
            "$GPU_FLAGS" \
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
            "$GPU_FLAGS" \
            -v "${MODELS_DIR}:/models" \
            --name "${CONTAINER_NAME}-cli" \
            "$DOCKER_IMAGE" \
            --run -m "/models/$1" --n-gpu-layers 35 "${@:2}"
        ;;
esac
