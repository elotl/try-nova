#!/usr/bin/env bash
#
# Create example Nova policies with sensible defaults. It creates 3 policies:
#
# 1. `system_policy.yaml` for system and configuration objects that will be duplicated across all clusters
# 2. TODO
# 3. TODO
#
# Requires kubectl >= 1.24
#

set -euo pipefail

# Argument is exit code
usage() {
	cat >&2 <<'EOF'
Create sample policies for Nova.

Usage:
  sample_policies.sh -l key=value [-l key=value ...]
EOF
	exit $1
}

labels=()

while [[ $# -gt 0 ]]; do
	case "$1" in
	-l | --label)
		[[ $# -ge 2 ]] || usage 2
		labels+=("$2")
		shift 2
		;;
	-h | --help)
		usage 0
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

# The system policy duplicates all the objects accross all clusters.
{
	cat <<EOF
apiVersion: policy.elotl.co/v1alpha1
kind: SchedulePolicy
metadata:
  name: system
spec:
  spreadConstraints:
    spreadMode: Duplicate
    topologyKey: kubernetes.io/metadata.name
  namespaceSelector:
    matchLabels:
EOF
	print_labels 6
	cat <<EOF
  resourceSelectors:
    labelSelectors:
      - matchLabels:
EOF
	print_labels 8
	cat <<EOF
    kinds:
      - kind: Namespace
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

EOF
} >system_policy.yaml
