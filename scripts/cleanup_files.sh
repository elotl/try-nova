#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(pwd)
kubeconfig_cp="${REPO_ROOT}/kubeconfig-cp"
kubeconfig_workload_1="${REPO_ROOT}/kubeconfig-workload-1"
kubeconfig_workload_2="${REPO_ROOT}/kubeconfig-workload-2"
echo "--- Deleting KubeConfig files $kubeconfig_cp $kubeconfig_workload_1 $kubeconfig_workload_2 ..."
rm $kubeconfig_cp $kubeconfig_workload_1 $kubeconfig_workload_2

echo "--- Deleting try nova files schedule-policy.yaml ..."
rm schedule-policy.yaml