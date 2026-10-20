#!/usr/bin/bash
set -eou pipefail

TAG="${1:-latest}"
VARIANT="${2:-generic}"

if [[ "${TAG}" == "--help" || "${TAG}" == "-h" ]]; then
    echo "Usage: $0 [main|latest|prerelease] [generic|nvidia|nvidia-legacy]"
    echo ""
    echo "Arguments:"
    echo "  main|latest|prerelease           Registry tag prefix (default: latest)"
    echo "  generic|nvidia|nvidia-legacy     Hardware variant (default: generic)"
    echo ""
    echo "Always builds both base and dx images. Resulting tags:"
    echo "  latest                 registry.blossomos.org/blossom/image-dev:latest"
    echo "  latest                 registry.blossomos.org/blossom/image-dev:latest-dx"
    echo "  latest nvidia          registry.blossomos.org/blossom/image-dev:latest-nvidia"
    echo "  latest nvidia          registry.blossomos.org/blossom/image-dev:latest-nvidia-dx"
    echo "  latest nvidia-legacy   registry.blossomos.org/blossom/image-dev:latest-nvidia-legacy"
    echo "  latest nvidia-legacy   registry.blossomos.org/blossom/image-dev:latest-nvidia-legacy-dx"
    echo "  main                   registry.blossomos.org/blossom/image:main"
    echo "  main                   registry.blossomos.org/blossom/image:main-dx"
    echo "  main nvidia            registry.blossomos.org/blossom/image:main-nvidia"
    echo "  main nvidia            registry.blossomos.org/blossom/image:main-nvidia-dx"
    echo "  main nvidia-legacy     registry.blossomos.org/blossom/image:main-nvidia-legacy"
    echo "  main nvidia-legacy     registry.blossomos.org/blossom/image:main-nvidia-legacy-dx"
    echo "  prerelease             registry.blossomos.org/blossom/image:prerelease"
    echo "  prerelease             registry.blossomos.org/blossom/image:prerelease-dx"
    echo "  prerelease nvidia      registry.blossomos.org/blossom/image:prerelease-nvidia"
    echo "  prerelease nvidia      registry.blossomos.org/blossom/image:prerelease-nvidia-dx"
    echo "  prerelease nvidia-legacy registry.blossomos.org/blossom/image:prerelease-nvidia-legacy"
    echo "  prerelease nvidia-legacy registry.blossomos.org/blossom/image:prerelease-nvidia-legacy-dx"
    exit 0
fi

if [[ "${TAG}" != "main" && "${TAG}" != "latest" && "${TAG}" != "prerelease" ]]; then
    echo "Usage: $0 [main|latest|prerelease] [generic|nvidia|nvidia-legacy]"
    echo "Error: first argument must be 'main', 'latest', or 'prerelease' (got '${TAG}')"
    exit 1
fi
if [[ "${VARIANT}" != "generic" && "${VARIANT}" != "nvidia" && "${VARIANT}" != "nvidia-legacy" ]]; then
    echo "Usage: $0 [main|latest|prerelease] [generic|nvidia|nvidia-legacy]"
    echo "Error: second argument must be 'generic', 'nvidia', or 'nvidia-legacy' (got '${VARIANT}')"
    exit 1
fi

REGISTRY="${REGISTRY:-registry.blossomos.org}"
REGISTRY_ORG="${REGISTRY_ORG:-blossom}"
REGISTRY_IMAGE="${REGISTRY_IMAGE:-image}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# CI (see .gitlab-ci.yml) points this at podman-ci-wrapper.sh so this job's
# podman calls land in storage isolated from other concurrent build-* jobs
# on the runner. `just build`/`just rechunk` already honor PODMAN via the
# Justfile, so the tag/push calls below must go through it too, or they'd
# tag/push against the default (wrong) podman storage instead of the one
# the image was actually built in.
PODMAN="${PODMAN:-podman}"

# Map variant to Justfile flavor and remote tag suffix
if [[ "${VARIANT}" == "nvidia" ]]; then
    FLAVOR="nvidia-open"
    VARIANT_SUFFIX="-nvidia"
elif [[ "${VARIANT}" == "nvidia-legacy" ]]; then
    FLAVOR="nvidia-legacy"
    VARIANT_SUFFIX="-nvidia-legacy"
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

    # Digest currently sitting behind the tag, so it can be cleaned up once replaced
    OLD_DIGEST="$(skopeo inspect --format '{{.Digest}}' "docker://${REMOTE_REF}" 2>/dev/null || true)"

    echo "==> Building ${LOCAL_REF} -> ${REMOTE_REF}"
    PUBLISHED_TAG="${REMOTE_TAG}" just build "${image}" "${BUILD_TAG}" "${FLAVOR}"

    # Rechunk against the currently published REMOTE_REF so unchanged layers
    # keep the same digest and neither clients nor the registry accumulate a
    # full new image on every build.
    echo "==> Rechunking ${LOCAL_REF} against ${REMOTE_REF}"
    just rechunk "${image}" "${BUILD_TAG}" "${FLAVOR}" 0 0 "${REMOTE_REF}"
    just load-rechunk "${image}" "${BUILD_TAG}" "${FLAVOR}"

    echo "==> Tagging ${LOCAL_REF} -> ${REMOTE_REF}"
    "${PODMAN}" tag "${LOCAL_REF}" "${REMOTE_REF}"

    echo "==> Pushing ${REMOTE_REF}"
    DIGEST_FILE="$(mktemp)"
    "${PODMAN}" push --digestfile "${DIGEST_FILE}" "${REMOTE_REF}"
    DIGEST="$(cat "${DIGEST_FILE}")"
    rm -f "${DIGEST_FILE}"

    REMOTE_DIGEST_REF="${REGISTRY}/${REGISTRY_ORG}/${REGISTRY_IMAGE}@${DIGEST}"
    echo "==> Pushed digest: ${DIGEST}"

    echo "==> Signing ${REMOTE_DIGEST_REF}"
    COSIGN_PASSWORD="" cosign sign --key "${SCRIPT_DIR}/cosign.key" "${REMOTE_DIGEST_REF}"

    # cosign 3 only writes new-format bundles (OCI referrers) by default, and
    # podman/skopeo/bootc can't see those: their signature policy, which
    # installed systems enforce (see build_files/base/16-integrity.sh), only
    # looks for the classic sha256-<digest>.sig tag. Write that one as well and
    # make sure it's there, an image without it can't be updated to.
    echo "==> Signing ${REMOTE_DIGEST_REF} (containers-policy compatible)"
    COSIGN_PASSWORD="" cosign sign --new-bundle-format=false --key "${SCRIPT_DIR}/cosign.key" "${REMOTE_DIGEST_REF}"
    SIG_REF="${REGISTRY}/${REGISTRY_ORG}/${REGISTRY_IMAGE}:${DIGEST/:/-}.sig"
    if ! skopeo inspect --raw "docker://${SIG_REF}" >/dev/null; then
        echo "ERROR: ${SIG_REF} is missing after signing, installed systems would refuse this image" >&2
        exit 1
    fi

    # Reference values for remote attestation (see docs/INTEGRITY.md). The
    # predicate carries the whole /usr file manifest, a few MB, which is too
    # large for the public Rekor transparency log.
    echo "==> Attesting integrity reference values for ${REMOTE_DIGEST_REF}"
    PREDICATE_DIR="$(mktemp -d)"
    "${PODMAN}" run --rm --network=none --security-opt label=disable \
        --volume "${SCRIPT_DIR}/build_files/shared/integrity-manifest.py:/tmp/integrity-manifest.py:ro" \
        --volume "${PREDICATE_DIR}:/out" \
        --entrypoint /usr/bin/python3 \
        "${LOCAL_REF}" /tmp/integrity-manifest.py \
        --repository "${REGISTRY}/${REGISTRY_ORG}/${REGISTRY_IMAGE}" \
        --digest "${DIGEST}" --tag "${REMOTE_TAG}" --out /out/predicate.json
    COSIGN_PASSWORD="" cosign attest --yes --key "${SCRIPT_DIR}/cosign.key" \
        --type "https://blossomos.org/integrity/v1" \
        --predicate "${PREDICATE_DIR}/predicate.json" \
        --use-signing-config=false --tlog-upload=false \
        "${REMOTE_DIGEST_REF}"
    rm -rf "${PREDICATE_DIR}"

    echo "==> Done: ${REMOTE_REF} (${DIGEST})"

    # Push and sign succeeded, so the previous digest behind this tag is now
    # dangling. Remove it (and its cosign signature) to keep the registry from
    # accumulating an orphaned image on every rebuild.
    # if [[ -n "${OLD_DIGEST}" && "${OLD_DIGEST}" != "${DIGEST}" ]]; then
    #     OLD_SIG_TAG="${OLD_DIGEST/:/-}.sig"
    #     echo "==> Cleaning up superseded digest: ${OLD_DIGEST}"
    #     skopeo delete "docker://${REGISTRY}/${REGISTRY_ORG}/${REGISTRY_IMAGE}:${OLD_SIG_TAG}" 2>/dev/null || true
    #     skopeo delete "docker://${REGISTRY}/${REGISTRY_ORG}/${REGISTRY_IMAGE}@${OLD_DIGEST}" || true
    # fi
}

build_and_push "blossomos"    ""
build_and_push "blossomos-dx" "-dx"
