#!/usr/bin/env bash
#
# Requires kubectl >= 1.24
#

set -euo pipefail

# Argument is exit code
usage() {
	cat >&2 <<'EOF'
Usage:
  add_labels.sh -l key=value [-l key=value ...]
    [--include none|templates|selectors]

Example:
  heml upgrade --install ... \
    --post-renderer add_label.sh \
    --post-renderer-args "-l foo=bar -l team=platform"
EOF
	exit $1
}

# Add labels to everything by default:
# https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/labels/
include=selectors
labels=()

while [[ $# -gt 0 ]]; do
	case "$1" in
	-l | --label)
		[[ $# -ge 2 ]] || usage 2
		labels+=("$2")
		shift 2
		;;
	--include)
		if [[ -z "$2" ]]; then
			echo "Missing value for --include" >&2
			usage 2
		fi
		case "$2" in
		none | selectors | templates)
			include="$2"
			;;
		*)
			echo "Invalid value for --include." >&2
			echo "  Expecting selectors or templates, got: $2" >&2
			usage 2
			;;
		esac
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

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat >"${tmp}/input.yaml"

yaml_squote() {
	# single-quote YAML scalar, doubling internal single quotes
	local s="${1//\'/\'\'}"
	printf "'%s'" "$s"
}

patch_object_type() {
	local value=$1
	local kind=$2
	local group=$3
	local version=$4
	cat <<EOF
  - patch: |-
      - op: add
        path: /metadata/labels
        value: {}
      - op: add
        path: /metadata/labels/nova.elotl.co~1type
        value: ${value}
    target:
      group: ${group}
      version: ${version}
      kind: ${kind}
EOF
}

patch_object_type_system() {
	patch_object_type system "$1" "$2" "$3"
}

patch_object_type_namespaced() {
	patch_object_type namespaced "$1" "$2" "$3"
}

patch_object_type_allocated() {
	patch_object_type allocated "$1" "$2" "$3"
}

{
	cat <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - input.yaml

patches:
EOF

	patch_object_type_system Namespace '' v1
	patch_object_type_system Namespace 'core' v1
	patch_object_type_system IngressClass 'networking.k8s.io' v1
	patch_object_type_system PriorityClass 'scheduling.k8s.io' v1
	patch_object_type_system ClusterRoleBinding 'rbac.authorization.k8s.io' v1
	patch_object_type_system ClusterRole 'rbac.authorization.k8s.io' v1
	patch_object_type_system MutatingWebhookConfiguration 'admissionregistration.k8s.io' v1
	patch_object_type_system ValidatingWebhookConfiguration 'admissionregistration.k8s.io' v1
	patch_object_type_system CustomResourceDefinition 'apiextensions.k8s.io' v1

	patch_object_type_namespaced ConfigMap '' v1
	patch_object_type_namespaced ConfigMap 'core' v1
	patch_object_type_namespaced Secret '' v1
	patch_object_type_namespaced Secret 'core' v1
	patch_object_type_namespaced ServiceAccount '' v1
	patch_object_type_namespaced ServiceAccount 'core' v1
	patch_object_type_namespaced Ingress 'networking.k8s.io' v1
	patch_object_type_namespaced NetworkPolicy 'networking.k8s.io' v1
	patch_object_type_namespaced Role 'rbac.authorization.k8s.io' v1
	patch_object_type_namespaced RoleBinding 'rbac.authorization.k8s.io' v1
	patch_object_type_namespaced HorizontalPodAutoscaler 'autoscaling' v2

	patch_object_type_allocated Pod '' v1
	patch_object_type_allocated Pod 'core' v1
	patch_object_type_allocated Deployment 'apps' v1
	patch_object_type_allocated StatefulSet 'apps' v1
	patch_object_type_allocated DaemonSet 'apps' v1
	patch_object_type_allocated ReplicaSet 'apps' v1
	patch_object_type_allocated Job 'batch' v1
	patch_object_type_allocated CronJob 'batch' v1
	patch_object_type_allocated PersistentVolumeClaim '' v1
	patch_object_type_allocated PersistentVolumeClaim 'core' v1
	patch_object_type_allocated Service '' v1
	patch_object_type_allocated Service 'core' v1

	cat <<EOF
labels:
  - pairs:
EOF

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
		printf "      %s: %s\n" "$(yaml_squote "$key")" "$(yaml_squote "$val")"
	done

	case "$include" in
	none) ;;
	selectors)
		echo "    includeSelectors: true"
		;;
	templates)
		echo "    includeTemplates: true"
		;;
	esac
} >"${tmp}/kustomization.yaml"

exec kubectl kustomize "$tmp"
