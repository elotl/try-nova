#!/usr/bin/env bash

# Validate script arguments
if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <kubeconfig_path> <range_start_suffix> <range_end_suffix>"
    exit 1
fi

kubeconfig_path="$1"
range_start_suffix="$2"
range_end_suffix="$3"

echo "called with kubeconfig_path: ${kubeconfig_path} range_start: ${range_start_suffix} range_end: ${range_end_suffix}"

# Determine the directory of the current script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Function to apply MetalLB configuration
applyMetalLB() {
    echo "--- Configuring Metal Load Balancer for cluster using kubeconfig: ${kubeconfig_path}"
    KUBECONFIG="${kubeconfig_path}" kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml
    KUBECONFIG="${kubeconfig_path}" kubectl patch -n metallb-system deploy controller --type='json' -p '[{"op": "add", "path": "/spec/strategy/rollingUpdate/maxUnavailable", "value": 0}]'
}

# Setup Metal Load Balancer for a workload cluster
applyMetalLB

# Check if 'kind' network exists
network_info=$(docker network inspect kind 2>/dev/null)
if [[ -z "$network_info" ]]; then
    echo "Error: 'kind' docker network not found."
    exit 1
fi

# Extract the Gateway from the first IPAM Config that has a Gateway set.  Use gateway w/IPV4 suffix
gateways=$(echo "$network_info" | jq -r '.[0].IPAM.Config | map(select(.Gateway != null)) | .[].Gateway')
gateway=""
suffix="0.1"
if [[ -z "$gateways" || "$gateways" == "null" ]]; then
    echo "Error: Gateway(s) not found."
    exit 1
else
    gateway_array=( $gateways )
    for gw in "${gateway_array[@]}"; do
        if [[ "$gw" == *"$suffix" ]]; then
            gateway=$gw
            break
        fi
    done
    if [[ -z $gateway ]]; then
        echo "Error: IPV4 Gateway not found."
        exit 1
    fi
fi
echo "Gateway: $gateway"

# Configure and apply MetalLB address pool
foo="${gateway%"$suffix"}"
export RANGE_START="${foo}255.${range_start_suffix}"
export RANGE_END="${foo}255.${range_end_suffix}"
envsubst < "${SCRIPT_DIR}/metal_lb_addrpool_template.yaml" > "./metal_lb_addrpool.yaml"
echo "--- Metal LB config:"
cat "./metal_lb_addrpool.yaml"
KUBECONFIG="${kubeconfig_path}" kubectl -n metallb-system wait pod --all --timeout=1200s --for=condition=Ready
KUBECONFIG="${kubeconfig_path}" kubectl -n metallb-system wait deploy controller --timeout=1200s --for=condition=Available
KUBECONFIG="${kubeconfig_path}" kubectl -n metallb-system wait apiservice v1beta1.metallb.io --timeout=1200s --for=condition=Available
KUBECONFIG="${kubeconfig_path}" kubectl apply -f ./metal_lb_addrpool.yaml
rm -f ./metal_lb_addrpool.yaml
