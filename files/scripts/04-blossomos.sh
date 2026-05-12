#!/usr/bin/env bash

echo "::group:: ===$(basename "$0")==="

set -ouex pipefail

BLOSSOM_REPO_URL="${BLOSSOM_REPO_URL:-https://repo.blossomos.org/indev/main/}"

if [[ "$BLOSSOM_REPO_URL" =~ /release/ ]]; then
    REPO_ID="blossomos-main"
    REPO_NAME="BlossomOS Main"
else
    REPO_ID="blossomos-main-indev"
    REPO_NAME="BlossomOS Main (indev)"
fi

# rpm --rebuilddb cannot atomically rename in this container fs; manually place the rebuilt DB
rm -f /usr/share/rpm/rpmdb.sqlite-shm /usr/share/rpm/rpmdb.sqlite-wal
rpm --rebuilddb 2>/dev/null || true
REBUILD_DIR=$(ls -d /usr/share/rpmrebuilddb.* 2>/dev/null | sort -t. -k2 -n | tail -1)
if [ -n "${REBUILD_DIR}" ]; then
    cp -f "${REBUILD_DIR}"/rpmdb.sqlite /usr/share/rpm/rpmdb.sqlite
    rm -rf "${REBUILD_DIR}"
fi
rm -f /usr/share/rpm/rpmdb.sqlite-shm /usr/share/rpm/rpmdb.sqlite-wal

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
    blossomui \
    atuin \
    adjust \
    pkglayer \
    blossomos-kinfocenter \
    kwin-pen-cursor

# blossomos-shellconfig conflicts with bash/zsh over /etc/skel/.bashrc and
# .zshrc; dnf5 has no --replacefiles flag so install via rpm directly
dnf5 download --destdir=/tmp/blossom --enablerepo="${REPO_ID}" blossomos-shellconfig
rpm -i --replacefiles /tmp/blossom/blossomos-shellconfig*.rpm
rm -rf /tmp/blossom

# Add BlossomOS Flatpak remote
curl -fsSL https://repo.blossomos.org/BLOSSOMOS-GPG-KEY.pub -o /tmp/flatpak-repo-key.asc
flatpak remote-add --system --if-not-exists \
    --gpg-import=/tmp/flatpak-repo-key.asc \
    blossomos https://repo.blossomos.org/flatpak
rm -f /tmp/flatpak-repo-key.asc

# Rebuild RPM DB into a clean, WAL-free state before committing the layer.
# Do NOT remove WAL/SHM first — rpm --rebuilddb must read them to get the
# full post-dnf5 package set. Only clean up after the new DB is in place.
rpm --rebuilddb 2>/dev/null || true
REBUILD_DIR=$(ls -d /usr/share/rpmrebuilddb.* 2>/dev/null | sort -t. -k2 -n | tail -1)
if [ -n "${REBUILD_DIR}" ]; then
    cp -f "${REBUILD_DIR}"/rpmdb.sqlite /usr/share/rpm/rpmdb.sqlite
    rm -rf "${REBUILD_DIR}"
fi
rm -f /usr/share/rpm/rpmdb.sqlite-shm /usr/share/rpm/rpmdb.sqlite-wal

echo "::endgroup::"
