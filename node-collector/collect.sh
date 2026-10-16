#!/bin/sh
# Node diagnostics for Kubermatic support bundles.
#
# entrypoint.sh feeds this file to the host's /bin/sh via nsenter, so it runs
# with the host's binaries and filesystem. Keep it a single POSIX sh file,
# never write to disk, and run commands only through the section helpers.

# The sh -c scripts are single-quoted on purpose: they expand in the inner shell.
# shellcheck disable=SC2016
MODULES="system journal network kubernetes"
SECTION_TIMEOUT="${SECTION_TIMEOUT:-30}"
# Stop starting sections after this many seconds so output arrives before the collector timeout.
MODULE_DEADLINE="${MODULE_DEADLINE:-100}"
JOURNAL_SINCE="${JOURNAL_SINCE:--48h}"
CRI_ENDPOINT="${CRI_ENDPOINT:-unix:///run/containerd/containerd.sock}"
# POSIX sed has no I flag: _ci turns a lowercase word into a bracket regex ([pP][aA]...).
_ci() {
    _ci_out=
    _ci_rest=$1
    while [ -n "$_ci_rest" ]; do
        _ci_c=${_ci_rest%"${_ci_rest#?}"}
        _ci_rest=${_ci_rest#?}
        _ci_cls=$_ci_c
        for _ci_p in aA bB cC dD eE fF gG hH iI jJ kK lL mM nN oO pP qQ rR sS tT uU vV wW xX yY zZ; do
            if [ "${_ci_p%?}" = "$_ci_c" ]; then
                _ci_cls="[$_ci_p]"
                break
            fi
        done
        _ci_out="$_ci_out$_ci_cls"
    done
}

# _ci_join word... sets _CI_ALT to (word1|word2|...) with every word case-insensitive.
_ci_join() {
    _CI_ALT=
    for _ci_w in "$@"; do
        _ci "$_ci_w"
        _CI_ALT="$_CI_ALT|$_ci_out"
    done
    _CI_ALT="(${_CI_ALT#|})"
}

_ci_join api access secret private
_CI_KIND=$_CI_ALT
_ci key
_CI_KEY=$_ci_out
_ci_join password passwd auth authorization token secret credential credentials
_CI_NAMES=$_CI_ALT
REDACT_SED='s/("?('"${_CI_NAMES}|${_CI_KIND}[_-]?${_CI_KEY}"')"?[[:space:]]*[:=][[:space:]]*).*/\1"REDACTED"/'

_ci_join token password secret certificate-key credential credentials
_CI_FLAGS=$_CI_ALT
REDACT_ARGS_SED='s/(^|[[:space:]"'"'"'])(--[A-Za-z0-9_-]*('"${_CI_FLAGS}|${_CI_KIND}-${_CI_KEY}"')[= ]+)[^[:space:]"'"'"',]+/\1\2REDACTED/g'

# Applied to every section: PEM private keys and kubeconfig key data.
REDACT_PEM_LINE_SED='s/-----BEGIN [A-Z ]*PRIVATE KEY-----.*-----END [A-Z ]*PRIVATE KEY-----/[REDACTED PRIVATE KEY]/'
REDACT_PEM_BLOCK_SED='/-----BEGIN [A-Z ]*PRIVATE KEY-----/,/-----END [A-Z ]*PRIVATE KEY-----/{/-----(BEGIN|END) [A-Z ]*PRIVATE KEY-----/!s/.*/REDACTED/;}'
REDACT_KEY_DATA_SED='s/(client-key-data"?[[:space:]]*:[[:space:]]*"?)[^"[:space:],]+/\1REDACTED/'

# stdin is the script itself, so commands must never read it.
if timeout 1 true </dev/null >/dev/null 2>&1; then _HAVE_TIMEOUT=1; else _HAVE_TIMEOUT=; fi

_run() {
    if [ -n "$_HAVE_TIMEOUT" ]; then
        timeout "$_timeout" "$@" </dev/null
    else
        "$@" </dev/null
    fi
}

_limit_output() {
    case "$1" in
        all) cat ;;
        *) "$1" -c "$2" ;;
    esac
}

# _section mode(all|head|tail) max-bytes title command [args...]
_section() {
    _mode=$1
    _limit=$2
    _title=$3
    shift 3
    _rc=
    printf '===== BEGIN %s =====\n$ %s\n' "$_title" "$*"
    _timeout=$SECTION_TIMEOUT
    _remaining=
    if [ -n "${_MODULE_START:-}" ]; then
        _remaining=$((MODULE_DEADLINE - ($(date +%s) - _MODULE_START)))
        if [ "$_remaining" -lt "$_timeout" ]; then _timeout=$_remaining; fi
    fi
    if [ -n "$_remaining" ] && [ "$_remaining" -le 0 ]; then
        printf '(skipped: module deadline of %ss reached)\n' "$MODULE_DEADLINE"
        _rc=skipped
    elif ! command -v "$1" >/dev/null 2>&1; then
        printf '(command not found: %s)\n' "$1"
        _rc=127
    else
        # fd 3 carries the command's exit code past the redaction/limit pipe.
        {
            _rc=$({ { _run "$@" 2>&1; echo "$?" >&3; } | sed -E -e "$REDACT_ARGS_SED" -e "$REDACT_PEM_LINE_SED" -e "$REDACT_PEM_BLOCK_SED" -e "$REDACT_KEY_DATA_SED" | _limit_output "$_mode" "$_limit" >&4; } 3>&1)
        } 4>&1
        if [ "$_mode" != all ]; then
            if [ "$_mode" = head ]; then _which=first; else _which=last; fi
            printf '\n(output limited to the %s %s bytes)' "$_which" "$_limit"
        fi
    fi
    printf '\n===== END %s (exit=%s) =====\n\n' "$_title" "${_rc:-unknown}"
}

section() { _section all 0 "$@"; }
section_head() { _section head "$@"; }
section_tail() { _section tail "$@"; }

collect_system() {
    section "os-release" cat /etc/os-release
    section "uname" uname -a
    section "uptime" uptime
    section "date" date -u
    section "timedatectl" timedatectl status
    section "timesyncd" timedatectl timesync-status
    section "chrony" chronyc tracking
    section "memory" free -m
    section "meminfo" cat /proc/meminfo
    section "cpu" lscpu
    section "loadavg" cat /proc/loadavg
    section "pressure" sh -c 'grep . /proc/pressure/*'
    section "disk usage" df -h
    section "inode usage" df -i
    section "block devices" lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,RO
    section_head 1048576 "mounts" cat /proc/mounts
    section "swap" cat /proc/swaps
    section "kernel modules" lsmod
    section_head 1048576 "sysctl" sysctl -a
    section "file handles" cat /proc/sys/fs/file-nr
    section "failed units" systemctl --failed --no-pager
    section "service units" systemctl list-units --type=service --all --no-pager
    section_head 1048576 "processes" ps auxww --sort=-rss
    section_head 524288 "top" top -b -n 1
}

collect_journal() {
    section_tail 3145728 "journal kubelet" journalctl -u kubelet --since "$JOURNAL_SINCE" --no-pager -o short-iso
    section_tail 1048576 "journal containerd" journalctl -u containerd --since "$JOURNAL_SINCE" --no-pager -o short-iso
    section_tail 1048576 "journal kernel" journalctl -k --since "$JOURNAL_SINCE" --no-pager -o short-iso
    section_tail 524288 "journal warnings" journalctl -p warning --since "$JOURNAL_SINCE" --no-pager -o short-iso
    section_tail 524288 "dmesg" dmesg -T
    section_tail 524288 "cloud-init.log" sh -c 'sed -E "$1" /var/log/cloud-init.log' _ "$REDACT_SED"
    section_tail 524288 "cloud-init-output.log" sh -c 'sed -E "$1" /var/log/cloud-init-output.log' _ "$REDACT_SED"
}

collect_network() {
    section "addresses" ip -d address show
    section "links" ip -s -d link show
    section "routes" ip route show table all
    section "routes ipv6" ip -6 route show table all
    section "rules" ip rule show
    section "neighbours" ip neigh show
    section "listening sockets" ss -tulpn
    section "socket summary" ss -s
    section_head 2097152 "iptables" iptables-save
    section_head 1048576 "ip6tables" ip6tables-save
    section_head 2097152 "nftables" nft list ruleset
    section_head 1048576 "ipvs" ipvsadm -Ln
    section "conntrack" sh -c 'grep . /proc/sys/net/netfilter/nf_conntrack_count /proc/sys/net/netfilter/nf_conntrack_max'
    section "forwarding" sh -c 'grep . /proc/sys/net/ipv4/ip_forward /proc/sys/net/ipv6/conf/all/forwarding /proc/sys/net/bridge/bridge-nf-call-iptables'
    section "resolv.conf" cat /etc/resolv.conf
    section "resolvectl" resolvectl status
    section "hosts" cat /etc/hosts
    section "cni config directory" ls -la /etc/cni/net.d
    # Only network configs: the directory may also hold CNI kubeconfigs with tokens.
    section "cni config" sh -c 'for f in /etc/cni/net.d/*.conf /etc/cni/net.d/*.conflist /etc/cni/net.d/*.json; do [ -f "$f" ] || continue; echo "--- $f"; cat "$f"; echo; done'
    section "cni binaries" ls -l /opt/cni/bin
}

collect_kubernetes() {
    section "kubelet unit" systemctl cat kubelet --no-pager
    section "kubelet status" systemctl status kubelet --no-pager -l
    section "kubelet config" cat /var/lib/kubelet/config.yaml
    section "kubelet flags" cat /var/lib/kubelet/kubeadm-flags.env
    section "containerd unit" systemctl cat containerd --no-pager
    section "containerd status" systemctl status containerd --no-pager -l
    section_head 1048576 "containerd config" sh -c 'containerd config dump | sed -E "$1"' _ "$REDACT_SED"
    section "containerd registry hosts" sh -c 'for f in /etc/containerd/certs.d/*/hosts.toml; do [ -f "$f" ] || continue; echo "--- $f"; sed -E "$1" "$f"; done' _ "$REDACT_SED"
    section "containerd socket" ls -l /run/containerd/containerd.sock
    section "crictl version" crictl --runtime-endpoint "$CRI_ENDPOINT" version
    section_head 1048576 "crictl info" sh -c 'crictl --runtime-endpoint "$1" info | sed -E "$2"' _ "$CRI_ENDPOINT" "$REDACT_SED"
    section_head 1048576 "crictl pods" crictl --runtime-endpoint "$CRI_ENDPOINT" pods
    section_head 1048576 "crictl containers" crictl --runtime-endpoint "$CRI_ENDPOINT" ps -a
    section_head 1048576 "crictl images" crictl --runtime-endpoint "$CRI_ENDPOINT" images
    section "containerd disk usage" df -h /var/lib/containerd
    section "kubelet disk usage" df -h /var/lib/kubelet
    section "static pod manifests" ls -l /etc/kubernetes/manifests
    # Prints only certificate metadata; key material never leaves the host.
    section "certificate expiry" sh -c 'command -v openssl >/dev/null || { echo "openssl not available"; exit 0; }; for c in /etc/kubernetes/pki/*.crt /etc/kubernetes/pki/etcd/*.crt /var/lib/kubelet/pki/*.crt /var/lib/kubelet/pki/kubelet-client-current.pem; do [ -f "$c" ] || continue; echo "--- $c"; openssl x509 -noout -subject -issuer -enddate -in "$c"; done'
}

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
    _MODULE_START=$(date +%s)
    print_header "$_module"
    "collect_$_module"
}

if [ -z "${COLLECT_LIB_ONLY:-}" ]; then
    main "$@"
fi
