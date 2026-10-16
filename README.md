# Kubermatic Support Tools

Collects a support bundle from a Kubernetes cluster so Kubermatic support can
analyse problems without access to your environment. Built on
[Troubleshoot](https://troubleshoot.sh) (`kubectl support-bundle`).

## Usage

1. Install the plugin: `kubectl krew install support-bundle`
   (or download `support-bundle` from the
   [Troubleshoot releases](https://github.com/replicatedhq/troubleshoot/releases)).
2. Point your kubeconfig at the affected cluster and run:

   ```bash
   kubectl support-bundle https://raw.githubusercontent.com/kubermatic/support/v0.1.0/bundle/kubermatic-support-bundle.yaml
   ```

3. Upload the resulting `support-bundle-<timestamp>.tar.gz` to your support case
   at https://support.kubermatic.com.

## What is collected

- Cluster information and Kubernetes resources (including custom resources).
- Per node, via a short-lived privileged DaemonSet in `kube-system` that runs
  on every node and is deleted afterwards:
  - `node-system`: OS release, kernel, time sync, CPU/memory/disk usage,
    mounts, sysctl, systemd units, processes.
  - `node-journal`: kubelet, containerd, kernel and warning-level journal
    entries of the last 48 hours, dmesg, cloud-init logs.
  - `node-network`: addresses, routes, sockets, iptables/nftables/IPVS rules,
    conntrack, DNS configuration, CNI configuration.
  - `node-kubernetes`: kubelet and containerd units and configuration,
    container runtime state, static pod manifests, certificate expiry dates.

Nothing is written to the nodes. Private keys, kubeconfigs and Secret contents
are not collected; registry credentials in containerd configuration, credential
values in cloud-init logs, and values of command-line flags such as `--token`,
`--password` or `--client-secret` are replaced with `REDACTED`, and Troubleshoot's
built-in redactors are applied to the whole bundle. Review the bundle before
uploading if your policies require it.

## Air-gapped environments

Mirror `quay.io/kubermatic/support:v0.1.0` into your registry, download
`bundle/kubermatic-support-bundle.yaml`, replace every
`quay.io/kubermatic/support` reference with your mirror and run
`kubectl support-bundle ./kubermatic-support-bundle.yaml`.

## Development

```bash
make tools   # pinned support-bundle, yq and bats in .tools/
make lint    # shellcheck
make test    # unit and spec tests
make e2e     # kind-based end-to-end test (KEEP_CLUSTER=1 keeps the cluster)
make release # multi-arch image push for the version in node-collector/VERSION
```

Releasing: bump `node-collector/VERSION` and the image tags in
`bundle/kubermatic-support-bundle.yaml` (enforced by `make test`), run
`make release`, then tag the repository with the same version so the
raw URL above resolves.

## Legacy scripts

`collection/kubernetes/support.sh` is the previous collection approach. It is
kept until the support bundle covers the same cluster-level data and will be
removed afterwards.

<!-- explicitly send a `page` query parameter to Scarf to work around GitHub pre-caching -->
<img referrerpolicy="no-referrer-when-downgrade" src="https://static.scarf.sh/a.png?x-pxid=89abb35c-9553-4806-9a74-ee8ccbb99ac0&page=README.md" />