#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

# Disable uupd from updating distroboxes
sed -i 's|uupd|& --disable-module-distrobox|' /usr/lib/systemd/system/uupd.service

set -eoux pipefail

# Setup Systemd
systemctl enable --force plasmalogin.service
systemctl enable plasma-setup.service
systemctl enable rpm-ostree-countme.service
systemctl disable tailscaled.service
systemctl disable netbird.service
systemctl disable mullvad-daemon.service
systemctl disable mullvad-early-boot-blocking.service
# systemd-oomd's default cgroup pressure thresholds kill foreground apps
# (Plasma, browser tabs) too eagerly under memory pressure before MGLRU's
# working-set protection gets a chance to help. Disable it; the kernel's own
# OOM killer remains as the last resort.
systemctl disable systemd-oomd.service
systemctl disable systemd-oomd.socket
systemctl enable brew-setup.service
systemctl enable blossomos-groups.service
systemctl enable blossomos-dualboot-detect.service
systemctl enable blossomos-flatpak-overrides.service
systemctl --global enable blossomos-flatpak-overrides-user.service
systemctl --global enable podman-auto-update.timer
systemctl enable input-remapper.service

# dmem cgroup VRAM prioritization for foreground apps (games). No-op without
# a kernel that supports the dmem cgroup controller, see kernel-blossomos'
# cachyos patchset. plasma-foreground-booster.service has no [Install]
# section; it's autostarted via its KDE autostart .desktop entry instead.
systemctl enable dmemcg-booster-system.service
systemctl --global enable dmemcg-booster-user.service

# Enable kAirPods user service for all users
systemctl --global enable kairpodsd.service

# Nuke possible Fedora flatpak repos
systemctl enable flatpak-nuke-fedora.service

# disable sunshine service
systemctl --global disable app-dev.lizardbyte.app.Sunshine.service

# Enable the automatic updates by default
systemctl enable rpm-ostreed-automatic.timer

# Hide Desktop Files. Hidden removes mime associations
for file in htop nvtop; do
    if [[ -f "/usr/share/applications/${file}.desktop" ]]; then
        desktop-file-edit --set-key=Hidden --set-value=true /usr/share/applications/${file}.desktop
    fi
done

systemctl disable flatpak-add-fedora-repos.service

# Remove KCM Updates plugin so it doesn't appear in System Settings
rm -f /usr/lib64/qt6/plugins/plasma/kcms/systemsettings/kcm_updates.so

# NOTE: With isolated COPR installation, most repos are never enabled globally.
# We only need to clean up repos that were enabled during the build process.

# Disable third-party repos
for repo in fedora-multimedia tailscale netbird mullvad fedora-cisco-openh264; do
    if [[ -f "/etc/yum.repos.d/${repo}.repo" ]]; then
        sed -i 's@enabled=1@enabled=0@g' "/etc/yum.repos.d/${repo}.repo"
    fi
done

# Disable hardware:razer repo if it exists
if [[ -f "/etc/yum.repos.d/hardware:razer.repo" ]]; then
    sed -i 's@enabled=1@enabled=0@g' /etc/yum.repos.d/hardware:razer.repo
fi

# Disable Terra repos (installed on F42 and earlier)
for i in /etc/yum.repos.d/terra*.repo; do
    if [[ -f "$i" ]]; then
        sed -i 's@enabled=1@enabled=0@g' "$i"
    fi
done

# Disable all COPR repos (should already be disabled by helpers, but ensure)
for i in /etc/yum.repos.d/_copr:*.repo; do
    if [[ -f "$i" ]]; then
        sed -i 's@enabled=1@enabled=0@g' "$i"
    fi
done

# Disable RPM Fusion repos
for i in /etc/yum.repos.d/rpmfusion-*.repo; do
    if [[ -f "$i" ]]; then
        sed -i 's@enabled=1@enabled=0@g' "$i"
    fi
done

# Disable fedora-coreos-pool if it exists
if [ -f /etc/yum.repos.d/fedora-coreos-pool.repo ]; then
    sed -i 's@enabled=1@enabled=0@g' /etc/yum.repos.d/fedora-coreos-pool.repo
fi

echo "::endgroup::"
