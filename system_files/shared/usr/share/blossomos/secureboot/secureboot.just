export JUST_JUSTFILE := justfile()

enroll-mok:
    #!/usr/bin/env bash
    sudo mokutil --import /usr/share/blossomos/secureboot/blossomos-secureboot.der

enroll-ublue:
    #!/usr/bin/env bash
    set -e

    KEY=/etc/pki/akmods/certs/akmods-ublue.der
    if [[ ! -f "$KEY" ]]; then
        gum style --foreground 1 "Universal Blue key not found at $KEY"
        exit 1
    fi

    if mokutil --test-key "$KEY" 2>/dev/null | grep -q "already enrolled"; then
        gum style --foreground 2 "The Universal Blue key is already enrolled."
        exit 0
    fi

    gum style --foreground 3 "After the next reboot, choose \"Enroll MOK\" in the blue MOK manager screen and enter the password: universalblue"
    sudo mokutil --timeout -1 || :
    echo -e "universalblue\nuniversalblue" | sudo mokutil --import "$KEY"
    gum style --foreground 2 "Universal Blue key queued for enrollment. Reboot to finish."
