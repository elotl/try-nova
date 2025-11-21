#!/bin/bash

############
# Setup:
#  Context is expected to be set to the nova control plane
#  The k8s cluster name, K8s context name, and nova cluster name are expected to all match [consider dropping restriction later]

############
# Input arguments:
#  try_nova_path: path to local git clone of try-nova repo
#  schedgated.yaml, nonschedgated.yaml: nodecostestimate schedule-gated and non-schedule-gated versions of workload
#  Namespace: to use for workload policy and deployment; namespace itself should already have been spread scheduled
#  LabelKey,LabelVal: to use for workload policy, to select workload objects in namespace for group placement
# Example:
# ./cost-schedule.sh ${TRY_NOVA_PATH} ${SKYRAY_PATH}/luna-llm-serve/ray-service.llm-serve.schedgate.yaml ${SKYRAY_PATH}/luna-llm-serve/ray-service.llm-serve.noschedgate.yaml \
#  serving app.kubernetes.io/instance rayservice
export TRY_NOVA_PATH=$1
export GATED_YAML=$2
export UNGATED_YAML=$3
export WORKLOAD_NAMESPACE=$4
export WORKLOAD_LABELKEY=$5
export WORKLOAD_LABELVAL=$6

############
echo -e "\nGenerate gated workload deployment to gather cost information"
#  Deploy spread/duplicate policy for workload Namespace and LabelKey,LabelVal
envsubst < ${TRY_NOVA_PATH}/policies/spreadallpolicy.yaml | kubectl apply -f -
#  Deploy schedgated.yaml
kubectl apply -f ${GATED_YAML} -n ${WORKLOAD_NAMESPACE}
#  Delay to allow Nova spread scheduling and Luna cost estimation
sleep 30

############
# Set CLUSTER_COST to workload cost for each cluster; static->0, autoscaled+placeable->pods costs, autoscaled+unplaceable->high-cost
#  Key/Value pair with Cluster as Key and Workload Cost as Value
declare -A CLUSTER_COST
AUTOSCALED_CLUSTER_LIST=()

echo -e "\nCheck workload clusters managed by Nova to find autoscaled/non-autoscaled"
CLUSTER_LIST=$(kubectl get clusters -o jsonpath='{.items[*].spec.name}')
for CLUSTER_NAME in ${CLUSTER_LIST}; do
  if [[ $(kubectl get clusters $CLUSTER_NAME -o=jsonpath='{.status.autoscaled}') == "true" ]]; then
    echo "$CLUSTER_NAME is autoscaled"
    AUTOSCALED_CLUSTER_LIST+=($CLUSTER_NAME)
  else
    echo "$CLUSTER_NAME is not autoscaled"
    CLUSTER_COST[$CLUSTER_NAME]=0
  fi
done

echo -e "\nAutoscaled cluster list"
printf '%s\n' "${AUTOSCALED_CLUSTER_LIST[@]}"

#  For each autoscaled cluster, get nodecostestimate info for schedulegated pods in specified namespace (match labelkey/val also?)
HIGH_COST=65535
for CONTEXT_NAME in ${AUTOSCALED_CLUSTER_LIST[@]}; do
  totalcost=0
  COST_LIST=()
  echo " "
  POD_LIST=$(kubectl get pods -n ${WORKLOAD_NAMESPACE} --context ${CONTEXT_NAME} \
    -o jsonpath='{range .items[?(@.spec.schedulingGates[0].name == "nodecostestimate")]}{.metadata.name}{"\n"}{end}')
  for POD_NAME in $POD_LIST; do
    cost=$(kubectl get events -n ${WORKLOAD_NAMESPACE} --context ${CONTEXT_NAME} \
      --field-selector involvedObject.name="$POD_NAME",reason=NodeCostEstimate -o jsonpath='{range .items[*]}{.message}{"\n"}{end}')
    echo ${cost}
    if [[ "$cost" == "No node type found"* ]]; then
      totalcost=${HIGH_COST}
      break
    fi
    if [[ "$cost" == "Estimated cost $"* ]]; then
      COST_LIST+=("$cost")
    else
      echo "no nodecostestimate event found"
      totalcost=${HIGH_COST}
      break
    fi
  done
  if [[ $totalcost == 0 ]]; then
     readarray -td '' COST_LIST_SORTED < <(printf '%s\0' "${COST_LIST[@]}" | sort -z)
     readarray COST_LIST_SORTED_UNIQ < <(printf '%s\n' "${COST_LIST_SORTED[@]}" | uniq)
     for cost in "${COST_LIST_SORTED_UNIQ[@]}"; do
       costcut=$(echo $cost | cut -c 17-24)
       costcnt=$(echo "$cost" | awk -F'; ' '/estimated node count/ {print $2}' | cut -d' ' -f4)
       echo "$costcut x $costcnt"
       totalcost=$(python -c "print($totalcost + ($costcut * $costcnt))")
     done
  fi
  echo $CONTEXT_NAME $totalcost
  CLUSTER_COST[$CONTEXT_NAME]=$totalcost
done

echo -e "\nClean up gated workload deployment used to gather cost information, delay for completion"
kubectl delete -f ${GATED_YAML} -n ${WORKLOAD_NAMESPACE}
kubectl delete schedulepolicy spread-all-policy-${WORKLOAD_NAMESPACE}
sleep 30

SORTED_CLUSTER_LIST_RAW=$(for CLUSTER in "${!CLUSTER_COST[@]}"; do
  echo "$CLUSTER ${CLUSTER_COST[$CLUSTER]}"
done | sort -n -k2 | cut -d ' ' -f 1)
echo -e "\nSorted cluster list (raw)"
printf '%s\n' "${SORTED_CLUSTER_LIST_RAW[@]}"

SORTED_CLUSTER_LIST_STR=$(echo ${SORTED_CLUSTER_LIST_RAW})
export SORTED_CLUSTER_LIST=$(echo ${SORTED_CLUSTER_LIST_STR} | tr ' ' ',')
echo -e "\nSorted cluster list (comma separated)"
echo $SORTED_CLUSTER_LIST

echo -e "\nGenerate ungated workload deployment based on cost information"
#  Deploy priority policy for workload Namespace and LabelKey,LabelVal
envsubst < ${TRY_NOVA_PATH}/policies/clusterprioritypolicy.yaml | kubectl apply -f -
#  Deploy not schedgated.yaml
kubectl apply -f ${UNGATED_YAML} -n ${WORKLOAD_NAMESPACE}
