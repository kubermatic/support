#!/usr/bin/env bash
# Usage: verify-bundle.sh <support-bundle.tar.gz> <node-name>...
# Asserts that the bundle holds complete node-collector output for every node.
set -euo pipefail

bundle=${1:?usage: verify-bundle.sh <bundle.tar.gz> <node>...}
shift
if [ "$#" -eq 0 ]; then
    echo "usage: verify-bundle.sh <bundle.tar.gz> <node>..." >&2
    exit 2
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MODULES=$(sh -c "COLLECT_LIB_ONLY=1; . '$ROOT/node-collector/collect.sh'; echo \$MODULES")

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
tar -xzf "$bundle" -C "$work"

failures=0
fail() {
    echo "FAIL: $*" >&2
    failures=$((failures + 1))
}

find_one() {
    find "$work" -path "$1" -type f | head -n 1 || true
}

for node in "$@"; do
    for module in $MODULES; do
        file=$(find_one "*/node-$module/$node.log")
        if [ -z "$file" ]; then
            fail "node-$module/$node.log is missing"
            continue
        fi
        head -n 1 "$file" | grep -q "^# kubermatic node-collector module=$module " ||
            fail "node-$module/$node.log has no collector header"
        begins=$(grep -c '^===== BEGIN ' "$file" || true)
        ends=$(grep -c '^===== END ' "$file" || true)
        [ "$begins" -gt 0 ] || fail "node-$module/$node.log has no sections"
        [ "$begins" -eq "$ends" ] || fail "node-$module/$node.log has $begins BEGIN but $ends END markers"
    done
    journal=$(find_one "*/node-journal/$node.log")
    if [ -n "$journal" ]; then
        grep -q '^===== BEGIN journal kubelet =====' "$journal" || fail "node-journal/$node.log has no kubelet section"
        grep -Eq 'kubelet\[[0-9]+\]' "$journal" || fail "node-journal/$node.log contains no kubelet journal entries"
    fi
done

[ -n "$(find_one '*/cluster-resources/nodes.json')" ] || fail "cluster-resources/nodes.json is missing"

if [ "$failures" -gt 0 ]; then
    echo "verify-bundle: $failures failure(s)" >&2
    exit 1
fi
echo "verify-bundle: OK ($# nodes)"
