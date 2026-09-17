#!/usr/bin/bash

read -r message < /usr/lib/blossomos/bootmsg-text

plymouth display-message --text="$message" || :
