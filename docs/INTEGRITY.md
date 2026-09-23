# BlossomOS integrity and remote attestation

This describes what BlossomOS guarantees about a running system, and how
software that needs to trust it (for example a game's anti-cheat) can check
those guarantees, locally or remotely with a TPM quote.

It answers three questions:

1. Is the booted image a signed BlossomOS image?
2. Can an unsigned image boot?
3. Is `/usr` unlocked, overlaid or otherwise modified?

## What is enforced

| | Always | Integrity mode (`blossomos.integrity=1`, default on new installs) |
|---|---|---|
| Updates and image switches require a valid cosign signature | ✅ (`ostree-image-signed:` origin, `containers-policy.json`) | ✅ |
| Installer refuses to install an image without a valid signature | ✅ | ✅ |
| Booted image, signature state, `/usr` state and layering are recorded in TPM PCR 15 | ✅ (if a TPM is present) | ✅ |
| Boot is refused for unsigned, unlocked (`hotfix`) or layered deployments | | ✅ |
| rpm-ostree layering and overrides are locked | | ✅ |
| Every executed program, executable mapping and kernel module is hashed into PCR 10 (IMA) | | ✅ |

Integrity mode is on by default for systems installed from an ISO that
includes this, as long as the installed image has the boot gate and a
signature-enforced origin (the installer checks both). Existing installs can
turn it on with `adjust integrity on`. Either way, `adjust integrity off`
turns it off again; software that checks integrity will then treat the
system as untrusted.

While integrity mode is on, rpm-ostree layering and overrides are locked
(`LockLayering=true` in `/etc/rpm-ostreed.conf`, kept in place at every boot
by `blossomos-integrity-lock-layering.service`), since the boot gate would
refuse the resulting deployment anyway. Use distrobox (`adjust pkglayer`) or
Flatpak instead, or turn integrity mode off.

The IMA log records every program that runs on the machine. It is readable by
root only and never leaves the machine unless software running as root hands
it to someone, for example as part of an attestation.

## Components

- **Image signing** (`build.sh`): every pushed digest gets a classic cosign
  signature (`sha256-<digest>.sig`, what podman/skopeo/bootc check) and a
  cosign 3 bundle, both made with the key whose public half is `cosign.pub`.
- **Signature policy** (`build_files/base/16-integrity.sh`,
  `/etc/containers/policy.json`, `/etc/containers/registries.d/blossomos.yaml`):
  `registry.blossomos.org/blossom/image` and `image-dev` require a signature
  from `/usr/lib/blossomos/integrity/cosign.pub`; the default is `reject` with
  explicit accept-anything entries for every transport so other registries
  keep working.
- **Origin migration** (`blossomos-signed-origin.timer`): moves installs from
  `ostree-unverified-registry:` to `ostree-image-signed:` once a classic
  signature is available for their image. `adjust devmode toggle` switches
  with enforcement too.
- **Installer** (ISO repository): verifies the signature of the digest it
  actually installed, aborts the install otherwise, and sets up the signed
  origin.
- **Initramfs module** (`98blossomos-integrity`): the initramfs is part of the
  signed image and measured by GRUB into PCR 9, so what it records can be
  trusted. It measures the deployment into PCR 15, loads the IMA policy and
  gates the boot in integrity mode.
- **Reference values** (`build_files/shared/integrity-manifest.py`): attached
  to every digest as a cosign attestation of type
  `https://blossomos.org/integrity/v1`.
- **`blossomos-integrity`**: local status (`check`), TPM quotes (`attest`,
  `activate`), signature verification and policy maintenance.

## Local check

```sh
blossomos-integrity check --json        # exit code 0 = trusted
blossomos-integrity check --online      # also re-verify the digest's signature
```

`trusted` is true only with no `reasons`. Possible reasons:
`secure-boot-disabled`, `kernel-lockdown-off`, `no-tpm`,
`image-origin-not-signature-verified`, `image-not-from-blossomos`,
`signature-policy-missing`, `image-digest-signature-invalid`,
`usr-unlocked`, `usr-layered`, `ld-so-preload`, `integrity-mode-off`,
`ima-policy-not-loaded`, `boot-not-measured`, `boot-gate-not-passed`.

A local check is only as honest as the kernel and root user it runs under.
Anything that must hold against the machine's owner needs the remote
attestation below.

## Remote attestation

As root on the client, with a nonce chosen by the verifier:

```sh
blossomos-integrity attest --nonce <hex> --out <dir>
```

The bundle contains:

| File | Content |
|---|---|
| `ek.pem`, `ek.crt` | Endorsement key and, if the TPM has one, its vendor certificate |
| `ak.pem`, `ak.name` | Attestation key (ECC P-256, persistent handle `0x81000b10`) |
| `quote.msg`, `quote.sig`, `quote.pcrs` | `TPM2_Quote` over SHA-256 PCRs 0-15 with the nonce |
| `tcg-eventlog.bin` | Firmware/shim/GRUB event log (PCRs 0-9, 14) |
| `ima-log.bin` | IMA binary measurement list (PCR 10) |
| `systemd-tpm2-measure.log` | systemd's JSON-SEQ event log, holds the PCR 15 events |
| `status.json` | `blossomos-integrity check --json` at quote time (informational) |

The first time a verifier sees an attestation key it should bind it to the EK
with `TPM2_MakeCredential`; the client answers with
`blossomos-integrity activate --credential <blob> --secret-out <file>`.

### Verifier procedure

1. Trust the TPM: check `ek.crt` against TPM vendor roots and bind `ak.pem`
   to the EK via MakeCredential/ActivateCredential.
2. Check `quote.sig` with `ak.pem`, the nonce, and that the quoted PCR digest
   matches `quote.pcrs`.
3. Replay `tcg-eventlog.bin` against PCRs 0-9 and 14:
   - PCR 7: Secure Boot enabled, and the db/MokList contain the BlossomOS
     key (`secureboot.der`) and nothing unexpected.
   - PCR 4/9: the loaded kernel and initramfs match `kernels[]` of the image
     attestation below. The initramfs is what enforces everything else.
   - PCR 8: the kernel command line (GRUB records it). Check for
     `blossomos.integrity=1` and no `lockdown=none`, `ima_policy=`,
     `init=`, `rd.break` or similar.
4. Replay `systemd-tpm2-measure.log` against PCR 15. BlossomOS writes these
   events, in this order, once per boot:

   ```
   blossomos-integrity:v1
   blossomos-image:<origin, e.g. ostree-image-signed:docker://registry.blossomos.org/blossom/image:main>
   blossomos-manifest-digest:<sha256:...>
   blossomos-signature:signed|unsigned
   blossomos-usr:none|hotfix|development|transient
   blossomos-modified:none|<comma separated: packages,overrides,modules,initramfs,initramfs-etc>
   blossomos-mode:enforcing|off
   blossomos-gate:pass|fail
   ```

   Require `signature:signed`, `usr:none`, `modified:none`,
   `mode:enforcing` and `gate:pass`.
5. Fetch the image attestation for the measured manifest digest and verify it
   with `cosign.pub`:

   ```sh
   cosign verify-attestation --key cosign.pub --insecure-ignore-tlog=true \
       --type https://blossomos.org/integrity/v1 \
       registry.blossomos.org/blossom/image@<digest>
   ```

   The predicate's `ima.files.content` is a gzip'd, base64'd `sha256sum`
   list of every measurable file in `/usr`.
6. Replay `ima-log.bin` against PCR 10 and check every entry's hash against
   that list. Anything else (a binary from an unlocked `/usr` overlay,
   `/var/usrlocal`, `/tmp`, a user's home directory, ...) is code BlossomOS
   didn't ship; decide per path what is acceptable (a game's own files will
   show up here too). `CRITICAL_DATA` entries show SELinux being disabled or
   its policy changing.

## Limitations

- `/usr` is not sealed on disk. Root can still unlock or overlay it, or boot
  a hand-made deployment with a forged origin. That is detected, not
  prevented: the initramfs records the deployment's real state, and IMA
  records whatever code actually runs. Preventing it outright needs sealed
  composefs images (UKI with the composefs digest, systemd-boot), which
  requires a reinstall.
- Files that are read rather than executed (configuration, Python modules,
  game data) are not measured.
- `/etc` is writable by root. Its effect on executed code shows up in the IMA
  log (e.g. `/etc/ld.so.preload`), but configuration changes do not.
- The kernel is BlossomOS' own build, signed with BlossomOS' key. A verifier
  has to decide to trust that key; it can't rely on Microsoft's or Fedora's
  signing alone.
- Hardware attacks (DMA devices, a hypervisor underneath) need IOMMU
  settings and physical-TPM checks outside the scope of this document.
