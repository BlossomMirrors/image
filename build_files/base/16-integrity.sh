#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# Public half of the key build.sh signs images with. containers-policy.json
# (below) and the installer verify BlossomOS images against it.
install -Dm0644 /ctx/cosign.pub /usr/lib/blossomos/integrity/cosign.pub

# Require signatures for BlossomOS images, keep everything else pullable
# (see blossomos-integrity's POLICY_TRANSPORTS). Same code the running system
# uses to repair a locally modified policy.json.
/usr/bin/blossomos-integrity ensure-policy --root /

# Existing installs track an ostree-unverified-registry: origin; this moves
# them onto ostree-image-signed: once the registry has a podman-compatible
# signature for the image.
systemctl enable blossomos-signed-origin.timer

# Integrity mode (blossomos.integrity=1, on by default for fresh installs, see
# the ISO) refuses to boot layered deployments, so lock layering instead.
systemctl enable blossomos-integrity-lock-layering.service

echo "::endgroup::"
