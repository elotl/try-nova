# Just-in-time Standby Workload Cluster

## Functional Overview

Nova optionally supports putting an idle workload cluster into standby state, to reduce resource costs in the cloud.  When a standby workload cluster is needed to satisfy a Nova scheduling operation, the cluster is brought out standby state.  Nova can also optionally create additional cloud clusters, cloned from existing workload clusters, to satisfy the needs of policy-based or smart scheduling.

## Operational Description

If the environment variable NOVA_IDLE_ENTER_STANDBY_ENABLE is set when the Nova control plane is deployed, the Nova-JIT Workload Cluster Standby feature is enabled.  When the standby feature is enabled, a workload cluster that has been idle for 3600 secs (override via env var NOVA_IDLE_ENTER_STANDBY_SECS) is placed in standby state.  An idle workload cluster is one on which no Nova-scheduled object that consumes resources is running.  When Nova schedules an item to a workload cluster that is in standby state, the cluster is brought out of standby state.

### Suspend/Resume Standby Mode

In "suspend/resume" standby mode (default), all node groups/pools in a cluster in standby state are set to node count 0.  This setting change causes removal of all cluster resources, except the hidden cloud provider control plane, in ~2 minutes.  In standby, the status of all [non-Nova-scheduled] items (including the Nova agent) deployed in the cluster switches to pending.  EKS and GKE clusters in standby state cost $0.10/hour.  When the cluster exits standby, the node group/pool node counts are set back to their original values, which had been recorded by Nova in the cluster's custom resource object.  This setting change causes the restoration of the cluster resources in ~2 minutes, allowing its pending items (including the Nova agent) to resume running as well as allowing Nova-scheduled items to be placed successfully.

### Delete/Recreate Standby Mode

In "delete/recreate" standby mode (enabled via env var NOVA_DELETE_CLUSTER_IN_STANDBY), a workload cluster in standby state is completely deleted from the cloud, taking ~3-10 minutes.  When the cluster exits standby, the cluster is recreated in the cloud, taking ~3-15 minutes, and the Nova agent objects are redeployed.  The "delete/recreate" standby mode engenders greater cost savings than "suspend/resume", but the latencies to enter and exit standby state are significantly higher.

With the "create" option (enabled via env var NOVA_CREATE_CLUSTER_IF_NEEDED), a workload cluster is created via cloning an existing accessible (i.e., ready or can become ready via exiting standby) cluster to satisfy the needs of policy-based or smart scheduling.  The "create" option requires that "delete/recreate" standby mode be enabled, and created clusters can subsequently enter standby state.  The number of clusters that Nova will create is limited to 10 (override via env var NOVA_MAX_CREATED_CLUSTERS).  Cluster creation depends on the Nova deployment containing a cluster appropriate for cloning, i.e., that there is an existing accessible cluster that satisfies the scheduling policy constraints and resource capacity needs of the placement, but mismatches either the policy's specified cluster name or the placement's needed resource availability.

Note that Nova with the "create" option enabled will not choose to create a cluster to satisfy resource availability if it detects any existing accessible candidate target clusters have cluster autoscaling enabled; instead it will choose an accessible autoscaled cluster.  Nova's cluster autoscaling detection works for installations of Elotl Luna and of the Kubernetes Cluster Autoscaler.

## Cloud Operations

### Cloud Account Information

For Nova JIT to perform cloud operations, including getting/setting node group/pool configurations and deleting/recreating/creating clusters and node groups/pools, it requires the information needed to use a cloud account with the appropriate permissions.

For EKS, eksctl is used, which supports access to both managed and unmanaged node groups.  The eksctl credentials
are passed in the following environment variables, which should be set when the Nova control plane is deployed:
- AWS_ACCESS_KEY_ID     -- Set to access key id for AWS account for AWS workload cluster standby
- AWS_SECRET_ACCESS_KEY -- Set to secret access key for AWS account for AWS workload cluster standby

For GKE, gcloud is used; the following environment variables should be set when the Nova control plane is deployed:
- GCE_PROJECT_ID -- Set to project id of GCE account for GCE workload cluster standby
- GCE_ACCESS_KEY -- Set to base64 encoding of GCE service account json file for GCE workload cluster standby

### Accessing Recreated or Clone-created Clusters

To externally access clusters recreated or clone-created by Nova, a new context config must be created.
- For GKE, obtaining the config for the recreated cluster can be done via:
  - gcloud container clusters get-credentials _k8s-cluster-name_ --zone _zone-name_ --project _gce-project-name_
- For EKS, obtaining the config for the recreated cluster can be done via:
  - eksctl utils write-kubeconfig --cluster=_k8s-cluster-name_ --region _region-name_
- For KIND, obtaining the config for the recreated cluster can be done via:
  - kind get kubeconfig --name=_k8s-cluster-name_ >_k8s-cluster-name_.config

## Troubleshooting

### Logs and Commands

The Nova control plane logs report various information on JIT clusters operations.

For long-running cloud operations, it can be useful to obtain detailed information directly from cloud APIs.
- For EKS, useful commands include:
  - eksctl get cluster --name _k8s-cluster-name_ --region _region-name_
  - eksctl get nodegroup --cluster _k8s-cluster-name_ --region _region-name_
- For GKE, useful commands include:
  - gcloud container clusters describe _k8s-cluster-name_ --zone _zone-name_

### Known issues

EKS cluster deletion can sometimes fail; please see https://aws.amazon.com/premiumsupport/knowledge-center/eks-delete-cluster-issues/ for more information.
