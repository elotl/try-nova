# Nova - quickstart

This doc covers:
1. The installation guide of Nova.
2. A small Nova tutorial that walks you through the core functionalities of Nova.
3. This is a sandbox environment for trying Nova limited version (up to 10 workloads cluster). If you are interested in using full version, contact Elotl Inc.
4. We love the feedback, so feel free to ask questions by creating an issue in this repo, or joining our Slack [TODO LINK NEEDED]

## Installation on KIND (Kubernetes in Docker) clusters

To setup 3 kind clusters, and install Nova Control Plane + connect two kind clusters as workload clusters, run:

```sh
    $ ./scripts/setup_trial_env_on_kind.sh
```

Once installation finished, you can use following command to export Nova Control Plane kubeconfig + kubeconfigs of hosting and workload clusters:

```sh
    $ export KUBECONFIG=$PWD/scripts/nova-installer-output/nova-kubeconfig:$PWD/kubeconfig-e2e-test-cp:$PWD/kubeconfig-e2e-test-workload-1:$PWD/kubeconfig-e2e-test-workload-2
```

This gives you access to Nova Control Plane (`nova` context), cluster hosting Nova Control Plane (context  `kind-cp`) and two workload clusters (context `kind-workload-1` and `kind-workload-2`)

To interact with Nova control plane, use `--context=nova` flag in kubectl commands, e.g.:

```sh
  $ kubectl --context=nova get clusters
```

To get more insight into the clusters available resources:
```sh
  $ kubectl --context=nova get clusters -o go-template-file=./scripts/kubectl_templates/cluster_output.gotemplate
```

## Nova Tutorials / Testing

* [Annotation Based Scheduling](tutorials/poc-annotation-based-scheduling.md)
* [Policy Based Scheduling](tutorials/poc-policy-based-scheduling.md)
* [Smart Scheduling](tutorials/poc-smart-scheduling.md)
* [JIT Standby Workload Cluster](tutorials/poc-standby-workload-cluster.md)
* [Using Nova CLI](tutorials/nova-cli-usage.md)

### Supported api-resources

Nova supports the following standard kubernetes objects as well as CRDs:

* configmaps
* namespaces
* pods
* secrets
* serviceaccounts
* services
* daemonsets
* deployments
* replicasets
* statefulsets
* ingressclasses
* ingresses
* networkpolicies
* clusterrolebindings
* clusterroles
* rolebindings
* roles

## Removing Nova trial sandbox

    $ ./scripts/teardown_kind_cluster.sh

