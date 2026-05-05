#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# Enable Flathub
flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Generate flatpak preinstall files from packages.flatpak
# Format: <app_id> [remote]  — remote is optional, adds Origin= when specified
mkdir -p /usr/share/flatpak/preinstall.d
while read -r app_id remote; do
    origin_line=""
    [[ -n "${remote:-}" ]] && origin_line="Origin=${remote}"
    cat > "/usr/share/flatpak/preinstall.d/${app_id}.preinstall" << EOF
[Flatpak Preinstall ${app_id}]
Branch=stable
IsRuntime=false
${origin_line}
EOF
done < <(grep -v '^#\|^[[:space:]]*$' $CONFIG_DIRECTORY/packages.flatpak)

# Starship Shell Prompt
curl "https://github.com/starship/starship/releases/latest/download/starship-$(uname -m)-unknown-linux-gnu.tar.gz" --retry 3 -Lo /tmp/starship.tar.gz
curl "https://github.com/starship/starship/releases/latest/download/starship-$(uname -m)-unknown-linux-gnu.tar.gz.sha256" --retry 3 -Lo /tmp/starship.tar.gz.sha256

echo "$(cat /tmp/starship.tar.gz.sha256) /tmp/starship.tar.gz" | sha256sum --check
tar -xzf /tmp/starship.tar.gz -C /tmp
install -c -m 0755 /tmp/starship /usr/bin

# Nerdfont symbols
# to fix motd and prompt atleast temporarily
curl "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.zip" --retry 3 -Lo /tmp/nerdfontsymbols.zip
unzip /tmp/nerdfontsymbols.zip -d /tmp
mkdir -p /usr/share/fonts/nerd-fonts/NerdFontsSymbolsOnly/
mv /tmp/SymbolsNerdFont*.ttf /usr/share/fonts/nerd-fonts/NerdFontsSymbolsOnly/

# Bash Prexec v0.6.0
curl https://raw.githubusercontent.com/rcaloras/bash-preexec/b73ed5f7f953207b958f15b1773721dded697ac3/bash-preexec.sh --retry 3 -Lo /usr/share/bash-preexec

# use CoreOS' generator for emergency/rescue boot
# see detail: https://github.com/ublue-os/main/issues/653
mkdir -p /usr/lib/systemd/system-generators
curl "https://raw.githubusercontent.com/coreos/fedora-coreos-config/refs/heads/stable/overlay.d/05core/usr/lib/systemd/system-generators/coreos-sulogin-force-generator" --retry 3 -Lo /usr/lib/systemd/system-generators/coreos-sulogin-force-generator
chmod +x /usr/lib/systemd/system-generators/coreos-sulogin-force-generator

# rpm --rebuilddb cannot atomically rename in this container fs; manually place the rebuilt DB
rm -f /usr/share/rpm/rpmdb.sqlite-shm /usr/share/rpm/rpmdb.sqlite-wal
rpm --rebuilddb 2>/dev/null || true
REBUILD_DIR=$(ls -d /usr/share/rpmrebuilddb.* 2>/dev/null | sort -t. -k2 -n | tail -1)
if [ -n "${REBUILD_DIR}" ]; then
    cp -f "${REBUILD_DIR}"/rpmdb.sqlite /usr/share/rpm/rpmdb.sqlite
    rm -rf "${REBUILD_DIR}"
fi
rm -f /usr/share/rpm/rpmdb.sqlite-shm /usr/share/rpm/rpmdb.sqlite-wal

echo "::endgroup::"
