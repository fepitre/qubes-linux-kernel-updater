#!/bin/bash
# vim: set ts=4 sw=4 sts=4 et :

set -e
set -o pipefail

LOCALDIR="$(readlink -f "$(dirname "$0")")"
BUILDDIR="$(mktemp -d -p /home/user)"
TMPDIR="$BUILDDIR/gui-agent-linux"

GIT_UPSTREAM='QubesOS'
GIT_FORK='fepitre-bot'
GIT_BASEURL_UPSTREAM="https://github.com"
GIT_PREFIX_UPSTREAM="$GIT_UPSTREAM/qubes-"
GIT_BASEURL_FORK="git@github.com:"
GIT_PREFIX_FORK="$GIT_FORK/qubes-"

VARS='GITHUB_API_TOKEN GIT_UPSTREAM GIT_BASEURL_UPSTREAM GIT_PREFIX_UPSTREAM GIT_FORK GIT_BASEURL_FORK GIT_PREFIX_FORK'

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
        echo "-> An error occurred during build. Manual update is required"
    fi
    exit "${exit_code}"
}

trap 'exit_launcher' 0 1 2 3 6 15

git clone "${GIT_BASEURL_UPSTREAM}/${GIT_PREFIX_UPSTREAM}gui-agent-linux" "$TMPDIR"
git clone "${GIT_BASEURL_UPSTREAM}/${GIT_PREFIX_UPSTREAM}builder-rpm" "$BUILDDIR/builder-rpm"  # for keys only

cd "$TMPDIR"
export DNF_OPTS="--setopt=reposdir=$LOCALDIR/repos"
./get-latest-pulsecore.sh

LATEST_PULSE_VERSION="$(git status --short | sed 's|.*pulse/pulsecore-\(.*\)/|\1|')"
if [ -n "$LATEST_PULSE_VERSION" ]; then
    HEAD_BRANCH="update-v$LATEST_PULSE_VERSION"
    git checkout -b "$HEAD_BRANCH"
    git add pulse
    git commit -m "Add pulseaudio-$LATEST_PULSE_VERSION headers"
    git remote add fork "${GIT_BASEURL_FORK}${GIT_PREFIX_FORK}gui-agent-linux"
    git push -u fork "$HEAD_BRANCH"

    "$LOCALDIR/github-updater.py" \
        --create-pullrequest \
        --repo qubes-gui-agent-linux \
        --base "$GIT_UPSTREAM:master" \
        --head "$GIT_FORK:$HEAD_BRANCH" \
        --version="$LATEST_PULSE_VERSION"
fi
