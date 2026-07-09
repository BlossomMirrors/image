# switch to or back from the developer experience image
enable:
    #!/usr/bin/env bash
    set -e

    IMAGE_NAME=$(jq -r '."image-name"' /usr/share/ublue-os/image-info.json)
    REGISTRY="registry.blossomos.org/blossom/image"

    if lspci | grep -qi nvidia; then
        GPU_SUFFIX="-nvidia"
    else
        GPU_SUFFIX=""
    fi

    if [[ "$IMAGE_NAME" == *-dx* ]]; then
        TARGET="main${GPU_SUFFIX}"
        gum confirm "Switch back to ${TARGET}, dropping the developer experience image?" || exit 0
    else
        TAG=$(gum choose "latest" "main" --header "Enable developer mode using which image?")
        [[ -z "$TAG" ]] && exit 0
        TARGET="${TAG}${GPU_SUFFIX}-dx"
        gum confirm "Switch to ${TARGET}?" || exit 0
    fi

    sudo -v
    sudo bootc switch "${REGISTRY}:${TARGET}"
    gum style --foreground 2 "Switched to ${TARGET}. Reboot to apply."
