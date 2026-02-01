#!/bin/bash
#
# Build pglite for WASI using Docker
#
# Usage:
#   ./build-wasi.sh                      # Build REL_17_4_WASM (default)
#   ./build-wasi.sh REL_17_5_WASM        # Build specific version
#   PG_BRANCH=REL_17_5_WASM ./build-wasi.sh
#   WASI_SDK=29.0 ./build-wasi.sh
#

set -e

# Default version
PG_BRANCH="${PG_BRANCH:-${1:-REL_17_4_WASM}}"
WASI_SDK="${WASI_SDK:-29.0}"
WASI_SDK_TAG="${WASI_SDK//./_}"

# Extract version number from branch (REL_17_4_WASM -> 17.4)
PG_VERSION="${PG_VERSION:-$(echo "$PG_BRANCH" | sed -E 's/REL_([0-9]+)_([0-9]+)_WASM/\1.\2/')}"

DOCKER_IMAGE="pglite-wasi-builder-wasisdk${WASI_SDK_TAG}"

echo "Building pglite WASI"
echo "  PG_BRANCH:  $PG_BRANCH"
echo "  PG_VERSION: $PG_VERSION"
echo "  WASI_SDK:   $WASI_SDK"
echo "  Docker:     $DOCKER_IMAGE"
echo ""

# Check if Docker image exists, build if not
if ! docker image inspect "$DOCKER_IMAGE" &>/dev/null; then
    echo "Docker image '$DOCKER_IMAGE' not found. Building..."
    echo ""
    docker build --build-arg "WASI_SDK=$WASI_SDK" -f Dockerfile.wasi-builder -t "$DOCKER_IMAGE" .
    echo ""
fi

# Create output directory
mkdir -p output

# Run build in Docker
docker run --rm \
    -v "$(pwd)":/workspace \
    -v "$(pwd)/output:/tmp/sdk/dist" \
    "$DOCKER_IMAGE" \
    bash -c ". /tmp/sdk/wasm32-wasi-shell.sh && \
        cd /workspace && \
        PG_BRANCH=$PG_BRANCH \
        PG_VERSION=$PG_VERSION \
        WASI_SDK=$WASI_SDK \
        WASI=true \
        ./wasm-build.sh"

echo ""
echo "========================================"

# Check if main artifact exists
if [ -f "output/pglite.wasi" ]; then
    echo "BUILD SUCCESSFUL"
    echo ""
    echo "Output files:"
    ls -lh output/*.wasi output/*.tar.gz 2>/dev/null
    echo ""
    echo "Verify: file output/pglite.wasi"
    file output/pglite.wasi
else
    echo "BUILD FAILED - pglite.wasi not found"
    exit 1
fi
