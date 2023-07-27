# Annotation Based Scheduling

## Overview

Nova currently supports three ways to schedule a workload - annotation-based scheduling, policy based scheduling, and smart scheduling based on resource availability

### Annotation Based Scheduling Testing Example

In annotation-based scheduling, you specify an annotation in the workload manifest. The annotation tells Nova which workload cluster should run the workload.

1. If you used different names for your clusters, open `examples/sample-workloads/nginx.yaml` and edit annotation `nova.elotl.co/cluster: kind-workload-1` by replacing  `kind-workload-1` with name of one of your workload clusters.
2. Run `kubectl --context=nova apply -f examples/sample-workloads/nginx.yaml`
3. Run `kubectl --context=nova get deployments` should show the nginx deployment is up and running.
4. Now you should be able to see there are two pods running in your workload cluster.
5. Note that there will be no pod running in the nova control plane cluster - `kubectl --context=nova get pods` should show no pod.

### Updating/Deleting through nova

You can also modify or delete a workload through Nova and nova will automatically update the corresponding objects in the workload cluster.
Use the nginx deployment for the example:

1. Run `kubectl --context=nova edit deployment nginx`, and change the replica from 2 to 3.
2. In your workload cluster, there should be 3 nginx pods running.
3. Run `kubectl --context=nova get deployments`, and you should be able to see 3 replicas running.

Deleting a workload in nova will result in the workload deleted from the workload cluster too:
1. Run `kubectl --context=nova delete deployment nginx`.
2. You should be able to see the nginx deployment deleted both from nova control plane and your workload cluster.
