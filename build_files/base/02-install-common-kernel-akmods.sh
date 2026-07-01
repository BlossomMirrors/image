#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

#shellcheck source=build_files/shared/blossom-repo.sh
source /ctx/build_files/shared/blossom-repo.sh

# BlossomOS kernel build
# Not derived from the KERNEL build-arg. KERNEL picks the closest matching
# ublue-os akmods image, whose ostree.linux label carries a fc44 dist tag,
# but repo.blossomos.org's kernel package NVR does not carry one. Bump this
# by hand whenever a new kernel build is published to repo.blossomos.org.
BLOSSOM_KERNEL_VERSION="7.0.13-200"

blossom_repo_setup

# Remove Existing Kernel
for pkg in kernel kernel{-core,-modules,-modules-core,-modules-extra,-tools-libs,-tools}; do
    rpm --erase "${pkg}" --nodeps
done

# cleanup leftovers that are not covered by kernel-* packages for some reason
rm -rf /usr/lib/modules

# Install Kernel (pinned build from repo.blossomos.org, not Fedora's stock build)
#
# An ordinary `dnf5 install --enablerepo=...` can't be trusted to pick the
# blossomos copy over a same or higher versioned one in the base Fedora
# repos. Download the RPMs from the blossom repo explicitly and install the
# local files, so there is no repo resolution to get wrong.
KERNEL_PKGS=(
    "kernel-${BLOSSOM_KERNEL_VERSION}"
    "kernel-core-${BLOSSOM_KERNEL_VERSION}"
    "kernel-modules-${BLOSSOM_KERNEL_VERSION}"
    "kernel-modules-core-${BLOSSOM_KERNEL_VERSION}"
    "kernel-modules-extra-${BLOSSOM_KERNEL_VERSION}"
    "kernel-devel-${BLOSSOM_KERNEL_VERSION}"
    "kernel-devel-matched-${BLOSSOM_KERNEL_VERSION}"
)

mkdir -p /tmp/blossom-kernel
dnf5 download --destdir=/tmp/blossom-kernel --disablerepo='*' --enablerepo="${BLOSSOM_REPO_ID}" "${KERNEL_PKGS[@]}"
dnf5 install -y /tmp/blossom-kernel/*.rpm
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

# openrazer-kernel-modules-dkms' %posttrans hook builds against the running
# container's kernel (the build host's, not ours) and fails. Files are
# already on disk by then, so retarget the dkms build at our actual kernel.
dkms autoinstall -k "${BLOSSOM_KERNEL_VERSION}.x86_64" || true

echo "::endgroup::"
