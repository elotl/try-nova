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

- Installed and running Docker
- Installed [Kind](https://kind.sigs.k8s.io/)
- Installed [novactl](https://docs.elotl.co/nova/installation_novactl#install-novactl) (version >= 0.5.0)

## Installation on KIND (Kubernetes in Docker) clusters

Make sure you have correct `novactl` version (>= 0.5.0) installed:

```sh
  kubectl nova --version
  novactl version v0.6.0 (git: 141d6e91) built: 20230801122245

```

This script will allow you to create and configure 3 kind clusters - one of them will be the Nova Control Plane and the other two will be Nova workload clusters.

```sh
    ./scripts/setup_trial_env_on_kind.sh
```

Once installation finishes, you can use the following command to export Nova Control Plane kubeconfig as well as the kubeconfig of the hosting (or management) cluster and the workload clusters:

```sh
    export KUBECONFIG=$HOME/.nova/nova/nova-kubeconfig:$PWD/kubeconfig-e2e-test-cp:$PWD/kubeconfig-e2e-test-workload-1:$PWD/kubeconfig-e2e-test-workload-2
```

This gives you access to Nova Control Plane (`nova` context), cluster hosting Nova Control Plane (context `kind-cp`) and two workload clusters (context `kind-workload-1` and `kind-workload-2`)

To interact with the Nova control plane, use `--context=nova` flag in kubectl commands, e.g.:

```sh
  kubectl --context=nova get clusters
  NAME              K8S-VERSION   K8S-CLUSTER   REGION   ZONE   READY   IDLE   STANDBY
  kind-workload-1   1.25          workload-1                    True    True   False
  kind-workload-2   1.25          workload-2                    True    True   False

```

If you want to run multiple Nova Control Planes you probably will also want to rename your context:

```sh
  kubectl config rename-context nova <your custom name>
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

If you'd like to try Nova on the cloud (AWS, GCP, Azure, OCI, on-prem), please grab free trial bits at https://www.elotl.co/free-trial.html
