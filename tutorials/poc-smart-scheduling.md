# Smart Scheduling

## Overview

Nova currently supports two ways to schedule a workload - annotation-based scheduling, policy based scheduling (either explicitly to the defined cluster, or smart scheduling based on resource availability).

### Group Scheduling Based on Resource Availability Testing Example

Nova also supports smart group scheduling, which means scheduling a group of k8s objects to any cluster which has enough resources to host it.
In this exercise we will observe how Nova groups k8s objects into a ScheduleGroup and finds a workload cluster for a whole group.
Let's say you have a group of microservices, which combine into an application.
We will try to create two versions of the same application: microservices labeled `color: blue` and the same set of microservices labeled `color: green`.
By adding `.groupBy.labelKey` to the SchedulePolicy spec, Nova will create two ScheduleGroups: one with all objects with `color: blue` and another one with `color: green` label.
```yaml
apiVersion: policy.elotl.co/v1alpha1
kind: SchedulePolicy
metadata:
  ...
spec:
  groupBy:
    labelKey: color
  ...
```
Each group will be considered separately by Nova, and it is guaranteed that all objects in the group will run in the same workload cluster.
In this tutorial, we will let Nova figure out which workload cluster has enough resources to host each group. This can be done by not setting `.spec.clusterSelector`.


Let's start with creating a namespace that we will use:

1. `kubectl --context=nova apply -f examples/sample-group-scheduling/nginx-group-demo-ns.yaml`
2. `kubectl --context=nova apply -f examples/sample-group-scheduling/policy.yaml` This policy is saying, for any objects with label `nginxGroupScheduleDemo: "yes"`, group them based on the *value of the "color" label* and schedule a group to any cluster which has enough resources to run them.
3. Now, let's create green and blue instances of our app:
    ```shell
    kubectl --context=nova apply -f examples/sample-group-scheduling/blue-app.yaml -n nginx-group-demo
    kubectl --context=nova apply -f examples/sample-group-scheduling/green-app.yaml -n nginx-group-demo
    ```
4. Verifying whether the objects were assigned to the correct ScheduleGroup can be done by describing an object and looking at events:
    ```shell
    $ kubectl --context=nova describe deployment blue-nginx-deployment -n nginx-group-demo
    Name:                   blue-nginx-deployment
    Namespace:              nginx-group-demo
    CreationTimestamp:      Fri, 11 Aug 2023 14:19:57 -0500
    Labels:                 app.kubernetes.io/instance=blue
                            app.kubernetes.io/managed-by=kubernetes
                            app.kubernetes.io/name=nginx
                            app.kubernetes.io/part-of=blue
                            app.kubernetes.io/version=1.7.9
                            color=blue
                            nginxGroupScheduleDemo=yes
                            nova.elotl.co/target-cluster=kind-workload-2
    Selector:               app=nginx,color=blue
    Events:
    Type    Reason                 Age    From            Message
    ----    ------                 ----   ----            -------
    Normal  AddedToScheduleGroup   2m29s  nova-scheduler  added to ScheduleGroup demo-policy-69894944 which contains objects with groupBy.labelKey color=blue
    Normal  SchedulePolicyMatched  2m29s  nova-scheduler  schedule policy demo-policy will be used to determine target cluster
a

    ```
5. You can check if two ScheduleGroups were created: `kubectl --context=nova get schedulegroups`                               `
    ```shell
      NAME                   AGE
      demo-policy-1be06c9f   9m17s
      demo-policy-69894944   6m15s
    ```
6. `novactl` CLI provides a bit more context about schedulegroups: `kubectl nova get schedulegroups`
    ```shell
      NAME                 NOVA WORKLOAD CLUSTER                   NOVA POLICY NAME
    ------------------  --------------------------------------  --------------------------------------

    demo-policy-1be06c9f  kind-workload-2                           demo-policy

    demo-policy-69894944  kind-workload-2                           demo-policy
    ------------------  --------------------------------------  --------------------------------------
    ```
7. From the output above, we can see which workload cluster is hosting each ScheduleGroup.
8. Now, imagine you need to increase resource request or replica count on one of the microservices in the second app. In the meantime, there was other activity in the cluster and after your update there won't be enough resources in the cluster to satisfy your update.
   You can simulate this scenario using `examples/sample-group-scheduling/hog-pod.yaml` manifest. You should edit it, so the hog-pod will take almost all resources in your cluster.
   Now, you can apply it to the same cluster where `demo-policy-69894944` schedule group was scheduled (`kind-workload-2` in my case). `kubectl --context=nova apply -f examples/sample-group-scheduling/hog-pod.yaml`
9. Now let's increase replica count in green-app in the Nova control plane: `kubectl --context=nova scale deploy/green-nginx-deployment --replicas=3 -n nginx-group-demo`
10. If there is enough resources to satisfy new schedule group requirements (existing resource request for 2 nginx + increased replica count of `green deploymetn`), watching schedule group will show you schedule group being rescheduled to another cluster: `kubectl nova get schedulegroups`
    ```shell
      NAME                 NOVA WORKLOAD CLUSTER                   NOVA POLICY NAME
  ------------------  --------------------------------------  --------------------------------------

  demo-policy-1be06c9f  kind-workload-1                           demo-policy

  demo-policy-69894944  kind-workload-2                           demo-policy
  ------------------  --------------------------------------  --------------------------------------
    ```
11. To understand why the ScheduleGroup was rescheduled, we can use `kubectl --context=nova describe schedulegroup <group-name>` and see the event message:
    ```shell
        Name:                demo-policy-1be06c9f
        Namespace:
        Labels:             color=green
                            nova.elotl.co/matching-policy=demo-policy
                            nova.elotl.co/target-cluster=kind-workload-1
        Annotations:         <none>
        API Version:         policy.elotl.co/v1alpha1
        Kind:                ScheduleGroup
        ...
        Events:
        Type     Reason                                Age                  From            Message
        ----     ------                                ----                 ----            -------
        Normal   ScheduleGroupSyncedToWorkloadCluster  22m (x5 over 122m)   nova-scheduler  Multiple clusters matching policy demo-policy (empty cluster selector): kind-workload-2,kind-workload-1; Picked cluster kind-workload-2 because it has enough resources;
        Warning  ReschedulingTriggered                 3m12s (x4 over 68m)  nova-agent      deployment nginx-group-demo/green-nginx-deployment does not have minimum replicas available
        Normal   ScheduleGroupSyncedToWorkloadCluster  108s                 nova-scheduler  Multiple clusters matching policy demo-policy (empty cluster selector): kind-workload-2,kind-workload-1; Cluster kind-workload-2 skipped, does not have enough resources; Picked cluster kind-workload-1 because it has enough resources;

    ```
12. You can verify that green app is running by listing deployment in Nova Control Plane: `kubectl --context=nova get deployments -n nginx-group-demo -l color=green`
    ```
    NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
    green-nginx-deployment   3/3     3            3           24m
    
    ```

13. To remove all objects created for this demo, remove `nginx-group-demo` namespace: `kubectl --context=nova delete ns nginx-group-demo`
