#!/usr/bin/env bash

set -euo pipefail

cp_cluster="${K8S_HOSTING_CLUSTER:-cp}"
workload_cluster_1="${NOVA_WORKLOAD_CLUSTER_1:-workload-1}"
workload_cluster_2="${NOVA_WORKLOAD_CLUSTER_2:-workload-2}"

echo "--- Deleting $cp_cluster, $workload_cluster_1, and $workload_cluster_2 kind clusters ..."

kind delete cluster --name $cp_cluster
kind delete cluster --name $workload_cluster_1
kind delete cluster --name $workload_cluster_2

REPO_ROOT=$(pwd)
kubeconfig_cp="${REPO_ROOT}/kubeconfig-cp"
kubeconfig_workload_1="${REPO_ROOT}/kubeconfig-workload-1"
kubeconfig_workload_2="${REPO_ROOT}/kubeconfig-workload-2"
kubeconfig_vcluster_1="${REPO_ROOT}/kubeconfig-vcluster-1"
kubeconfig_vcluster_2="${REPO_ROOT}/kubeconfig-vcluster-2"

echo "--- Deleting KubeConfig files $kubeconfig_cp $kubeconfig_workload_1 $kubeconfig_workload_2 $kubeconfig_vcluster_1 $kubeconfig_vcluster_2 vcluster-schedule-policy.yaml ..."
rm $kubeconfig_cp $kubeconfig_workload_1 $kubeconfig_workload_2 $kubeconfig_vcluster_1 $kubeconfig_vcluster_2 vcluster-schedule-policy.yaml
