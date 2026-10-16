#!/usr/bin/env bats

setup() {
    ROOT="$BATS_TEST_DIRNAME/.."
    SPEC="$ROOT/bundle/kubermatic-support-bundle.yaml"
    MODULES=$(sh -c "COLLECT_LIB_ONLY=1; . '$ROOT/node-collector/collect.sh'; echo \$MODULES")
    MODULE_COUNT=$(echo $MODULES | wc -w | tr -d ' ')
}

yqs() {
    yq "$1" "$SPEC"
}

@test "spec is a SupportBundle" {
    [ "$(yqs '.apiVersion')" = "troubleshoot.sh/v1beta2" ]
    [ "$(yqs '.kind')" = "SupportBundle" ]
}

@test "one runDaemonSet collector per module, named node-<module>" {
    expected=$(for m in $MODULES; do echo "node-$m"; done | sort)
    actual=$(yqs '.spec.collectors[] | select(has("runDaemonSet")) | .runDaemonSet.name' | sort)
    [ "$actual" = "$expected" ]
}

@test "each collector passes its module as the only argument" {
    for m in $MODULES; do
        args=$(yqs ".spec.collectors[] | select(.runDaemonSet.name == \"node-$m\") | .runDaemonSet.podSpec.containers[0].args | join(\" \")")
        [ "$args" = "$m" ]
    done
}

@test "all collectors use the image tag from node-collector/VERSION" {
    images=$(yqs '.spec.collectors[] | select(has("runDaemonSet")) | .runDaemonSet.podSpec.containers[0].image' | sort -u)
    [ "$images" = "quay.io/kubermatic/support:$(cat "$ROOT/node-collector/VERSION")" ]
}

@test "collectors run privileged in host namespaces on every node" {
    count=$(yqs '[.spec.collectors[] | select(has("runDaemonSet")) | .runDaemonSet
        | select(.namespace == "kube-system")
        | select(.timeout == "150s")
        | select(.podSpec.hostPID == true and .podSpec.hostNetwork == true)
        | select(.podSpec.automountServiceAccountToken == false)
        | select((.podSpec.tolerations | length) == 1 and .podSpec.tolerations[0].operator == "Exists")
        | select(.podSpec.containers[0].securityContext.privileged == true)
        | select(.podSpec.containers[0].imagePullPolicy == "IfNotPresent")] | length')
    [ "$count" = "$MODULE_COUNT" ]
}

@test "collectors cache output in an emptyDir mounted at /cache" {
    count=$(yqs '[.spec.collectors[] | select(has("runDaemonSet")) | .runDaemonSet.podSpec
        | select(.volumes[0].name == "cache" and .volumes[0].emptyDir != null)
        | select(.containers[0].volumeMounts[0].name == "cache" and .containers[0].volumeMounts[0].mountPath == "/cache")] | length')
    [ "$count" = "$MODULE_COUNT" ]
}

@test "cluster-level collectors are present" {
    [ "$(yqs '[.spec.collectors[] | select(has("clusterInfo") or has("clusterResources"))] | length')" = 2 ]
}
