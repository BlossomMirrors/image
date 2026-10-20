export JUST_JUSTFILE := justfile()

# turn on integrity mode (measured boot with IMA, refuses modified systems)
on:
    #!/usr/bin/env bash
    set -euo pipefail

    report="$(blossomos-integrity check --json || true)"
    if [[ "$(jq -r .secure_boot <<<"$report")" != true ]]; then
        gum style --foreground 1 "Secure Boot is off. Enable it in your firmware settings first."
        exit 1
    fi
    if [[ "$(jq -r .tpm <<<"$report")" != true ]]; then
        gum style --foreground 1 "No TPM 2.0 found, integrity mode needs one to record measurements."
        exit 1
    fi
    if [[ "$(jq -r .image.signature <<<"$report")" != signed || "$(jq -r .image.trusted_repository <<<"$report")" != true ]]; then
        gum style --foreground 3 "This system doesn't track a signature-verified BlossomOS image yet."
        gum confirm "Switch to the signature-verified origin now?" || exit 0
        sudo blossomos-integrity migrate-origin
        staged="$(rpm-ostree status --json | jq -r '.deployments[] | select(.staged) | ."container-image-reference"')"
        if [[ "$staged" == ostree-image-signed:* ]]; then
            gum style --foreground 2 "Reboot, then run this again."
        else
            gum style --foreground 1 "No verifiable signature is published for your image yet, try again after the next update."
        fi
        exit 0
    fi
    if [[ "$(jq -r '.reasons | index("usr-unlocked")' <<<"$report")" != null ]]; then
        gum style --foreground 1 "/usr is unlocked. Reboot without unlocking it first."
        exit 1
    fi
    if [[ "$(jq -r '.reasons | index("usr-layered")' <<<"$report")" != null ]]; then
        gum style --foreground 1 "This system has layered or overridden packages. Remove them first (rpm-ostree reset)."
        exit 1
    fi

    gum style --border rounded --padding "0 1" \
        "Integrity mode refuses to boot unsigned, unlocked or layered systems," \
        "and makes the kernel record a hash of every program and library that" \
        "runs (IMA). That record stays on this machine unless you or software" \
        "you run hands it to someone, for example a game's anti-cheat."
    gum confirm "Turn on integrity mode?" || exit 0
    sudo rpm-ostree kargs --append-if-missing=blossomos.integrity=1
    sudo blossomos-integrity lock-layering true --reload
    gum style --foreground 2 "Integrity mode is on from the next boot. Package layering is locked."

# turn off integrity mode (allows package layering and unsigned images)
off:
    #!/usr/bin/env bash
    set -euo pipefail
    gum style --foreground 3 \
        "Games and other software that check this system's integrity may refuse to run" \
        "while it is off."
    gum confirm "Turn off integrity mode?" || exit 0
    sudo rpm-ostree kargs --delete-if-present=blossomos.integrity=1
    sudo blossomos-integrity lock-layering false --reload
    gum style --foreground 2 "Integrity mode is off from the next boot. Package layering is unlocked."

# show whether this boot counts as trusted, and why not
check:
    #!/usr/bin/env bash
    blossomos-integrity check --online

# write a TPM attestation bundle to ~/blossomos-attestation (for testing verifiers)
attest:
    #!/usr/bin/env bash
    set -euo pipefail
    out="${HOME}/blossomos-attestation"
    sudo blossomos-integrity attest --nonce "$(openssl rand -hex 32)" --out "$out"
    sudo chown -R "$(id -u):$(id -g)" "$out"
    gum style --foreground 2 "Written to $out"
