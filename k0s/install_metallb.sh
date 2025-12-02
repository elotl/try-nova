#!/bin/bash

# Install MetalLB and configure for Nova API access
# This script sets up MetalLB to provide LoadBalancer IPs for services

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Installing MetalLB for k0s ===${NC}"

# Check if kubectl is configured
if ! kubectl get nodes &>/dev/null; then
    echo -e "${RED}Error: kubectl not configured or cluster not accessible${NC}"
    echo "Set KUBECONFIG first: export KUBECONFIG=~/.kube/k0s-vm1-config"
    exit 1
fi

# Get current VM IP to determine IP range
VM_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "VM IP: $VM_IP"

# Calculate IP range for MetalLB (use a small range from the same subnet)
# If VM is 172.16.114.128, we'll use 172.16.114.200-172.16.114.210
IFS='.' read -ra IP_PARTS <<< "$VM_IP"
IP_BASE="${IP_PARTS[0]}.${IP_PARTS[1]}.${IP_PARTS[2]}"
METALLB_IP_START="${IP_BASE}.200"
METALLB_IP_END="${IP_BASE}.210"

echo -e "${YELLOW}MetalLB will use IP range: $METALLB_IP_START - $METALLB_IP_END${NC}"
echo ""

# Install MetalLB
echo -e "${BLUE}Installing MetalLB...${NC}"
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.3/config/manifests/metallb-native.yaml

# Wait for MetalLB to be ready
echo "Waiting for MetalLB pods to be ready..."
kubectl wait --namespace metallb-system \
    --for=condition=ready pod \
    --selector=app=metallb \
    --timeout=90s

echo -e "${GREEN}✓ MetalLB installed${NC}"
echo ""

# Configure MetalLB IP address pool
echo -e "${BLUE}Configuring MetalLB IP address pool...${NC}"

cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - $METALLB_IP_START-$METALLB_IP_END
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
EOF

echo -e "${GREEN}✓ MetalLB configured${NC}"
echo ""

echo -e "${GREEN}=== MetalLB Installation Complete ===${NC}"
echo ""
echo "Your LoadBalancer services will now get IPs from: $METALLB_IP_START - $METALLB_IP_END"
echo ""
echo "Your cluster endpoints will be:"
echo "  k0s API:  https://$VM_IP:6443"
echo "  Nova API: https://<LoadBalancer-IP>:443 (will be assigned from MetalLB pool)"
echo ""