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

cluster_definition_yaml() {
    local image=$1
    local extra_port_mappings=$2

    cat <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  image: ${image}
  kubeadmConfigPatches:
  - |
    kind: JoinConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        max-pods: "250"
EOF

	if [ "$extra_port_mappings" = true ]
	then
		cat <<EOF
  extraPortMappings:
  - containerPort: 32222
    hostPort: 80
  - containerPort: 32222
    hostPort: 443
EOF
	fi
}

# Function to create a kind cluster
create_kind_cluster() {
    local cluster_name=$1
    local kubeconfig_path=$2
    local image=$3
    local extra_port_mappings=$4

    touch "$kubeconfig_path"
    export KUBECONFIG="$kubeconfig_path"

    cluster_definition_yaml "$image" "$extra_port_mappings" |
        kind create cluster --name "$cluster_name" --config=-
}

echo "--- creating three kind clusters: $cp_cluster, $workload_cluster_1, $workload_cluster_2"

# Define Kubernetes versions and images
NOVA_K8S_VERSION=${NOVA_E2E_K8S_VERSION:-"v1.35.1"}
readonly cp_node_image="kindest/node:${NOVA_K8S_VERSION}"
readonly node_image="kindest/node:${NOVA_K8S_VERSION}"
readonly metallb_controller_image="quay.io/metallb/controller:v0.16.1"
readonly metallb_speaker_image="quay.io/metallb/speaker:v0.16.1"

docker pull "$metallb_controller_image" &
PID_METALLB_CONTROLLER=$!
docker pull "$metallb_speaker_image" &
PID_METALLB_SPEAKER=$!

# Create clusters in parallel
create_kind_cluster "$cp_cluster" "$kubeconfig_cp" "$cp_node_image" true &
PID_CP=$!

create_kind_cluster "$workload_cluster_1" "$kubeconfig_workload_1" "$node_image" false &
PID_W1=$!

create_kind_cluster "$workload_cluster_2" "$kubeconfig_workload_2" "$node_image" false &
PID_W2=$!

# Wait for all cluster creations to finish
wait $PID_CP
wait $PID_W1
wait $PID_W2
wait $PID_METALLB_CONTROLLER
wait $PID_METALLB_SPEAKER

for cluster in "$cp_cluster" "$workload_cluster_1" "$workload_cluster_2"; do
    kind load docker-image --name "$cluster" "$metallb_controller_image" "$metallb_speaker_image" &
done
wait

echo "--- clusters created."

# Configure Metal Load Balancers using the script in the same directory as this script
echo "--- configuring Metal Load Balancers for clusters..."
(
    source "${SCRIPT_DIR}/setup_metal_lb.sh.inc" "$kubeconfig_cp" "200" "210"
) &
PID_METALLB_CP=$!
(
    source "${SCRIPT_DIR}/setup_metal_lb.sh.inc" "$kubeconfig_workload_1" "211" "230"
) &
PID_METALLB_W1=$!
(
    source "${SCRIPT_DIR}/setup_metal_lb.sh.inc" "$kubeconfig_workload_2" "231" "255"
) &
PID_METALLB_W2=$!
wait $PID_METALLB_CP
wait $PID_METALLB_W1
wait $PID_METALLB_W2

echo "--- Metal Load Balancer installed in all clusters."
echo "--- Clusters ready for nova-scheduler and nova-agent deployments."
echo "--- kubeconfig paths:"
echo "    - CP cluster: $kubeconfig_cp"
echo "    - Workload 1 cluster: $kubeconfig_workload_1"
echo "    - Workload 2 cluster: $kubeconfig_workload_2"
