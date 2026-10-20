#!/usr/bin/bash

check() {
    return 0
}

depends() {
    echo systemd
    return 0
}

install() {
    inst_multiple awk basename cat grep head mkdir readlink sed sleep sort tail touch tr
    # ostree reads the image manifest digest, systemd-pcrextend (plus the
    # tpm2-tss libraries from 90-ublue-luks.conf's tpm2-tss module) measures
    inst_multiple -o ostree plymouth /usr/lib/systemd/systemd-pcrextend
    inst_simple /usr/lib/blossomos/integrity/ima-policy
    inst_simple /usr/lib/blossomos/integrity/signed-repos
    inst_script "$moddir/blossomos-integrity-initrd.sh" /usr/libexec/blossomos-integrity-initrd
    inst_simple "$moddir/blossomos-integrity-ima.service" \
        "$systemdsystemunitdir/blossomos-integrity-ima.service"
    inst_simple "$moddir/blossomos-integrity-measure.service" \
        "$systemdsystemunitdir/blossomos-integrity-measure.service"
    $SYSTEMCTL -q --root "$initdir" add-wants initrd.target blossomos-integrity-ima.service
    $SYSTEMCTL -q --root "$initdir" add-wants initrd.target blossomos-integrity-measure.service
}
