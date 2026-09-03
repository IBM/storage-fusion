#!/bin/bash
# Build and push chat-app image to registry.
#
# Two-stage build:
#   Stage 1 (no --platform) — Node 20 builds the React UI natively on the host
#                              arch (arm64 on Apple Silicon). No QEMU, no crash.
#   Stage 2 (--platform linux/amd64) — Python 3.11 runs FastAPI. Python has no
#                              JIT so QEMU handles this stage without crashing.
#
# The --platform linux/amd64 flag is placed only on Stage 2 inside the
# Dockerfile, not on the `podman build` command itself.  podman/buildah then
# runs Stage 1 on the native arch and Stage 2 under emulation.

set -e

IMAGE_NAME="${IMAGE_NAME:-your-registry.example.com/your-namespace/chat-app:latest}"
DOCKERFILE="Dockerfile.chat-app"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$APP_DIR"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔨 Building and Pushing Chat App Image (React UI + FastAPI)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📦 Image : $IMAGE_NAME"
echo "   Stage 1 (no --platform) : Node 20 — React build on host arch"
echo "   Stage 2 (linux/amd64)   : Python 3.11-slim — FastAPI serve"
echo "   Port : 8000  (/healthz, /api/*, /)"
echo ""

if [ ! -f "$DOCKERFILE" ]; then
    echo "❌ $DOCKERFILE not found."
    exit 1
fi

# Single podman build — the Dockerfile handles both stages correctly
podman build -f "$DOCKERFILE" -t "$IMAGE_NAME" .

echo ""
echo "✅ Build complete!"
echo ""
echo "📤 Pushing image to registry..."
podman push "$IMAGE_NAME"

echo ""
echo "✅ Push successful!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Image ready: $IMAGE_NAME"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "  1. Update chart/values.yaml  →  image.repository / image.tag"
echo "  2. Commit and push"
echo "  3. ArgoCD auto-syncs the Helm chart — pod restarts with the new image"
echo ""
