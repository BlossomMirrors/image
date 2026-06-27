#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -ouex pipefail

# use negativo17 for 3rd party packages with higher priority than default
if ! grep -q fedora-multimedia <(dnf5 repolist); then
    # Enable or Install Repofile
    dnf5 config-manager setopt fedora-multimedia.enabled=1 ||
        dnf5 config-manager addrepo --from-repofile="https://negativo17.org/repos/fedora-multimedia.repo"
fi
# Set higher priority
dnf5 config-manager setopt fedora-multimedia.priority=90

# Add Flathub to the image for eventual application
mkdir -p /etc/flatpak/remotes.d/
curl --retry 3 -Lo /etc/flatpak/remotes.d/flathub.flatpakrepo https://dl.flathub.org/repo/flathub.flatpakrepo

# may break SDDM/KWin when upgraded
dnf5 versionlock add "qt6-*"

# use override to replace mesa and others with less crippled versions
OVERRIDES=(
    "intel-gmmlib"
    "intel-mediasdk"
    "intel-vpl-gpu-rt"
    "libheif"
    "libva"
    "libva-intel-media-driver"
    "mesa-dri-drivers"
    "mesa-filesystem"
    "mesa-libEGL"
    "mesa-libGL"
    "mesa-libgbm"
    "mesa-va-drivers"
    "mesa-vulkan-drivers"
)

dnf5 distro-sync --skip-unavailable -y --repo='fedora-multimedia' "${OVERRIDES[@]}"
dnf5 versionlock add "${OVERRIDES[@]}"
# All DNF-related operations should be done here whenever possible
#shellcheck source=build_files/shared/copr-helpers.sh
source /ctx/build_files/shared/copr-helpers.sh

# NOTE:
# Packages are split into FEDORA_PACKAGES and COPR_PACKAGES to prevent
# malicious COPRs from injecting fake versions of Fedora packages.
# Fedora packages are installed first in bulk (safe).
# COPR packages are installed individually with isolated enablement.

# Base packages from Fedora repos - common to all versions

# Prevent partial upgrading, major kde version updates black screened
# https://github.com/ublue-os/aurora/issues/1227
dnf5 versionlock add plasma-desktop

mapfile -t FEDORA_PACKAGES < <(grep -v '^#\|^[[:space:]]*$' /ctx/build_files/base/packages.dnf)

# Version-specific Fedora package additions
case "$FEDORA_MAJOR_VERSION" in
    43)
        FEDORA_PACKAGES+=(
        )
        ;;
    44)
        FEDORA_PACKAGES+=(
        )
        ;;
esac

NEGATIVO_PACKAGES=(
    ffmpeg
    ffmpeg-libs
    intel-vaapi-driver
    libfdk-aac
    libva-utils
    pipewire-libs-extra
    uld
  )

# Install all Fedora packages (bulk - safe from COPR injection)
echo "Installing ${#FEDORA_PACKAGES[@]} packages from Fedora repos and ${#NEGATIVO_PACKAGES[@]} from Negativo..."
dnf5 -y install "${FEDORA_PACKAGES[@]}" "${NEGATIVO_PACKAGES[@]}"

# Install tailscale package from their repo
echo "Installing tailscale from official repo..."
dnf config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
dnf config-manager setopt tailscale-stable.enabled=0
dnf -y install --enablerepo='tailscale-stable' tailscale

# Install netbird from their official repo
echo "Installing netbird from official repo..."
tee /etc/yum.repos.d/netbird.repo <<'EOF'
[netbird]
name=netbird
baseurl=https://pkgs.netbird.io/yum/
enabled=0
gpgcheck=1
gpgkey=https://pkgs.netbird.io/yum/repodata/repomd.xml.key
repo_gpgcheck=0
EOF
rpm --import https://pkgs.netbird.io/yum/repodata/repomd.xml.key
dnf5 download --destdir=/tmp/netbird --arch="$(rpm -E '%_arch')" --enablerepo='netbird' netbird
rpm -i --noscripts /tmp/netbird/netbird*.rpm
rm -rf /tmp/netbird
# netbird service install (run by %post) is skipped above because it tries to
# start the daemon in the build context. Write the unit file it would generate.
cat > /usr/lib/systemd/system/netbird.service <<'EOF'
[Unit]
Description=NetBird mesh network client
ConditionFileIsExecutable=/usr/bin/netbird
After=network.target syslog.target

[Service]
StartLimitInterval=5
StartLimitBurst=10
ExecStart=/usr/bin/netbird "service" "run" "--log-level" "info" "--daemon-addr" "unix:///var/run/netbird.sock" "--log-file" "/var/log/netbird/client.log"
Restart=always
RestartSec=120
EnvironmentFile=-/etc/sysconfig/netbird
Environment=SYSTEMD_UNIT=netbird

[Install]
WantedBy=multi-user.target
EOF

# Install COPR packages using isolated enablement (secure)
echo "Installing COPR packages with isolated repo enablement..."

# From ublue-os/staging
copr_install_isolated "ublue-os/staging" \
    "fw-fanctrl" \
    "plasma-setup"

# From ublue-os/packages
copr_install_isolated "ublue-os/packages" \
    "oversteer-udev" \
    "uupd"

# Version-specific COPR packages
# Example:
# copr_install_isolated "ublue-os/packages" "uupd"
case "$FEDORA_MAJOR_VERSION" in
    43)

        ;;
    44)

        ;;
esac

# kAirpods from ledif/kairpods COPR
copr_install_isolated "ledif/kairpods" \
    "kairpods"

# Sunshine from lizardbyte/beta COPR
copr_install_isolated "lizardbyte/beta" \
    "sunshine"

# Bibata cursor theme from peterwu/rendezvous COPR
copr_install_isolated "peterwu/rendezvous" \
    "bibata-cursor-themes"

# KDE Beta COPR
KDE_BETA_COPR="@kdesig/kde-beta"
KDE_BETA_REPO="copr:copr.fedorainfracloud.org:group_kdesig:kde-beta"
dnf5 -y copr enable "$KDE_BETA_COPR"
dnf5 -y copr disable "$KDE_BETA_COPR"
dnf5 versionlock delete "qt6-*" 2>/dev/null || true
dnf5 versionlock delete "plasma-desktop" 2>/dev/null || true
dnf5 upgrade --skip-unavailable -y --enablerepo="$KDE_BETA_REPO"

# Packages to exclude - common to all versions
EXCLUDED_PACKAGES=(
    sddm
    default-fonts-cjk-sans
    fedora-bookmarks
    fedora-chromium-config
    fedora-chromium-config-kde
    fedora-third-party
    ffmpegthumbnailer
    firefox
    firefox-langpacks
    firewall-config
    google-noto-sans-cjk-vf-fonts
    kcharselect
    khelpcenter
    krfb
    krfb-libs
    plasma-discover-kns
    plasma-discover-rpm-ostree
    plasma-welcome-fedora
    plasma-welcome
    podman-docker
    kaddressbook
)

# Version-specific package exclusions
case "$FEDORA_MAJOR_VERSION" in
    43)
        EXCLUDED_PACKAGES+=()
        ;;
    44)
        EXCLUDED_PACKAGES+=()
        ;;
esac

# Remove excluded packages if they are installed
if [[ "${#EXCLUDED_PACKAGES[@]}" -gt 0 ]]; then
    readarray -t INSTALLED_EXCLUDED < <(rpm -qa --queryformat='%{NAME}\n' "${EXCLUDED_PACKAGES[@]}" 2>/dev/null || true)
    if [[ "${#INSTALLED_EXCLUDED[@]}" -gt 0 ]]; then
        echo "Removing excluded packages: ${INSTALLED_EXCLUDED[*]}"
        for pkg in "${INSTALLED_EXCLUDED[@]}"; do
            echo "Removing package: $pkg"
            rpm --erase --nodeps "$pkg" || echo "Warning: Failed to remove $pkg"
        done
    else
        echo "No excluded packages found to remove."
    fi
fi

# we can't remove plasma-lookandfeel-fedora package because it is a dependency of plasma-desktop
rpm --erase --nodeps plasma-lookandfeel-fedora
# rpm erase doesn't remove actual files
rm -rf /usr/share/plasma/look-and-feel/org.fedoraproject.fedora.desktop/


## Pins and Overrides
## Use this section to pin packages in order to avoid regressions
# Remember to leave a note with rationale/link to issue for each pin!
#
# Example:
#if [ "$FEDORA_MAJOR_VERSION" -eq "42" ]; then
#    Workaround pkcs11-provider regression, see issue #1943
#    dnf5 upgrade --refresh --advisory=FEDORA-2024-dd2e9fb225
#fi

dnf -y install plasma-firewall

# Install DX specific packages
if [[ "${IMAGE_FLAVOR}" == "dx" ]]; then
  /ctx/build_files/dx/00-dx.sh
fi

echo "::endgroup::"
