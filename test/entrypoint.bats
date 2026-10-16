#!/usr/bin/env bats

setup() {
    ENTRYPOINT="$BATS_TEST_DIRNAME/../node-collector/entrypoint.sh"
    export CACHE_DIR="$BATS_TEST_TMPDIR/cache"
    export COLLECT_SCRIPT="$BATS_TEST_TMPDIR/fake-collect.sh"
    export RUNS_FILE="$BATS_TEST_TMPDIR/runs"
    export NSENTER=""
    mkdir -p "$CACHE_DIR"
    cat >"$COLLECT_SCRIPT" <<'EOF'
echo "run module=$1"
echo x >>"$RUNS_FILE"
EOF
}

runs() {
    wc -l <"$RUNS_FILE" | tr -d ' '
}

@test "runs the collect script for the given module" {
    run sh "$ENTRYPOINT" system
    [ "$status" -eq 0 ]
    [ "$output" = "run module=system" ]
}

@test "replays cached output after a restart without collecting again" {
    run sh "$ENTRYPOINT" system
    run sh "$ENTRYPOINT" system
    [ "$status" -eq 0 ]
    [ "$output" = "run module=system" ]
    [ "$(runs)" = 1 ]
}

@test "caches each module separately" {
    run sh "$ENTRYPOINT" system
    run sh "$ENTRYPOINT" network
    [ "$output" = "run module=network" ]
    [ "$(runs)" = 2 ]
}

@test "truncates output above MAX_OUTPUT_BYTES" {
    printf 'printf "0123456789ABCDEF\\n"\n' >"$COLLECT_SCRIPT"
    MAX_OUTPUT_BYTES=10 run sh "$ENTRYPOINT" system
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "0123456789" ]
    [ "${lines[1]}" = "===== OUTPUT TRUNCATED: kept 10 of 17 bytes =====" ]
}

@test "fails with usage when no module is given" {
    run sh "$ENTRYPOINT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"usage: entrypoint.sh <module>"* ]]
}
