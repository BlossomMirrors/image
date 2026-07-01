#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

#shellcheck source=build_files/shared/copr-helpers.sh
source /ctx/build_files/shared/copr-helpers.sh

# Not available for Fedora 43 yet
dnf config-manager setopt excludepkgs=golang-github-nvidia-container-toolkit

# BlossomOS builds the nvidia-open kmod itself instead of relying on
# ublue-os/akmods' bundled nvidia-install.sh: its precompiled kmod-nvidia
# is built against Fedora's stock fc44-tagged kernel and hard-requires a
# kernel-uname-r our kernel-core doesn't provide, which fails the install
# outright. ublue-os-nvidia-addons (repo files, nvidia CDI service,
# SELinux policy) is still pulled from their akmods-nvidia-open image
# since none of that is kernel-version sensitive.
dnf5 -y install /tmp/rpms/nvidia/ublue-os/ublue-os-nvidia-addons-*.rpm

dnf5 config-manager setopt fedora-nvidia*.enabled=1 nvidia-container-toolkit.enabled=1

# Pin an exact NVR so the akmod and the userspace driver below resolve to
# the same release even if negativo17 publishes a new build mid-transaction.
DRIVER_VERSION="$(dnf5 info akmod-nvidia | grep -E '^Version|^Release' | awk '{print $3}' | xargs | sed 's/ /-/')"
dnf5 -y install "akmod-nvidia-${DRIVER_VERSION}"

# Our own kernel, not the running container host's. akmod-nvidia builds the
# open kernel modules (vs. proprietary) when KERNEL_MODULE_TYPE=open, same
# as ublue-os/akmods' own build script for this exact package.
KERNEL_UNAME_R="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
export KERNEL_MODULE_TYPE=open
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

KMOD_VERSION="$(rpm -q --queryformat '%{VERSION}' kmod-nvidia)"
NVIDIA_DRIVER_VERSION="$(rpm -q --queryformat '%{VERSION}' nvidia-driver)"
if [[ "${KMOD_VERSION}" != "${NVIDIA_DRIVER_VERSION}" ]]; then
    echo "Error: kmod-nvidia version (${KMOD_VERSION}) does not match nvidia-driver version (${NVIDIA_DRIVER_VERSION})"
    exit 1
fi

dnf5 config-manager setopt fedora-nvidia*.enabled=0 nvidia-container-toolkit.enabled=0

systemctl enable ublue-nvctk-cdi.service
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

[ -d /ctx/system_files/nvidia ] && rsync -rvKl /ctx/system_files/nvidia/ /

echo "::endgroup::"
