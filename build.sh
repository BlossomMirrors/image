#!/usr/bin/bash
set -eou pipefail

TAG="${1:-latest}"
VARIANT="${2:-generic}"

if [[ "${TAG}" == "--help" || "${TAG}" == "-h" ]]; then
    echo "Usage: $0 [main|latest] [generic|nvidia]"
    echo ""
    echo "Arguments:"
    echo "  main|latest   Registry tag prefix (default: latest)"
    echo "  generic|nvidia  Hardware variant (default: generic)"
    echo ""
    echo "Always builds both base and dx images. Resulting tags:"
    echo "  latest          registry.blossomos.org/blossom/image:latest"
    echo "  latest          registry.blossomos.org/blossom/image:latest-dx"
    echo "  latest nvidia   registry.blossomos.org/blossom/image:latest-nvidia"
    echo "  latest nvidia   registry.blossomos.org/blossom/image:latest-nvidia-dx"
    echo "  main            registry.blossomos.org/blossom/image:main"
    echo "  main            registry.blossomos.org/blossom/image:main-dx"
    echo "  main nvidia     registry.blossomos.org/blossom/image:main-nvidia"
    echo "  main nvidia     registry.blossomos.org/blossom/image:main-nvidia-dx"
    exit 0
fi

if [[ "${TAG}" != "main" && "${TAG}" != "latest" ]]; then
    echo "Usage: $0 [main|latest] [generic|nvidia]"
    echo "Error: first argument must be 'main' or 'latest' (got '${TAG}')"
    exit 1
fi
if [[ "${VARIANT}" != "generic" && "${VARIANT}" != "nvidia" ]]; then
    echo "Usage: $0 [main|latest] [generic|nvidia]"
    echo "Error: second argument must be 'generic' or 'nvidia' (got '${VARIANT}')"
    exit 1
fi

REGISTRY="${REGISTRY:-registry.blossomos.org}"
REGISTRY_ORG="${REGISTRY_ORG:-blossom}"
REGISTRY_IMAGE="${REGISTRY_IMAGE:-image}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Map variant to Justfile flavor and remote tag suffix
if [[ "${VARIANT}" == "nvidia" ]]; then
    FLAVOR="nvidia-open"
    VARIANT_SUFFIX="-nvidia"
else
    FLAVOR="main"
    VARIANT_SUFFIX=""
fi

# Justfile build tag (Fedora stream selection)
BUILD_TAG="latest"

build_and_push() {
    local image="$1"
    local dx_suffix="$2"

    # Derive local image name matching Justfile image_name logic
    if [[ "${FLAVOR}" == "main" ]]; then
        local_name="${image}"
    else
        local_name="${image}-${FLAVOR}"
    fi

    LOCAL_REF="localhost/${local_name}:${BUILD_TAG}"
    REMOTE_TAG="${TAG}${VARIANT_SUFFIX}${dx_suffix}"
    REMOTE_REF="${REGISTRY}/${REGISTRY_ORG}/${REGISTRY_IMAGE}:${REMOTE_TAG}"

    echo "==> Building ${LOCAL_REF} -> ${REMOTE_REF}"
    just build "${image}" "${BUILD_TAG}" "${FLAVOR}"

    echo "==> Tagging ${LOCAL_REF} -> ${REMOTE_REF}"
    podman tag "${LOCAL_REF}" "${REMOTE_REF}"

    echo "==> Pushing ${REMOTE_REF}"
    DIGEST_FILE="$(mktemp)"
    podman push --digestfile "${DIGEST_FILE}" "${REMOTE_REF}"
    DIGEST="$(cat "${DIGEST_FILE}")"
    rm -f "${DIGEST_FILE}"

    REMOTE_DIGEST_REF="${REGISTRY}/${REGISTRY_ORG}/${REGISTRY_IMAGE}@${DIGEST}"
    echo "==> Pushed digest: ${DIGEST}"

    echo "==> Signing ${REMOTE_DIGEST_REF}"
    COSIGN_PASSWORD="" cosign sign --key "${SCRIPT_DIR}/cosign.key" "${REMOTE_DIGEST_REF}"

    echo "==> Done: ${REMOTE_REF} (${DIGEST})"
}

build_and_push "blossomos"    ""
build_and_push "blossomos-dx" "-dx"
