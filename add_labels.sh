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

{
	cat <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - input.yaml

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
