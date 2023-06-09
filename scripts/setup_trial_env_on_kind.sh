#!/usr/bin/env bash

set -e
set -x

# (Pawel)
# Unfortunately there are some hacks needed to setup two kind cluster where one can reach Nova API Server over NodePort
# and at the same time user can reach Nova API Server over MetalLB IP.
# This requires generating kube-apiserver-csr with both MetalLB IP and kind-cp node IP.
# Additionally, we want to have two different kubeconfigs for Nova Control Plane:
# 1. For Nova Agent, which will talk to Nova API Server over kind-cp-node-ip:NodePort
# 2. For human user, which will talk to Nova API Server over MetalLB IP.
export KUBECONFIG=./kubeconfig-e2e-test
REPO_ROOT=$(git rev-parse --show-toplevel)

# Bootstrap two kind clusters
"${REPO_ROOT}/scripts/setup_kind_cluster.sh"


# Get IP of a node where Nova APIServer runs and it's exposed on 32222 hardcoded NodePort.
nova_node_ip=$(KUBECONFIG="${REPO_ROOT}/kubeconfig-e2e-test-cp" kubectl get nodes -o=jsonpath='{.items[0].status.addresses[0].address}' | xargs)
echo "nova_node_ip: $nova_node_ip\n"

# patch apiserver-service for integration test
sed -i.bak 's/targetPort: 6443/& \n      nodePort: 32222/g' "${REPO_ROOT}"/scripts/templates/apiserver-service.yaml
rm "${REPO_ROOT}"/scripts/templates/apiserver-service.yaml.bak


export SCHEDULER_IMAGE_TAG="v0.5.1"
export SCHEDULER_IMAGE_REPO="elotl/nova-scheduler-trial"
export AGENT_IMAGE_TAG="v0.5.1"
export AGENT_IMAGE_REPO="elotl/nova-agent-trial"

pushd "${REPO_ROOT}"/scripts

# Deploy Nova control plane to kind-cp
KUBECONFIG="${REPO_ROOT}/kubeconfig-e2e-test-cp" NOVA_NODE_IP=$nova_node_ip ./deploy_nova.sh kind-cp ""

# restore old apiserver-service.yaml
git checkout -- templates/apiserver-service.yaml

apiserver_endpoint_patch="server: https://$nova_node_ip:32222"
sed -i.bak "s~server: .*~$apiserver_endpoint_patch~g" ./nova-installer-output/manifests/nova-agent-secret.yaml
export OVERRIDE_NOVA_AGENT_SECRET="./nova-installer-output/manifests/nova-agent-secret.yaml"

# Deploy Nova agent to kind-workload-1 and kind-workload-2
KUBECONFIG="${REPO_ROOT}/kubeconfig-e2e-test-workload-1" ./deploy_nova.sh "" kind-workload-1
KUBECONFIG="${REPO_ROOT}/kubeconfig-e2e-test-workload-2" ./deploy_nova.sh "" kind-workload-2
