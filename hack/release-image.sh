#!/usr/bin/env bash
# Builds and pushes the multi-arch collector image. Requires a docker buildx
# builder with multi-platform support and push access to the registry.
set -euo pipefail

VERSION=${1:?usage: release-image.sh <version, e.g. v0.1.0>}
IMAGE=${IMAGE:-quay.io/kubermatic/support}
ROOT=$(cd "$(dirname "$0")/.." && pwd)

if [ "$VERSION" != "$(cat "$ROOT/node-collector/VERSION")" ]; then
    echo "version $VERSION does not match node-collector/VERSION" >&2
    exit 1
fi

docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --build-arg VERSION="$VERSION" \
    -t "$IMAGE:$VERSION" \
    --push \
    "$ROOT/node-collector"
