export JUST_JUSTFILE := justfile()

enroll-mok:
    #!/usr/bin/env bash
    sudo mokutil --import /usr/share/blossomos/secureboot/blossomos-secureboot.der
