#!/usr/bin/bash

set -eoux pipefail

if [[ -n "${FEDORA_MAJOR_VERSION:-}" ]]; then
    sed -i "s|^VERSION_ID=.*|VERSION_ID=${FEDORA_MAJOR_VERSION}|" /usr/lib/os-release
    sed -i "s|^VERSION_ID=.*|VERSION_ID=${FEDORA_MAJOR_VERSION}|" /etc/os-release || true
fi

echo "::group:: Copy Files"

# Speeds up local builds
dnf config-manager setopt keepcache=1

# We need to remove this package here because files we add from system_files override the rpm files
# they go away when you do dnf remove
# Keep *-logos in RPM DB for downstream package installations
# We are not allowed to ship an empty fedora-logos package
dnf -y swap fedora-logos generic-logos
rpm --erase --nodeps --nodb generic-logos

# Copy Files to Container
rsync -rvKl /ctx/system_files/shared/ /

if [[ "${IMAGE_FLAVOR}" == "dx" ]]; then
  /ctx/build_files/shared/build-dx.sh
fi

echo "::endgroup::"
