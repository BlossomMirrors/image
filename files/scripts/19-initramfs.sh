#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -ouex pipefail

# Derive kernel version from /usr/lib/modules rather than the RPM DB; the DB
# is written in WAL mode across container layer boundaries and has been
# unreliable in this overlayfs environment.
KERNEL_VERSION=$(ls /usr/lib/modules/ 2>/dev/null | sort -V | tail -1)
if [[ -z "${KERNEL_VERSION}" ]]; then
    echo "ERROR: no kernel found in /usr/lib/modules/" >&2
    exit 1
fi

export DRACUT_NO_XATTR=1
/usr/bin/dracut --no-hostonly --kver "${KERNEL_VERSION}" --reproducible -v -f "/usr/lib/modules/${KERNEL_VERSION}/initramfs.img"
chmod 0600 "/usr/lib/modules/${KERNEL_VERSION}/initramfs.img"

echo "::endgroup::"
