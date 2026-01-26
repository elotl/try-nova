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
    local image_tag=""
    if [[ -n "${IMAGE_TAG:-}" ]]; then
        image_tag="--image-tag=${IMAGE_TAG}"
    fi
    local image_pull_policy=""
    if [[ -n "${IMAGE_PULL_POLICY:-}" ]]; then
        image_pull_policy="--image-pull-policy=${IMAGE_PULL_POLICY}"
    fi
    env \
        KUBECONFIG="${kubeconfig_cp}" \
        NOVA_NODE_IP=$(extract_nova_node_ip) \
    kubectl nova install cp \
        --image-repository "${SCHEDULER_IMAGE_REPO}" \
        ${image_tag} \
        ${image_pull_policy} \
        --context kind-${K8S_HOSTING_CLUSTER} \
        ${NOVA_CONTROLPLANE_CONTEXT}
}

# Function to patch GPU nodes
patch_node_gpu() {
    local kubeconfig="$1"
    local node_name="$2"
    local gpu_type="$3"
    local gpu_count="$4"
    local gpu_product="$5"
    local gpu_memory="$6"

    KUBECONFIG="${kubeconfig}" kubectl patch node "${node_name}" --type merge --patch "
metadata:
  labels:
    ${gpu_type}.com/gpu.count: \"${gpu_count}\"
    ${gpu_type}.com/gpu.product: \"${gpu_product}\"
    ${gpu_type}.com/gpu.memory: \"${gpu_memory}\"
"
}

# Function to patch GPU capacity in workload clusters
patch_workload_gpu_capacity() {
    local kubeconfig="$1"
    local cluster_name="$2"
    local resource_name="$3"
    
    KUBECONFIG="${kubeconfig}" kubectl get nodes -o name | while read -r node; do
        node_name=$(echo "$node" | cut -d'/' -f2)
        echo "Patching GPU capacity on node: $node_name in $cluster_name cluster"
        KUBECONFIG="${kubeconfig}" kubectl patch node "${node_name}" --subresource=status --type=json -p '[
            {"op":"add","path":"/status/capacity/'${resource_name}'","value":"4"},
            {"op":"add","path":"/status/allocatable/'${resource_name}'","value":"4"}
        ]'
    done
}

# Function to patch GPU labels in workload clusters
patch_workload_gpu_labels() {
    local kubeconfig="$1"
    local cluster_name="$2"
    local gpu_type="$3"
    local gpu_count="$4"
    local gpu_model="$5"
    local gpu_memory="$6"
    
    KUBECONFIG="${kubeconfig}" kubectl get nodes -o name | while read -r node; do
        node_name=$(echo "$node" | cut -d'/' -f2)
        echo "Patching $gpu_type GPU on node: $node_name in $cluster_name cluster"
        patch_node_gpu "${kubeconfig}" "$node_name" "$gpu_type" "$gpu_count" "$gpu_model" "$gpu_memory"
    done
}

# Function to patch GPU nodes in workload clusters
patch_workload_gpu_nodes() {
    # Patch workload 1 cluster with NVIDIA GPUs
    patch_workload_gpu_labels "${kubeconfig_workload_1}" "workload-1" "nvidia" "4" "NVIDIA-A100-PCIE-80GB" "81920"
    
    # Patch workload 2 cluster with AMD GPUs
    patch_workload_gpu_labels "${kubeconfig_workload_2}" "workload-2" "amd" "4" "AMD-MI300X-192G" "196608"
    
    # Patch workload 1 cluster capacity
    patch_workload_gpu_capacity "${kubeconfig_workload_1}" "workload-1" "nvidia.com~1gpu"
    
    # Patch workload 2 cluster capacity
    patch_workload_gpu_capacity "${kubeconfig_workload_2}" "workload-2" "amd.com~1gpu"
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
        local image_pull_policy=""
        if [[ -n "${IMAGE_PULL_POLICY:-}" ]]; then
            image_pull_policy="--image-pull-policy=${IMAGE_PULL_POLICY}"
        fi
        env \
            KUBECONFIG="$kubeconfig" \
        kubectl nova install agent \
            --image-repository "${AGENT_IMAGE_REPO}" \
            ${image_tag_option} \
            ${image_pull_policy} \
            --context "${context}" \
            "${AGENT_NAME_PREFIX}""${name}"
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
    patch_workload_gpu_nodes
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
