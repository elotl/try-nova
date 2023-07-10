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
We will use [GCP Microservice Demo App](https://github.com/GoogleCloudPlatform/microservices-demo) which includes 10 different microservices.
Total resources requested in this app is 1570 millicores of CPU and 1368 Mi of memory.

Let's start with creating a namespace that we will use:

1. `kubectl --context=kind-workload-1 create namespace microsvc-demo`
2. `kubectl --context=kind-workload-2 create namespace microsvc-demo`
3. `kubectl --context=nova apply -f examples/sample-group-scheduling/microsvc-demo-ns.yaml`
4. `kubectl --context=nova apply -f examples/sample-group-scheduling/policy.yaml` This policy is saying, for any objects with label `microServicesDemo: "yes"`, group them based on the *value of the "color" label* and schedule a group to any cluster which has enough resources to run them.
5. Now, let's create green and blue instances of our app:
    ```shell
    kubectl --context=nova apply -f examples/sample-group-scheduling/blue-app.yaml -n microsvc-demo
    kubectl --context=nova apply -f examples/sample-group-scheduling/green-app.yaml -n microsvc-demo
    ```
6. Verifying whether the objects were assigned to the correct ScheduleGroup can be done by describing an object and looking at events:
    ```shell
    $ kubectl --context=nova describe deployment frontend -n microsvc-demo
    Name:                   frontend
    Namespace:              microsvc-demo
    CreationTimestamp:      Wed, 01 Feb 2023 15:42:31 +0100
    Labels:                 color=blue
                            microServicesDemo=yes
                            nova.elotl.co/target-cluster=kind-workload-1
    ...
    Events:
    Type    Reason                 Age   From            Message
      ----    ------                 ----  ----            -------
    Normal  AddedToScheduleGroup   17s   nova-scheduler  added to ScheduleGroup demo-policy-4f068569 which contains objects with groupBy.labelKey color=blue
    Normal  SchedulePolicyMatched  17s   nova-scheduler  schedule policy demo-policy will be used to determine target cluster

    ```
7. You can check if two ScheduleGroups were created: `kubectl --context=nova get schedulegroups`
    ```shell
    NAME                   AGE
    demo-policy-4f068569   9s
    demo-policy-f73297b2   4s
    ```
8. `novactl` CLI provides a bit more context about schedulegroups: `KUBECONFIG=./nova-installer-output/nova-kubeconfig kubectl nova get schedulegroups`
    ```shell
     NAME                 NOVA WORKLOAD CLUSTER                   NOVA POLICY NAME    
      ------------------  --------------------------------------  --------------------------------------
    
      demo-policy-4f068569  kind-workload-1                           demo-policy         
    
      demo-policy-f73297b2  kind-workload-2                           demo-policy         
      ------------------  --------------------------------------  --------------------------------------
    ```
9. From the output above, we can see which workload cluster is hosting each ScheduleGroup.
10. Now, imagine you need to increase resource request or replica count on one of the microservices in the second app. In the meantime, there was other activity in the cluster and after your update there won't be enough resources in the cluster to satisfy your update.
    You can simulate this scenario using `examples/sample-group-scheduling/hog-pod.yaml` manifest. You should edit it, so the hog-pod will take almost all resources in your cluster.
    Now, you can apply it to the same cluster where `demo-policy-f73297b2` schedule group was scheduled (`kind-workload-2` in my case). `kubectl --context=nova apply -f examples/sample-group-scheduling/hog-pod.yaml`
11. Now let's increase replica count in frontend-2 microservice (which is one of the microservices in green app) in the Nova control plane: `kubectl --context=nova scale deploy/frontend-2 --replicas=5 -n microsvc-demo`
12. If there is enough resources to satisfy new schedule group requirements (existing resource request for 9 microservices + increased replica count of `frontend-2`), watching schedule group will show you schedule group being rescheduled to another cluster: `KUBECONFIG=./nova-installer-output/nova-kubeconfig kubectl nova get schedulegroups`
    ```shell
     NAME                 NOVA WORKLOAD CLUSTER                   NOVA POLICY NAME    
      ------------------  --------------------------------------  --------------------------------------
    
      demo-policy-4f068569  kind-workload-1                           demo-policy         
    
      demo-policy-f73297b2  kind-workload-1                           demo-policy         
      ------------------  --------------------------------------  --------------------------------------
    ```
13. To understand why the ScheduleGroup was rescheduled, we can use `kubectl --context=nova describe schedulegroup <group-name>` and see the event message:
    ```shell
        Name:                demo-policy-f73297b2 
        Labels:              color=green
                             nova.elotl.co/matching-policy=demo-policy
                             nova.elotl.co/target-cluster=kind-workload-1
        API Version:         policy.elotl.co/v1alpha1
        Kind:                ScheduleGroup
        ...
        Type     Reason                                Age                  From            Message
         ----     ------                                ----                 ----            -------
        Warning  ReschedulingTriggered                 106s                 nova-agent      deployment microsvc-demo/frontend-2 does not have minimum replicas available

    ```
14. You can verify that green app is running by listing deployment in Nova Control Plane: `kubectl --context=nova get deployments -n microsvc-demo -l color=green`
    ```
    NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
    adservice-2               1/1     1            1           2m1s
    cartservice-2             1/1     1            1           2m2s
    checkoutservice-2         1/1     1            1           2m3s
    currencyservice-2         1/1     1            1           2m2s
    emailservice-2            1/1     1            1           2m3s
    frontend-2                5/5     5            5           2m3s
    loadgenerator-2           1/1     1            1           2m2s
    paymentservice-2          1/1     1            1           2m3s
    productcatalogservice-2   1/1     1            1           2m2s
    recommendationservice-2   1/1     1            1           2m3s
    redis-cart-2              1/1     1            1           2m1s
    shippingservice-2         1/1     1            1           2m2s
    ```

15. To remove all objects created for this demo, remove `microsvc-demo` namespace: `kubectl --context=nova delete ns microsvc-demo`
