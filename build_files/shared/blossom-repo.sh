#!/usr/bin/bash
set -euo pipefail

BLOSSOM_REPO_ID="blossomos-main"

blossom_repo_setup() {
    local repo_url="${BLOSSOM_REPO_URL:-https://repo.blossomos.org/rpm/}"

    if [[ -f /etc/yum.repos.d/blossom.repo ]]; then
        return
    fi

    rpm --import https://repo.blossomos.org/BLOSSOMOS-GPG-KEY.pub

    cat > /etc/yum.repos.d/blossom.repo << EOF
[${BLOSSOM_REPO_ID}]
name=BlossomOS Main
baseurl=${repo_url}
enabled=0
gpgcheck=1
gpgkey=https://repo.blossomos.org/BLOSSOMOS-GPG-KEY.pub
EOF
}

# Compare two EVR strings ("E:V-R"); prints -1, 0 or 1 like rpmvercmp
blossom_vercmp() {
    rpm --eval "%{lua: print(rpm.vercmp('$1', '$2'))}"
}

# Installed packages as "name.arch E:V-R", skipping multi-instance names
# (gpg-pubkey, kernels) which can't be compared one-to-one
_blossom_rpm_snapshot() {
    rpm -qa --qf '%{NAME}.%{ARCH} %{EPOCHNUM}:%{VERSION}-%{RELEASE}\n' \
        | awk '{ n[$1]++; v[$1] = $0 } END { for (k in n) if (n[k] == 1) print v[k] }' \
        | LC_ALL=C sort
}

# Replace stock packages with our patched builds from the BlossomOS repo.
#   blossom_replace_pkg [--replacefiles] <pkg>...
# Fails the build if a stock package is the same or newer than ours (dnf5
# would silently keep the stock one), if our build didn't end up installed,
# or if the transaction downgraded anything.
# --replacefiles installs via `rpm -i --replacefiles` for overlay packages
# whose files are owned by another package.
blossom_replace_pkg() {
    local replacefiles=0
    if [[ "${1:-}" == "--replacefiles" ]]; then
        replacefiles=1
        shift
    fi

    local dir
    dir="$(mktemp -d /tmp/blossom-replace.XXXXXX)"
    dnf5 download --destdir="${dir}" --disablerepo='*' --enablerepo="${BLOSSOM_REPO_ID}" "$@"

    local rpmf name new old fail=0
    local -a expected=()
    for rpmf in "${dir}"/*.rpm; do
        name="$(rpm -qp --qf '%{NAME}' "${rpmf}")"
        new="$(rpm -qp --qf '%{EPOCHNUM}:%{VERSION}-%{RELEASE}' "${rpmf}")"
        expected+=("${name} ${new}")
        while read -r old; do
            [[ -n "${old}" ]] || continue
            if (( $(blossom_vercmp "${old}" "${new}") >= 0 )); then
                echo "ERROR: ${name}: installed ${old} is not older than BlossomOS build ${new}; our patched build would not be applied. Rebuild ${name} against the current base." >&2
                fail=1
            fi
        done < <(rpm -q --qf '%{EPOCHNUM}:%{VERSION}-%{RELEASE}\n' "${name}" 2>/dev/null || true)
    done
    if (( fail )); then
        rm -rf "${dir}"
        return 1
    fi

    local before after
    before="$(_blossom_rpm_snapshot)"
    if (( replacefiles )); then
        rpm -i --replacefiles "${dir}"/*.rpm
    else
        dnf5 install -y "${dir}"/*.rpm
    fi
    after="$(_blossom_rpm_snapshot)"
    rm -rf "${dir}"

    local entry evr
    for entry in "${expected[@]}"; do
        read -r name new <<< "${entry}"
        if ! rpm -q --qf '%{EPOCHNUM}:%{VERSION}-%{RELEASE}\n' "${name}" | grep -qxF "${new}"; then
            echo "ERROR: ${name} ${new} from BlossomOS repo is not installed after replacement" >&2
            fail=1
        fi
    done

    local pkg
    while read -r pkg old evr; do
        if (( $(blossom_vercmp "${old}" "${evr}") > 0 )); then
            echo "ERROR: ${pkg} was downgraded from ${old} to ${evr} while replacing $*" >&2
            fail=1
        fi
    done < <(LC_ALL=C join <(echo "${before}") <(echo "${after}"))

    return "${fail}"
}
