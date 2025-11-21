#!/usr/bin/env bash

set -euo pipefail

# Ensure required tools are installed
for tool in kubectl kind jq envsubst; do
    if ! command -v "$tool" &> /dev/null; then
        echo "Error: Required tool ${tool} is not installed."
        exit 1
    fi
done

export KUBECONFIG=./kubeconfig
REPO_ROOT=$(pwd)

# Determine the directory of the current script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Define kubeconfig paths
kubeconfig_cp="${REPO_ROOT}/kubeconfig-cp"
kubeconfig_workload_1="${REPO_ROOT}/kubeconfig-workload-1"
kubeconfig_workload_2="${REPO_ROOT}/kubeconfig-workload-2"

# Set image repositories with defaults or use the provided values
SCHEDULER_IMAGE_REPO=${SCHEDULER_IMAGE_REPO:-"elotl/nova-scheduler-trial"}
AGENT_IMAGE_REPO=${AGENT_IMAGE_REPO:-"elotl/nova-agent-trial"}

# Used for backwards compatibility with e2e test pipeline
AGENT_NAME_PREFIX="${AGENT_NAME_PREFIX:-}"

# Function to check if clusters already exist
clusters_exist() {
    local all_exist=true
    for cluster in ${K8S_HOSTING_CLUSTER} ${NOVA_WORKLOAD_CLUSTER_1} ${NOVA_WORKLOAD_CLUSTER_2}; do
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
    KUBECONFIG="${kubeconfig_cp}" NOVA_NODE_IP=$(extract_nova_node_ip) kubectl nova install cp --image-repository "${SCHEDULER_IMAGE_REPO}" ${image_tag_option} --context kind-${K8S_HOSTING_CLUSTER} ${NOVA_CONTROLPLANE_CONTEXT}
}

# Function to deploy Nova agents
deploy_nova_agents() {
    clusters=("${kubeconfig_workload_1} kind-${NOVA_WORKLOAD_CLUSTER_1} ${NOVA_WORKLOAD_CLUSTER_1}" "${kubeconfig_workload_2} kind-${NOVA_WORKLOAD_CLUSTER_2} ${NOVA_WORKLOAD_CLUSTER_2}")

    for cluster in "${clusters[@]}"; do
        read -r kubeconfig context name <<< "$cluster"
        local image_tag_option=""
        if [[ -n "${IMAGE_TAG:-}" ]]; then
            image_tag_option="--image-tag ${IMAGE_TAG}"
        fi
        KUBECONFIG="$kubeconfig" kubectl nova install agent --image-repository "${AGENT_IMAGE_REPO}" ${image_tag_option} --context "${context}" "${AGENT_NAME_PREFIX}""${name}"
    done
}

# Function to create namespaces in workload clusters
create_workload_namespaces() {
    for kubeconfig in "${kubeconfig_workload_1}" "${kubeconfig_workload_2}"; do
        KUBECONFIG="$kubeconfig" kubectl create ns "${NOVA_NAMESPACE}" || true # Ignore if already exists
    done
}

# Function to wait for and apply the nova-cluster-init-kubeconfig secret to workload clusters
wait_and_apply_nova_cluster_init() {
    while ! KUBECONFIG="${HOME}/.nova/nova/nova-kubeconfig" kubectl get secret nova-cluster-init-kubeconfig --namespace=${NOVA_NAMESPACE} &>/dev/null; do
        echo "Waiting for nova-cluster-init-kubeconfig secret creation"
        sleep 5
    done

    for kubeconfig in "${kubeconfig_workload_1}" "${kubeconfig_workload_2}"; do
        KUBECONFIG="${HOME}/.nova/nova/nova-kubeconfig" kubectl get secret --namespace=${NOVA_NAMESPACE} nova-cluster-init-kubeconfig -o yaml |
            KUBECONFIG="$kubeconfig" kubectl apply -f -
    done
}

# Check if clusters already exist
if [ "$(clusters_exist)" = false ]; then
    source "${SCRIPT_DIR}/setup_kind_cluster.sh.inc" ${K8S_HOSTING_CLUSTER} ${NOVA_WORKLOAD_CLUSTER_1} ${NOVA_WORKLOAD_CLUSTER_2}
else
    # TODO: when we start using different env vars we need to make sure we don't skip 
    # and leave user with clusters setup with different names
    echo "Clusters already exist, skipping kind cluster creation and MetalLB setup."
fi

nova_node_ip=$(extract_nova_node_ip)
echo "Nova node IP: $nova_node_ip"

export APISERVER_ENDPOINT_PATCH="${nova_node_ip}:32222"
export APISERVER_SERVICE_NODEPORT="32222"
export NOVA_API_PUBLIC_HOST_OVERRIDE="0.0.0.0"

deploy_nova_control_plane
create_workload_namespaces
wait_and_apply_nova_cluster_init
deploy_nova_agents

echo "Nova control plane and agents deployed successfully."
