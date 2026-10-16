#!/bin/sh
# Node diagnostics for Kubermatic support bundles.
#
# entrypoint.sh feeds this file to the host's /bin/sh via nsenter, so it runs
# with the host's binaries and filesystem. Keep it a single POSIX sh file,
# never write to disk, and run commands only through the section helpers.

# The sh -c scripts are single-quoted on purpose: they expand in the inner shell.
# shellcheck disable=SC2016
MODULES="system journal network kubernetes"
SECTION_TIMEOUT="${SECTION_TIMEOUT:-60}"
JOURNAL_SINCE="${JOURNAL_SINCE:--48h}"
CRI_ENDPOINT="${CRI_ENDPOINT:-unix:///run/containerd/containerd.sock}"
REDACT_SED='s/("?(password|auth|[Aa]uthorization|identitytoken|identityToken|registrytoken|registryToken|token)"?[[:space:]]*[:=][[:space:]]*).*/\1"REDACTED"/'

# stdin is the script itself, so commands must never read it.
if timeout 1 true </dev/null >/dev/null 2>&1; then _HAVE_TIMEOUT=1; else _HAVE_TIMEOUT=; fi

_run() {
    if [ -n "$_HAVE_TIMEOUT" ]; then
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
    section_tail 524288 "cloud-init.log" cat /var/log/cloud-init.log
    section_tail 524288 "cloud-init-output.log" cat /var/log/cloud-init-output.log
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
    print_header "$_module"
    "collect_$_module"
}

if [ -z "${COLLECT_LIB_ONLY:-}" ]; then
    main "$@"
fi
