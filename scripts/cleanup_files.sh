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

REPO_ROOT=$(pwd)
kubeconfig_cp="${REPO_ROOT}/kubeconfig-cp"
kubeconfig_workload_1="${REPO_ROOT}/kubeconfig-workload-1"
kubeconfig_workload_2="${REPO_ROOT}/kubeconfig-workload-2"
echo "--- Deleting KubeConfig files $kubeconfig_cp $kubeconfig_workload_1 $kubeconfig_workload_2 ..."
rm $kubeconfig_cp $kubeconfig_workload_1 $kubeconfig_workload_2

echo "--- Deleting try nova files schedule-policy.yaml ..."
rm schedule-policy.yaml