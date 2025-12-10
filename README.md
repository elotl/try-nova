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


## Install `novactl`

`novactl` is a CLI that allows you to easily create new Nova Control Planes, register new Nova Workload Clusters, check the health of your Nova cluster, and more!

Download `novactl`.
```bash
curl -s https://api.github.com/repos/elotl/novactl/releases/latest | \
jq -r '.assets[].browser_download_url' | \
grep "$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m | sed 's/x86_64/amd64/;s/i386/386/;s/aarch64/arm64/')" | \
xargs -I {} curl -L {} -o novactl
```

Make sure `novactl` is executable.
```bash
chmod +x novactl
```

Place `novactl` in your PATH. The following is an example to install the plugin in `/usr/local/bin` for Unix-like operating systems:

```bash
sudo mv novactl /usr/local/bin/novactl
```

Install `novactl` as a [kubectl plugin](https://kubernetes.io/docs/tasks/extend-kubectl/kubectl-plugins/). **Our docs assume you're using `novactl` as kubectl plugin**. To make this work, simply run:
```bash
sudo novactl kubectl-install
```

## Try Nova on KIND

Verify `novactl` is installed.
```sh
  kubectl nova --version
```

Navigate to the root of this repository and setup enviornment variables for trial environment.
```sh
export NOVA_NAMESPACE=elotl
export NOVA_CONTROLPLANE_CONTEXT=nova
export K8S_CLUSTER_CONTEXT_1=k8s-cluster-1
export K8S_CLUSTER_CONTEXT_2=k8s-cluster-2
export K8S_HOSTING_CLUSTER_CONTEXT=kind-hosting-cluster
export NOVA_WORKLOAD_CLUSTER_1=wlc-1
export NOVA_WORKLOAD_CLUSTER_2=wlc-2
export K8S_HOSTING_CLUSTER=hosting-cluster
```

Create trial environment with 3 Kind clusters. First Kind cluster will host Nova. Second Kind cluster will host workload cluster `wlc-1`. Third Kind cluster will host workload cluster `wlc-2`. Nova will manage `wlc-1` and `wlc-2` as a fleet.
```sh
./scripts/setup_trial_env_on_kind.sh
```

Update KUBECONFIG to include Nova and workload clusters.
```sh
export KUBECONFIG=$HOME/.nova/nova/nova-kubeconfig:$PWD/kubeconfig-cp:$PWD/kubeconfig-workload-1:$PWD/kubeconfig-workload-2
```

You should see the two workload clusters as part of Nova's fleet.

```sh
kubectl --context=nova get clusters
```

Let us run a simple tutorial where Nova spreads pods for an Nginx deployment in a 20:80 fashion across the two workload clusters.

Create Nova SchedulePolicy.
```sh
cat <<EOF > ./schedule-policy.yaml
apiVersion: policy.elotl.co/v1alpha1
kind: SchedulePolicy
metadata:
  name: spread-group-policy
spec:
  namespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: default
  groupBy:
    labelKey: app
  spreadConstraints:
    topologyKey: kubernetes.io/metadata.name
    percentageSplit:
    - topologyValue: wlc-1 
      percentage: 20
    - topologyValue: wlc-2
      percentage: 80
  clusterSelector:
    matchExpressions:
    - key: kubernetes.io/metadata.name
      operator: In
      values:
      - wlc-1
      - wlc-2
  resourceSelectors:
    labelSelectors:
    - matchLabels:
        group-policy: nginx-spread
EOF
```

Apply the SchedulePolicy.
```sh
kubectl --context=nova apply -f ./schedule-policy.yaml
```
Feel free to inspect the newly created SchedulePolicy in Nova.
```sh
kubectl --context=nova get schedulepolicies
```
Create Nginx deployment.
```sh
kubectl --context=nova apply -f examples/sample-spread-scheduling/nginx-app.yaml
```

Verify Nova sees 10 replicas of Nginx.
```sh
kubectl --context=nova get deployment
```

Look at `wlc-1` - you should see 2 Nginx replicas on it!
```sh
KUBECONFIG=./kubeconfig-workload-1 kubectl get deployment
```
Look at `workload-2` - you should see 8 Nginx replicas on it!
```
KUBECONFIG=./kubeconfig-workload-2 kubectl get deployment
```

Feeling brave? Edit the SchedulePolicy to change pod split percentages in `spec:spreadConstraints:percentageSplit:percentage` from 20:80 to any other value, say 50:50.
```sh
kubectl --context=nova edit schedulepolicy spread-group-policy
```
Watch Nova dynamically rebalance pod split across the two workload clusters - `wlc-1` should now have 5 replicas and `wlc-2` should have 5 replicas as well to honor 50:50 split!
```sh
KUBECONFIG=./kubeconfig-workload-1 kubectl get deployment
KUBECONFIG=./kubeconfig-workload-2 kubectl get deployment
```

Want to explore other fun Nova Schedule Policies? Check them out here! 
* [Annotation-based Scheduling](https://docs.elotl.co/nova/Tutorials/poc-annotation-based-scheduling)
* [Policy-based Scheduling](https://docs.elotl.co/nova/Tutorials/poc-policy-based-scheduling)
* [Capacity-based Scheduling](https://docs.elotl.co/nova/Tutorials/poc-capacity-based-scheduling)
* [Spread Scheduling](https://docs.elotl.co/nova/Tutorials/poc-spread-onto-multiple-clusters)
* [Just In Time Clusters](https://docs.elotl.co/nova/Tutorials/poc-standby-workload-cluster)

After you are done with the trial, delete Kind environment.
```sh
./scripts/teardown_kind_cluster.sh
./scripts/cleanup_files.sh
```

## Try Nova on vCluster

[Install vCluster](https://www.vcluster.com/install) command line.
```sh
  brew install loft-sh/tap/vcluster
```

Verify `novactl` is installed.
```sh
  kubectl nova --version
```

Navigate to the root of this repository and setup enviornment variables for trial environment.
```sh
export NOVA_NAMESPACE=elotl
export NOVA_CONTROLPLANE_CONTEXT=nova
export K8S_CLUSTER_CONTEXT_1=k8s-cluster-1
export K8S_CLUSTER_CONTEXT_2=k8s-cluster-2
export K8S_HOSTING_CLUSTER_CONTEXT=kind-hosting-cluster
export NOVA_WORKLOAD_CLUSTER_1=wlc-1
export NOVA_WORKLOAD_CLUSTER_2=wlc-2
export K8S_HOSTING_CLUSTER=hosting-cluster
export VCLUSTER_1=vcluster-1
export VCLUSTER_2=vcluster-2
```

Create trial environment with 3 Kind clusters. First Kind cluster will host Nova. Second Kind cluster will host `vCluster-1`. Third Kind cluster will host `vCluster-2`. Nova will manage `vCluster-1` and `vCluster-2` as a fleet.
```sh
    ./scripts/setup_vcluster.sh
```

Update KUBECONFIG to include Nova.
```sh
export KUBECONFIG=~/.kube/config:$HOME/.nova/nova/nova-kubeconfig
```

You should see the two vClusters as part of Nova's fleet.
```sh
kubectl --context=nova get clusters
```

Let us run a simple tutorial where Nova spreads pods for an Nginx deployment in a 20:80 fashion across the two vClusters.

Create Nova SchedulePolicy.
```sh
cat <<EOF > ./vcluster-schedule-policy.yaml
apiVersion: policy.elotl.co/v1alpha1
kind: SchedulePolicy
metadata:
  name: spread-group-policy
spec:
  namespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: default
  groupBy:
    labelKey: app
  spreadConstraints:
    topologyKey: kubernetes.io/metadata.name
    percentageSplit:
    - topologyValue: vcluster-vcluster-1-vcluster-1-kind-wlc-1 
      percentage: 20
    - topologyValue: vcluster-vcluster-2-vcluster-2-kind-wlc-2
      percentage: 80
  clusterSelector:
    matchExpressions:
    - key: kubernetes.io/metadata.name
      operator: In
      values:
      - vcluster-vcluster-1-vcluster-1-kind-wlc-1
      - vcluster-vcluster-2-vcluster-2-kind-wlc-2
  resourceSelectors:
    labelSelectors:
    - matchLabels:
        group-policy: nginx-spread
EOF
```

Apply the SchedulePolicy.
```sh
kubectl --context=nova apply -f ./vcluster-schedule-policy.yaml
```

Feel free to inspect the newly created SchedulePolicy in Nova.
```sh
kubectl --context=nova get schedulepolicies
```

Create Nginx deployment.
```sh
kubectl --context=nova apply -f examples/sample-spread-scheduling/nginx-app.yaml
```

Verify Nova sees 10 replicas of Nginx.
```sh
kubectl --context=nova get deployment
```

Look at `vCluster-1` - you should see 2 Nginx replicas on it!
```sh
KUBECONFIG=./kubeconfig-vcluster-1 kubectl get deployment
```
Look at `vCluster-2` - you should see 8 Nginx replicas on it!
```
KUBECONFIG=./kubeconfig-vcluster-2 kubectl get deployment
```

Feeling brave? Edit the SchedulePolicy to change pod split percentages in `spec:spreadConstraints:percentageSplit:percentage` from 20:80 to any other value, say 50:50.
```sh
kubectl --context=nova edit schedulepolicy spread-group-policy
```
Watch Nova dynamically rebalance pod split across the two vClusters - `vCluster-1` should now have 5 replicas and `vCluster-2` should have 5 replicas as well to honor 50:50 split!
```sh
KUBECONFIG=./kubeconfig-vcluster-1 kubectl get deployment
KUBECONFIG=./kubeconfig-vcluster-2 kubectl get deployment
```

Want to explore other fun Nova Schedule Policies? Check them out here! 
* [Annotation-based Scheduling](https://docs.elotl.co/nova/Tutorials/poc-annotation-based-scheduling)
* [Policy-based Scheduling](https://docs.elotl.co/nova/Tutorials/poc-policy-based-scheduling)
* [Capacity-based Scheduling](https://docs.elotl.co/nova/Tutorials/poc-capacity-based-scheduling)
* [Spread Scheduling](https://docs.elotl.co/nova/Tutorials/poc-spread-onto-multiple-clusters)
* [Just In Time Clusters](https://docs.elotl.co/nova/Tutorials/poc-standby-workload-cluster)

After you are done with the trial, delete vCluster environment.
```sh
./scripts/teardown_vcluster.sh
```

# Beyond KIND / vCluster

If you'd like to try Nova on hyperscalers (AWS, GCP, Azure, OCI, etc), neoclouds (CoreWeave, Lambda, etc), or on-prem, please grab free trial bits at https://www.elotl.co/nova-free-trial.html
