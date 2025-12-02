# Install Longhorn on a Single-node K0s cluster

SSH into the Nova control plane cluster or first Ubuntu VM (`ubuntu-vm1`)

## Install helm

For helm install to work on k0s, these prerequisite steps are needed:

Replace <user> with your username on the Ubuntu VM.

```
sudo cp /var/lib/k0s/pki/admin.conf ~/admin.conf
export KUBECONFIG=~/admin.conf
sudo chown <user> ./admin.conf
chmod g-r ./admin.conf
```

Ref: [https://stackoverflow.com/questions/67418363/helm-charts-how-to-install-a-package-in-a-k0s-cluster](https://stackoverflow.com/questions/67418363/helm-charts-how-to-install-a-package-in-a-k0s-cluster)

Now, we can install helm:

```
$ curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
$ chmod 700 get_helm.sh
$ ./get_helm.sh
```

## Install the Longhorn helm chart


```
sudo apt-get update
sudo apt-get install -y open-iscsi
```

```
helm repo add longhorn https://charts.longhorn.io
helm repo update
```

```
sudo k0s kubectl create namespace longhorn-system
```

```
helm install longhorn longhorn/longhorn --namespace longhorn-system
```

Ensure that all longhorn pods are running before going to the Nova install step:

```
$ sudo k0s kubectl -n longhorn-system get pods
NAME                                                READY   STATUS    RESTARTS        AGE
csi-attacher-7558bd8ffb-92pz2                       1/1     Running   0               82s
csi-attacher-7558bd8ffb-qljw5                       1/1     Running   0               82s
csi-attacher-7558bd8ffb-qxpcx                       1/1     Running   0               82s
csi-provisioner-bcd886f95-7jpp8                     1/1     Running   0               82s
csi-provisioner-bcd886f95-kkhxd                     1/1     Running   0               82s
csi-provisioner-bcd886f95-w6jnh                     1/1     Running   0               82s
csi-resizer-684f4f6845-9gjtp                        1/1     Running   0               82s
csi-resizer-684f4f6845-k7pnh                        1/1     Running   0               82s
csi-resizer-684f4f6845-wxnqb                        1/1     Running   0               82s
csi-snapshotter-bf76678bd-5cpdt                     1/1     Running   0               82s
csi-snapshotter-bf76678bd-qjcff                     1/1     Running   0               82s
csi-snapshotter-bf76678bd-sp6qp                     1/1     Running   0               82s
engine-image-ei-3154f3aa-jbszl                      1/1     Running   0               2m8s
instance-manager-65561370c35b7bcc3e00283f742bb706   1/1     Running   0               97s
longhorn-csi-plugin-z5mnp                           3/3     Running   0               82s
longhorn-driver-deployer-676f7f6c5c-nkh6q           1/1     Running   0               3m34s
longhorn-manager-wg2gh                              2/2     Running   1 (2m28s ago)   3m34s
longhorn-ui-7c54575f4d-2zvrq                        1/1     Running   0               3m34s
longhorn-ui-7c54575f4d-7zc6k                        1/1     Running   0               3m34s
```

Ref: [https://blog.helmuth.at/2024/11/k0s-longhorn-part3/](https://blog.helmuth.at/2024/11/k0s-longhorn-part3/)
