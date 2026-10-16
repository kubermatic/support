#!/usr/bin/env bats

setup() {
    COLLECT_SH="$BATS_TEST_DIRNAME/../node-collector/collect.sh"
}

# Runs a snippet under /bin/sh with collect.sh loaded as a library.
lib() {
    run sh -c "COLLECT_LIB_ONLY=1; . '$COLLECT_SH'; $1"
}

@test "section frames output and reports exit code" {
    lib 'section greeting echo hello'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "===== BEGIN greeting =====" ]
    [ "${lines[1]}" = '$ echo hello' ]
    [ "${lines[2]}" = "hello" ]
    [ "${lines[3]}" = "===== END greeting (exit=0) =====" ]
}

@test "section reports non-zero exit codes without failing" {
    lib 'section failing sh -c "echo oops; exit 3"'
    [ "$status" -eq 0 ]
    [ "${lines[2]}" = "oops" ]
    [ "${lines[3]}" = "===== END failing (exit=3) =====" ]
}

@test "section captures stderr" {
    lib 'section errors sh -c "echo bad >&2"'
    [ "${lines[2]}" = "bad" ]
}

@test "section reports missing commands" {
    lib 'section nothing no-such-command-xyz --flag'
    [ "$status" -eq 0 ]
    [ "${lines[2]}" = "(command not found: no-such-command-xyz)" ]
    [ "${lines[3]}" = "===== END nothing (exit=127) =====" ]
}

@test "section_head keeps the first bytes" {
    lib 'section_head 5 head-test printf 0123456789'
    [ "${lines[2]}" = "01234" ]
    [ "${lines[3]}" = "(output limited to the first 5 bytes)" ]
    [[ "${lines[4]}" =~ ^=====\ END\ head-test\ \(exit=[0-9]+\)\ =====$ ]]
}

@test "section_tail keeps the last bytes and the exit code" {
    lib 'section_tail 5 tail-test sh -c "printf 0123456789; exit 4"'
    [ "${lines[2]}" = "56789" ]
    [ "${lines[3]}" = "(output limited to the last 5 bytes)" ]
    [ "${lines[4]}" = "===== END tail-test (exit=4) =====" ]
}

@test "titles with spaces are preserved" {
    lib 'section "journal kubelet" echo x'
    [ "${lines[0]}" = "===== BEGIN journal kubelet =====" ]
    [ "${lines[3]}" = "===== END journal kubelet (exit=0) =====" ]
}

@test "commands cannot consume the script from stdin" {
    run sh -c "{ echo 'COLLECT_LIB_ONLY=1'; cat '$COLLECT_SH'; echo 'section reader cat'; echo 'echo \"still-\$((1+1))\"'; } | sh -s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"still-2"* ]]
}

@test "REDACT_SED removes credentials from toml, json and headers" {
    lib 'printf "%s\n" "password = \"s3cret\"" "  \"auth\": \"YWJj\"," "  Authorization = \"Basic Zm9v\"" "  \"auths\": {" | sed -E "$REDACT_SED"'
    [ "$status" -eq 0 ]
    [[ "$output" != *s3cret* ]]
    [[ "$output" != *YWJj* ]]
    [[ "$output" != *Zm9v* ]]
    [ "${lines[0]}" = 'password = "REDACTED"' ]
    [ "${lines[3]}" = '  "auths": {' ]
}

@test "print_header identifies module, version, host and time" {
    lib 'COLLECTOR_VERSION=v9; print_header system'
    [[ "${lines[0]}" =~ ^#\ kubermatic\ node-collector\ module=system\ version=v9\ hostname=[^\ ]+\ time=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "main rejects unknown modules" {
    run sh "$COLLECT_SH" bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown module: bogus"* ]]
}

@test "main rejects a missing module" {
    run sh "$COLLECT_SH"
    [ "$status" -eq 2 ]
}

@test "collect.sh never redirects output into files" {
    run grep -nE '>[[:space:]]*[^&[:space:]]' "$COLLECT_SH"
    [ -z "$(printf '%s\n' "$output" | grep -v '/dev/null' || true)" ]
}

@test "every module has a collect function" {
    lib 'for m in $MODULES; do command -v "collect_$m" >/dev/null || { echo "missing collect_$m"; exit 1; }; done'
    [ "$status" -eq 0 ]
}
