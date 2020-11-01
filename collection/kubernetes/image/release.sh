#!/usr/bin/env bash

NUMBER=0
VERSION=0.0.1

set -euox pipefail

docker build --no-cache --pull -t quay.io/kubermatic/support:${VERSION}-${NUMBER} .
docker push quay.io/kubermatic/support:${VERSION}-${NUMBER}