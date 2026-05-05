# BlossomOS Image

[![Build Status](https://ci.blossomos.org/api/badges/1/status.svg)](https://ci.blossomos.org)

BlossomOS is a Fedora-based bootable container image built on top of [Fedora Kinoite](https://fedoraproject.org/kinoite/) (KDE Plasma), using [BlueBuild](https://blue-build.org/) for declarative image configuration.

## Images

Published to `git.blossomos.org/blossom/image`.

| Tag | Description |
|-----|-------------|
| `:latest` | Base desktop |
| `:latest-dx` | Developer experience variant |
| `:latest-nvidia` | NVIDIA open kernel module support |
| `:latest-dx-nvidia` | Developer experience + NVIDIA |
| `:main` | Base desktop (release repo) |
| `:main-dx` | Developer experience (release repo) |
| `:main-nvidia` | NVIDIA (release repo) |
| `:main-dx-nvidia` | Developer experience + NVIDIA (release repo) |

`latest` tags use the in-development package repo. `main` tags use the stable release repo and are built on manual trigger.

## Repository layout

```
recipes/          # BlueBuild recipe files — one per image variant
  recipe.yml
  recipe-nvidia.yml
  recipe-dx.yml
  recipe-dx-nvidia.yml
files/
  scripts/        # Build-time scripts run inside the container
  system/         # Runtime system files copied to / in the image
  packages.dnf    # RPM package list
  packages.flatpak  # Flatpak preinstall list
```

## Building locally

Requires the [BlueBuild CLI](https://blue-build.org/learn/getting-started/) and Podman (v4+) or Buildah (v1.29+).

```sh
# Install the CLI
curl -fsSL -o /usr/local/bin/bluebuild \
  https://github.com/blue-build/cli/releases/latest/download/bluebuild-x86_64-unknown-linux-musl
chmod +x /usr/local/bin/bluebuild

# Build a variant
bluebuild build recipes/recipe.yml
bluebuild build recipes/recipe-dx.yml
bluebuild build recipes/recipe-nvidia.yml
bluebuild build recipes/recipe-dx-nvidia.yml
```

## Verification

Images are signed with cosign. Verify with the included public key:

```sh
cosign verify --key cosign.pub git.blossomos.org/blossom/image:latest
```

## License

[Apache 2.0](LICENSE)
