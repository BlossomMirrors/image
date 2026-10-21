#!/usr/bin/python3
"""Build the BlossomOS integrity attestation predicate for an image.

build.sh runs this inside the freshly built (rechunked) image and attaches the
result to the pushed digest with `cosign attest`. It holds the reference
values a remote verifier compares a TPM quote against (see docs/INTEGRITY.md):

  kernels[].initramfs_sha256  GRUB measures the initramfs file into PCR 9
  kernels[].vmlinuz_sha256    likewise for the kernel
"""

import argparse
import hashlib
import json
import os


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def kernels():
    out = []
    moddir = "/usr/lib/modules"
    for kver in sorted(os.listdir(moddir)):
        vmlinuz = os.path.join(moddir, kver, "vmlinuz")
        initramfs = os.path.join(moddir, kver, "initramfs.img")
        if not os.path.exists(vmlinuz):
            continue
        out.append({
            "release": kver,
            "vmlinuz_sha256": sha256(vmlinuz),
            "initramfs_sha256": sha256(initramfs) if os.path.exists(initramfs) else None,
        })
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--repository", required=True)
    p.add_argument("--digest", required=True)
    p.add_argument("--tag", required=True)
    p.add_argument("--out", required=True)
    args = p.parse_args()

    predicate = {
        "schema": "https://blossomos.org/integrity/v1",
        "image": {"repository": args.repository, "digest": args.digest, "tag": args.tag},
        "kernels": kernels(),
    }
    with open(args.out, "w") as f:
        json.dump(predicate, f, indent=1)
        f.write("\n")


if __name__ == "__main__":
    main()
