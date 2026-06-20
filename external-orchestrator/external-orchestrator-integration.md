# Integration with an External Orchestrator

Nova can be integrated with an external workload orchestrator that handles workload scheduling within each cluster. Nova, as a multi-cluster scheduler decides *which* workload cluster receives each workload according to a user-defined Schedule Policy. And the external orchestrator is responsible for placing workloads within the target cluster.

## How It Works

1. Nova evaluates a workload's matching `SchedulePolicy` and selects a target cluster based on available resources and policy constraints.
2. Nova records the target cluster on the workload object via the `nova.elotl.co/target-cluster` label.
3. The external orchestrator reads the `nova.elotl.co/target-cluster` label and submits the workload to the chosen cluster, adding the label `nova.elotl.co/schedule: "true"` to the workload on that cluster.
4. Nova marks the schedule status as `delegated`, indicating that placement responsibility has been delegated to the external orchestrator.
5. The Nova Agent on the workload cluster detects the `nova.elotl.co/schedule: "true"` label and begins watching the workload for status changes. Once the workload is running, its status is available in the Nova Control Plane.


## Installing the Nova Agent

When deploying Nova alongside an external orchestrator, install the Nova Agent with orchestration and rescheduling disabled using the flags shown below.

```bash
kubectl nova install agent \
  --context=<WORKLOAD_CLUSTER_CONTEXT> \
  --namespace=<NOVA_NAMESPACE> \
  --orchestration-enabled=false \
  --rescheduling-enabled=false \
  <NOVA_WORKLOAD_CLUSTER_NAME>
```

| Flag | Default | Description |
|------|---------|-------------|
| `--orchestration-enabled` | `true` | When set to `true` Nova is responsible for applying workloads on the target workload cluster. When set to false, an external orchestrator is responsible for workload placement. |
| `--rescheduling-enabled` | `true` | When set to `true` Nova is responsible for determining an alternative target cluster placement when the workload pods remain pending in the initial cluster choice. When set to false, Nova does not reschedule the workload i.e. it does not try find an alternate placement that will satisfy the matching Schedule Policy.|


## Verifying the Integration

After a workload is submitted through Nova with a matching `SchedulePolicy`, we can confirm that Nova has selected a target cluster, as follows:

```bash
kubectl --context=<NOVA_CONTROLPLANE_CONTEXT> get deployment <deployment-name> \
  -o jsonpath='{.metadata.labels.nova\.elotl\.co/target-cluster}'
```

The external orchestrator reads this label and places the workload on the chosen target cluster, with the `nova.elotl.co/schedule: "true"` label set on the workload object in that cluster.

To confirm Nova is tracking the workload and propagating status, check that the label is present on the workload:

```bash
kubectl --context=<WORKLOAD_CLUSTER_CONTEXT> get deployment <deployment-name> \
  -o jsonpath='{.metadata.labels.nova\.elotl\.co/schedule}'
```

This should return `true`. Once the workload is running, its status will be visible on the Nova Control Plane:

```bash
kubectl --context=<NOVA_CONTROLPLANE_CONTEXT> get deployment <deployment-name>
```

