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

Nothing is written to the nodes. Each node module stops after about 100
seconds, so a hung node still returns partial data. Private keys, kubeconfigs
and Secret contents are not collected; PEM private key blocks and kubeconfig
`client-key-data` are redacted from all node output, registry credentials in
containerd configuration, credential values in cloud-init logs, and values of
command-line flags such as `--token`, `--password` or `--client-secret` are
replaced with `REDACTED` (credential names are matched case-insensitively), and Troubleshoot's
built-in redactors are applied to the whole bundle. Review the bundle before
uploading if your policies require it.

## Air-gapped environments

Mirror `quay.io/kubermatic/support:v0.1.0` into your registry, download
`bundle/kubermatic-support-bundle.yaml`, replace every
`quay.io/kubermatic/support` reference with your mirror and run
`kubectl support-bundle ./kubermatic-support-bundle.yaml`.

## Development

See [DEVELOPMENT.md](DEVELOPMENT.md) for building, testing and releasing.

