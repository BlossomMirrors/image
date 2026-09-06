# BlossomOS Image

[![pipeline status](https://dev.blossomos.org/blossom/os/core/image/badges/main/pipeline.svg)](https://dev.blossomos.org/blossom/os/core/image/-/commits/main)

BlossomOS is a Fedora-based bootable container image built on top of [Fedora Kinoite](https://fedoraproject.org/kinoite/) (KDE Plasma).

## Images

`latest` tags are published to `registry.blossomos.org/blossom/image-dev`. `main` and `prerelease` tags are published to `registry.blossomos.org/blossom/image`.

| Tag | Description |
|-----|-------------|
| `:latest` | Base desktop |
| `:latest-dx` | Developer experience variant |
| `:latest-nvidia` | NVIDIA open kernel module support (Turing and newer) |
| `:latest-nvidia-dx` | Developer experience + NVIDIA |
| `:latest-nvidia-legacy` | NVIDIA proprietary driver, 580 LTS branch (Maxwell, Pascal, Volta) |
| `:latest-nvidia-legacy-dx` | Developer experience + NVIDIA legacy |
| `:main` | Base desktop (release repo) |
| `:main-dx` | Developer experience (release repo) |
| `:main-nvidia` | NVIDIA (release repo) |
| `:main-nvidia-dx` | Developer experience + NVIDIA (release repo) |
| `:main-nvidia-legacy` | NVIDIA legacy (release repo) |
| `:main-nvidia-legacy-dx` | Developer experience + NVIDIA legacy (release repo) |

`latest` tags use the in-development package repo. `main` tags use the stable release repo and are built on manual trigger.

## Repository layout

```
Containerfile.in     # Templated Containerfile (preprocessed per variant via #if defined blocks)
Justfile             # Build, rechunk, and utility recipes
build.sh             # CI entrypoint: build, rechunk, push, and sign all variants for a tag
build_files/
  base/               # Build-time scripts run inside the container (packages, kernel/akmods, etc.)
  dx/                 # Developer experience variant scripts
  shared/             # Scripts shared across variants
system_files/
  shared/             # Runtime system files copied to / in the image
image-versions.yml    # Pinned digests/versions (brew image, Plasma snapshot, etc.)
```

## Building locally

Requires [Just](https://github.com/casey/just), Podman (v4+) or Docker, and `yq`.

```sh
# Build a variant: just build [image] [fedora-tag] [flavor]
just build blossomos latest main
just build blossomos-dx latest main
just build blossomos latest nvidia-open
just build blossomos latest nvidia-legacy
```

`image` is `blossomos` or `blossomos-dx`, `fedora-tag` is `stable`, `latest`, or `beta`, and `flavor` is `main`, `nvidia-open`, or `nvidia-legacy`.

To reproduce a full CI build (build, rechunk, tag, push, and cosign-sign every variant for a registry tag), use `./build.sh [main|latest|prerelease] [generic|nvidia|nvidia-legacy]`; this requires registry credentials and the cosign/secure boot signing keys.

## Verification

Images are signed with cosign. Verify with the included public key, for example:

```sh
cosign verify --key cosign.pub registry.blossomos.org/blossom/image:main
```

## License

[Apache 2.0](LICENSE)
