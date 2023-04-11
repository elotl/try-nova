# Spread Scheduling 

## Overview

Nova supports spreading a group of workloads onto multiple clusters. This may be useful in cases such us spreading a workload across clusters in different zones / regions to ensure High Availability.

## Tutorial

In this example, we will group nginx Deployment and ServiceAccount onto two workload clusters and we will learn how to configure spread constraints in SchedulePolicy.
To follow this tutorial you will need Nova Control Plane with at least two workload clusters connected.
You can check connected clusters using kubectl:

    $ kubectl --context=nova get clusters --show-labels
    NAME              K8S-VERSION   K8S-CLUSTER   REGION   ZONE   READY   IDLE   STANDBY   LABELS
    kind-workload-1   1.22          workload-1                    True    True   False     kubernetes.io/metadata.name=kind-workload-1,nova.elotl.co/cluster.novacreated=false,nova.elotl.co/cluster.provider=kind,nova.elotl.co/cluster.version=1.22
    kind-workload-2   1.22          workload-2                    True    True   False     kubernetes.io/metadata.name=kind-workload-2,nova.elotl.co/cluster.novacreated=false,nova.elotl.co/cluster.provider=kind,nova.elotl.co/cluster.version=1.22

Here is ServiceAccount & Deployment we want to spread:

    $ cat <<EOF > sample-spread-scheduling/nginx-app.yaml
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: nginx
      namespace: default
      labels:
        app: nginx
        group-policy: nginx-spread
    spec:
      replicas: 10
      selector:
        matchLabels:
          app: nginx
      template:
        metadata:
          labels:
            app: nginx
            group-policy: nginx-spread
        spec:
          serviceAccountName: nginx-sa
          containers:
          - name: nginx
            image: nginx:1.14.2
            ports:
            - containerPort: 80
    ---
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: nginx-sa
      namespace: default
      labels:
        app: nginx
        group-policy: nginx-spread
    EOF

Now, we need to define SchedulePolicy matching those two objects.
We want to run 50% of replicas in `kind-workload-1` cluster and 50% in `kind-workload-2`. ServiceAccount needs to be present in both clusters.

    $ cat <<EOF > sample-spread-scheduling/policy.yaml
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
      clusterSelector:
        matchExpressions:
        - key: kubernetes.io/metadata.name
          operator: In
          values:
          - kind-workload-1
          - kind-workload-2
      resourceSelectors:
        labelSelectors:
        - matchLabels:
            group-policy: nginx-spread

Let's explain each field in .spec:

* `namespaceSelector` says "Match only k8s resources (e.g. Deployment) in `default` namespace"
* `groupBy` says "For each matched object, check a value of label `app`. Create ScheduleGroup containing k8s resources that share the same value of this label"
* `spreadConstraints` says "For each matched cluster, check a value of `kubernetes.io/metadata.name` and create a bucket of clusters for every value of that label" (In this example, we use label which value is unique for each cluster, so every bucket will have only one cluster)
* `clusterSelector` says "Consider workload clusters which have `kubernetes.io/metadata.name` equal to `kind-workload-1` or `kind-workload-2`"
* `resourceSelectors` says "Match only k8s resources (e.g. Deployment) that have label `group-policy=nginx-spread`"

Note: If your workload clusters have different names, you need to edit this policy before applying.

We can now apply policy and nginx app to the Nova Control Plane:

    $ kubectl --context=nova apply -f sample-spread-scheduling/policy.yaml
    $ kubectl --context=nova apply -f sample-spread-scheduling/nginx-app.yaml

Nova should now create nginx Deployment with 5 replicas in `kind-workload-1` & `kind-workload-2`. Nova will sync Deployment status to the Control Plane:

    $ kubectl --context=nova get deployment,serviceaccount
    NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
    deployment.apps/nginx   10/10     10            10           51s
    
    NAME                      SECRETS   AGE
    serviceaccount/nginx-sa   1         51s

**Currently, Nova supports syncing status for Deployments, ReplicaSets and StatefulSets**.

Let's verify if 5 replicas run in both clusters:

    $ kubectl --context=kind-workload-1 get deployment,serviceaccount
    NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
    deployment.apps/nginx   5/5     5            5           2m25s

    NAME                      SECRETS   AGE
    serviceaccount/default    1         18h
    serviceaccount/nginx-sa   1         2m25s

    $ kubectl --context=kind-workload-2 get deployment,serviceaccount
    NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
    deployment.apps/nginx   5/5     5            5           2m25s

    NAME                      SECRETS   AGE
    serviceaccount/default    1         18h
    serviceaccount/nginx-sa   1         2m25s


### Define % split of replicas
Nova also provides a way to define not even split of replicas between workload clusters. For that purpose, you need to specify this constraint in SchedulePolicy's `.spec.spreadConstraints`.


    $ cat <<EOF > sample-spread-scheduling/policy-percentage.yaml
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
        - topologyValue: kind-workload-1
          percentage: 20
        - topologyValue: kind-workload-2
          percentage: 80
      clusterSelector:
        matchExpressions:
        - key: kubernetes.io/metadata.name
          operator: In
          values:
          - kind-workload-1
          - kind-workload-2
      resourceSelectors:
        labelSelectors:
        - matchLabels:
            group-policy: nginx-spread

We added `percentageSplit` field, which says "Run 20% of replicas in a workload cluster with `kubernetes.io/metadata.name=kind-workload-1` and 80% in `kubernetes.io/metadata.name=kind-workload-2` workload cluster"

We can apply this policy now, and Nova will apply changes to match the constraints we specified.

    $ kubectl --context=nova apply -f sample-spread-scheduling/policy-percentage.yaml

When you update spreadConstraints in the SchedulePolicy, Nova will always re-balance the split to ensure that your requirements are met.

Let's verify if `kind-workload-1` has 2 replicas and `kind-workload-2` 8 replicas.

    $ kubectl --context=kind-workload-1 get deployment,serviceaccount
    NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
    deployment.apps/nginx   2/2     2            2           2m25s

    NAME                      SECRETS   AGE
    serviceaccount/default    1         18h
    serviceaccount/nginx-sa   1         2m25s

    $ kubectl --context=kind-workload-2 get deployment,serviceaccount
    NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
    deployment.apps/nginx   8/8     8            8           2m25s

    NAME                      SECRETS   AGE
    serviceaccount/default    1         18h
    serviceaccount/nginx-sa   1         2m25s

NOTE: For k8s resources which aren't pod controllers (pod controllers such as Deployment, ReplicaSet, StatefulSet, etc.) percentage split is ignored (resource will be created in each cluster). In our tutorial, ServiceAccount represents such resource.

**NOTE: Nova will try it's best to satisfy % split. But in cases when it's not possible to divide replicas without the remainder, Nova will floor the result of division (e.g. 5 replicas, 70%/30% split, will result in 3/1 split)**

To clean up all resources created in this tutorial, run:

    $ kubectl --context=nova delete -f sample-spread-scheduling/nginx-app.yaml
    $ kubectl --context=nova delete -f sample-spread-scheduling/policy-percentage.yaml

