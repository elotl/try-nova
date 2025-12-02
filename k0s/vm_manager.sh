#!/bin/bash

# VM Management and k0s Installation Script
# Manages VMs and installs k0s Kubernetes cluster

set -e

# Configuration
VM_DIR="$HOME/Virtual Machines"
VM1_NAME="ubuntu-vm1"
VM2_NAME="ubuntu-vm2"
VMRUN="/Applications/VMware Fusion.app/Contents/Library/vmrun"

# VM credentials (set these after Ubuntu installation)
VM_USER="${VM_USER:-ubuntu}"
VM_PASSWORD="${VM_PASSWORD:-}"

# k0s configuration
K0S_VERSION="${K0S_VERSION:-v1.31.2+k0s.0}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to get VM IP
get_vm_ip() {\
    local VM_NAME=$1
    local VMX_FILE="$VM_DIR/$VM_NAME.vmwarevm/$VM_NAME.vmx"
    
    # Check if VM is running without any output
    if ! "$VMRUN" list 2>/dev/null | grep -q "$VMX_FILE"; then
        return 1
    fi
    
    # Get IP and only output the IP, nothing else
    "$VMRUN" getGuestIPAddress "$VMX_FILE" 2>/dev/null | tr -d '"'"'\\n'"'"'
}

# Function to check if VM is running
is_vm_running() {
    local VM_NAME=$1
    local VMX_FILE="$VM_DIR/$VM_NAME.vmwarevm/$VM_NAME.vmx"
    
    if "$VMRUN" list | grep -q "$VMX_FILE"; then
        return 0
    else
        return 1
    fi
}

# Function to execute command on VM via SSH
vm_exec() {
    local VM_IP=$1
    shift
    local COMMAND="$@"
    
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q "$VM_USER@$VM_IP" "$COMMAND"
}

# Function to setup SSH keys
setup_ssh_keys() {
    echo -e "${BLUE}=== Setting up SSH keys ===${NC}"
    
    # Check if sshpass is available
    local HAS_SSHPASS=false
    if command -v sshpass &> /dev/null; then
        HAS_SSHPASS=true
    fi
    
    if [ ! -f ~/.ssh/id_rsa ]; then
        echo "Generating SSH key..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
    fi
    
    for VM in "$VM1_NAME" "$VM2_NAME"; do
        if is_vm_running "$VM"; then
            local IP=$(get_vm_ip "$VM")
            
            if [ -n "$IP" ]; then
                echo "Copying SSH key to $VM ($IP)..."
                
                if [ "$HAS_SSHPASS" = true ] && [ -n "$VM_PASSWORD" ]; then
                    # Use sshpass if available and password provided
                    if sshpass -p "$VM_PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no "$VM_USER@$IP" 2>&1 | grep -v "WARNING"; then
                        echo -e "${GREEN}✓ SSH key copied to $VM${NC}"
                    else
                        echo -e "${RED}✗ Failed to copy SSH key to $VM${NC}"
                    fi
                else
                    # Interactive mode
                    echo -e "${YELLOW}Please enter password for $VM_USER@$IP when prompted${NC}"
                    if ssh-copy-id -o StrictHostKeyChecking=no "$VM_USER@$IP" 2>&1; then
                        echo -e "${GREEN}✓ SSH key copied to $VM${NC}"
                    else
                        echo -e "${RED}✗ Failed to copy SSH key to $VM${NC}"
                    fi
                fi
            else
                echo -e "${YELLOW}Skipping $VM - IP not available yet${NC}"
            fi
        else
            echo -e "${YELLOW}Skipping $VM - not running${NC}"
        fi
        echo ""
    done
    
    if [ "$HAS_SSHPASS" = false ]; then
        echo -e "${YELLOW}Tip: Install sshpass for automated SSH key setup:${NC}"
        echo "  brew install hudochenkov/sshpass/sshpass"
    fi
    
    echo -e "${GREEN}SSH key setup complete!${NC}"
}

# Function to install prerequisites on VMs
install_prerequisites() {
    local VM_IP=$1
    local VM_NAME=$2
    
    echo -e "${BLUE}Installing prerequisites on $VM_NAME...${NC}"
    
    vm_exec "$VM_IP" "sudo apt-get update"
    vm_exec "$VM_IP" "sudo apt-get install -y curl wget"
    
    echo -e "${GREEN}✓ Prerequisites installed on $VM_NAME${NC}"
}

# Function to install k0s as single-node cluster
install_k0s_single() {
    local VM_IP=$1
    local VM_NAME=$2
    local CLUSTER_NAME=${3:-k0s}
    
    echo -e "${BLUE}=== Installing k0s Single-Node Cluster on $VM_NAME ===${NC}"
    
    # Download and install k0s
    echo "Downloading k0s..."
    vm_exec "$VM_IP" "curl -sSLf https://get.k0s.sh | sudo sh -s -- -v $K0S_VERSION"
    
    # Create k0s configuration with external access
    echo "Creating k0s configuration..."
    vm_exec "$VM_IP" "sudo mkdir -p /etc/k0s"
    
    # Create config that allows external access
    # Add IPs specified in Metallb range setup
    # TODO check to make sure if this needed
    cat << EOF | vm_exec "$VM_IP" "sudo tee /etc/k0s/k0s.yaml > /dev/null"
apiVersion: k0s.k0sproject.io/v1beta1
kind: ClusterConfig
metadata:
  name: $CLUSTER_NAME
spec:
  api:
    externalAddress: $VM_IP
    sans:
    - $VM_IP
    - 192.168.1.200
    - 192.168.1.201
    - 192.168.1.202
    - 192.168.1.203
    - 192.168.1.204
    - 192.168.1.205
    - 192.168.1.206
    - 192.168.1.207
    - 192.168.1.208
    - 192.168.1.209
    - 192.168.1.210
EOF
    
    # Install k0s as controller+worker (single node)
    echo "Installing k0s single-node cluster..."
    vm_exec "$VM_IP" "sudo k0s install controller --config /etc/k0s/k0s.yaml --enable-worker"
    
    # Start k0s
    echo "Starting k0s..."
    vm_exec "$VM_IP" "sudo k0s start"
    
    # Wait for k0s to be ready
    echo "Waiting for k0s to be ready..."
    sleep 20
    
    # Wait for API server to be responsive
    echo "Waiting for API server..."
    local ATTEMPTS=0
    while [ $ATTEMPTS -lt 30 ]; do
        if vm_exec "$VM_IP" "sudo k0s kubectl get nodes 2>/dev/null" > /dev/null 2>&1; then
            break
        fi
        sleep 2
        ATTEMPTS=$((ATTEMPTS + 1))
    done
    
    # Get kubeconfig
    echo "Getting kubeconfig..."
    mkdir -p ~/.kube
    local KUBECONFIG_FILE="$HOME/.kube/${CLUSTER_NAME}-config"
    vm_exec "$VM_IP" "sudo k0s kubeconfig admin" > "$KUBECONFIG_FILE"
    
    # Fix server address in kubeconfig
    sed -i.bak "s/localhost:6443/$VM_IP:6443/g" "$KUBECONFIG_FILE"
    sed -i.bak "s/127.0.0.1:6443/$VM_IP:6443/g" "$KUBECONFIG_FILE"
    
    echo -e "${GREEN}✓ k0s single-node cluster installed on $VM_NAME${NC}"
    echo ""
    echo "Kubeconfig saved to: $KUBECONFIG_FILE"
    echo "Use it with: export KUBECONFIG=$KUBECONFIG_FILE"
    echo ""
    echo "Testing connection from your Mac..."
    if KUBECONFIG="$KUBECONFIG_FILE" kubectl get nodes 2>/dev/null; then
        echo -e "${GREEN}✓ Successfully connected to cluster from Mac!${NC}"
    else
        echo -e "${YELLOW}⚠ Could not connect yet. Wait a few more seconds and try: kubectl get nodes${NC}"
    fi
    
    echo ""
}

# Function to install two separate single-node clusters
install_k0s_separate_clusters() {
    echo -e "${BLUE}=== Installing Separate k0s Clusters ===${NC}"
    
    # Check if VMs are running
    if ! is_vm_running "$VM1_NAME" || ! is_vm_running "$VM2_NAME"; then
        echo -e "${RED}Error: Both VMs must be running${NC}"
        exit 1
    fi
    
    # Get IPs without extra output
    local VM1_IP=$(get_vm_ip "$VM1_NAME")
    local VM2_IP=$(get_vm_ip "$VM2_NAME")
    
    if [ -z "$VM1_IP" ] || [ -z "$VM2_IP" ]; then
        echo -e "${RED}Error: Could not get VM IP addresses${NC}"
        exit 1
    fi
    
    echo "VM1 IP: $VM1_IP"
    echo "VM2 IP: $VM2_IP"
    echo ""
    
    # Install prerequisites
    install_prerequisites "$VM1_IP" "$VM1_NAME"
    install_storage_prereqs "$VM1_IP" "$VM1_NAME"
    install_prerequisites "$VM2_IP" "$VM2_NAME"
    
    # Install separate clusters
    install_k0s_single "$VM1_IP" "$VM1_NAME" "k0s-vm1"
    echo ""
    install_k0s_single "$VM2_IP" "$VM2_NAME" "k0s-vm2"
    
    echo ""
    echo -e "${GREEN}=== Two Separate k0s Clusters Installation Complete ===${NC}"
    echo ""
    echo "Cluster 1 (VM1):"
    echo "  Kubeconfig: ~/.kube/k0s-vm1-config"
    echo "  Command:    export KUBECONFIG=~/.kube/k0s-vm1-config"
    echo ""
    echo "Cluster 2 (VM2):"
    echo "  Kubeconfig: ~/.kube/k0s-vm2-config"
    echo "  Command:    export KUBECONFIG=~/.kube/k0s-vm2-config"
    echo ""
}

# Function to install storage-related prerequisites
install_storage_prereqs() {
    local VM_IP=$1
    local VM_NAME=$2

    echo -e "${BLUE}Installing storage prerequisites on $VM_NAME...${NC}"

    vm_exec "$VM_IP" "sudo apt-get update -y"
    vm_exec "$VM_IP" "sudo apt-get install -y open-iscsi nfs-common jq"
    vm_exec "$VM_IP" "sudo systemctl enable --now iscsid"

    echo -e "${GREEN}✓ Storage prerequisites installed on $VM_NAME${NC}"
}

# Function to show help
show_help() {
    cat << EOF
${BLUE}VM Management and k0s Installation Script${NC}

Usage: $0 [command]

Commands:
  setup-ssh         Setup SSH key authentication
  install-separate  Install separate single-node clusters on each VM
  help              Show this help message

Environment Variables:
  VM_USER           Username for VMs (default: ubuntu)
  VM_PASSWORD       Password for VMs (optional, for automated setup)
  K0S_VERSION       k0s version to install (default: v1.31.2+k0s.0)

Examples:
  # Start VMs
  $0 start

  # Setup SSH keys (run once after VM installation)
  VM_USER=test VM_PASSWORD=test $0 setup-ssh

  # Install TWO separate single-node clusters (one per VM)
  VM_USER=test $0 install-separate

EOF
}

# Main script
case "${1:-help}" in
    setup-ssh)
        if [ -z "$VM_PASSWORD" ]; then
            echo -e "${YELLOW}Warning: VM_PASSWORD not set. You'll need to enter password manually.${NC}"
            echo "Or run: VM_USER=test VM_PASSWORD=test $0 setup-ssh"
            echo ""
        fi
        setup_ssh_keys
        ;;
    install-separate)
        install_k0s_separate_clusters
        ;;
    help|*)
        show_help
        ;;
esac
