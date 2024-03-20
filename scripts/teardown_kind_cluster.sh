#!/usr/bin/env bash

set -euo pipefail

cp_cluster="${K8S_HOSTING_CLUSTER:-cp}"
workload_cluster_1="${NOVA_WORKLOAD_CLUSTER_1:-workload-1}"
workload_cluster_2="${NOVA_WORKLOAD_CLUSTER_2:-workload-2}"

echo "--- deleting $cp_cluster, $workload_cluster_1, and $workload_cluster_2 kind clusters..."

kind delete cluster --name $cp_cluster
kind delete cluster --name $workload_cluster_1
kind delete cluster --name $workload_cluster_2
