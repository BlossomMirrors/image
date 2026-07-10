# enable netbird
netbird:
    sudo systemctl enable --now netbird

# enable tailscale
tailscale:
    sudo systemctl enable --now tailscaled

# enable mullvad
mullvad:
    sudo systemctl enable --now mullvad-early-boot-blocking
    sudo systemctl enable --now mullvad-daemon
    mkdir -p ~/.local/share/applications
    cp /usr/share/applications/mullvad-vpn.desktop.bak ~/.local/share/applications/mullvad-vpn.desktop
