#!/bin/bash
# vim: set ts=4 sw=4 sts=4 et :

set -e
set -o pipefail

LOCALDIR="$(readlink -f "$(dirname "$0")")"
BUILDDIR="$(mktemp -d -p /home/user)"
KERNELDIR="$BUILDDIR/linux-kernel-${BRANCH_linux_kernel}"

GIT_UPSTREAM='QubesOS'
GIT_FORK='fepitre-bot'
GIT_BASEURL_UPSTREAM="https://github.com"
GIT_PREFIX_UPSTREAM="$GIT_UPSTREAM/qubes-"
GIT_BASEURL_FORK="git@github.com:"
GIT_PREFIX_FORK="$GIT_FORK/qubes-"

VARS='BRANCH_linux_kernel GITHUB_API_TOKEN GIT_UPSTREAM GIT_BASEURL_UPSTREAM GIT_PREFIX_UPSTREAM GIT_FORK GIT_BASEURL_FORK GIT_PREFIX_FORK'

# Check if necessary variables are defined in the environment
for var in $VARS; do
    if [ "x${!var}" = "x" ]; then
        echo "Please provide $var in env"
        exit 1
    fi
done

# Hide sensitive info
[ "$DEBUG" = "1" ] && set -x

exit_launcher() {
    local exit_code=$?
    sudo rm -rf "$BUILDDIR"
    if [ ${exit_code} -ge 1 ]; then
        echo "-> An error occurred during build. Manual update for kernel ${BRANCH_linux_kernel} is required"
    fi
    exit "${exit_code}"
}

trap 'exit_launcher' 0 1 2 3 6 15

UPDATE_NEEDED="$("$LOCALDIR"/github-updater.py --repo qubes-linux-kernel --check-update --base "$GIT_UPSTREAM:${BRANCH_linux_kernel:-master}")"
if [ -n "$UPDATE_NEEDED" ]; then
    git clone -b "${BRANCH_linux_kernel}" "${GIT_BASEURL_UPSTREAM}/${GIT_PREFIX_UPSTREAM}linux-kernel" "$KERNELDIR"
    git clone "${GIT_BASEURL_UPSTREAM}/${GIT_PREFIX_UPSTREAM}builder-rpm" "$BUILDDIR/builder-rpm"  # for keys only
    cd "$KERNELDIR"
    make update-sources BRANCH="${BRANCH_linux_kernel}"
    if [ -n "$(git diff version)" ]; then
        LATEST_KERNEL_VERSION="$(cat version)"
        HEAD_BRANCH="update-v$LATEST_KERNEL_VERSION"
        git checkout -b "$HEAD_BRANCH"
        echo 1 >rel
        git add version rel config-base
        git commit -m "Update to kernel-$LATEST_KERNEL_VERSION"
        git remote add fork "${GIT_BASEURL_FORK}${GIT_PREFIX_FORK}linux-kernel"
        git push -u fork "$HEAD_BRANCH"

        "$LOCALDIR/github-updater.py" \
            --create-pullrequest \
            --repo qubes-linux-kernel \
            --base "$GIT_UPSTREAM:${BRANCH_linux_kernel:-master}" \
            --head "$GIT_FORK:$HEAD_BRANCH"
    fi
fi
