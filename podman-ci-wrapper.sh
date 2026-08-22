#!/usr/bin/bash
# Every build-* job in .gitlab-ci.yml runs on the "bigboi" runner tag with no
# `needs` ordering between them, so GitLab can run several of them (generic,
# nvidia, nvidia-legacy, ...) concurrently on that one machine. All of them
# call podman rootful (via SUDOIF/PODMAN in Justfile), which by default means
# every concurrent job shares the same /var/lib/containers storage and the
# same "cache_ostree" named volume. Since nvidia/nvidia-legacy/generic builds
# derive from the same Fedora Kinoite base layers, one job's cleanup (podman
# rmi on a shared layer) can race a container another job is still using from
# that same layer, surfacing as "image is in use by a container: consider
# listing external containers and force-removing image".
#
# CI points PODMAN at this wrapper (see .gitlab-ci.yml) so every podman
# invocation for a given job is redirected to a --root/--runroot keyed on
# that job's CI_JOB_ID, giving each concurrent job fully isolated storage
# (including its own cache_ostree volume) instead of racing on shared state.
# Locally, CI_JOB_ID is never set, so this just execs the real podman
# unchanged.
set -eou pipefail

REAL_PODMAN="${REAL_PODMAN:-/usr/bin/podman}"

if [[ -z "${CI_JOB_ID:-}" ]]; then
    exec "${REAL_PODMAN}" "$@"
fi

STORAGE_BASE="/var/lib/containers-ci/${CI_JOB_ID}"
mkdir -p "${STORAGE_BASE}/storage" "${STORAGE_BASE}/runroot"

exec "${REAL_PODMAN}" --root "${STORAGE_BASE}/storage" --runroot "${STORAGE_BASE}/runroot" "$@"
