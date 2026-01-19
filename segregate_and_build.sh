#!/bin/bash

# Script to manually segregate shards and build Docker images
# Usage: ./segregate_and_build.sh <TEMP_DIR> <IMAGE_NAME> <IMAGE_TAG>

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <TEMP_DIR> <IMAGE_NAME> <IMAGE_TAG>"
    echo "Example: $0 /tmp/tmp.1QZXo3OynV ghcr.io/utoo0703/mlbakery hfl-Qwen3-4B"
    exit 1
fi

TEMP_DIR=$1
IMAGE_NAME=$2
IMAGE_TAG=$3

# Check if temp directory exists
if [ ! -d "$TEMP_DIR" ]; then
    echo "Error: Directory $TEMP_DIR does not exist"
    exit 1
fi

# Find the model directory (assumes only one model)
MODEL_DIR=$(find "$TEMP_DIR/models" -mindepth 1 -maxdepth 1 -type d | head -n 1)

if [ -z "$MODEL_DIR" ]; then
    echo "Error: No model directory found in $TEMP_DIR/models"
    exit 1
fi

MODEL_NAME=$(basename "$MODEL_DIR")
echo "Found model: $MODEL_NAME in $MODEL_DIR"

# Find all safetensors shard files
SHARD_FILES=($(ls "$MODEL_DIR"/model-*.safetensors 2>/dev/null | sort))

if [ ${#SHARD_FILES[@]} -eq 0 ]; then
    echo "Error: No safetensors shard files found"
    exit 1
fi

echo "Found ${#SHARD_FILES[@]} shards"

# Check if Dockerfile exists
if [ ! -f "Dockerfile" ]; then
    echo "Error: Dockerfile not found in current directory"
    exit 1
fi

# Create shard directories and build images
for i in "${!SHARD_FILES[@]}"; do
    SHARD_NUM=$((i + 1))
    SHARD_TAG="${IMAGE_TAG}-shard${SHARD_NUM}"
    
    # Create new temp directory for this shard
    SHARD_TEMP_DIR=$(mktemp -d)
    mkdir -p "$SHARD_TEMP_DIR/models/$MODEL_NAME"
    
    echo ""
    echo "=========================================="
    echo "Processing Shard $SHARD_NUM"
    echo "=========================================="
    
    if [ $SHARD_NUM -eq 1 ]; then
        # Shard 1: Copy all files
        echo "Copying ALL files for shard 1..."
        cp -r "$MODEL_DIR"/* "$SHARD_TEMP_DIR/models/$MODEL_NAME/"
        
        # Remove other safetensors shards (keep only first one)
        for ((j=1; j<${#SHARD_FILES[@]}; j++)); do
            rm -f "$SHARD_TEMP_DIR/models/$MODEL_NAME/$(basename "${SHARD_FILES[$j]}")"
        done
    else
        # Shard 2+: Copy only this safetensors file
        echo "Copying only safetensors for shard $SHARD_NUM..."
        cp "${SHARD_FILES[$i]}" "$SHARD_TEMP_DIR/models/$MODEL_NAME/"
    fi
    
    # Copy Dockerfile
    cp Dockerfile "$SHARD_TEMP_DIR/"
    
    # Show what's in the temp directory
    echo "Contents of shard $SHARD_NUM:"
    ls -lh "$SHARD_TEMP_DIR/models/$MODEL_NAME/"
    
    # Build Docker image
    echo ""
    echo "Building image: $IMAGE_NAME:$SHARD_TAG"
    docker build -t "$IMAGE_NAME:$SHARD_TAG" "$SHARD_TEMP_DIR"
    
    if [ $? -eq 0 ]; then
        echo "✓ Successfully built $IMAGE_NAME:$SHARD_TAG"
    else
        echo "✗ Failed to build $IMAGE_NAME:$SHARD_TAG"
    fi
    
    # Clean up shard temp directory
    rm -rf "$SHARD_TEMP_DIR"
    
    echo "Temp directory: $SHARD_TEMP_DIR"
done

echo ""
echo "=========================================="
echo "All shards processed!"
echo "=========================================="
echo ""
echo "Built images:"
docker images | grep "$IMAGE_TAG"

echo ""
echo "Original temp directory preserved at: $TEMP_DIR"
