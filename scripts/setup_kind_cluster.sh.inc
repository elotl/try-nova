#!/usr/bin/env bash

set -euo pipefail

cp_cluster="${1:-cp}"
workload_cluster_1="${2:-workload-1}"
workload_cluster_2="${3:-workload-2}"

# Define kubeconfig paths
kubeconfig_cp="./kubeconfig-cp"
kubeconfig_workload_1="./kubeconfig-workload-1"
kubeconfig_workload_2="./kubeconfig-workload-2"

# Determine the directory of the current script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Function to create a kind cluster
create_kind_cluster() {
    local cluster_name=$1
    local kubeconfig_path=$2
    local image=$3 # Renamed to avoid conflict with readonly variables
    local extra_port_mappings=${4:-}

    touch "$kubeconfig_path"
    export KUBECONFIG="$kubeconfig_path"

    if [[ -n "$extra_port_mappings" ]]; then
        cat <<EOF | kind create cluster --name "$cluster_name" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  image: ${image}
  extraPortMappings:
  - containerPort: 32222
    hostPort: 80
  - containerPort: 32222
    hostPort: 443
EOF
    else
        cat <<EOF | kind create cluster --name "$cluster_name" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  image: ${image}
EOF
    fi
}

echo "--- creating three kind clusters: $cp_cluster, $workload_cluster_1, $workload_cluster_2"

# Define Kubernetes versions and images
NOVA_K8S_VERSION=${NOVA_E2E_K8S_VERSION:-"v1.28.7"}
readonly cp_node_image="kindest/node:${NOVA_K8S_VERSION}"
readonly node_image="kindest/node:${NOVA_K8S_VERSION}"

# Create clusters
create_kind_cluster "$cp_cluster" "$kubeconfig_cp" "$cp_node_image" "true"
create_kind_cluster "$workload_cluster_1" "$kubeconfig_workload_1" "$node_image"
create_kind_cluster "$workload_cluster_2" "$kubeconfig_workload_2" "$node_image"

echo "--- clusters created."

# Configure Metal Load Balancers using the script in the same directory as this script
echo "--- configuring Metal Load Balancers for clusters..."
source "${SCRIPT_DIR}/setup_metal_lb.sh.inc" "$kubeconfig_cp" "200" "210"
source "${SCRIPT_DIR}/setup_metal_lb.sh.inc" "$kubeconfig_workload_1" "211" "230"
source "${SCRIPT_DIR}/setup_metal_lb.sh.inc" "$kubeconfig_workload_2" "231" "255"

echo "--- Metal Load Balancer installed in all clusters."
echo "--- Clusters ready for nova-scheduler and nova-agent deployments."
echo "--- kubeconfig paths:"
echo "    - CP cluster: $kubeconfig_cp"
echo "    - Workload 1 cluster: $kubeconfig_workload_1"
echo "    - Workload 2 cluster: $kubeconfig_workload_2"
