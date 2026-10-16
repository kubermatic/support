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
    lib 'section_tail 6 tail-test sh -c "printf 0123456789; echo; exit 4"'
    [ "${lines[2]}" = "56789" ]
    [ "${lines[3]}" = "(output limited to the last 6 bytes)" ]
    [ "${lines[4]}" = "===== END tail-test (exit=4) =====" ]
}

@test "REDACT_ARGS_SED redacts secret command-line flags only" {
    lib 'printf "%s\n" "kubeadm join 10.0.0.1:6443 --token abcdef.0123456789abcdef --discovery-token-ca-cert-hash sha256:1234" "agent --password=hunter2 --client-secret=s3 --certificate-key abc" "  \"--token=xyz\"," "my-secret 0 abc" "kubeadm token create --token-ttl 24h" | sed -E "$REDACT_ARGS_SED"'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = 'kubeadm join 10.0.0.1:6443 --token REDACTED --discovery-token-ca-cert-hash sha256:1234' ]
    [ "${lines[1]}" = 'agent --password=REDACTED --client-secret=REDACTED --certificate-key REDACTED' ]
    [ "${lines[2]}" = '  "--token=REDACTED",' ]
    [ "${lines[3]}" = 'my-secret 0 abc' ]
    [ "${lines[4]}" = 'kubeadm token create --token-ttl 24h' ]
}

@test "section redacts secret flags in every command output" {
    lib 'section flags echo "run --token abc --x y"'
    [ "${lines[2]}" = "run --token REDACTED --x y" ]
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

@test "section skips commands once the module deadline is reached" {
    lib 'MODULE_DEADLINE=100; _MODULE_START=$(( $(date +%s) - 101 )); section late sh -c "echo \$((40+2))"'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "===== BEGIN late =====" ]
    [ "${lines[1]}" = '$ sh -c echo $((40+2))' ]
    [ "${lines[2]}" = "(skipped: module deadline of 100s reached)" ]
    [ "${lines[3]}" = "===== END late (exit=skipped) =====" ]
    [[ "$output" != *$'\n'42$'\n'* ]]
}

@test "section runs normally before the module deadline" {
    lib 'MODULE_DEADLINE=100; _MODULE_START=$(date +%s); section early echo canary'
    [ "${lines[2]}" = "canary" ]
    [ "${lines[3]}" = "===== END early (exit=0) =====" ]
}

@test "section without a module start has no deadline" {
    lib 'MODULE_DEADLINE=0; unset _MODULE_START; section free echo canary'
    [ "${lines[2]}" = "canary" ]
}

@test "main records the module start time before collecting" {
    lib 'collect_system() { echo "start=$_MODULE_START"; }; main system'
    [[ "$output" =~ start=[0-9]{9,} ]]
}

@test "main stops starting sections after the module deadline" {
    lib 'MODULE_DEADLINE=1; collect_system() { section first sleep 2; section second echo canary; }; main system'
    [[ "$output" == *"BEGIN second"* ]]
    [[ "$output" == *"(skipped: module deadline of 1s reached)"* ]]
    [[ "$output" == *"END second (exit=skipped)"* ]]
}

@test "section redacts PEM private keys but keeps certificates" {
    printf "%s\n" "before" "-----BEGIN RSA PRIVATE KEY-----" "MIIEowIBAAKCAQEA" "abcd" "-----END RSA PRIVATE KEY-----" "-----BEGIN EC PRIVATE KEY-----" "ECSECRET" "-----END EC PRIVATE KEY-----" "-----BEGIN CERTIFICATE-----" "CERTBODY" "-----END CERTIFICATE-----" '{"k":"-----BEGIN PRIVATE KEY-----\nONELINE\n-----END PRIVATE KEY-----"}' "after" >"$BATS_TEST_TMPDIR/pem"
    lib "section pem cat '$BATS_TEST_TMPDIR/pem'"
    [ "$status" -eq 0 ]
    [[ "$output" != *MIIEow* ]]
    [[ "$output" != *abcd* ]]
    [[ "$output" != *ECSECRET* ]]
    [[ "$output" != *ONELINE* ]]
    [[ "$output" == *CERTBODY* ]]
    [ "${lines[2]}" = "before" ]
    [ "${lines[3]}" = "-----BEGIN RSA PRIVATE KEY-----" ]
    [ "${lines[4]}" = "REDACTED" ]
    [ "${lines[6]}" = "-----END RSA PRIVATE KEY-----" ]
    [[ "$output" == *$'\n'"-----BEGIN CERTIFICATE-----"$'\n'CERTBODY$'\n'"-----END CERTIFICATE-----"$'\n'* ]]
    [[ "$output" == *$'\n'after$'\n'* ]]
}

@test "section redacts client-key-data in yaml and json" {
    printf "%s\n" "    client-key-data: LS0tLUJFR0lO" '  "client-key-data": "LS0tLUJFR0lO",' "    client-certificate-data: Q0VSVA==" >"$BATS_TEST_TMPDIR/kc"
    lib "section kc cat '$BATS_TEST_TMPDIR/kc'"
    [ "$status" -eq 0 ]
    [[ "$output" != *LS0tLUJFR0lO* ]]
    [ "${lines[2]}" = "    client-key-data: REDACTED" ]
    [ "${lines[3]}" = '  "client-key-data": "REDACTED",' ]
    [ "${lines[4]}" = "    client-certificate-data: Q0VSVA==" ]
}

@test "REDACT_SED is case-insensitive and covers api and access keys" {
    lib 'printf "%s\n" "Password = \"a1\"" "PASSWORD=a2" "passwd: a3" "\"apiKey\": \"a4\"" "api-key = a5" "access_key=a6" "secret_access_key: a7" "private-key: a8" "Credentials: a9" "AUTH: b1" "AuthoriZation: b2" "REGISTRYTOKEN=b3" "\"identityToken\": \"b4\"" "key = keep1" "keyring = keep2" "key_file = keep3" "keyFile: keep4" "key-file: keep5" "\"auths\": {" | sed -E "$REDACT_SED"'
    [ "$status" -eq 0 ]
    for v in a1 a2 a3 a4 a5 a6 a7 a8 a9 b1 b2 b3 b4; do [[ "$output" != *"$v"* ]]; done
    for v in keep1 keep2 keep3 keep4 keep5; do [[ "$output" == *"$v"* ]]; done
    [ "${lines[18]}" = '"auths": {' ]
}

@test "REDACT_ARGS_SED is case-insensitive and covers key and credential flags" {
    lib 'printf "%s\n" "x --Password=p1 --API-KEY k1 --access-key=k2 --secret-key k3 --private-key=k4 --credentials c1 --credential=c2 --ApiToken t1" "x --token-ttl 24h --tls-private-key-file /a/b --key-file /c --discovery-token-ca-cert-hash sha256:1" | sed -E "$REDACT_ARGS_SED"'
    [ "$status" -eq 0 ]
    for v in p1 k1 k2 k3 k4 c1 c2 t1; do [[ "${lines[0]}" != *"$v"* ]]; done
    [ "${lines[1]}" = "x --token-ttl 24h --tls-private-key-file /a/b --key-file /c --discovery-token-ca-cert-hash sha256:1" ]
}
