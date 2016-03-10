#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-02-10 23:18:47 +0000 (Wed, 10 Feb 2016)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback
#
#  https://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x

srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/.."

. "$srcdir/utils.sh"

echo "
# ============================================================================ #
#                               T a c h y o n
# ============================================================================ #
"

TACHYON_HOST="${DOCKER_HOST:-${TACHYON_HOST:-${HOST:-localhost}}}"
TACHYON_HOST="${TACHYON_HOST##*/}"
TACHYON_HOST="${TACHYON_HOST%%:*}"
export TACHYON_HOST
echo "using docker address '$TACHYON_HOST'"
export TACHYON_MASTER_PORT="${TACHYON_MASTER_PORT:-19999}"
export TACHYON_WORKER_PORT="${TACHYON_WORKER_PORT:-30000}"

export DOCKER_CONTAINER="nagios-plugins-tachyon"

if ! which docker &>/dev/null; then
    echo 'WARNING: Docker not found, skipping tachyon checks!!!'
    exit 0
fi

startupwait=10
[ -n "${TRAVIS:-}" ] && let startupwait+=20

hr
echo "Setting up test tachyon container"
hr
# reuse container it's faster
#docker rm -f "$DOCKER_CONTAINER" &>/dev/null
#sleep 1
if ! is_docker_container_running "$DOCKER_CONTAINER"; then
    docker rm -f "$DOCKER_CONTAINER" &>/dev/null || :
    echo "Starting Docker tachyon test container"
    # need tty for sudo which tachyon-start.sh local uses while ssh'ing localhost
    docker run -d -t --name "$DOCKER_CONTAINER" -p $TACHYON_MASTER_PORT:$TACHYON_MASTER_PORT -p $TACHYON_WORKER_PORT:$TACHYON_WORKER_PORT harisekhon/tachyon
    echo "waiting $startupwait seconds for Tachyon Master + Worker to become responsive..."
    sleep $startupwait
else
    echo "Docker tachyon test container already running"
fi

hr
./check_tachyon_master.py -v
hr
#docker exec -ti "$DOCKER_CONTAINER" ps -ef
./check_tachyon_worker.py -v
hr
./check_tachyon_running_workers.py -v
hr
./check_tachyon_dead_workers.py -v
hr
echo
if [ -z "${NODELETE:-}" ]; then
    echo -n "Deleting container "
    docker rm -f "$DOCKER_CONTAINER"
fi
echo; echo
