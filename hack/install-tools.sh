#!/usr/bin/env bash
# Installs pinned tool versions into .tools/ (no global installs).
set -euo pipefail

TROUBLESHOOT_VERSION=v0.134.1
YQ_VERSION=v4.54.1
BATS_VERSION=v1.14.0

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TOOLS="$ROOT/.tools"
mkdir -p "$TOOLS/bin"

os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m)
case "$arch" in
    x86_64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
esac

if [ ! -x "$TOOLS/bin/support-bundle" ]; then
    asset="support-bundle_${os}_${arch}.tar.gz"
    if [ "$os" = darwin ]; then
        asset=support-bundle_darwin_all.tar.gz
    fi
    curl -fsSL "https://github.com/replicatedhq/troubleshoot/releases/download/${TROUBLESHOOT_VERSION}/${asset}" |
        tar -xz -C "$TOOLS/bin" support-bundle
fi

if [ ! -x "$TOOLS/bin/yq" ]; then
    curl -fsSL -o "$TOOLS/bin/yq" "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_${os}_${arch}"
    chmod +x "$TOOLS/bin/yq"
fi

if [ ! -x "$TOOLS/bats-core/bin/bats" ]; then
    git clone -q --depth 1 --branch "$BATS_VERSION" https://github.com/bats-core/bats-core "$TOOLS/bats-core"
fi
ln -sf ../bats-core/bin/bats "$TOOLS/bin/bats"
