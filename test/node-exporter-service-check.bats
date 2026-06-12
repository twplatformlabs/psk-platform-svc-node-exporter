#!/usr/bin/env bats
#
# node-exporter.bats — confirms node-exporter is healthy and serving node_*
# metrics, reached from OUTSIDE the cluster through the Kubernetes API server
# proxy (no pod exec, no exposed node port).
#
# Requires: bats-core (>= 1.5) and kubectl pointed at the target cluster.
# Run:      bats node-exporter.bats
# Override: NS=observe \
#           NE_LABEL='app.kubernetes.io/name=prometheus-node-exporter' \
#           NE_PORT=9100 bats node-exporter.bats

setup_file() {
  export NS="${NS:-observe}"
  export NE_LABEL="${NE_LABEL:-app.kubernetes.io/name=prometheus-node-exporter}"
  export NE_PORT="${NE_PORT:-9100}"

  # Gather pod names once for the whole file. `|| true` keeps a transient
  # kubectl error from aborting the entire suite via errexit.
  PODS="$(kubectl -n "$NS" get pods -l "$NE_LABEL" \
            -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)"
  export PODS
}

# Scrape /metrics for one pod via the API server pod-proxy subresource.
scrape() {
  kubectl get --raw "/api/v1/namespaces/${NS}/pods/${1}:${NE_PORT}/proxy/metrics"
}

@test "API server is reachable" {
  run kubectl get --raw /healthz
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "node-exporter pods exist" {
  [ -n "$PODS" ]
}

@test "DaemonSet is ready on every scheduled node" {
  run kubectl -n "$NS" get daemonset -l "$NE_LABEL" \
        -o jsonpath='{.items[0].status.desiredNumberScheduled}/{.items[0].status.numberReady}'
  [ "$status" -eq 0 ]
  local desired="${output%/*}" ready="${output#*/}"
  desired="${desired:-0}"
  ready="${ready:-0}"
  [ "$desired" -gt 0 ]
  [ "$desired" -eq "$ready" ]
}

@test "every pod serves node_* metrics through the API proxy" {
  [ -n "$PODS" ]
  for pod in $PODS; do
    run scrape "$pod"
    [ "$status" -eq 0 ] || { echo "scrape failed for $pod (status $status): $output"; return 1; }
    [[ "$output" == *"node_cpu_seconds_total"* ]] || { echo "no node_ metrics from $pod"; return 1; }
  done
}

@test "key host signals are present (cpu steal, mem, inodes, load)" {
  local pod="${PODS%% *}"   # first pod name
  run scrape "$pod"
  [ "$status" -eq 0 ]
  [[ "$output" == *'node_cpu_seconds_total'* ]]
  [[ "$output" == *'mode="steal"'* ]]
  [[ "$output" == *'node_memory_MemAvailable_bytes'* ]]
  [[ "$output" == *'node_filesystem_files_free'* ]]
  [[ "$output" == *'node_load1'* ]]
}

@test "conntrack table metric present (skips if collector inactive)" {
  local pod="${PODS%% *}"
  run scrape "$pod"
  [ "$status" -eq 0 ]
  [[ "$output" == *'node_nf_conntrack_entries'* ]] \
    || skip "conntrack collector not exposing entries on this node"
}
