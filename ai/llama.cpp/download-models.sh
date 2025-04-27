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
