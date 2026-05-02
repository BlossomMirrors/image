# BlossomOS Image

[![Build Status](https://ci.blossomos.org/api/badges/1/status.svg)](https://ci.blossomos.org)

BlossomOS is a Fedora-based bootable container image built on top of [Fedora Kinoite](https://fedoraproject.org/kinoite/) (KDE Plasma), using [Universal Blue](https://universal-blue.org/) tooling.

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

## Building

Requires [just](https://just.systems/) and Podman (or Docker).

```sh
# Build base image
just build blossomos latest main

# Build dx variant
just build blossomos-dx latest main

# Build with NVIDIA support
just build blossomos latest nvidia-open
```

## Verification

Images are signed with cosign. Verify with the included public key:

```sh
cosign verify --key cosign.pub git.blossomos.org/blossom/image:latest
```

## License

[Apache 2.0](LICENSE)
