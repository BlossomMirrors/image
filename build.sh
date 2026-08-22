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
    echo "  latest                 registry.blossomos.org/blossom/image:latest"
    echo "  latest                 registry.blossomos.org/blossom/image:latest-dx"
    echo "  latest nvidia          registry.blossomos.org/blossom/image:latest-nvidia"
    echo "  latest nvidia          registry.blossomos.org/blossom/image:latest-nvidia-dx"
    echo "  latest nvidia-legacy   registry.blossomos.org/blossom/image:latest-nvidia-legacy"
    echo "  latest nvidia-legacy   registry.blossomos.org/blossom/image:latest-nvidia-legacy-dx"
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

# Refresh plasma-rpms/ to match image-versions.yml's plasma_version, so the
# build always uses the declared pin rather than whatever's left over from a
# previous run (or nothing, on a fresh checkout - plasma-rpms/ isn't committed).
# Skipped if a matching snapshot is already in place, and skipped entirely if
# plasma_version is empty/unset (track Fedora's live Plasma packages).
#
# Deliberately skipped when running as root: build.sh runs under `sudo` in CI
# (see .gitlab-ci.yml, where this same sync runs as a non-sudo before_script
# step instead), and fetch-plasma-rpms's podman calls don't need root. Doing
# it here too under sudo would leave plasma-rpms/*.rpm genuinely root-owned,
# which the *next* pipeline's git checkout (running as the unprivileged
# runner user) can't clean up - and since that checkout happens before any
# script of ours runs, nothing we write here could ever fix it after the
# fact. Learned this the hard way: see commit 828fbd7.
if [[ "${EUID}" -eq 0 ]]; then
    echo "==> Running as root (sudo) - skipping plasma-rpms sync here; it must be synced by a non-root step beforehand (CI's before_script, or run 'just fetch-plasma-rpms' yourself first)."
else
    PLASMA_VERSION="$(yq -r '.plasma_version // ""' "${SCRIPT_DIR}/image-versions.yml")"
    if [[ -n "${PLASMA_VERSION}" && "${PLASMA_VERSION}" != "null" ]]; then
        CURRENT_PINNED="$(awk -F= '/^resolved-plasma-version=/{print $2}' "${SCRIPT_DIR}/plasma-rpms/MANIFEST.txt" 2>/dev/null || true)"
        if [[ "${CURRENT_PINNED}" != "${PLASMA_VERSION}" ]]; then
            echo "==> Freezing Plasma to ${PLASMA_VERSION} (image-versions.yml)"
            just fetch-plasma-rpms "${PLASMA_VERSION}"
        fi
    fi
fi

build_and_push "blossomos"    ""
build_and_push "blossomos-dx" "-dx"
