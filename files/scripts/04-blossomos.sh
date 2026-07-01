#!/usr/bin/env bash

echo "::group:: ===$(basename "$0")==="

set -ouex pipefail

BLOSSOM_REPO_URL="${BLOSSOM_REPO_URL:-https://repo.blossomos.org/rpm/}"

REPO_ID="blossomos-main"
REPO_NAME="BlossomOS Main"

# Import GPG key
rpm --import https://repo.blossomos.org/BLOSSOMOS-GPG-KEY.pub

# Add repo (disabled — installed packages use --enablerepo)
cat > /etc/yum.repos.d/blossom.repo << EOF
[${REPO_ID}]
name=${REPO_NAME}
baseurl=${BLOSSOM_REPO_URL}
enabled=0
gpgcheck=1
gpgkey=https://repo.blossomos.org/BLOSSOMOS-GPG-KEY.pub
EOF

# Remove conflicting packages from RPM DB only — files live in ostree layer and
# cannot be deleted by a normal transaction
rpm -e --nodeps --justdb generic-logos 2>/dev/null || true

# Install BlossomOS RPM packages
dnf5 -y install \
    --enablerepo="${REPO_ID}" \
    blossomos-branding \
    blossom-arc \
    blossomos-webapps \
    blossomos-skel \
    blossomui \
    blossom-sound-theme \
    plasma-patches-blossom \
    atuin \
    umu-launcher \
    adjust \
    pkglayer \
    kwin-pen-cursor \
    micro \
    python3-pip

# Install OpenRazer daemon (kmod is installed by the akmods module)
dnf -y config-manager addrepo --overwrite --from-repofile=https://openrazer.github.io/hardware:razer.repo
dnf -y install openrazer-daemon || true
sed -i 's@enabled=1@enabled=0@g' /etc/yum.repos.d/hardware:razer.repo

# blossomos-shellconfig conflicts with existing files;
# dnf5 has no --replacefiles flag so install via rpm directly
dnf5 download --destdir=/tmp/blossom --enablerepo="${REPO_ID}" blossomos-shellconfig
rpm -i --replacefiles /tmp/blossom/blossomos-shellconfig*.rpm
rm -rf /tmp/blossom

# Add BlossomOS Flatpak remote
curl -fsSL https://repo.blossomos.org/BLOSSOMOS-GPG-KEY.pub -o /tmp/flatpak-repo-key.asc
flatpak remote-add --system --if-not-exists \
    --gpg-import=/tmp/flatpak-repo-key.asc \
    blossomos https://repo.blossomos.org/flatpak
rm -f /tmp/flatpak-repo-key.asc

echo "::endgroup::"
