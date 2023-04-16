# Nova Quickstart

This README includes:
1. An installation guide for Nova on KIND clusters.
The scripts in this repo will allow you to create a sandbox environment for using Nova's trial version (for managing up to 3 workload clusters). If you are interested in using the full version, please contact us at info@elotl.com.
2. Tutorials that walk you through the core functionalities of Nova.

We love feedback, so please feel free to ask questions by creating an issue in this repo or writing to us at info@elotl.co

## Installation on KIND (Kubernetes in Docker) clusters

This script will allow you to create and configure 3 kind clusters - one of them will be the Nova Control Plane and the other two will be Nova workload clusters.

```sh
    $ ./scripts/setup_trial_env_on_kind.sh
```

Once installation finishes, you can use the following command to export Nova Control Plane kubeconfig as well as the kubeconfig of the hosting (or management) cluster and the workload clusters:

```sh
    $ export KUBECONFIG=$PWD/scripts/nova-installer-output/nova-kubeconfig:$PWD/kubeconfig-e2e-test-cp:$PWD/kubeconfig-e2e-test-workload-1:$PWD/kubeconfig-e2e-test-workload-2
```

This gives you access to Nova Control Plane (`nova` context), cluster hosting Nova Control Plane (context `kind-cp`) and two workload clusters (context `kind-workload-1` and `kind-workload-2`)

To interact with the Nova control plane, use `--context=nova` flag in kubectl commands, e.g.:

```sh
  $ kubectl --context=nova get clusters
```

To get more insight into the cluster's available resources:
```sh
  $ kubectl --context=nova get clusters -o go-template-file=./scripts/kubectl_templates/cluster_output.gotemplate
```

## Nova Tutorials

* [Annotation-based Scheduling](https://docs.elotl.co/nova/Tutorials/poc-annotation-based-scheduling)
* [Policy-based Scheduling](https://docs.elotl.co/nova/Tutorials/poc-policy-based-scheduling)
* [Capacity-based Scheduling](https://docs.elotl.co/nova/Tutorials/poc-capacity-based-scheduling)
* [Just-in-time Standby Workload Clusters](https://docs.elotl.co/nova/Tutorials/poc-standby-workload-cluster)
* [Using Nova CLI](tutorials/nova-cli-usage.md)

### Supported api-resources

Nova supports the following standard Kubernetes objects as well as CRDs:

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

## Deleting Nova trial sandbox

    $ ./scripts/teardown_kind_cluster.sh

