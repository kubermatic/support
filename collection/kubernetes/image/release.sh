#!/usr/bin/env bash

NUMBER=0
VERSION=0.0.1

set -euox pipefail

docker build --platform=amd64,arm64 --no-cache -t quay.io/kubermatic/support:${VERSION}-${NUMBER} .
docker push --all-platforms quay.io/kubermatic/support:${VERSION}-${NUMBER}