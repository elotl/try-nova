#!/bin/bash

# Setup Metal Load Balancer for a workload cluster
echo "--- Configuring Metal Load Balancer for cluster using kubeconfig: $1"
KUBECONFIG="$1" kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml
KUBECONFIG="$1" kubectl patch -n metallb-system deploy controller --type='json' -p '[{"op": "add", "path": "/spec/strategy/rollingUpdate/maxUnavailable", "value": 0}]'

# subnet for kind bridge: https://kind.sigs.k8s.io/docs/user/loadbalancer/
gateway=$(docker network inspect -f '{{json (index .IPAM.Config 0).Gateway}}' kind | xargs)
suffix="0.1"
foo=${gateway%"$suffix"}
export RANGE_START=$(echo $foo"255.200")
export RANGE_END=$(echo  $foo"255.255")
envsubst < "${REPO_ROOT}/scripts/metal_lb_addrpool_template.yaml" > "./metal_lb_addrpool.yaml"
echo "--- Metal LB config:"
cat ./metal_lb_addrpool.yaml
KUBECONFIG="$1" kubectl -n metallb-system wait pod --all --timeout=90s --for=condition=Ready
KUBECONFIG="$1" kubectl -n metallb-system wait deploy controller --timeout=90s --for=condition=Available
KUBECONFIG="$1" kubectl -n metallb-system wait apiservice v1beta1.metallb.io --timeout=90s --for=condition=Available
KUBECONFIG="$1" kubectl apply -f ./metal_lb_addrpool.yaml
rm ./metal_lb_addrpool.yaml || true
