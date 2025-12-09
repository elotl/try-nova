# Installing Nova on K0s on VMware Fusion ARM64 Ubuntu VMs

## Setup

- Two Ubuntu VMs running `ubuntu-22.04.5` for ARM64 on VMware Fusion. 
- The VMs will use bridged networking to allow for access (SSH, kubeconfig) from the host and to allow for Nova workload clusters to access the Nova Control Plane.
- Each VM will run k0s in single-node mode, i.e. both K0s control plane and worker runs on the same VM. 
 
For ease of illustration, the rest of this doc assumes that the VMs are named "ubuntu-vm1" and "ubuntu-vm2" and that the username and password are both set as `test`.

## (Prereq 1) K0s Cluster Setup and Access


### 1.1 K0s Cluster Setup

K0s needs to be setup with a ClusterConfig to allow access from your local laptop.

Download k0s as per the first step here: [https://docs.k0sproject.io/head/install/#install-k0s](https://docs.k0sproject.io/head/install/#install-k0s)

Create a k0s configuration file as follows:
```
sudo mkdir -p /etc/k0s
```

This config will specify a range of IPs (e.g. 192.168.1.200-210) that will be used during the Metallb setup
Create a file: `/etc/k0s/k0s.yaml` with the manifest given below. Replace `$CLUSTER_NAME` and `$VM_IP` with the cluster
name (eg, "k0s-vm1") and IP address of your VM (e.g. 192.168.1.74).

IP address of your VM can be determined using the `ip a` command.

```
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
```

Install k0s single-node cluster as follows:

```
sudo k0s install controller --config /etc/k0s/k0s.yaml --enable-worker"
```

Start the k0s service:
```
sudo k0s start
```

Check the k0s service status and nodes before continuing to the next step.

```
sudo k0s status
```

```
sudo k0s kubectl get nodes
```

### 1.2 K0s Cluster Access

We will need the kubeconfig files to access both k0s clusters from your laptop.

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

### 1.3 Untaint Nodes for Single-node K0s clusters

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

## (Prereq 2) Setup MetalLB

Metallb is needed so that the Nova Control Plane API server can be reached via an external IP by the Nova agent
running on the Nova workload clusters

Make sure to set the KUBECONFIG env variable first before running this script:

```ssh
export KUBECONFIG=~/.kube/k0s-vm1-config
```

```ssh
./install_metallb.sh
```

Metallb is not needed for the Nova workload cluster, so this step does not need not be repeated on the second VM.

## (Prereq 3) Install Longhorn on the Nova Control Plane VM

Nova uses etcd as its backing store. So a default storage class is needed to be able to run the etcd' `StatefulSet` and its associated 
`Persistent Volume`. Instructions to install Longhorn are available in the `install_longhorn.md`. At the end of the install, please ensure that all Longhorn pods are running before beginning Nova Control Plane install steps in the next section.

```
$ sudo k0s kubectl -n longhorn-system get pods
NAME                                                READY   STATUS    RESTARTS        AGE
csi-attacher-7558bd8ffb-92pz2                       1/1     Running   0               82s
csi-attacher-7558bd8ffb-qljw5                       1/1     Running   0               82s
csi-attacher-7558bd8ffb-qxpcx                       1/1     Running   0               82s

...SNIP...

engine-image-ei-3154f3aa-jbszl                      1/1     Running   0               2m8s
instance-manager-65561370c35b7bcc3e00283f742bb706   1/1     Running   0               97s
longhorn-csi-plugin-z5mnp                           3/3     Running   0               82s
longhorn-driver-deployer-676f7f6c5c-nkh6q           1/1     Running   0               3m34s
longhorn-manager-wg2gh                              2/2     Running   1 (2m28s ago)   3m34s
longhorn-ui-7c54575f4d-2zvrq                        1/1     Running   0               3m34s
longhorn-ui-7c54575f4d-7zc6k                        1/1     Running   0               3m34s
```


## Install Nova Control Plane

We will now install the Nova Control plane on the the first VM, `ubuntu-vm1`:
```ssh
export KUBECONFIG=~/.kube/k0s-vm1-config
```

In order to run Nova in a resource-constrained local env, we decrease Nova Control plane's etcd storage from 50Gi to 5Gi in the manifest:
From your downloaded files, edit this manifest: `nova-linux-arm64-v1.3.13/nova/install/base/control-plane/nova_cp.yaml`) and replace 50Gi with 10Gi.

After the etcd manifest is updated, please follow instructions provided here: [https://docs.elotl.co/nova/installation/](https://docs.elotl.co/nova/installation/)

### Temporary fix to use ARM64 images for the Nova control plane
```ssh
KUBECONFIG=~/.kube/k0s-vm1-config kubectl edit deploy nova-scheduler -n elotl
```

Replace `image: elotl/nova-scheduler:v1.3.13` with `image: elotl/nova-scheduler-dev:v1.3.13-1-g3388cf5`

## Install Nova Workload Cluster

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



## Appendix

If you need to setup your environment from scratch, you can use some of the helper scripts described in the following sections:

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

### (Optional) Passwordless SSH to both VMs

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


