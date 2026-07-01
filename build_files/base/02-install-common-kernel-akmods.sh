#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

#shellcheck source=build_files/shared/blossom-repo.sh
source /ctx/build_files/shared/blossom-repo.sh

# BlossomOS kernel build
# Derived from the KERNEL build-arg (akmods flavor's ostree.linux label) so
# akmods (v4l2loopback, xone, openrazer, nvidia-open, zfs) below stay
# ABI-compatible. repo.blossomos.org must publish a matching kernel build.
KERNEL_VERSION="${KERNEL%.*}"

blossom_repo_setup

# Remove Existing Kernel
for pkg in kernel kernel{-core,-modules,-modules-core,-modules-extra,-tools-libs,-tools}; do
    rpm --erase "${pkg}" --nodeps
done

# cleanup leftovers that are not covered by kernel-* packages for some reason
rm -rf /usr/lib/modules

# Install Kernel (pinned build from repo.blossomos.org, not Fedora's stock build)
#
# The patched kernel keeps Fedora's exact NVR, so an ordinary
# `dnf5 install --enablerepo=...` can't be trusted to pick the blossomos
# copy over an identically-versioned one in the base Fedora repos. Download
# the RPMs from the blossom repo explicitly and install the local files, so
# there is no repo resolution to get wrong.
KERNEL_PKGS=(
    "kernel-${KERNEL_VERSION}"
    "kernel-core-${KERNEL_VERSION}"
    "kernel-modules-${KERNEL_VERSION}"
    "kernel-modules-core-${KERNEL_VERSION}"
    "kernel-modules-extra-${KERNEL_VERSION}"
)
if [[ "${IMAGE_FLAVOR}" == "dx" ]]; then
    KERNEL_PKGS+=(
        "kernel-devel-${KERNEL_VERSION}"
        "kernel-devel-matched-${KERNEL_VERSION}"
    )
fi

mkdir -p /tmp/blossom-kernel
dnf5 download --destdir=/tmp/blossom-kernel --disablerepo='*' --enablerepo="${BLOSSOM_REPO_ID}" "${KERNEL_PKGS[@]}"
rpm -ivh /tmp/blossom-kernel/*.rpm
rm -rf /tmp/blossom-kernel

dnf5 versionlock add kernel kernel-devel kernel-devel-matched kernel-core kernel-modules kernel-modules-core kernel-modules-extra

dnf -y install /tmp/rpms/{common,kmods}/*xone*.rpm /tmp/rpms/{common,kmods}/*openrazer*.rpm || true

dnf -y install /tmp/rpms/{kmods,common}/*v4l2loopback*.rpm || true

mkdir -p /etc/pki/akmods/certs
curl "https://github.com/ublue-os/akmods/raw/refs/heads/main/certs/public_key.der" --retry 3 -Lo /etc/pki/akmods/certs/akmods-ublue.der

# OpenRazer from hardware:razer repo (not a COPR)
dnf -y config-manager addrepo --from-repofile=https://openrazer.github.io/hardware:razer.repo
dnf -y install openrazer-daemon || true
sed -i 's@enabled=1@enabled=0@g' /etc/yum.repos.d/hardware:razer.repo

echo "::endgroup::"
