#!/usr/bin/env bash
# Usage: verify-redaction.sh <support-bundle.tar.gz>
# Asserts that no LEAKCHECK credential from test/fixtures/kkp-credentials.yaml
# is in the bundle and that the KEEPCHECK diagnostics survived.
set -euo pipefail

bundle=${1:?usage: verify-redaction.sh <bundle.tar.gz>}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FIXTURE="$ROOT/test/fixtures/kkp-credentials.yaml"

work=$(mktemp -d)
trap 'rm -rf "$work" "$work.keep"' EXIT
tar -xzf "$bundle" -C "$work"

failures=0
fail() {
    echo "FAIL: $*" >&2
    failures=$((failures + 1))
}

for plural in presets.kubermatic.k8c.io clusters.kubermatic.k8c.io \
    kubermaticconfigurations.kubermatic.k8c.io seeds.kubermatic.k8c.io \
    applicationinstallations.apps.kubermatic.k8c.io \
    applicationdefinitions.apps.kubermatic.k8c.io widgets.example.com; do
    if [ -z "$(find "$work" -path "*cluster-resources/custom-resources/$plural*" -type f | head -n 1)" ]; then
        fail "no custom resources collected for $plural"
    fi
done

leaks=$(grep -rhoE 'LEAKCHECK[-A-Za-z0-9_=]*' "$work" | sort -u || true)
if [ -n "$leaks" ]; then
    for leak in $leaks; do
        files=$(grep -rl "$leak" "$work" | sed "s|^$work/||" | tr '\n' ' ')
        fail "leaked $leak in: $files"
    done
fi

grep -oE 'KEEPCHECK[-A-Za-z0-9_.]*' "$FIXTURE" | sort -u >"$work.keep"
while read -r keep; do
    if ! grep -rqF "$keep" "$work"; then
        fail "redacted too much, missing $keep"
    fi
done <"$work.keep"

if [ "$failures" -ne 0 ]; then
    echo "verify-redaction: $failures failure(s)" >&2
    exit 1
fi
echo "verify-redaction: OK"
