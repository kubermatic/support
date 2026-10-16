# Development

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
raw URL in the [README](README.md) resolves.
