#!/usr/bin/env bash
# Builds the collector image, runs the support bundle spec against a kind
# cluster and verifies the node data and the cleanup.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CLUSTER=${CLUSTER:-kubermatic-support-e2e}
IMAGE=${IMAGE:-quay.io/kubermatic/support:dev}
OUT=${OUT:-$ROOT/_output/e2e}
export PATH="$ROOT/.tools/bin:$PATH"

created_cluster=
cleanup() {
    status=$?
    if [ -n "$created_cluster" ] && [ -z "${KEEP_CLUSTER:-}" ]; then
        kind delete cluster --name "$CLUSTER"
    fi
    exit "$status"
}
trap cleanup EXIT

rm -rf "$OUT"
mkdir -p "$OUT"

if ! kind get clusters | grep -qx "$CLUSTER"; then
    kind create cluster --name "$CLUSTER" --config "$ROOT/test/kind-config.yaml" --wait 180s
    created_cluster=1
fi
kind get kubeconfig --name "$CLUSTER" >"$OUT/kubeconfig"
export KUBECONFIG="$OUT/kubeconfig"

docker build --build-arg VERSION=e2e -t "$IMAGE" "$ROOT/node-collector"
kind load docker-image "$IMAGE" --name "$CLUSTER"

nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')

for node in $nodes; do
    docker exec "$node" ls -A /tmp >"$OUT/tmp-before-$node.txt"
done

IMAGE="$IMAGE" yq '(.spec.collectors[] | select(has("runDaemonSet")) | .runDaemonSet.podSpec.containers[0].image) = strenv(IMAGE)' \
    "$ROOT/bundle/kubermatic-support-bundle.yaml" >"$OUT/spec.yaml"

(cd "$OUT" && support-bundle --interactive=false spec.yaml)
bundle=$(ls "$OUT"/support-bundle-*.tar.gz)

# shellcheck disable=SC2086 # one argument per node
"$ROOT/test/verify-bundle.sh" "$bundle" $nodes

for node in $nodes; do
    docker exec "$node" ls -A /tmp >"$OUT/tmp-after-$node.txt"
    if ! diff -u "$OUT/tmp-before-$node.txt" "$OUT/tmp-after-$node.txt"; then
        echo "FAIL: files left in /tmp on $node" >&2
        exit 1
    fi
done

leftover=$(kubectl get daemonsets -A -l troubleshoot-role=run-daemonset-collector -o name)
if [ -n "$leftover" ]; then
    echo "FAIL: collector DaemonSets left behind: $leftover" >&2
    exit 1
fi

echo "e2e: PASS (bundle: $bundle)"
