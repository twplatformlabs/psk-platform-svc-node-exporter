#!/usr/bin/env bash
set -euo pipefail
source bash-functions.sh

cluster_role=$1

node_exporter_chart_version=$(jq -er .node_exporter_chart_version environments/$cluster_role.json)
argocd_namespace=$(jq -er .argocd_namespace environments/$cluster_role.json)

# perform trivy scan of chart with role configuration.
# ArgoCD Core will do the actual Helm install, this is just a pre-flight security review
helm repo add prometheus https://prometheus-community.github.io/helm-charts
helm repo update
trivyScan "prometheus/prometheus-node-exporter" "prometheus-node-exporter" "$node_exporter_chart_version" "deploy-templates/default-values.yaml"

echo "Application resource and configuration files for node-exporter"
echo "node-exporter chart version: $node_exporter_chart_version"
echo "creating deploy-files directory for all the node-exporter files that will written to psk-platform-control-plane-configuration repository"
mkdir deploy-files
mkdir deploy-files/node-exporter

# generate application.yaml for both Applications then stage the files for writing to the app-of-app config repo
echo "generating node-exporter application.yaml"
cat <<EOF > deploy-files/node-exporter/application.yaml
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: node-exporter
  namespace: $argocd_namespace
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  project: psk-aws-control-plane-configuration

  sources:
    - repoURL: https://prometheus-community.github.io/helm-charts
      chart: prometheus-node-exporter
      targetRevision: $node_exporter_chart_version
      helm:
        valueFiles:
          - \$config/roles/$cluster_role/node-exporter/default-values.yaml
          - \$config/roles/$cluster_role/node-exporter/$cluster_role-values.yaml
    - repoURL: https://github.com/twplatformlabs/psk-aws-control-plane-configuration
      targetRevision: HEAD
      ref: config
  destination:
    server: https://kubernetes.default.svc
    namespace: observe
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 30s
        factor: 2
        maxDuration: 5m
EOF
cat deploy-files/node-exporter/application.yaml

echo "copying default values"
cp -v deploy-templates/default-values.yaml deploy-files/node-exporter/default-values.yaml
cp -v deploy-templates/$cluster_role-values.yaml deploy-files/node-exporter/$cluster_role-values.yaml
