#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

#shellcheck source=build_files/shared/copr-helpers.sh
source /ctx/build_files/shared/copr-helpers.sh

# Not available for Fedora 43 yet
dnf config-manager setopt excludepkgs=golang-github-nvidia-container-toolkit

# ublue-os-nvidia-addons (repo files, nvidia CDI service, SELinux policy) is
# kernel-version independent, so it is still pulled from the akmods-nvidia-open
# image even though this variant never touches the open kernel modules.
dnf5 -y install /tmp/rpms/nvidia/ublue-os/ublue-os-nvidia-addons-*.rpm

# negativo17's 580 branch is the last one to support Maxwell, Pascal and Volta
# GPUs; upstream nvidia dropped those architectures from the open kernel
# modules, so 580 only ships proprietary kmods. It isn't part of
# ublue-os-nvidia-addons, so the repo is added by hand here instead.
tee /etc/yum.repos.d/fedora-nvidia-580.repo <<EOF
[fedora-nvidia-580]
name=negativo17 - Nvidia 580 LTS
baseurl=https://negativo17.org/repos/nvidia-580/fedora-\$releasever/\$basearch/
enabled=0
skip_if_unavailable=1
gpgcheck=1
gpgkey=https://negativo17.org/repos/RPM-GPG-KEY-slaanesh
enabled_metadata=1
metadata_expire=6h
type=rpm-md
repo_gpgcheck=0
EOF

# Keep the regular (non-LTS) fedora-nvidia repo out of the transaction so
# akmod-nvidia/nvidia-driver always resolve to the 580 branch here.
dnf5 config-manager setopt fedora-nvidia.enabled=0 fedora-nvidia-580.enabled=1 nvidia-container-toolkit.enabled=1

# Pin an exact NVR so the akmod and the userspace driver below resolve to
# the same release even if negativo17 publishes a new build mid-transaction.
DRIVER_VERSION="$(dnf5 info akmod-nvidia | grep -E '^Version|^Release' | awk '{print $3}' | xargs | sed 's/ /-/')"
# akmod-nvidia's own %post always tries (and, as root inside a container
# build, always fails non-critically) to auto-build immediately on
# install; dnf5 reports that as a failed transaction even though the
# package's files land fine, so this is wrapped and followed by an
# explicit akmods build below.
dnf5 -y install "akmod-nvidia-${DRIVER_VERSION}" || true

# Our own kernel, not the running container host's. The 580 branch's
# akmod-nvidia has no open kernel module sources (Maxwell/Pascal/Volta don't
# support them), so this always builds the proprietary modules.
KERNEL_UNAME_R="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
akmods --force --kernels "${KERNEL_UNAME_R}" --kmod nvidia
modinfo /usr/lib/modules/"${KERNEL_UNAME_R}"/extra/nvidia/nvidia{,-drm,-modeset,-peermem,-uvm}.ko.xz >/dev/null ||
    (find /var/cache/akmods/nvidia/ -name '*.failed.log' -print -exec cat {} \; && exit 1)

dnf5 -y install \
    nvidia-driver \
    nvidia-driver-cuda \
    nvidia-modprobe \
    nvidia-persistenced \
    nvidia-settings \
    nvidia-xconfig \
    nvidia-container-toolkit \
    egl-wayland \
    libva-nvidia-driver

# BASE_IMAGE_NAME is always kinoite here; supergfxctl is ublue-os/staging's
# hybrid GPU switching daemon for kinoite/silverblue.
copr_install_isolated "ublue-os/staging" supergfxctl

# Read straight from the built module rather than `rpm -q kmod-nvidia`:
# akmods registers it under a kernel-embedded name like
# kmod-nvidia-${KERNEL_UNAME_R}, not the bare name.
KMOD_VERSION="$(modinfo -F version /usr/lib/modules/"${KERNEL_UNAME_R}"/extra/nvidia/nvidia.ko.xz)"
NVIDIA_DRIVER_VERSION="$(rpm -q --queryformat '%{VERSION}' nvidia-driver)"
if [[ "${KMOD_VERSION}" != "${NVIDIA_DRIVER_VERSION}" ]]; then
    echo "Error: kmod-nvidia version (${KMOD_VERSION}) does not match nvidia-driver version (${NVIDIA_DRIVER_VERSION})"
    exit 1
fi

dnf5 config-manager setopt fedora-nvidia-580.enabled=0 nvidia-container-toolkit.enabled=0

semodule --verbose --install /usr/share/selinux/packages/nvidia-container.pp

# force driver load to fix black screen on boot for nvidia desktops, and
# pre-load intel/amd iGPU else chromium web browsers fail to use hardware
# acceleration
sed -i 's@omit_drivers@force_drivers@g' /usr/lib/dracut/dracut.conf.d/99-nvidia.conf
sed -i 's@ nvidia @ i915 amdgpu nvidia @g' /usr/lib/dracut/dracut.conf.d/99-nvidia.conf

rm -f /usr/share/vulkan/icd.d/nouveau_icd.*.json
ln -sf libnvidia-ml.so.1 /usr/lib64/libnvidia-ml.so
tee /usr/lib/bootc/kargs.d/00-nvidia.toml <<EOF
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1", "initcall_blacklist=simpledrm_platform_driver_init"]
EOF

[ -d /ctx/system_files/nvidia-legacy ] && rsync -rvKl /ctx/system_files/nvidia-legacy/ /
[ -d /ctx/system_files/nvidia ] && rsync -rvKl /ctx/system_files/nvidia/ /

echo "::endgroup::"
