#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-02-10 23:18:47 +0000 (Wed, 10 Feb 2016)
#
#  https://github.com/harisekhon
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

export DOCKER_CONTAINER="nagios-plugins-tachyon"
TACHYON_HOST="${TACHYON_HOST:-${HOST:-localhost}}"
export TACHYON_MASTER_PORT="${TACHYON_MASTER_PORT:-19999}"
export TACHYON_WORKER_PORT="${TACHYON_WORKER_PORT:-30000}"

if ! which docker &>/dev/null; then
    echo 'WARNING: Docker not found, skipping tachyon checks!!!'
    exit 0
fi

hr
echo "Setting up test tachyon container"
hr
# reuse container it's faster
#docker rm -f "$DOCKER_CONTAINER" &>/dev/null
#sleep 1
if ! docker ps | tee /dev/stderr | grep -q "[[:space:]]$DOCKER_CONTAINER$"; then
    hr
    echo "Starting Docker tachyon test container"
    # need tty for sudo which tachyon-start.sh local uses while ssh'ing localhost
    docker run -d -t --name "$DOCKER_CONTAINER" -p $TACHYON_MASTER_PORT:$TACHYON_MASTER_PORT -p $TACHYON_WORKER_PORT:$TACHYON_WORKER_PORT harisekhon/tachyon
    echo "waiting 10 seconds for Tachyon Master + Worker to become responsive..."
    sleep 10
else
    echo "Docker tachyon test container already running"
fi

hr
./check_tachyon_master.py
hr
./check_tachyon_worker.py
hr
./check_tachyon_running_workers.py
hr
./check_tachyon_dead_workers.py
hr
echo
echo -n "Deleting container "
docker rm -f "$DOCKER_CONTAINER"
echo; echo
