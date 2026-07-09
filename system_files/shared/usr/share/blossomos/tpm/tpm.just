# show which unlock methods are enrolled for the encrypted disk
status:
    #!/usr/bin/env bash
    set -e

    mapfile -t UUIDS < <(sudo awk '$1 !~ /^#/ && NF {print $2}' /etc/crypttab | sed 's/^UUID=//')
    if [[ ${#UUIDS[@]} -eq 0 ]]; then
        gum style --foreground 1 "No encrypted device found in /etc/crypttab"
        exit 1
    fi

    for CRYPT_UUID in "${UUIDS[@]}"; do
        CRYPT_DEV=$(blkid -U "$CRYPT_UUID")
        gum style --bold "$CRYPT_DEV"
        sudo systemd-cryptenroll "$CRYPT_DEV"
        echo
    done

# enroll the TPM as an unlock method for the encrypted disk
enroll:
    #!/usr/bin/env bash
    set -e

    mapfile -t UUIDS < <(sudo awk '$1 !~ /^#/ && NF {print $2}' /etc/crypttab | sed 's/^UUID=//')
    if [[ ${#UUIDS[@]} -eq 0 ]]; then
        gum style --foreground 1 "No encrypted device found in /etc/crypttab"
        exit 1
    elif [[ ${#UUIDS[@]} -eq 1 ]]; then
        CRYPT_UUID="${UUIDS[0]}"
    else
        CRYPT_UUID=$(gum choose "${UUIDS[@]}" --header "Multiple encrypted devices found, choose one")
        [[ -z "$CRYPT_UUID" ]] && exit 0
    fi
    CRYPT_DEV=$(blkid -U "$CRYPT_UUID")

    gum style --foreground 3 "This adds the TPM as an extra unlock method for $CRYPT_DEV. Your passphrase keeps working as a fallback."
    gum confirm "Enroll the TPM for $CRYPT_DEV?" || exit 0

    sudo systemd-cryptenroll --tpm2-device=auto "$CRYPT_DEV"
    gum style --foreground 2 "TPM enrolled for $CRYPT_DEV. It now unlocks automatically on boot as long as the TPM state does not change, such as after a Secure Boot or firmware update."

# remove the TPM as an unlock method for the encrypted disk
wipe:
    #!/usr/bin/env bash
    set -e

    mapfile -t UUIDS < <(sudo awk '$1 !~ /^#/ && NF {print $2}' /etc/crypttab | sed 's/^UUID=//')
    if [[ ${#UUIDS[@]} -eq 0 ]]; then
        gum style --foreground 1 "No encrypted device found in /etc/crypttab"
        exit 1
    elif [[ ${#UUIDS[@]} -eq 1 ]]; then
        CRYPT_UUID="${UUIDS[0]}"
    else
        CRYPT_UUID=$(gum choose "${UUIDS[@]}" --header "Multiple encrypted devices found, choose one")
        [[ -z "$CRYPT_UUID" ]] && exit 0
    fi
    CRYPT_DEV=$(blkid -U "$CRYPT_UUID")

    gum confirm "Remove the TPM unlock method for $CRYPT_DEV?" || exit 0
    sudo systemd-cryptenroll --wipe-slot=tpm2 "$CRYPT_DEV"
    gum style --foreground 2 "TPM unlock removed for $CRYPT_DEV."
