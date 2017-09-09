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
srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$srcdir/.."

. "$srcdir/utils.sh"

echo "
# ============================================================================ #
#                                 A l l u x i o
# ============================================================================ #
"

export ALLUXIO_VERSIONS="${@:-${ALLUXIO_VERSIONS:-latest 2.0 1.1}}"

ALLUXIO_HOST="${DOCKER_HOST:-${ALLUXIO_HOST:-${HOST:-localhost}}}"
ALLUXIO_HOST="${ALLUXIO_HOST##*/}"
ALLUXIO_HOST="${ALLUXIO_HOST%%:*}"
export ALLUXIO_HOST

export ALLUXIO_MASTER_PORT_DEFAULT="${ALLUXIO_MASTER_PORT:-19999}"
export ALLUXIO_WORKER_PORT_DEFAULT="${ALLUXIO_WORKER_PORT:-30000}"

startupwait 15

check_docker_available

trap_debug_env alluxio

test_alluxio(){
    local version="$1"
    hr
    echo "Setting up Alluxio $version test container"
    hr
    #launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $ALLUXIO_MASTER_PORT $ALLUXIO_WORKER_PORT
    VERSION="$version" docker-compose up -d
    export ALLUXIO_MASTER_PORT="`docker-compose port "$DOCKER_SERVICE" "$ALLUXIO_MASTER_PORT_DEFAULT" | sed 's/.*://'`"
    export ALLUXIO_WORKER_PORT="`docker-compose port "$DOCKER_SERVICE" "$ALLUXIO_WORKER_PORT_DEFAULT" | sed 's/.*://'`"
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    when_ports_available "$startupwait" "$ALLUXIO_HOST" "$ALLUXIO_MASTER_PORT" "$ALLUXIO_WORKER_PORT"
    if [ "$version" = "latest" ]; then
        local version=".*"
    fi
    hr
    echo "retrying for $startupwait secs to give Alluxio time to initialize"
    for x in `seq $startupwait`; do
        ./check_alluxio_master_version.py -v -e "$version" && break
        sleep 1
    done
    hr
    echo "./check_alluxio_master_version.py -v -e $version"
    ./check_alluxio_master_version.py -v -e "$version"
    hr
    echo "echo ./check_alluxio_worker_version.py -v -e $version"
    ./check_alluxio_worker_version.py -v -e "$version"
    hr
    echo "./check_alluxio_master.py -v"
    ./check_alluxio_master.py -v
    hr
    #docker exec -ti "$DOCKER_CONTAINER" ps -ef
    echo "./check_alluxio_worker.py -v"
    ./check_alluxio_worker.py -v
    hr
    echo "./check_alluxio_running_workers.py -v"
    ./check_alluxio_running_workers.py -v
    hr
    echo "./check_alluxio_dead_workers.py -v"
    ./check_alluxio_dead_workers.py -v
    hr
    #delete_container
    docker-compose down
    echo
}

run_test_versions Alluxio
