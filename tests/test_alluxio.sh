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

section "A l l u x i o"

export ALLUXIO_VERSIONS="${@:-${ALLUXIO_VERSIONS:-latest 1.0 1.1 1.2 1.3 1.4 1.5 1.6}}"

ALLUXIO_HOST="${DOCKER_HOST:-${ALLUXIO_HOST:-${HOST:-localhost}}}"
ALLUXIO_HOST="${ALLUXIO_HOST##*/}"
ALLUXIO_HOST="${ALLUXIO_HOST%%:*}"
export ALLUXIO_HOST

export ALLUXIO_MASTER_PORT_DEFAULT=19999
export ALLUXIO_WORKER_PORT_DEFAULT=30000

startupwait 30

check_docker_available

trap_debug_env alluxio

test_alluxio(){
    local version="$1"
    section2 "Setting up Alluxio $version test container"
    VERSION="$version" docker-compose pull $docker_compose_quiet
    VERSION="$version" docker-compose up -d
    echo "getting Alluxio dynamic port mappings:"
    printf "Alluxio Master port => "
    export ALLUXIO_MASTER_PORT="`docker-compose port "$DOCKER_SERVICE" "$ALLUXIO_MASTER_PORT_DEFAULT" | sed 's/.*://'`"
    echo "$ALLUXIO_MASTER_PORT"
    printf "Alluxio Worker port => "
    export ALLUXIO_WORKER_PORT="`docker-compose port "$DOCKER_SERVICE" "$ALLUXIO_WORKER_PORT_DEFAULT" | sed 's/.*://'`"
    echo "$ALLUXIO_WORKER_PORT"
    if [ -z "$ALLUXIO_MASTER_PORT" ]; then
        echo "FAILED to get Alluxio Master port... did the container or Master process crash?"
        exit 1
    fi
    if [ -z "$ALLUXIO_WORKER_PORT" ]; then
        echo "FAILED to get Alluxio Worker port... did the container or Worker process crash?"
        exit 1
    fi
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    when_ports_available "$ALLUXIO_HOST" "$ALLUXIO_MASTER_PORT" "$ALLUXIO_WORKER_PORT"
    if [ "$version" = "latest" ]; then
        local version=".*"
    fi
    hr
    echo "retrying for $startupwait secs to give Alluxio time to initialize"
    SECONDS=0
    count=1
    while true; do
        echo "try $count: "
        if ./check_alluxio_master_version.py -v -e "$version" &&
           ./check_alluxio_worker_version.py -v -e "$version"; then
            echo "Alluxio Master & Worker up after $SECONDS secs, continuing with tests"
            break
        fi
        # ! [] is better then [ -gt ] because if either variable breaks the test will fail correctly
        if ! [ $SECONDS -le $startupwait ]; then
            echo "FAIL: Alluxio did not start up within $startupwait secs"
            exit 1
        fi
        let count+=1
        sleep 1
    done
    hr
    run ./check_alluxio_master_version.py -v -e "$version"
    hr
    run_conn_refused ./check_alluxio_master_version.py -v -e "$version"
    hr
    run ./check_alluxio_worker_version.py -v -e "$version"
    hr
    run_conn_refused ./check_alluxio_worker_version.py -v -e "$version"
    hr
    run ./check_alluxio_master.py -v
    hr
    run_conn_refused ./check_alluxio_master.py -v
    hr
    run ./check_alluxio_worker.py -v
    hr
    run_conn_refused ./check_alluxio_worker.py -v
    hr
    run ./check_alluxio_running_workers.py -v
    hr
    run_conn_refused ./check_alluxio_running_workers.py -v
    hr
    run ./check_alluxio_dead_workers.py -v
    hr
    run_conn_refused ./check_alluxio_dead_workers.py -v
    hr
    echo "Completed $run_count Alluxio tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    echo
}

run_test_versions Alluxio
