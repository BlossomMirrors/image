#!/usr/bin/bash

type getargbool >/dev/null 2>&1 || . /lib/dracut-lib.sh

getargbool 1 rd.blossomos.bootmsg || exit 0

plymouth --ping >/dev/null 2>&1 || exit 0

# plymouthd survives switch-root, so this stays up for the whole boot
plymouth display-message --text="0.3.0 Alpha"
