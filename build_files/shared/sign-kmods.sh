#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# Sign every out-of-tree kernel module with BlossomOS' secure boot key.
#
# akmods (xone, v4l2loopback, nvidia) has no signing key in the build
# container, so it leaves its modules unsigned. dkms (openrazer) signs with a
# throwaway key it generates on the spot. The precompiled kmods from the
# ublue-os akmods images (zfs) carry ublue's key. None of those verify under
# secure boot lockdown ("Loading of unsigned module is rejected" / "Key was
# rejected by service"), so re-sign all of them with the key whose cert is
# enrolled as a MOK via /usr/share/blossomos/secureboot.
#
# Must run in the same RUN step as, and after, whatever built the modules,
# with the SECUREBOOT_KEY secret mounted.

KREL="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
SIGN_FILE="/usr/src/kernels/${KREL}/scripts/sign-file"
SIGN_HASH="$(sed -n 's/^CONFIG_MODULE_SIG_HASH="\(.*\)"$/\1/p' "/usr/lib/modules/${KREL}/config")"
SIG_MAGIC=$'~Module signature appended~\n'

if [[ ! -f /run/secrets/SECUREBOOT_KEY ]]; then
    echo "WARNING: no secure boot signing key (secureboot.key) - out-of-tree kernel modules stay unsigned, secure boot will reject them"
    echo "::endgroup::"
    exit 0
fi

# Drop an existing appended signature, so the module ends up with exactly
# one: ours. Trailer layout is <sig><struct module_signature (12 bytes, sig
# length as a big-endian u32 in the last 4)><magic (28 bytes)>.
strip_module_sig() {
    local ko="$1" size siglen
    [[ "$(tail -c 28 "${ko}")" == "${SIG_MAGIC%$'\n'}" ]] || return 0
    size="$(stat -c %s "${ko}")"
    siglen="$(tail -c 32 "${ko}" | head -c 4 | od -An -tu4 --endian=big | tr -d ' ')"
    truncate -s "$((size - siglen - 12 - 28))" "${ko}"
}

while IFS= read -r -d '' mod; do
    case "${mod}" in
    *.ko.xz)
        xz -d "${mod}"
        ko="${mod%.xz}"
        ;;
    *.ko)
        ko="${mod}"
        ;;
    *)
        continue
        ;;
    esac

    strip_module_sig "${ko}"
    "${SIGN_FILE}" "${SIGN_HASH}" /run/secrets/SECUREBOOT_KEY /ctx/secureboot.der "${ko}"

    if [[ "${mod}" == *.ko.xz ]]; then
        # Same xz parameters as the kernel's own modules, the in-kernel
        # decompressor only handles crc32 checks
        xz -f --check=crc32 --lzma2=dict=1MiB "${ko}"
    fi

    [[ "$(modinfo -F signer "${mod}")" == "BlossomOS Secure Boot" ]] ||
        { echo "Error: ${mod} did not end up signed by BlossomOS Secure Boot"; exit 1; }
done < <(find "/usr/lib/modules/${KREL}/extra" "/usr/lib/modules/${KREL}/updates" \
    -name '*.ko*' -print0 2>/dev/null)

depmod -a "${KREL}"

echo "::endgroup::"
