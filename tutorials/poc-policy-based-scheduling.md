# Policy Based Scheduling

## Overview

Nova currently supports three ways to schedule a workload - annotation-based scheduling, policy based scheduling, and smart scheduling based on resource availability

### Policy Based Scheduling Testing Example

Policy based scheduling is done via scheduling is through Nova's SchedulePolicy CRD. A schedule policy contains one or more resource selectors, and a placement to tell how the scheduling should happen for matching resources.

In this example, we use one kube-config with three defined contexts: 

* `nova` for Nova Control Plane
* `kind-workload-1` for workload cluster 1
* `kind-workload-2` for workload cluster 2

Your kube-contexts are likely named differently. To follow this tutorial, please set following environment variables to appropriate context names:

Both workload clusters are connected to the Nova Control Plane. We will use the names of those clusters in the SchedulePolicy.
You can check how your clusters are named in the Nova Control Plane:
```shell
   kubectl --context=nova get clusters
   NAME                    K8S-VERSION   K8S-CLUSTER   REGION   ZONE   READY   IDLE   STANDBY
   kind-workload-1   1.22          workload-1                    True    True   False
   kind-workload-2   1.22          workload-2                    True    True   False
```


1. `kubectl --context=nova apply -f examples/sample-policy-scheduling/policy.yaml`. This policy is saying, for any objects with label `app: redis` or `app: guestbook`, schedule them to cluster `kind-workload-1`.
2. `kubectl --context=nova apply -f examples/sample-policy-scheduling/guestbook-all-in-one.yaml -n guestbook`. This schedules the guestbook stateless application into `kind-workload-1`.
3. `kubectl --context=nova get all -n guestbook`. You should be able to see something like the following:
    ```
    NAME                     TYPE           CLUSTER-IP     EXTERNAL-IP    PORT(S)        AGE
    service/frontend         LoadBalancer   10.96.25.97    35.223.90.60      80:31528/TCP   82s
    service/redis-follower   ClusterIP      10.96.251.47   <none>         6379/TCP       83s
    service/redis-leader     ClusterIP      10.96.27.169   <none>         6379/TCP       83s

    NAME                             READY   UP-TO-DATE   AVAILABLE   AGE
    deployment.apps/frontend         3/3     3            3           83s
    deployment.apps/redis-follower   2/2     2            2           83s
    deployment.apps/redis-leader     1/1     1            1           83s
    ```

The external-ip of the frontend service should lead you to the main page of the guestbook application.

### Workload migration

Now let's say your `kind-workload-1` will go through some maintenance and you want to migrate your guestbook application to `kind-workload-2`.
You can achieve this by editing the schedulePolicy:

1. `kubectl --context=nova edit schedulepolicy app-guestbook -n guestbook`. Update `kind-workload-1` to `kind-workload-2`.
2. You should be able to see your workload deleted from `kind-workload-1` and recreated in`kind-workload-2`.


## Policy configuration

SchedulePolicy Custom Resource selects objects from their labels and namespace via `.spec.resourceSelectors.labelSelectors` and `.spec.namespaceSelector`. The selected objects are dispatched to the clusters specified in `.spec.clusterSelector`.

### Matching Kubernetes Objects
To match objects from `default` namespace, define a SchedulePolicy like this:
```yaml
apiVersion: policy.elotl.co/v1alpha1
kind: SchedulePolicy
metadata:
   ...
spec:
  namespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: default
  ...
```

To match objects from a multiple namespaces define a SchedulePolicy like this:

```yaml
apiVersion: policy.elotl.co/v1alpha1
kind: SchedulePolicy
metadata:
   ...
spec:
  namespaceSelector:
    matchExpressions:
    - key: kubernetes.io/metadata.name
      operator: In
      values:
      - namespace-one
      - namespace-two
      - namespace-three
  ...
```

To match objects from all namespaces define a SchedulePolicy like this:
```yaml
apiVersion: policy.elotl.co/v1alpha1
kind: SchedulePolicy
metadata:
   ...
spec:
  namespaceSelector:
    matchExpressions:
    - key: kubernetes.io/metadata.name
      operator: Exists
  ...
```

Only the objects selected by `.spec.namespaceSelector` and `.spec.resourceSelectors.labelSelectors` are selected. To match all object in multiple namespaces define a resource selector like this:

```yaml
apiVersion: policy.elotl.co/v1alpha1
kind: SchedulePolicy
metadata:
   ...
spec:
  resourceSelectors:
    labelSelectors:
    - matchExpressions: []
  namespaceSelector:
    matchExpressions:
    - key: kubernetes.io/metadata.name
      operator: In
      values:
      - namespace-one
      - namespace-two
      ...
  ...
```

### Specifying target cluster(s)

When Nova is scheduling objects, it finds matching SchedulePolicy. By default, if no `.spec.clusterSelector` is set, Nova will try to pick any workload cluster connected, based on available resources (see [Smart scheduling](./poc-smart-scheduling.md)).
You can narrow down a list of cluster, using `.spec.clusterSelector`. You can also set target cluster explicitly, similar as it was described in [Annotation based scheduling](./poc-annotation-based-scheduling.md).

You can get a list of clusters connected to Nova, using kubectl:

   $ kubectl get clusters

We can use cluster properties (such as name, cluster provider, kubernetes version, cluster region, zone, etc.) exposed by Nova as Cluster object labels, to instrument where the workloads should run.

To schedule all objects matching a SchedulePolicy to one of the clusters which is kubernetes version `v1.25.0`:

```yaml
apiVersion: policy.elotl.co/v1alpha1
kind: SchedulePolicy
metadata:
   ...
spec:
  clusterSelector:
     matchLabels:
       nova.elotl.co/cluster.version: "v1.25.0"
  resourceSelectors:
    labelSelectors:
    ...
  namespaceSelector:
      ...
  ...
```

To schedule all objects matching a SchedulePolicy to the cluster named `cluster-one`:

```yaml
apiVersion: policy.elotl.co/v1alpha1
kind: SchedulePolicy
metadata:
   ...
spec:
  clusterSelector:
     matchLabels:
       kubernetes.io/metadata.name: "cluster-one"
  resourceSelectors:
    labelSelectors:
    ...
  namespaceSelector:
      ...
  ...
```

To schedule all objects matching a SchedulePolicy to one of the clusters which is not running in region `us-east-1`:

```yaml
apiVersion: policy.elotl.co/v1alpha1
kind: SchedulePolicy
metadata:
   ...
spec:
  clusterSelector:
     matchExpressions:
     - key: nova.elotl.co/cluster.region
       operator: NotIn
       values:
       - us-east-1
  resourceSelectors:
    labelSelectors:
    ...
  namespaceSelector:
      ...
  ...
```

You can also set custom labels to the `Cluster` objects and use them. For example if you mix on-prem and cloud clusters, and want to schedule workloads in on-prem clusters only, you can label all on-prem clusters objects with `on-prem: true` and use it in SchedulePolicy:

```yaml
apiVersion: policy.elotl.co/v1alpha1
kind: SchedulePolicy
metadata:
   ...
spec:
   clusterSelector:
      matchLabels:
         on-prem: "true"
   resourceSelectors:
      labelSelectors:
      ...
   namespaceSelector:
      ...
   ...
```
