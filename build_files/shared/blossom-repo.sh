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
