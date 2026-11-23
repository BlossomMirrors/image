#!/usr/bin/env bash

echo "::group:: ===$(basename "$0")==="

set -euo pipefail

#shellcheck source=build_files/shared/blossom-repo.sh
source /ctx/build_files/shared/blossom-repo.sh

REPO_ID="${BLOSSOM_REPO_ID}"

# Add repo (disabled — installed packages use --enablerepo)
blossom_repo_setup

# Remove conflicting packages from RPM DB only — files live in ostree layer and
# cannot be deleted by a normal transaction
rpm -e --nodeps --justdb generic-logos 2>/dev/null || true

# Lay our branding over fedora-release-common's /etc/os-release and friends
# instead of replacing that package: fedora-release-kinoite requires its exact
# version, and Fedora 45's redhat-systemd-presets-common conflicts with any
# other provider of it. First, since it also provides system-logos.
blossom_replace_pkg --replacefiles blossomos-branding

# Install BlossomOS RPM packages
dnf5 -y install \
    --enablerepo="${REPO_ID}" \
    blossom-arc \
    google-noto-emoji-fonts-3d \
    blossomos-webapps \
    blossomos-skel \
    blossomui \
    blossom-sound-theme \
    blossom-udev-rules \
    blossom-plymouth-theme \
    blossom-kcm-software-update \
    blossom-kcm-help-support \
    driveman \
    blossom-recovery \
    blossom-p2pupdated \
    blossom-welcome \
    quick-appearance-kcm \
    dmemcg-booster \
    kcgroups-dmemcg \
    goxlr-utility \
    atuin \
    umu-launcher \
    adjust \
    pkglayer \
    kwin-pen-cursor \
    micro \
    python3-pip

# Use our sweeping-bar theme instead of the stock spinner; 19-initramfs.sh
# rebuilds the initramfs later in the build and will pick this up
plymouth-set-default-theme blossom

# Replace stock kinfocenter with our BlossomOS-patched build
blossom_replace_pkg --replacepkgs kinfocenter

# Replace stock xdg-desktop-portal with our BlossomOS-patched build, so files opened from sandboxed apps (e.g. Helium) reach flatpaks with sub id desktop files like org.libreoffice.LibreOffice.writer
blossom_replace_pkg xdg-desktop-portal

# Replace stock plasma-setup with our BlossomOS-patched build
blossom_replace_pkg plasma-setup

# Overlay our BlossomOS-patched Session KCM on the stock plasma-desktop, so it can pick BlossomOS Recovery for the next restart (with blossom-recovery's units and polkit rule).
# Its files are also owned by plasma-desktop and dnf5 has no --replacefiles flag, so it is installed via rpm directly
# It requires exactly the plasma-desktop it was built from (the latest one in Fedora's updates), which the base
# image may not have caught up with yet, so first move plasma-desktop to that version
KCM_PLASMA_DESKTOP="$(dnf5 repoquery -q --disablerepo='*' --enablerepo="${REPO_ID}" --latest-limit=1 --requires kcm_smserver-blossomos |
    sed -n 's/^plasma-desktop(x86-64) = //p' | head -1)"
if [[ -z "${KCM_PLASMA_DESKTOP}" ]]; then
    echo "ERROR: could not tell which plasma-desktop kcm_smserver-blossomos needs" >&2
    exit 1
fi
if [[ "$(rpm -q --qf '%{VERSION}' plasma-desktop)" != "${KCM_PLASMA_DESKTOP}" ]]; then
    dnf5 -y install --allowerasing "plasma-desktop-${KCM_PLASMA_DESKTOP}"
fi
blossom_replace_pkg --replacefiles kcm_smserver-blossomos

# Install OpenRazer daemon (kmod is installed by the akmods module)
dnf -y config-manager addrepo --overwrite --from-repofile=https://openrazer.github.io/hardware:razer.repo
dnf -y install openrazer-daemon || true
sed -i 's@enabled=1@enabled=0@g' /etc/yum.repos.d/hardware:razer.repo

# blossomos-shellconfig and plasma-patches-blossom conflict with existing files;
# dnf5 has no --replacefiles flag so install via rpm directly
dnf5 download --destdir=/tmp/blossom --enablerepo="${REPO_ID}" blossomos-shellconfig plasma-patches-blossom
# rpm doesn't resolve dependencies, so install the plain ones the image doesn't
# have yet first (e.g. git: Fedora 45's base only ships git-core). Versioned
# and rich dependencies are left for rpm to check.
BLOSSOM_MISSING_DEPS=()
while read -r dep; do
    rpm -q --whatprovides "${dep}" >/dev/null 2>&1 || BLOSSOM_MISSING_DEPS+=("${dep}")
done < <(rpm -qpR /tmp/blossom/blossomos-shellconfig*.rpm /tmp/blossom/plasma-patches-blossom*.rpm |
    grep -vE '^(rpmlib\(|\()' | grep -v ' ' | sort -u)
if ((${#BLOSSOM_MISSING_DEPS[@]})); then
    dnf5 -y install --enablerepo="${REPO_ID}" "${BLOSSOM_MISSING_DEPS[@]}"
fi
rpm -i --replacefiles /tmp/blossom/blossomos-shellconfig*.rpm /tmp/blossom/plasma-patches-blossom*.rpm
rm -rf /tmp/blossom

# Add BlossomOS Flatpak remote
curl -fsSL https://repo.blossomos.org/BLOSSOMOS-GPG-KEY.pub -o /tmp/flatpak-repo-key.asc
flatpak remote-add --system --if-not-exists \
    --gpg-import=/tmp/flatpak-repo-key.asc \
    blossomos https://forge.arcstore.net/flatpak
rm -f /tmp/flatpak-repo-key.asc

echo "::endgroup::"
