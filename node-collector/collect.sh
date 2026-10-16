#!/bin/sh
# Node diagnostics for Kubermatic support bundles.
#
# entrypoint.sh feeds this file to the host's /bin/sh via nsenter, so it runs
# with the host's binaries and filesystem. Keep it a single POSIX sh file,
# never write to disk, and run commands only through the section helpers.

MODULES="system journal network kubernetes"
SECTION_TIMEOUT="${SECTION_TIMEOUT:-60}"
# Read by the collect_* modules added in a later step.
# shellcheck disable=SC2034
JOURNAL_SINCE="${JOURNAL_SINCE:--48h}"
# shellcheck disable=SC2034
CRI_ENDPOINT="${CRI_ENDPOINT:-unix:///run/containerd/containerd.sock}"
# shellcheck disable=SC2034
REDACT_SED='s/("?(password|auth|[Aa]uthorization|identitytoken|identityToken|registrytoken|registryToken|token)"?[[:space:]]*[:=][[:space:]]*).*/\1"REDACTED"/'

# stdin is the script itself, so commands must never read it.
_run() {
    if timeout 1 true </dev/null >/dev/null 2>&1; then
        timeout "$SECTION_TIMEOUT" "$@" </dev/null
    else
        "$@" </dev/null
    fi
}

# _section mode(all|head|tail) max-bytes title command [args...]
_section() {
    _mode=$1
    _limit=$2
    _title=$3
    shift 3
    _rc=
    printf '===== BEGIN %s =====\n$ %s\n' "$_title" "$*"
    if ! command -v "$1" >/dev/null 2>&1; then
        printf '(command not found: %s)\n' "$1"
        _rc=127
    elif [ "$_mode" = all ]; then
        _run "$@" 2>&1
        _rc=$?
    else
        # fd 3 carries the command's exit code past the head/tail pipe.
        {
            _rc=$({ { _run "$@" 2>&1; echo "$?" >&3; } | "$_mode" -c "$_limit" >&4; } 3>&1)
        } 4>&1
        if [ "$_mode" = head ]; then _which=first; else _which=last; fi
        printf '\n(output limited to the %s %s bytes)' "$_which" "$_limit"
    fi
    printf '\n===== END %s (exit=%s) =====\n\n' "$_title" "${_rc:-unknown}"
}

section() { _section all 0 "$@"; }
section_head() { _section head "$@"; }
section_tail() { _section tail "$@"; }

print_header() {
    printf '# kubermatic node-collector module=%s version=%s hostname=%s time=%s\n\n' \
        "$1" "${COLLECTOR_VERSION:-dev}" "$(hostname 2>/dev/null || cat /proc/sys/kernel/hostname)" \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

main() {
    _module="${1:-}"
    case " $MODULES " in
        *" $_module "*) ;;
        *)
            echo "unknown module: $_module (expected one of: $MODULES)" >&2
            return 2
            ;;
    esac
    print_header "$_module"
    "collect_$_module"
}

if [ -z "${COLLECT_LIB_ONLY:-}" ]; then
    main "$@"
fi
