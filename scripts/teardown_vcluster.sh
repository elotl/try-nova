#!/usr/bin/env bash
# Copyright The Nova Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0


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
