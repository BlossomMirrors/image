#!/usr/bin/bash

check() {
    return 0
}

depends() {
    echo plymouth
    return 0
}

install() {
    inst_hook pre-mount 50 "$moddir/blossomos-bootmsg.sh"
}
