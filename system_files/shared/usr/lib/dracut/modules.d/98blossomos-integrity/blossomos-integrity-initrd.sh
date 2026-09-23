#!/usr/bin/bash
# BlossomOS integrity, initramfs side.
#
# This runs from the initramfs, which ships inside the signed image and which
# GRUB measures into PCR 9, so a verifier that trusts PCR 9 can trust what this
# script records. see docs/INTEGRITY.md in the image repository.
#
#   ima-policy  (integrity mode only) load the IMA measurement policy
#   measure     record the deployment about to boot into PCR 15 and, in
#               integrity mode, refuse to boot anything that isn't an
#               unmodified, signature-verified BlossomOS image
#
# Outside integrity mode this must never fail: the measure unit powers the
# machine off on failure.

set -uo pipefail

CONF_DIR=/usr/lib/blossomos/integrity
STATE_DIR=/run/blossomos-integrity
PCR=15

log() {
    echo "blossomos-integrity: $*" >&2
}

integrity_mode() {
    grep -qw 'blossomos.integrity=1' /proc/cmdline
}

load_ima_policy() {
    mkdir -p "${STATE_DIR}"
    # Writing a path (rather than the rules) makes IMA read the file itself.
    if echo "${CONF_DIR}/ima-policy" >/sys/kernel/security/ima/policy; then
        touch "${STATE_DIR}/ima-policy-loaded"
    else
        log "failed to load the IMA policy"
    fi
    return 0
}

extend() {
    [[ -x /usr/lib/systemd/systemd-pcrextend ]] || return 1
    /usr/lib/systemd/systemd-pcrextend --graceful --pcr="${PCR}" "$1"
}

# Everything that makes a deployment differ from the image it was pulled
# from: client-side layering, overrides, a locally regenerated initramfs.
local_modifications() {
    awk -F= '
        /^\[/ { section = $0; next }
        section == "[packages]" && $2 != "" { print "packages" }
        section == "[overrides]" && $2 != "" { print "overrides" }
        section == "[modules]" && $2 != "" { print "modules" }
        section == "[rpmostree]" && $1 == "regenerate-initramfs" && $2 == "true" { print "initramfs" }
        section == "[rpmostree]" && $1 == "initramfs-etc" && $2 != "" { print "initramfs-etc" }
    ' "$1" | sort -u | tr '\n' ',' | sed 's/,$//'
}

signed_blossomos_origin() {
    local ref="$1" repo
    [[ "${ref}" =~ ^ostree-image-signed:(docker://|registry:)(.+)$ ]] || return 1
    repo="${BASH_REMATCH[2]}"
    repo="${repo%@*}"
    [[ "${repo##*/}" == *:* ]] && repo="${repo%:*}"
    local line
    while read -r line; do
        [[ "${line}" == "${repo}" ]] && return 0
    done <"${CONF_DIR}/signed-repos"
    return 1
}

refuse_boot() {
    local reasons="$1"
    log "refusing to boot: ${reasons}"
    plymouth quit 2>/dev/null || true
    cat >/dev/console <<EOF

  BlossomOS integrity mode is on, and the system about to boot is not an
  unmodified, signature-verified BlossomOS image (${reasons}).

  Booting it is refused. The machine powers off in 60 seconds; on the next
  start the boot menu appears, where you can pick the previous entry, or
  press 'e' and remove blossomos.integrity=1 to boot this one anyway.
  To turn integrity mode off for good, run 'adjust integrity off'.

EOF
    sleep 60
    exit 1
}

measure() {
    local ostree_arg deploy origin csum ref unlocked modified digest signature mode gate reasons measured
    mkdir -p "${STATE_DIR}"

    ostree_arg="$(tr ' ' '\n' </proc/cmdline | sed -n 's/^ostree=//p' | tail -n1)"
    if [[ -z "${ostree_arg}" ]]; then
        # Live ISO or anything else that isn't an ostree deployment
        echo "OSTREE=no" >"${STATE_DIR}/initrd.env"
        return 0
    fi

    deploy="$(readlink -f "/sysroot${ostree_arg}")"
    origin="${deploy}.origin"
    csum="$(basename "${deploy}")"
    csum="${csum%.*}"

    ref="$(sed -n 's/^container-image-reference=//p' "${origin}" 2>/dev/null | head -n1)"
    unlocked="$(sed -n 's/^unlocked=//p' "${origin}" 2>/dev/null | head -n1)"
    unlocked="${unlocked:-none}"
    modified="$(local_modifications "${origin}" 2>/dev/null)"
    modified="${modified:-none}"
    digest="$(ostree --repo=/sysroot/ostree/repo show --print-metadata-key=ostree.manifest-digest "${csum}" 2>/dev/null | tr -d "'")"
    digest="${digest:-none}"

    signature=unsigned
    signed_blossomos_origin "${ref}" && signature=signed

    mode=off
    integrity_mode && mode=enforcing

    reasons=()
    [[ "${signature}" == signed ]] || reasons+=("image not signature-verified")
    [[ "${unlocked}" == none ]] || reasons+=("/usr unlocked (${unlocked})")
    [[ "${modified}" == none ]] || reasons+=("locally modified (${modified})")
    [[ "${digest}" == none ]] && reasons+=("no image manifest digest")
    gate=pass
    [[ ${#reasons[@]} -eq 0 ]] || gate=fail

    measured=yes
    for word in \
        "blossomos-integrity:v1" \
        "blossomos-image:${ref:-none}" \
        "blossomos-manifest-digest:${digest}" \
        "blossomos-signature:${signature}" \
        "blossomos-usr:${unlocked}" \
        "blossomos-modified:${modified}" \
        "blossomos-mode:${mode}" \
        "blossomos-gate:${gate}"; do
        extend "${word}" || measured=no
    done
    # --graceful turns a missing TPM into success, so check for one as well
    [[ -e /dev/tpmrm0 || -e /dev/tpm0 ]] || measured=no

    cat >"${STATE_DIR}/initrd.env" <<EOF
OSTREE=yes
IMAGE=${ref}
COMMIT=${csum}
MANIFEST_DIGEST=${digest}
SIGNATURE=${signature}
USR=${unlocked}
MODIFIED=${modified}
MODE=${mode}
GATE=${gate}
MEASURED=${measured}
EOF

    if [[ "${mode}" == enforcing && "${gate}" == fail ]]; then
        local IFS=';'
        refuse_boot "${reasons[*]}"
    fi
    return 0
}

case "${1:-}" in
    ima-policy)
        integrity_mode && load_ima_policy
        exit 0
        ;;
    measure)
        measure
        exit 0
        ;;
    *)
        echo "usage: $0 ima-policy|measure" >&2
        exit 0
        ;;
esac
