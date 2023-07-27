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

## Kind Operations

Nova JIT cluster delete/recreate standby and cluster clone/create can be run locally on kind clusters.  In this section, we walk through examples of each.

Start the Nova JIT helper tool in a separate terminal.  This tool executes "cloud" operations on your local kind clusters, including cluster deletion and creation.

    $ ./bin/nova-jit-helper # use version for your OS and processor

You need to enable Nova JIT at deployment time.  Teardown any existing non-JIT deployment of the Nova trial sandbox:

    $ ./scripts/teardown_kind_cluster.sh

You can double-check that there are no running kind clusters:

    $ kind get clusters
    No kind clusters found.

Set the following environment variables to enable standby in delete/recreate mode with enter-standby set to 90 secs and to enable cluster create/clone:

    $ export NOVA_IDLE_ENTER_STANDBY_ENABLE="true"
    $ export NOVA_DELETE_CLUSTER_IN_STANDBY="true"
    $ export NOVA_IDLE_ENTER_STANDBY_SECS="120"
    $ export NOVA_CREATE_CLUSTER_IF_NEEDED="true"

After ensuring the appropriate novactl binary from try-nova/bin is installed, deploy Nova:

    $ ./scripts/setup_trial_env_on_kind.sh

After the Nova deployment is fully initialized, you will see that both workload clusters are ready, idle, and not in standby:

    $ kubectl --context=nova get clusters
    NAME              K8S-VERSION   K8S-CLUSTER   REGION   ZONE   READY   IDLE   STANDBY
    kind-workload-1   1.25          workload-1                    True    True   False
    kind-workload-2   1.25          workload-2                    True    True   False

And you can see the kind clusters backing the nova cp and the workload clusters:

    $ kind get clusters
    cp
    workload-1
    workload-2

After NOVA_IDLE_ENTER_STANDBY_SECS seconds have elapsed, the workload clusters enter standby, and after an additional short period they are no longer reported as ready:

    $ kubectl --context=nova get clusters
    NAME              K8S-VERSION   K8S-CLUSTER   REGION   ZONE   READY   IDLE   STANDBY
    kind-workload-1   1.25          workload-1                    False   True   True
    kind-workload-2   1.25          workload-2                    False   True   True

And the kind clusters backing the workload clusters are deleted:

    $ kind get clusters
    cp

At this point, you can bring the clusters out of standby by, e.g., scheduling spread workloads that need both workload clusters:

    $ kubectl --context=nova apply -f examples/sample-spread-scheduling/busybox.yaml
    deployment.apps/busybox created

You can almost immediately see that the workload clusters are no longer idle and no longer considered to be in standby, but they are not yet ready:

    $ kubectl --context=nova get clusters
    NAME              K8S-VERSION   K8S-CLUSTER   REGION   ZONE   READY   IDLE    STANDBY
    kind-workload-1   1.25          workload-1                    False   False   False
    kind-workload-2   1.25          workload-2                    False   False   False

After the workload clusters are recreated and the nova agent software is reinstalled, they become ready:

    $ kubectl --context=nova get clusters
    NAME              K8S-VERSION   K8S-CLUSTER   REGION   ZONE   READY   IDLE    STANDBY
    kind-workload-1   1.25          workload-1                    True    False   False
    kind-workload-2   1.25          workload-2                    True    False   False

And the busybox spread workloads are successfully scheduled:

    $ kubectl --context=nova get all --all-namespaces
    NAMESPACE   NAME                        READY   STATUS    RESTARTS   AGE
    default     pod/busybox-66f46bc-w4m6v   1/1     Running   0          89s
    default     pod/busybox-66f46bc-zrh5p   1/1     Running   0          108s

    NAMESPACE   NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
    default     service/kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP   7m20s

    NAMESPACE   NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
    default     deployment.apps/busybox   2/2     2            2           2m45s

    NAMESPACE   NAME                              DESIRED   CURRENT   READY   AGE
    default     replicaset.apps/busybox-66f46bc   1         0         0       108s

And you can see the kind workload clusters have been recreated:

    $ kind get clusters
    cp
    workload-1
    workload-2

If you want to access the recreated workload clusters directly, you can generate kubeconfigs for them:

    $ kind get kubeconfig --name=workload-1 > workload-1.config
    $ kind get kubeconfig --name=workload-2 > workload-2.config

And then you can check them directly:

    $ KUBECONFIG=./workload-1.config kubectl get all
    NAME                        READY   STATUS    RESTARTS   AGE
    pod/busybox-66f46bc-zrh5p   1/1     Running   0          50m

    NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
    service/kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP   50m

    NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
    deployment.apps/busybox   1/1     1            1           50m

    NAME                              DESIRED   CURRENT   READY   AGE
    replicaset.apps/busybox-66f46bc   1         1         1       50m

    $ KUBECONFIG=./workload-2.config kubectl get all
    NAME                        READY   STATUS    RESTARTS   AGE
    pod/busybox-66f46bc-w4m6v   1/1     Running   0          49m

    NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
    service/kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP   50m

    NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
    deployment.apps/busybox   1/1     1            1           49m

    NAME                              DESIRED   CURRENT   READY   AGE
    replicaset.apps/busybox-66f46bc   1         1         1       49m

So we've just seen an example of Nova JIT cluster delete/recreate standby.  Next let's look at an example of Nova JIT cluster create/clone.  Nova JIT cluster create/clone creates a new cluster if needed to satisfy a Nova policy.  Such policies apply to a number of use cases, including resource availability, K8s upgrade, and resource isolation.

In our example, we define a policy created to allocate a cluster to isolate a new customer's workloads.  The policy indicates that workloads matching namespace "namespace-customer3" should be placed on cluster kind-workload-3, which does not currently exist:

    $ kubectl --context=nova apply -f examples/sample-policy/schedule_policy_namespace.yaml
    schedulepolicy.policy.elotl.co/trial-policy-customer1 created

We then deploy the namespace and a workload pod pod-customer3 in that namespace.

    $ kubectl --context=nova apply -f examples/sample-workloads/pod_namespace.yaml
    namespace/namespace-customer3 created
    pod/pod-customer3 created

Nova JIT begins the process of creating kind-workload-3 to accommodate the placement:

    $ kubectl --context=nova get clusters
    NAME              K8S-VERSION   K8S-CLUSTER   REGION   ZONE   READY   IDLE    STANDBY
    kind-workload-1   1.25          workload-1                    True    False   False
    kind-workload-2   1.25          workload-2                    True    False   False
    kind-workload-3   1.25          workload-3                    False   False   False

And after the cluster is created and the Nova agent is installed on it, it becomes ready for use:

    $ kubectl --context=nova get clusters
    NAME              K8S-VERSION   K8S-CLUSTER   REGION   ZONE   READY   IDLE    STANDBY
    kind-workload-1   1.25          workload-1                    True    False   False
    kind-workload-2   1.25          workload-2                    True    False   False
    kind-workload-3   1.25          workload-3                    True    False   False

You can see the new kind cluster that is backing the new K8s cluster:

    $ kind get clusters
    cp
    workload-1
    workload-2
    workload-3

And you can see the new pod running via Nova control plane:

    $ kubectl --context=nova get all --all-namespaces
    NAMESPACE             NAME                        READY   STATUS    RESTARTS   AGE
    default               pod/busybox-66f46bc-dbbdq   1/1     Running   0          5m40s
    default               pod/busybox-66f46bc-wztzf   1/1     Running   0          5m21s
    namespace-customer3   pod/pod-customer3           1/1     Running   0          2m23s

    NAMESPACE   NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
    default     service/kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP   10m

    NAMESPACE   NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
    default     deployment.apps/busybox   2/2     2            2           6m25s

    NAMESPACE   NAME                              DESIRED   CURRENT   READY   AGE
    default     replicaset.apps/busybox-66f46bc   1         1         0       5m41s

You can generate a kubeconfig for the newly created cluster:

    $ kind get kubeconfig --name=workload-3 > workload-3.config

And you can use it to check the target workload cluster directly:

    $ KUBECONFIG=./workload-3.config kubectl get all -n namespace-customer3
    NAME                READY   STATUS    RESTARTS   AGE
    pod/pod-customer3   1/1     Running   0          3m11s

Note that when you get ready to teardown your kind clusters, "./scripts/teardown_kind_cluster.sh" only deletes the kind clusters that were deployed by default.  To delete the kind cluster that Nova clone/create created, run:

    $ kind delete cluster --name workload-3

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
