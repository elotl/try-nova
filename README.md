# Nova Quickstart
[![Slack][Slack-Image]][Slack-Url]  [![Docs][Docs-Image]][Docs-Url] [![Elotl Inc.][Elotl-Image]][Elotl-Url]


[Docs-Image]: https://img.shields.io/badge/nova-docs-blue
[Docs-Url]: https://docs.elotl.co/nova/intro
[Elotl-Image]: https://img.shields.io/badge/Elotl-home-blue
[Elotl-Url]: https://www.elotl.co/
[Slack-Image]: https://img.shields.io/badge/chat-on%20slack-green
[Slack-Url]: https://join.slack.com/t/elotl-free-trial/shared_invite/zt-1tciz8cck-H9Swzl2grCqPaLJeHYtbBQ

This README includes:
1. An installation guide for Nova on KIND clusters.
The scripts in this repo will allow you to create a sandbox environment for using Nova's trial version (for managing up to 6 workload clusters). If you are interested in using the full version, please contact us at info@elotl.co
2. Tutorials that walk you through the core functionalities of Nova.

We love feedback, so please feel free to ask questions by creating an issue in this repo, joining our Slack: [Elotl Free Trial](https://join.slack.com/t/elotl-free-trial/shared_invite/zt-1tciz8cck-H9Swzl2grCqPaLJeHYtbBQ) or writing to us at info@elotl.co

## Prerequisites

You should have:

- Installed and running [Docker](https://docs.docker.com/engine/install/) (tested on version `27.0.3`)
- Installed [Kind](https://kind.sigs.k8s.io/docs/user/quick-start) (tested on version `0.21.0`)
- Installed [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl) (tested on client version `v1.31.0`)
- Installed [jq](https://jqlang.github.io/jq/download/) (tested on version `1.7`)
- Installed [envsubst](https://github.com/a8m/envsubst) (tested on version `0.22.4`)

Please note that Nova on KIND is tested on:
1. Mac OS Version 13.6
2. Ubuntu Version 22.04.1

In some Linux environments, the default [inotify](https://linux.die.net/man/7/inotify) resource configuration might not allow you to create sufficient Kind clusters to successfully install Nova. View more about why this is needed [here](https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files)

To increase these inotify limits, edit the file `/etc/sysctl.conf` and add these lines:
```bash
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
```
Use the following command to load the new sysctl settings:
```bash
sudo sysctl -p
```
Ensure these variables have been set correctly by using these commands:
```bash
sysctl -n fs.inotify.max_user_watches
sysctl -n fs.inotify.max_user_instances
```


## Install Nova's command line tool `novactl`

`novactl` is our CLI that allows you to easily create new Nova Control Planes, register new Nova Workload Clusters, check the health of your Nova cluster, and more!

### Download `novactl`

```bash
curl -s https://api.github.com/repos/elotl/novactl/releases/latest | \
jq -r '.assets[].browser_download_url' | \
grep "$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m | sed 's/x86_64/amd64/;s/i386/386/;s/aarch64/arm64/')" | \
xargs -I {} curl -L {} -o novactl
```

### Install `novactl`

#### Make the binary executable

Once you have the binary, run:

```bash
chmod +x novactl
```

#### Place the binary in your PATH

The following is an example to install the plugin in `/usr/local/bin` for Unix-like operating systems:

```bash
sudo mv novactl /usr/local/bin/novactl
```

#### Install it as kubectl plugin

`novactl` is ready to work as a [kubectl plugin](https://kubernetes.io/docs/tasks/extend-kubectl/kubectl-plugins/). **Our docs assume you're using `novactl` as kubectl plugin**. To make this work, simply run:

```bash
sudo novactl kubectl-install
```

## Installation of Nova on KIND (Kubernetes in Docker) clusters

Make sure you have the expected `novactl` version installed. If you're expecting to use `v0.9.0` this is how you can check:

```sh
  kubectl nova --version
```
```sh
  kubectl-nova version v0.9.0 (git: 58407116) built: 20240312092623
```

Navigate to the root of the repository.

This script will allow you to create and configure 3 kind clusters - one of them will be the Nova Control Plane and the other two will be Nova workload clusters.

```sh
export NOVA_NAMESPACE=elotl
export NOVA_CONTROLPLANE_CONTEXT=nova
export K8S_CLUSTER_CONTEXT_1=k8s-cluster-1
export K8S_CLUSTER_CONTEXT_2=k8s-cluster-2
export K8S_HOSTING_CLUSTER_CONTEXT=kind-hosting-cluster
export NOVA_WORKLOAD_CLUSTER_1=kind-wlc-1
export NOVA_WORKLOAD_CLUSTER_2=kind-wlc-2
export K8S_HOSTING_CLUSTER=hosting-cluster
```

```sh
    ./scripts/setup_trial_env_on_kind.sh
```

Once installation finishes, you can use the following command to export Nova Control Plane kubeconfig as well as the kubeconfig of the hosting (or management) cluster and the workload clusters:

```sh
    export KUBECONFIG=$HOME/.nova/nova/nova-kubeconfig:$PWD/kubeconfig-cp:$PWD/kubeconfig-workload-1:$PWD/kubeconfig-workload-2
```

This gives you access to Nova Control Plane (`${NOVA_CONTROLPLANE_CONTEXT}` context), cluster hosting Nova Control Plane (context `kind-${K8S_HOSTING_CLUSTER}`) and two workload clusters (context `kind-${NOVA_WORKLOAD_CLUSTER_1}` and `kind-${NOVA_WORKLOAD_CLUSTER_1}`)

To interact with the Nova control plane, use `--context=${NOVA_CONTROLPLANE_CONTEXT}` flag in kubectl commands, e.g.:

```sh
  kubectl --context=${NOVA_CONTROLPLANE_CONTEXT} get clusters
```

```text
  NAME    K8S-VERSION   K8S-CLUSTER   REGION   ZONE   READY   IDLE   STANDBY
  wlc-1   1.28          wlc-1                         True    True   False
  wlc-2   1.28          wlc-2                         True    True   False  
```

*Optional*

You may rename Kubernetes contexts, if you want to give them more meaningful names, as follows:

```sh
kubectl config rename-context "kind-${K8S_HOSTING_CLUSTER}" ${K8S_HOSTING_CLUSTER_CONTEXT}
kubectl config rename-context "kind-${NOVA_WORKLOAD_CLUSTER_1}" ${K8S_CLUSTER_CONTEXT_1}
kubectl config rename-context "kind-${NOVA_WORKLOAD_CLUSTER_2}" ${K8S_CLUSTER_CONTEXT_2}
```

## Nova Tutorials

* [Annotation-based Scheduling](https://docs.elotl.co/nova/Tutorials/poc-annotation-based-scheduling)
* [Policy-based Scheduling](https://docs.elotl.co/nova/Tutorials/poc-policy-based-scheduling)
* [Capacity-based Scheduling](https://docs.elotl.co/nova/Tutorials/poc-capacity-based-scheduling)
* [Spread Scheduling](https://docs.elotl.co/nova/Tutorials/poc-spread-onto-multiple-clusters)
* [Just In Time Clusters](https://docs.elotl.co/nova/Tutorials/poc-standby-workload-cluster)


## Deleting Nova trial sandbox

    ./scripts/teardown_kind_cluster.sh

# Beyond KIND

If you'd like to try Nova on the cloud (AWS, GCP, Azure, OCI, on-prem), please grab free trial bits at https://www.elotl.co/nova-free-trial.html
