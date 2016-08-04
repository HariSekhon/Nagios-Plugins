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
#                                 A l l u x i o
# ============================================================================ #
"

export ALLUXIO_VERSIONS="${@:-${ALLUXIO_VERSIONS:-latest 1.0 1.1}}"

ALLUXIO_HOST="${DOCKER_HOST:-${ALLUXIO_HOST:-${HOST:-localhost}}}"
ALLUXIO_HOST="${ALLUXIO_HOST##*/}"
ALLUXIO_HOST="${ALLUXIO_HOST%%:*}"
export ALLUXIO_HOST

export ALLUXIO_MASTER_PORT="${ALLUXIO_MASTER_PORT:-19999}"
export ALLUXIO_WORKER_PORT="${ALLUXIO_WORKER_PORT:-30000}"

export DOCKER_IMAGE="harisekhon/alluxio"
export DOCKER_CONTAINER="nagios-plugins-alluxio-test"

startupwait=15

if ! is_docker_available; then
    echo 'WARNING: Docker not found, skipping Alluxio checks!!!'
    exit 0
fi

test_alluxio(){
    local version="$1"
    hr
    echo "Setting up Alluxio $version test container"
    hr
    launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $ALLUXIO_MASTER_PORT $ALLUXIO_WORKER_PORT
    if [ -n "${NOTESTS:-}" ]; then
        return 0
    fi
    if [ "$version" = "latest" ]; then
        local version=".*"
    fi
    hr
    ./check_alluxio_master_version.py -v -e "$version"
    hr
    ./check_alluxio_worker_version.py -v -e "$version"
    hr
    ./check_alluxio_master.py -v
    hr
    #docker exec -ti "$DOCKER_CONTAINER" ps -ef
    ./check_alluxio_worker.py -v
    hr
    ./check_alluxio_running_workers.py -v
    hr
    ./check_alluxio_dead_workers.py -v
    hr
    delete_container
    echo
}

for version in $(ci_sample $ALLUXIO_VERSIONS); do
    test_alluxio $version
done
