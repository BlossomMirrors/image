# check this system against the Easy Anti-Cheat Linux v2 requirements
eac-check:
    #!/usr/bin/env bash

    FAILED=0
    pass() { gum style --foreground 2 "✔ $1"; }
    fail() { gum style --foreground 1 "✘ $1"; [[ -n "${2:-}" ]] && gum style --faint "  $2"; FAILED=1; }
    warn() { gum style --foreground 3 "! $1"; [[ -n "${2:-}" ]] && gum style --faint "  $2"; }

    # 1. signed kernel & kernel modules
    # taint bit 13 (E) = an unsigned module got loaded
    if (( $(cat /proc/sys/kernel/tainted) & (1 << 13) )); then
        fail "Unsigned kernel module loaded" "$(grep -l E /sys/module/*/taint 2>/dev/null | cut -d/ -f4 | tr '\n' ' ')"
    else
        pass "No unsigned kernel modules loaded"
    fi

    # 2. TPM 2.0
    if [[ "$(cat /sys/class/tpm/tpm0/tpm_version_major 2>/dev/null)" == "2" ]]; then
        pass "TPM 2.0 present"
    else
        fail "No TPM 2.0 found" "Enable the TPM (fTPM / PTT) in your firmware settings"
    fi

    # 3. secure boot
    if mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"; then
        pass "Secure Boot enabled"
    else
        fail "Secure Boot disabled" "Enable Secure Boot in your firmware settings and run: adjust secureboot enroll-mok"
    fi

    # 4. measured boot - grub2 measures the kernel and cmdline into PCR 8/9
    if [[ -s /sys/kernel/security/tpm0/binary_bios_measurements ]] &&
        sudo tpm2_eventlog /sys/kernel/security/tpm0/binary_bios_measurements 2>/dev/null | grep -qE 'PCRIndex: (8|9)$'; then
        pass "Measured boot log present"
    else
        fail "No measured boot log from the boot loader"
    fi

    # 5. IOMMU, no passthrough
    if [[ -z "$(ls -A /sys/class/iommu 2>/dev/null)" ]]; then
        fail "IOMMU not active" "Enable VT-d / AMD-Vi (IOMMU) in your firmware settings"
    elif grep -qwE 'iommu=pt|iommu.passthrough=1' /proc/cmdline; then
        fail "IOMMU in passthrough mode" "Remove iommu=pt / iommu.passthrough=1 from the kernel command line"
    else
        pass "IOMMU active with DMA translation"
        # some drivers (e.g. amdgpu on some ASICs) still ask for an identity
        # domain for their own device, which is not a global passthrough
        for group in $(grep -lx identity /sys/kernel/iommu_groups/*/type 2>/dev/null | cut -d/ -f5); do
            for dev in /sys/kernel/iommu_groups/"$group"/devices/*; do
                warn "Identity mapped by its driver: $(lspci -s "${dev##*/}" 2>/dev/null || echo "${dev##*/}")"
            done
        done
    fi

    # 6. lockdown integrity, explicitly requested at boot
    if ! grep -qE '\[(integrity|confidentiality)\]' /sys/kernel/security/lockdown 2>/dev/null; then
        fail "Kernel lockdown not active"
    elif ! grep -qwE 'lockdown=(integrity|confidentiality)' /proc/cmdline; then
        fail "Kernel lockdown not set on the kernel command line" "Run: adjust grub add-karg lockdown=integrity"
    else
        pass "Kernel lockdown integrity mode"
    fi

    # 7. kexec disabled
    if [[ "$(cat /proc/sys/kernel/kexec_load_disabled)" == "1" ]]; then
        pass "kexec disabled"
    else
        fail "kexec enabled" "Run: adjust grub add-karg sysctl.kernel.kexec_load_disabled=1"
    fi

    # 8. BPF LSM
    if grep -qw bpf /sys/kernel/security/lsm; then
        pass "BPF LSM active"
    else
        fail "BPF LSM not active"
    fi

    echo
    if [[ "$FAILED" == "0" ]]; then
        gum style --foreground 2 --bold "This system meets the Easy Anti-Cheat Linux v2 requirements."
    else
        gum style --foreground 1 --bold "This system does not meet all Easy Anti-Cheat Linux v2 requirements."
    fi
    warn "Games also check the kernel is signed with a key on Epic's well-known list." "BlossomOS kernels and modules are signed with the BlossomOS Secure Boot key."
    exit "$FAILED"
