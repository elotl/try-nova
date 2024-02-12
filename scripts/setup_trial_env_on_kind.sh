#!/usr/bin/env bash

set -euo pipefail

# Ensure required tools are installed
for tool in kubectl kind jq; do
    if ! command -v "$tool" &> /dev/null; then
        echo "Error: Required tool ${tool} is not installed."
        exit 1
    fi
done

export KUBECONFIG=./kubeconfig-e2e-test
REPO_ROOT=$(git rev-parse --show-toplevel)

# Determine the directory of the current script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Define kubeconfig paths
kubeconfig_cp="${REPO_ROOT}/kubeconfig-e2e-test-cp"
kubeconfig_workload_1="${REPO_ROOT}/kubeconfig-e2e-test-workload-1"
kubeconfig_workload_2="${REPO_ROOT}/kubeconfig-e2e-test-workload-2"

# Set image repositories with defaults or use the provided values
SCHEDULER_IMAGE_REPO=${SCHEDULER_IMAGE_REPO:-"elotl/nova-scheduler-trial"}
AGENT_IMAGE_REPO=${AGENT_IMAGE_REPO:-"elotl/nova-agent-trial"}

# Function to check if clusters already exist
clusters_exist() {
    local all_exist=true
    for cluster in cp workload-1 workload-2; do
        if ! kind get clusters | grep -q "^${cluster}$"; then
            all_exist=false
            break
        fi
    done
    echo "$all_exist"
}

# Function to extract node IP for Nova API Server access
extract_nova_node_ip() {
    KUBECONFIG="${kubeconfig_cp}" kubectl get nodes -o=jsonpath='{.items[0].status.addresses[0].address}' | xargs
}

# Function to deploy Nova control plane
deploy_nova_control_plane() {
    local image_tag_option=""
    if [[ -n "${IMAGE_TAG:-}" ]]; then
        image_tag_option="--image-tag ${IMAGE_TAG}"
    fi
    KUBECONFIG="${kubeconfig_cp}" NOVA_NODE_IP=$(extract_nova_node_ip) kubectl nova install cp --image-repository "${SCHEDULER_IMAGE_REPO}" ${image_tag_option} --context kind-cp nova
}

# Function to deploy Nova agents
deploy_nova_agents() {
    for kubeconfig in "${kubeconfig_workload_1}" "${kubeconfig_workload_2}"; do
        local image_tag_option=""
        if [[ -n "${IMAGE_TAG:-}" ]]; then
            image_tag_option="--image-tag ${IMAGE_TAG}"
        fi
        context=$(basename "$kubeconfig" | sed 's/kubeconfig-e2e-test-//')
        KUBECONFIG="$kubeconfig" kubectl nova install agent --image-repository "${AGENT_IMAGE_REPO}" ${image_tag_option} --context kind-"${context}" kind-"${context}"
    done
}

# Function to create namespaces in workload clusters
create_workload_namespaces() {
    for kubeconfig in "${kubeconfig_workload_1}" "${kubeconfig_workload_2}"; do
        KUBECONFIG="$kubeconfig" kubectl create ns elotl || true # Ignore if already exists
    done
}

# Function to wait for and apply the nova-cluster-init-kubeconfig secret to workload clusters
wait_and_apply_nova_cluster_init() {
    while ! KUBECONFIG="${HOME}/.nova/nova/nova-kubeconfig" kubectl get secret nova-cluster-init-kubeconfig --namespace elotl; do
        echo "Waiting for nova-cluster-init-kubeconfig secret creation"
        sleep 5
    done

    for kubeconfig in "${kubeconfig_workload_1}" "${kubeconfig_workload_2}"; do
        KUBECONFIG="${HOME}/.nova/nova/nova-kubeconfig" kubectl get secret -n elotl nova-cluster-init-kubeconfig -o yaml |
            KUBECONFIG="$kubeconfig" kubectl apply -f -
    done
}

# Check if clusters already exist
if [ "$(clusters_exist)" = false ]; then
    "${SCRIPT_DIR}/setup_kind_cluster.sh"
    # Setup MetalLB only if clusters were just created
    source "${SCRIPT_DIR}/setup_metal_lb.sh" "$kubeconfig_cp" "200" "210"
    source "${SCRIPT_DIR}/setup_metal_lb.sh" "$kubeconfig_workload_1" "211" "230"
    source "${SCRIPT_DIR}/setup_metal_lb.sh" "$kubeconfig_workload_2" "231" "255"
    echo "--- Metal Load Balancer installed in all clusters."
else
    echo "Clusters already exist, skipping kind cluster creation and MetalLB setup."
fi

nova_node_ip=$(extract_nova_node_ip)
echo "Nova node IP: $nova_node_ip"

export APISERVER_ENDPOINT_PATCH="${nova_node_ip}:32222"
export APISERVER_SERVICE_NODEPORT="32222"

deploy_nova_control_plane
create_workload_namespaces
wait_and_apply_nova_cluster_init
deploy_nova_agents

echo "Nova control plane and agents deployed successfully."
