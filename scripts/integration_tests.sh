#!/usr/bin/env bash
set -euo pipefail
source bash-functions.sh

# the argocd core reconciliation loop runs every 3min
sleep 240

cluster=$1
cluster_role=$2
argocd_namespace=$(jq -er .argocd_namespace environments/$cluster_role.json)
metrics_server_chart_version=$(jq -er .metrics_server_chart_version environments/$cluster_role.json)

# confirm new version has been synced
validate_argocore_helm_app_resource "$argocd_namespace" "metrics-server" "$metrics_server_chart_version"

# run basic smoketest for service health
bats test/metrics-server-service-check.bats

# run horizontalpodautoscaler test to confirm metrics-server working health
kubectl apply -f test/hpa-test-deployment.yaml
sleep 30
kubectl apply -f test/hpa-test-load-generator.yaml
sleep 120

replicas=$(kubectl get hpa php-apache -n psk-system | awk 'NR > 1 { print $7 }')
echo "hpa reports $replicas replicas"

if [[ "$replicas" > 1 ]]; then
  echo "hpa-test replicas scaled under load."
else
  echo "error: hpa-test replicas not scaling under load."
  exit 1
fi
kubectl delete -f test/hpa-test-deployment.yaml
kubectl delete -f test/hpa-test-load-generator.yaml
