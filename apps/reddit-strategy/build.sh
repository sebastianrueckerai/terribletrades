#!/bin/bash
set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
IMAGE_NAME="reddit-strategy"
VERSION=$(git rev-parse --short HEAD 2>/dev/null || echo "latest")

# Build Docker image
echo "Building $IMAGE_NAME:$VERSION..."
docker build -t $IMAGE_NAME:$VERSION -t $IMAGE_NAME:latest $SCRIPT_DIR

echo "Image built: $IMAGE_NAME:$VERSION"

# If registry URL is provided, push to registry
if [ -n "$1" ]; then
  REGISTRY_URL="$1"
  REMOTE_IMAGE="$REGISTRY_URL/$IMAGE_NAME:$VERSION"
  REMOTE_LATEST="$REGISTRY_URL/$IMAGE_NAME:latest"
  
  echo "Tagging for registry: $REMOTE_IMAGE"
  docker tag $IMAGE_NAME:$VERSION $REMOTE_IMAGE
  docker tag $IMAGE_NAME:latest $REMOTE_LATEST
  
  echo "Pushing to registry..."
  docker push $REMOTE_IMAGE
  docker push $REMOTE_LATEST
  
  echo "Image pushed: $REMOTE_IMAGE"
fi