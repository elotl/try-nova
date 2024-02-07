#!/bin/bash

timeout_seconds=180
interval_seconds=5

start_time=$(date +%s)
end_time=$((start_time + timeout_seconds))

while true; do
    kubectl --context kind-workload-1 get clusterpolicies require-labels &>/dev/null
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