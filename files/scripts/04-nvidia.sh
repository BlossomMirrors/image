#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# NVIDIA driver installation is handled by the akmods BlueBuild module.
# This script handles only the post-install configuration.

# Not available for Fedora 43 yet
dnf config-manager setopt excludepkgs=golang-github-nvidia-container-toolkit

rm -f /usr/share/vulkan/icd.d/nouveau_icd.*.json
ln -sf libnvidia-ml.so.1 /usr/lib64/libnvidia-ml.so
tee /usr/lib/bootc/kargs.d/00-nvidia.toml <<EOF
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1", "initcall_blacklist=simpledrm_platform_driver_init"]
EOF

echo "::endgroup::"
