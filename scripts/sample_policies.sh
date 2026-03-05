#!/usr/bin/env bash
#
# Create example Nova policies with sensible defaults.
#
# Use it like this:
#
#   sample_policies.sh -l nova=duplicate duplicate nova | kubectl --context nova apply -f -
#
# Requires kubectl >= 1.24
#

set -euo pipefail

# Argument is exit code
usage() {
	cat >&2 <<'EOF'
Create sample policies for Nova.

Usage:
  sample_policies.sh -l key=value [-l key=value ...] [-p policy-prefix] <command>

Commands:
  duplicate <group-by-key>

EOF
	exit $1
}

labels=()
prefix=''
command=''
labelKey=''

while [[ $# -gt 0 ]]; do
	case "$1" in
	-l | --label)
		[[ $# -ge 2 ]] || usage 2
		labels+=("$2")
		shift 2
		;;
	-p | --prefix)
		if [[ -z "$2" ]]; then
			echo "Missing value for --prefix" >&2
			usage 2
		fi
		prefix=$2
		shift 2
		;;
	-h | --help)
		usage 0
		;;
	duplicate)
		if [[ -z "$2" ]]; then
			echo "Missing group by label key for duplicate command" >&2
			usage 2
		fi
		command=duplicate
		labelKey=$2
		shift 2
		;;
	*)
		echo "Unknown arg: $1" >&2
		usage 2
		;;
	esac
done

if [[ ${#labels[@]} -eq 0 ]]; then
	echo "At least one -l/--label key=value is required" >&2
	usage 2
fi

yaml_squote() {
	# single-quote YAML scalar, doubling internal single quotes
	local s="${1//\'/\'\'}"
	printf "'%s'" "$s"
}

# Usage: print_labels <indent in spaces>
print_labels() {
	local indent=$1
	for kv in "${labels[@]}"; do
		[[ "$kv" == *"="* ]] || {
			echo "Invalid label (expected key=value): $kv" >&2
			exit 2
		}
		key="${kv%%=*}"
		val="${kv#*=}"
		[[ -n "$key" ]] || {
			echo "Invalid label key in: $kv" >&2
			exit 2
		}
		printf "%*s%s: %s\n" "$indent" ' ' "$(yaml_squote "$key")" "$(yaml_squote "$val")"
	done
}

schedule_policy() {
	local name=$1
	shift
	local spreadconstraints=$1
	shift
	local objects=$1
	shift

	cat <<EOF
apiVersion: policy.elotl.co/v1alpha1
kind: SchedulePolicy
metadata:
  name: ${name}
spec:
${spreadconstraints}
  namespaceSelector:
    matchLabels:
EOF
	print_labels 6
	cat <<EOF
  resourceSelectors:
    labelSelectors:
      - matchLabels:
EOF
	print_labels 10
	printf '    kinds:\n%s' "$objects"
	# Extra
	printf '%s' "$@"
}

readonly system_objects='      - kind: Namespace
        version: v1
        group: core
      - kind: IngressClass
        version: v1
        group: networking.k8s.io
      - kind: PriorityClass
        version: v1
        group: scheduling.k8s.io
      - kind: ClusterRoleBinding
        version: v1
        group: rbac.authorization.k8s.io
      - kind: ClusterRole
        version: v1
        group: rbac.authorization.k8s.io
      - kind: MutatingWebhookConfiguration
        version: v1
        group: admissionregistration.k8s.io
      - kind: ValidatingWebhookConfiguration
        version: v1
        group: admissionregistration.k8s.io
      - kind: CustomResourceDefinition
        version: v1
        group: apiextensions.k8s.io
'

readonly namespaced_objects='      - kind: ConfigMap
        version: v1
        group: core
      - kind: Secret
        version: v1
        group: core
      - kind: ServiceAccount
        version: v1
        group: core
      - kind: Ingress
        version: v1
        group: networking.k8s.io
      - kind: NetworkPolicy
        version: v1
        group: networking.k8s.io
      - kind: RoleBinding
        version: v1
        group: rbac.authorization.k8s.io
      - kind: Role
        version: v1
        group: rbac.authorization.k8s.io
      - kind: HorizontalPodAutoscaler
        version: v2
        group: autoscaling
'

readonly allocated_objects='     - kind: Pod
       version: v1
       group: core
     - kind: Deployment
       version: v1
       group: apps
     - kind: StatefulSet
       version: v1
       group: apps
     - kind: DaemonSet
       version: v1
       group: apps
     - kind: Job
       version: v1
       group: batch
     - kind: CronJob
       version: v1
       group: batch
     - kind: ReplicaSet
       version: v1
       group: apps
     - kind: PersistentVolumeClaim
       version: v1
       group: core
     - kind: Service
       version: v1
       group: core
'

readonly spread_constraints_duplicate="  groupBy:
    labelKey: ${labelKey}
  spreadConstraints:
    spreadMode: Duplicate
    topologyKey: kubernetes.io/metadata.name"

case "$command" in
duplicate)
	schedule_policy "${prefix}system" "$spread_constraints_duplicate" "$system_objects"
	echo '---'
	schedule_policy "${prefix}namespaced" "$spread_constraints_duplicate" "$namespaced_objects"
	echo '---'
	schedule_policy "${prefix}allocated" "$spread_constraints_duplicate" "$allocated_objects"
	;;
*)
	echo 'No command specified' >&2
	usage 2
	;;
esac
