#!/usr/bin/env bash
set -euo pipefail
source bash-functions.sh

# the argocd core reconciliation loop runs every 3min
sleep 240

cluster=$1
cluster_role=$2
argocd_namespace=$(jq -er .argocd_namespace environments/$cluster_role.json)
node_exporter_chart_version=$(jq -er .node_exporter_chart_version environments/$cluster_role.json)

# confirm new version has been synced
validate_argocore_helm_app_resource "$argocd_namespace" "node-exporter" "$node_exporter_chart_version"

# run basic smoketest for service health
bats test/node-exporter-service-check.bats
