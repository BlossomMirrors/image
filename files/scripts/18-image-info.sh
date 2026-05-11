#!/usr/bin/env bash

echo "::group:: ===$(basename "$0")==="

set -ouex pipefail

mkdir -p /usr/share/ublue-os/

# These variables were previously injected as Containerfile ARGs.
# BlueBuild sets IMAGE_NAME automatically from the recipe name field.
# OS_VERSION is set by BlueBuild to the base image VERSION_ID.
IMAGE_NAME="${IMAGE_NAME:-blossomos}"
IMAGE_VENDOR="${IMAGE_VENDOR:-blossomos}"
FEDORA_MAJOR_VERSION="${FEDORA_MAJOR_VERSION:-${OS_VERSION:-44}}"
UBLUE_IMAGE_TAG="${UBLUE_IMAGE_TAG:-latest}"
SHA_HEAD_SHORT="${SHA_HEAD_SHORT:-}"
if [[ -z "${BASE_IMAGE_NAME:-}" ]]; then
  if [[ "${IMAGE_NAME}" =~ nvidia ]]; then
    BASE_IMAGE_NAME="kinoite-nvidia"
  else
    BASE_IMAGE_NAME="kinoite-main"
  fi
fi

IMAGE_PRETTY_NAME="BlossomOS"
IMAGE_LIKE="fedora"
HOME_URL="https://blossomos.org/"
DOCUMENTATION_URL="https://docs.blossomos.org"
SUPPORT_URL="https://community.blossomos.org"
BUG_SUPPORT_URL="https://community.blossomos.org"
CODE_NAME="Sakura"
VERSION="${VERSION:-00.00000000}"

IMAGE_INFO="/usr/share/ublue-os/image-info.json"
IMAGE_REF="${IMAGE_REF:-ostree-image-signed:docker://registry.blossomos.org/blossomos/$IMAGE_NAME}"

# Image Flavor
image_flavor="main"
if [[ "${IMAGE_NAME}" =~ nvidia-open ]]; then
  image_flavor="nvidia-open"
fi

cat >$IMAGE_INFO <<EOF
{
  "image-name": "$IMAGE_NAME",
  "image-flavor": "$image_flavor",
  "image-vendor": "$IMAGE_VENDOR",
  "image-ref": "$IMAGE_REF",
  "image-tag":"$UBLUE_IMAGE_TAG",
  "base-image-name": "$BASE_IMAGE_NAME",
  "fedora-version": "$FEDORA_MAJOR_VERSION"
}
EOF

# OS Release File
sed -i "s|^VARIANT_ID=.*|VARIANT_ID=$IMAGE_NAME|" /usr/lib/os-release
sed -i "s|^PRETTY_NAME=.*|PRETTY_NAME=\"${IMAGE_PRETTY_NAME} (Version: ${VERSION})\"|" /usr/lib/os-release

if [[ "${UBLUE_IMAGE_TAG}" == "beta" ]]; then
  sed -i "s|^RELEASE_TYPE=.*|RELEASE_TYPE=${UBLUE_IMAGE_TAG}|" /usr/lib/os-release
fi

sed -i "s|^NAME=.*|NAME=\"$IMAGE_PRETTY_NAME\"|" /usr/lib/os-release
sed -i "s|^HOME_URL=.*|HOME_URL=\"$HOME_URL\"|" /usr/lib/os-release
sed -i "s|^DOCUMENTATION_URL=.*|DOCUMENTATION_URL=\"$DOCUMENTATION_URL\"|" /usr/lib/os-release
sed -i "s|^SUPPORT_URL=.*|SUPPORT_URL=\"$SUPPORT_URL\"|" /usr/lib/os-release
sed -i "s|^BUG_REPORT_URL=.*|BUG_REPORT_URL=\"$BUG_SUPPORT_URL\"|" /usr/lib/os-release
sed -i "s|^CPE_NAME=\"cpe:/o:fedoraproject:fedora|CPE_NAME=\"cpe:/o:blossomos:${IMAGE_PRETTY_NAME,}|" /usr/lib/os-release
sed -i "s|^DEFAULT_HOSTNAME=.*|DEFAULT_HOSTNAME=\"blossomos,\"|" /usr/lib/os-release
sed -i "s|^ID=fedora|ID=${IMAGE_PRETTY_NAME,}\nID_LIKE=\"${IMAGE_LIKE}\"|" /usr/lib/os-release
sed -i "/^REDHAT_BUGZILLA_PRODUCT=/d; /^REDHAT_BUGZILLA_PRODUCT_VERSION=/d; /^REDHAT_SUPPORT_PRODUCT=/d; /^REDHAT_SUPPORT_PRODUCT_VERSION=/d" /usr/lib/os-release
sed -i "s|^VERSION_CODENAME=.*|VERSION_CODENAME=\"$CODE_NAME\"|" /usr/lib/os-release
sed -i "s|^VERSION=.*|VERSION=\"${VERSION} (${BASE_IMAGE_NAME^})\"|" /usr/lib/os-release
sed -i "s|^OSTREE_VERSION=.*|OSTREE_VERSION=\'${VERSION}\'|" /usr/lib/os-release

if [[ -n "${SHA_HEAD_SHORT:-}" ]]; then
echo "BUILD_ID=\"$SHA_HEAD_SHORT\"" >>/usr/lib/os-release
fi

# Added in systemd 249.
# https://www.freedesktop.org/software/systemd/man/latest/os-release.html#IMAGE_ID=
echo "IMAGE_ID=\"${IMAGE_NAME}\"" >> /usr/lib/os-release
echo "IMAGE_VERSION=\"${VERSION}\"" >> /usr/lib/os-release

# Debugging
cat /usr/lib/os-release

# Fix issues caused by ID no longer being fedora
sed -i "s|^EFIDIR=.*|EFIDIR=\"fedora\"|" /usr/sbin/grub2-switch-to-blscfg

echo "::endgroup::"
