#!/bin/bash

kubeconfig_path=$1; shift
range_start_suffix=$1; shift
range_end_suffix=$1; shift

echo "called with kubeconfigpath: ${kubeconfig_path} range_start: ${range_start_suffix} range_end: ${range_end_suffix}"
# Setup Metal Load Balancer for a workload cluster
echo "--- Configuring Metal Load Balancer for cluster using kubeconfig: ${kubeconfig_path}"
KUBECONFIG="${kubeconfig_path}" kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml
KUBECONFIG="${kubeconfig_path}" kubectl patch -n metallb-system deploy controller --type='json' -p '[{"op": "add", "path": "/spec/strategy/rollingUpdate/maxUnavailable", "value": 0}]'

# subnet for kind bridge: https://kind.sigs.k8s.io/docs/user/loadbalancer/
gateway=$(docker network inspect -f '{{json (index .IPAM.Config 0).Gateway}}' kind | xargs)
if [ -z "$gateway" ]; then
    # If the gateway is empty, try with index 1
    gateway=$(docker network inspect -f '{{json (index .IPAM.Config 1).Gateway}}' kind | xargs)
fi
suffix="0.1"
foo=${gateway%"$suffix"}
export RANGE_START="${foo}255.${range_start_suffix}"
export RANGE_END="${foo}255.${range_end_suffix}"
envsubst < "${REPO_ROOT}/scripts/metal_lb_addrpool_template.yaml" > "./metal_lb_addrpool.yaml"
echo "--- Metal LB config:"
cat ./metal_lb_addrpool.yaml
KUBECONFIG="${kubeconfig_path}" kubectl -n metallb-system wait pod --all --timeout=1200s --for=condition=Ready
KUBECONFIG="${kubeconfig_path}" kubectl -n metallb-system wait deploy controller --timeout=1200s --for=condition=Available
KUBECONFIG="${kubeconfig_path}" kubectl -n metallb-system wait apiservice v1beta1.metallb.io --timeout=1200s --for=condition=Available
KUBECONFIG="${kubeconfig_path}" kubectl apply -f ./metal_lb_addrpool.yaml
rm ./metal_lb_addrpool.yaml || true
