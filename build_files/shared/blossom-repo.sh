#!/usr/bin/bash
set -euo pipefail

BLOSSOM_REPO_ID="blossomos-main"

blossom_repo_setup() {
    local repo_url="${BLOSSOM_REPO_URL:-https://repo.blossomos.org/rpm/}"

    if [[ -f /etc/yum.repos.d/blossom.repo ]]; then
        return
    fi

    # The repos are split by Fedora release (e.g. rpm-testing/45/), so an F44
    # build never picks up packages built against F45. A repo that isn't
    # split (yet) is used as is. Anything but "there" or "not there" fails
    # the build, so a network hiccup can't fall back to the wrong release.
    local fedora="${FEDORA_MAJOR_VERSION:-$(rpm -E %fedora)}"
    local versioned="${repo_url%/}/${fedora}/"
    local status
    status="$(curl -sS -o /dev/null -w '%{http_code}' --retry 3 "${versioned}repodata/repomd.xml" || true)"
    case "${status}" in
        200) repo_url="${versioned}" ;;
        404) echo "BlossomOS repo has no ${fedora}/ folder, using ${repo_url} as is" ;;
        *)
            echo "ERROR: checking ${versioned} returned HTTP ${status}" >&2
            return 1
            ;;
    esac
    echo "Using BlossomOS repo ${repo_url}"

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
