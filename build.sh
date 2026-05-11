#!/usr/bin/bash
set -eou pipefail

IMAGE="${1:-blossomos}"
TAG="${2:-latest}"
FLAVOR="${3:-main}"

REGISTRY="${REGISTRY:-git.blossomos.org}"
REGISTRY_ORG="${REGISTRY_ORG:-blossom}"
REGISTRY_IMAGE="${REGISTRY_IMAGE:-image}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Derive local image name the same way the Justfile does
if [[ "${FLAVOR}" == "main" ]]; then
    IMAGE_NAME="${IMAGE}"
else
    IMAGE_NAME="${IMAGE}-${FLAVOR}"
fi

LOCAL_REF="localhost/${IMAGE_NAME}:${TAG}"
REMOTE_REF="${REGISTRY}/${REGISTRY_ORG}/${REGISTRY_IMAGE}:${TAG}"

echo "==> Building ${LOCAL_REF}"
just build "${IMAGE}" "${TAG}" "${FLAVOR}"

echo "==> Tagging ${LOCAL_REF} -> ${REMOTE_REF}"
podman tag "${LOCAL_REF}" "${REMOTE_REF}"

echo "==> Pushing ${REMOTE_REF}"
DIGEST_FILE="$(mktemp)"
podman push --digestfile "${DIGEST_FILE}" "${REMOTE_REF}"
DIGEST="$(cat "${DIGEST_FILE}")"
rm -f "${DIGEST_FILE}"

REMOTE_DIGEST_REF="${REGISTRY}/${REGISTRY_ORG}/${IMAGE_NAME}@${DIGEST}"
echo "==> Pushed digest: ${DIGEST}"

echo "==> Signing ${REMOTE_DIGEST_REF}"
COSIGN_PASSWORD="" cosign sign --key "${SCRIPT_DIR}/cosign.key" "${REMOTE_DIGEST_REF}"

echo "==> Done: ${REMOTE_REF} (${DIGEST})"
