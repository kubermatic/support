#!/bin/sh
# Runs collect.sh in the host namespaces of PID 1 and caches the result:
# the DaemonSet restarts the container after it exits, and Troubleshoot reads
# the log of the restarted container, which then replays the cache.
set -u

module="${1:?usage: entrypoint.sh <module>}"
cache_dir="${CACHE_DIR:-/cache}"
script="${COLLECT_SCRIPT:-/opt/kubermatic/collect.sh}"
max_bytes="${MAX_OUTPUT_BYTES:-8388608}"
nsenter_cmd="${NSENTER-nsenter --target 1 --mount --uts --ipc --net --pid --}"

out="$cache_dir/$module.out"

if [ ! -f "$out.done" ]; then
    raw="$out.raw"
    # shellcheck disable=SC2086 # nsenter_cmd is intentionally split into words
    $nsenter_cmd sh -s -- "$module" <"$script" >"$raw" 2>&1
    size=$(wc -c <"$raw" | tr -d ' ')
    if [ "$size" -gt "$max_bytes" ]; then
        head -c "$max_bytes" "$raw" >"$out"
        printf '\n===== OUTPUT TRUNCATED: kept %s of %s bytes =====\n' "$max_bytes" "$size" >>"$out"
        rm -f "$raw"
    else
        mv "$raw" "$out"
    fi
    touch "$out.done"
fi

cat "$out"
