#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

#shellcheck source=build_files/shared/blossom-repo.sh
source /ctx/build_files/shared/blossom-repo.sh
#shellcheck source=build_files/shared/copr-helpers.sh
source /ctx/build_files/shared/copr-helpers.sh

# BlossomOS kernel build
# Not derived from the KERNEL build-arg. KERNEL picks the closest matching
# ublue-os akmods image, whose ostree.linux label carries a fc44 dist tag,
# but repo.blossomos.org's kernel package NVR does not carry one. Bump this
# by hand whenever a new kernel build is published to repo.blossomos.org.
BLOSSOM_KERNEL_VERSION="7.1.3-201"

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

mkdir -p /etc/pki/akmods/certs
curl "https://github.com/ublue-os/akmods/raw/refs/heads/main/certs/public_key.der" --retry 3 -Lo /etc/pki/akmods/certs/akmods-ublue.der

# /var is a fresh, empty tmpfs for this RUN step (Containerfile.in mounts
# it that way), so /var/tmp doesn't have the usual world-writable sticky
# bit yet. akmods drops privileges to the akmods user via runuser to run
# rpmbuild, which needs to write there; without this every akmods build
# below fails with "Permission denied" writing to /var/tmp.
mkdir -p /var/tmp
chmod 1777 /var/tmp

# xone (Xbox controller/wireless adapter) from ublue-os' own akmods COPR,
# as an akmod (dkms-buildable source) instead of the precompiled kmod-xone
# mounted from the akmods image, which is built against Fedora's stock
# fc44-tagged kernel and can never match our kernel-uname-r.
#
# akmod-* packages' own %post/%posttrans hooks always try (and, as root
# inside a container build, always fail non-critically) to auto-build
# immediately on install; dnf5 reports that as a failed transaction even
# though the package's files land fine, so this is always wrapped in
# `|| true` and followed by an explicit akmods build below.
copr_install_isolated "ublue-os/akmods" akmod-xone xone-kmod-common || true
akmods --force --kernels "${BLOSSOM_KERNEL_VERSION}.x86_64" --kmod xone || true

# v4l2loopback from RPM Fusion, same reasoning as xone above
dnf -y install "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
dnf -y install akmod-v4l2loopback || true
sed -i 's@enabled=1@enabled=0@g' /etc/yum.repos.d/rpmfusion-free*.repo
akmods --force --kernels "${BLOSSOM_KERNEL_VERSION}.x86_64" --kmod v4l2loopback || true

# OpenRazer from hardware:razer repo (not a COPR)
dnf -y config-manager addrepo --from-repofile=https://openrazer.github.io/hardware:razer.repo
dnf -y install openrazer-daemon || true
sed -i 's@enabled=1@enabled=0@g' /etc/yum.repos.d/hardware:razer.repo

# openrazer-kernel-modules-dkms' %posttrans hook builds against the running
# container's kernel (the build host's, not ours) and fails. Files are
# already on disk by then, so retarget the dkms build at our actual kernel.
dkms autoinstall -k "${BLOSSOM_KERNEL_VERSION}.x86_64" || true

echo "::endgroup::"
