#!/bin/bash
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


timeout_seconds=180
interval_seconds=5

start_time=$(date +%s)
end_time=$((start_time + timeout_seconds))

while true; do
    kubectl --context=${K8S_CLUSTER_CONTEXT_1} get clusterpolicies require-labels &>/dev/null
    if [ $? -eq 0 ]; then
        echo "Clusterpolicy require-labels exists"
        exit 0
    fi

    current_time=$(date +%s)
    if [ "$current_time" -ge "$end_time" ]; then
        echo "Timeout reached. Clusterpolicy require-labels not found within $timeout_seconds seconds."
        exit 1
    fi

    sleep "$interval_seconds"
done