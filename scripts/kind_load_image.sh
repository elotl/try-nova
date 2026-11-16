#!/usr/bin/env bash
#
# Usage: kind_load_image.sh <kind-cluster-name> <image> [<image>...]
#
# Loads local docker images into a kind cluster.
#
# With Docker 29+ (containerd image store enabled by default), `kind load docker-image`
# fails for multi-platform images whose content is only partially present locally:
#
#   ctr: content digest sha256:...: not found
#
# because kind imports with `ctr images import --all-platforms`. When that happens we
# fall back to saving only the host platform (`docker save --platform`) and loading
# the resulting archive with `kind load image-archive`.

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "usage: $0 <kind-cluster-name> <image> [<image>...]" >&2
    exit 1
fi

cluster="$1"
shift

archive=""
cleanup() {
    if [[ -n "$archive" ]]; then
        rm -f "$archive"
    fi
}
trap cleanup EXIT

for image in "$@"; do
    if kind load docker-image --name "$cluster" "$image"; then
        continue
    fi

    platform="linux/$(docker version --format '{{.Server.Arch}}')"
    echo "--- kind load docker-image failed for $image on $cluster; retrying with $platform-only image archive" >&2
    archive=$(mktemp "${TMPDIR:-/tmp}/kind-load-image.XXXXXX")
    docker save --platform "$platform" -o "$archive" "$image"
    kind load image-archive --name "$cluster" "$archive"
    rm -f "$archive"
    archive=""
done
