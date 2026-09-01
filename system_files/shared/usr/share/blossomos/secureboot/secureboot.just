export JUST_JUSTFILE := justfile()

[private]
default:
    #!/usr/bin/env bash
    sudo mokutil --import /usr/share/blossomos/secureboot/blossomos-secureboot.der
