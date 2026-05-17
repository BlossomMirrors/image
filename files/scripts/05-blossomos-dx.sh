#!/usr/bin/env bash

echo "::group:: ===$(basename "$0")==="

set -ouex pipefail

# Install BlossomOS SDK package from the already-configured BlossomOS repo
dnf5 -y install \
    --enablerepo="blossomos-main" \
    blossomos-sdk

echo "::endgroup::"
