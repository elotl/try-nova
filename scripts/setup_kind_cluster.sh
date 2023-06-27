#!/usr/bin/env bash

set -e

cp_cluster="cp"
workload_cluster_1="workload-1"
workload_cluster_2="workload-2"

touch ./kubeconfig-e2e-test-cp
export KUBECONFIG="./kubeconfig-e2e-test-cp"

echo "--- creating three kind clusters: cp, workload-1, and workload-2"
# create workload and Control plane clusters
NOVA_K8S_VERSION=${NOVA_E2E_K8S_VERSION:-"v1.25.1"}
CP_NOVA_K8S_VERSION=${NOVA_E2E_K8S_VERSION:-"v1.22.15"}
readonly cp_node_image="kindest/node:${CP_NOVA_K8S_VERSION}"
readonly node_image="kindest/node:${NOVA_K8S_VERSION}"
if [[ $OSTYPE == 'darwin'* ]]; then
    cat <<EOF | kind create cluster --name $cp_cluster --config=-
    kind: Cluster
    apiVersion: kind.x-k8s.io/v1alpha4
    nodes:
    - role: control-plane
      image: ${cp_node_image}
      extraPortMappings:
      - containerPort: 32222
        hostPort: 80
      - containerPort: 32222
        hostPort: 443
EOF
else
    cat <<EOF | kind create cluster --name $cp_cluster --config=-
    kind: Cluster
    apiVersion: kind.x-k8s.io/v1alpha4
    nodes:
    - role: control-plane
      image: ${cp_node_image}
      extraPortMappings:
      - containerPort: 32222
        hostPort: 80
      - containerPort: 32222
        hostPort: 443
EOF
fi

touch ./kubeconfig-e2e-test-workload-1
export KUBECONFIG="./kubeconfig-e2e-test-workload-1"
cat <<EOF | kind create cluster --name $workload_cluster_1 --config=-
    kind: Cluster
    apiVersion: kind.x-k8s.io/v1alpha4
    nodes:
    - role: control-plane
      image: ${node_image}
EOF

touch ./kubeconfig-e2e-test-workload-2
export KUBECONFIG="./kubeconfig-e2e-test-workload-2"
cat <<EOF | kind create cluster --name $workload_cluster_2 --config=-
    kind: Cluster
    apiVersion: kind.x-k8s.io/v1alpha4
    nodes:
    - role: control-plane
      image: ${node_image}
EOF


echo "--- clusters created."
# build nova scheduler and load it into CP cluster
REPO_ROOT=$(git rev-parse --show-toplevel)
cd "${REPO_ROOT}"

# Setup Metal Load Balancer for CP cluster:
echo "--- configuring Metal Load Balancer for kind-cp cluster..."
source ./setup_kind_cluster.sh "./kubeconfig-e2e-test-cp"

# Setup Metal Load Balancer for Workload 1 cluster:
echo "--- configuring Metal Load Balancer for kind-workload-1 cluster..."
source ./setup_kind_cluster.sh "./kubeconfig-e2e-test-workload-1"

# Setup Metal Load Balancer for Workload 2 cluster:
echo "--- configuring Metal Load Balancer for kind-workload-2 cluster..."
source ./setup_kind_cluster.sh "./kubeconfig-e2e-test-workload-2"

echo "--- Metal Load Balancer installed in kind-cp cluster."
echo "--- Metal Load Balancer installed in kind-workload-1 cluster."
echo "--- Metal Load Balancer installed in kind-workload-2 cluster."
echo "--- clusters ready for nova-scheduler and nova-agent deployments."
echo "--- kubeconfig for kind-cp cluster: ./kubeconfig-e2e-test-cp"
echo "--- kubeconfig for kind-workload-1 cluster: ./kubeconfig-e2e-test-workload-1"
echo "--- kubeconfig for kind-workload-2 cluster: ./kubeconfig-e2e-test-workload-2"
