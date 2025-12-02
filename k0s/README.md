# Installing Nova on K0s on VMware Fusion ARM64 Ubuntu VMs

## Setup

- Two Ubuntu VMs running `ubuntu-22.04.5` for ARM64 on VMware fusion. 
- Each VM will run k0s in single-node mode, i.e. both K0s control plane and worker runs on the same VM. 
- The VMs will use bridged networking to allow for SSH access from the host and to allow for Nova workload clusters to access the Nova Control Plane.
 
For ease of illustration, the rest of this doc assumes that the VMs are named "ubuntu-vm1" and "ubuntu-vm2" and that the username and password are both set as `test`.

## Enable k0s cluster access

If k0s is already installed on both VMs, save the kubeconfig of both k0s clusters.

For the purpose of this doc, we will use Kubeconfig files in the following locations:
```sh
~/.kube/k0s-vm1-config
~/.kube/k0s-vm2-config
```

Within the VMs, the `kubeconfig` can be generated using this command:

```
sudo k0s kubeconfig admin > ~/k0s-vm1-config
```

In the Kubeconfig file, replace localhost or IP references with the server's external IP address, VM_IP:
So replace, `localhost:6443` with `VM_IP:6443` and `127.0.0.1:6443` with `VM_IP:6443`

You can the `scp` the generated kubeconfig file from the VM to your laptop.

After copying the kubeconfig files from the VM, ensure that you are able to run `kubectl` commands on both the clusters from your local machine: 

```sh
KUBECONFIG=~/.kube/k0s-vm1-config kubectl get nodes
KUBECONFIG=~/.kube/k0s-vm2-config kubectl get nodes
```

## Untaint nodes for single-node clusters

In a single-node k0s cluster, the K0s control plane and worker runs on the same VM. In order to allow workload pods to run on this single-node cluster, we need to remove taints on this node:

- Save the node name and remove the control-plane taint
```ssh
NODE_NAME=$(KUBECONFIG=~/.kube/k0s-vm1-config kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
```
Please note that we expect only one node to be returned.

```ssh
KUBECONFIG=~/.kube/k0s-vm1-config kubectl taint nodes $NODE_NAME node-role.kubernetes.io/control-plane:NoSchedule-
```

Repeat the above two steps on the second VM that will run the Nova workload cluster:

```ssh
NODE_NAME=$(KUBECONFIG=~/.kube/k0s-vm2-config kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
```

```ssh
KUBECONFIG=~/.kube/k0s-vm2-config kubectl taint nodes $NODE_NAME node-role.kubernetes.io/control-plane:NoSchedule-
```

## Setup MetalLB

Metallb is needed so that the Nova Control plane API server can be reached via an external IP by the Nova agent runnong on the Nova workload clusters

Make sure to set the KUBECONFIG env variable first before running this script:

```ssh
export KUBECONFIG=~/.kube/k0s-vm1-config
```

```ssh
./install_metallb.sh
```

Metallb is not needed for the Nova workload cluster, so this step does not need not be repeated on the second VM.

## Install Longhorn on the Nova control plane

Instructions to install longhorn are in `install_longhorn.md`. At the end of the install, ensure that all Longhorn pods are running.


## Install Nova Control Plane

We will now install the Nova Control plane on the the first VM, `ubuntu-vm1`:
```ssh
export KUBECONFIG=~/.kube/k0s-vm1-config
```

In order to run Nova in a resource-constrained local env, we decrease Nova Control plane's etcd storage from 50Gi to 5Gi in the manifest:
From your downloaded files, edit this manifest: `nova-linux-arm64-v1.3.13/nova/install/base/control-plane/nova_cp.yaml`) and replace 50Gi with 5Gi.

After the etcd manifest is updated, please follow instructions provided here: [https://docs.elotl.co/nova/installation/](https://docs.elotl.co/nova/installation/)

### Temporary fix to use ARM64 images for the Nova control plane
```ssh
KUBECONFIG=~/.kube/k0s-vm1-config kubectl edit deploy nova-scheduler -n elotl
```

Replace `image: elotl/nova-scheduler:v1.3.13` with `image: elotl/nova-scheduler-dev:v1.3.13-1-g3388cf5`

## Install Nova Workload cluster

We will install the Nova workload cluster components on the the second VM, `ubuntu-vm2`:
```ssh
export KUBECONFIG=~/.kube/k0s-vm2-config
```

Please follow instructions provided here: [https://docs.elotl.co/nova/installation/](https://docs.elotl.co/nova/installation/)

### Temporary fix to use ARM64 images for the Nova workload cluster

```ssh
KUBECONFIG=~/.kube/k0s-vm2-config kubectl edit deploy nova-agent  -n elotl
```

Replace `image: elotl/nova-scheduler:v1.3.13` with `image: elotl/nova-scheduler-dev:v1.3.13-1-g3388cf5`


### (Optional) Create Ubuntu VMs

If you donot have your Ubuntu VMs setup, This script can be used to create VMs on VMware Fusion.

```ssh
./vmware_setup.sh
```

Once the script completes, finish installation by clicking through the Ubuntu installation on each VM.
The rest of this doc assumes that the VMs are named "ubuntu-vm1" and "ubuntu-vm2" and that the username and password are both set as `test`.

### (Optional) Install k0s on both VMs

If you do not have k0s installed on your VMs, you can use the following script:

```ssh
VM_USER=test VM_PASSWORD=test ./vm_manager.sh install-separate
```
After successful k0s installation on both VMs, check that these kubectl commands return the list of nodes:

```sh
KUBECONFIG=~/.kube/k0s-vm1-config kubectl get nodes
KUBECONFIG=~/.kube/k0s-vm2-config kubectl get nodes
```

## (Optional) Passwordless SSH to both VMs

Install SSH keys in both VMs to allow for passwordless SSH into the two VMs from your local machine.

Test that SSH access works as expected, as shown below. Please replace the IP address with the IPs assigned to your VMs.

```ssh
ssh test@192.168.1.85 "echo 'Connected without password!'"
```

Next, we will enable running sudo commands through passwordless SSH.

SSH into your VM1
```ssh
ssh test@192.168.1.85
```

Once logged in, run the following commands:
```ssh
echo 'test ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/test
sudo chmod 440 /etc/sudoers.d/test
exit
```

Ensure that sudo commands can now be executed without password:

```
ssh test@192.168.1.85 sudo apt-get update
```

Repeat for VM2 which will run the Nova workload cluster


