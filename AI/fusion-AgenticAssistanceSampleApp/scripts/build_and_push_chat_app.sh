#!/bin/bash
# Build and push chat-app image to Artifactory

set -e

IMAGE_NAME="docker-na-public.artifactory.swg-devops.com/hyc-abell-devops-team-dev-docker-local/purnanand/chat-app:latest"
DOCKERFILE="Dockerfile.chat-app"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔨 Building and Pushing Chat App Image"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if Dockerfile exists
if [ ! -f "$DOCKERFILE" ]; then
    echo "❌ Error: $DOCKERFILE not found"
    echo "   Looking for: $DOCKERFILE"
    exit 1
fi

echo "📦 Building image: $IMAGE_NAME"
echo "   Dockerfile: $DOCKERFILE"
echo "   Platform: linux/amd64"
echo ""

# Build the image
podman build --platform linux/amd64 -f "$DOCKERFILE" -t "$IMAGE_NAME" .

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Build successful!"
    echo ""
    echo "📤 Pushing image to Artifactory..."
    podman push "$IMAGE_NAME"
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✅ Push successful!"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "✅ Image ready: $IMAGE_NAME"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "The deployment in gitops/applications/chat-app-deployment.yaml"
        echo "has been updated to use this image."
        echo ""
        echo "Next steps:"
        echo "1. Commit and push the updated deployment"
        echo "2. ArgoCD will automatically sync and deploy the new image"
        echo ""
    else
        echo ""
        echo "❌ Push failed!"
        exit 1
    fi
else
    echo ""
    echo "❌ Build failed!"
    exit 1
fi

