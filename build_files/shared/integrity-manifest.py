#!/usr/bin/python3
"""Build the BlossomOS integrity attestation predicate for an image.

build.sh runs this inside the freshly built (rechunked) image and attaches the
result to the pushed digest with `cosign attest`. It holds the reference
values a remote verifier compares a TPM quote against (see docs/INTEGRITY.md):

  kernels[].initramfs_sha256  GRUB measures the initramfs file into PCR 9
  kernels[].vmlinuz_sha256    likewise for the kernel
  ima.files                   sha256 of every executable, shared library and
                              kernel module in /usr, for checking the IMA log
                              (PCR 10) an integrity-mode boot produces
"""

import argparse
import base64
import gzip
import hashlib
import json
import os
import stat

MODULE_SUFFIXES = (".ko", ".ko.xz", ".ko.zst", ".ko.gz")
IMA_POLICY = "/usr/lib/blossomos/integrity/ima-policy"


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def measurable(path, st):
    """What the integrity-mode IMA policy can measure: exec'd files,
    executable mappings and kernel modules."""
    if st.st_mode & 0o111:
        return True
    name = os.path.basename(path)
    if name.endswith(".so") or ".so." in name or name.endswith(MODULE_SUFFIXES):
        return True
    try:
        with open(path, "rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False


def usr_manifest():
    lines = []
    for root, dirs, files in os.walk("/usr"):
        dirs.sort()
        for name in files:
            path = os.path.join(root, name)
            st = os.lstat(path)
            if stat.S_ISREG(st.st_mode) and measurable(path, st):
                lines.append(f"{sha256(path)}  {path}")
    lines.sort(key=lambda l: l[66:])
    return lines


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

    files = usr_manifest()
    predicate = {
        "schema": "https://blossomos.org/integrity/v1",
        "image": {"repository": args.repository, "digest": args.digest, "tag": args.tag},
        "kernels": kernels(),
        "ima": {
            "policy_sha256": sha256(IMA_POLICY),
            "files": {
                "format": "sha256sum",
                "encoding": "gzip+base64",
                "count": len(files),
                "content": base64.b64encode(
                    gzip.compress(("\n".join(files) + "\n").encode(), mtime=0)
                ).decode(),
            },
        },
    }
    with open(args.out, "w") as f:
        json.dump(predicate, f, indent=1)
        f.write("\n")


if __name__ == "__main__":
    main()
