#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-10-07 13:41:58 +0100 (Wed, 07 Oct 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help improve or steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

# shellcheck disable=SC1090
. "$srcdir/utils.sh"

section "G e n t o o"

echo "NOT READY YET", skipping...
exit 0

export DOCKER_IMAGE="gentoo/stage3-amd64"
export DOCKER_CONTAINER="nagios-plugins-gentoo-test"

export DOCKER_MOUNT_DIR="/tmp/nagios-plugins"

if ! is_docker_available; then
    echo 'WARNING: Docker not found, skipping Gentoo checks!!!'
    exit 0
fi

#trap "docker rm -f $DOCKER_CONTAINER &>/dev/null" SIGINT SIGTERM EXIT

startupwait 0

if ! is_docker_available; then
    echo 'WARNING: Docker not found, skipping Gentoo checks!!!'
    exit 0
fi

if is_CI; then
    # want splitting
    # shellcheck disable=SC2086
    trap 'docker_rmi_grep gentoo' $TRAP_SIGNALS
fi

echo "Setting up Gentoo test container"
export DOCKER_OPTS="-v $srcdir/..:$DOCKER_MOUNT_DIR"
export DOCKER_CMD="tail -f /dev/null"
launch_container "$DOCKER_IMAGE" "$DOCKER_CONTAINER"
#docker exec "$DOCKER_CONTAINER" yum makecache fast
if [ -n "${NOTESTS:-}" ]; then
    exit 0
fi
hr
docker_exec older/check_gentoo_portage.py --all-updates
hr
docker_exec older/check_gentoo_portage.py --warn-on-any-update
hr
delete_container
echo
echo "All Gentoo tests completed successfully"
echo
echo
