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

# shellcheck disable=SC1090
. "$srcdir/utils.sh"

section "A l l u x i o"

export ALLUXIO_VERSIONS="${*:-${ALLUXIO_VERSIONS:-1.0 1.1 1.2 1.3 1.4 1.5 1.6 latest}}"

ALLUXIO_HOST="${DOCKER_HOST:-${ALLUXIO_HOST:-${HOST:-localhost}}}"
ALLUXIO_HOST="${ALLUXIO_HOST##*/}"
ALLUXIO_HOST="${ALLUXIO_HOST%%:*}"
export ALLUXIO_HOST

export ALLUXIO_MASTER_PORT_DEFAULT=19999
export ALLUXIO_WORKER_PORT_DEFAULT=30000

startupwait 50

check_docker_available

trap_debug_env alluxio

test_alluxio(){
    local version="$1"
    section2 "Setting up Alluxio $version test container"
    docker_compose_pull
    if [ -z "${KEEPDOCKER:-}" ]; then
        docker-compose down || :
    fi
    VERSION="$version" docker-compose up -d --remove-orphans
    hr
    echo "getting Alluxio dynamic port mappings:"
    docker_compose_port "Alluxio Master"
    docker_compose_port "Alluxio Worker"
    hr
    when_ports_available "$ALLUXIO_HOST" "$ALLUXIO_MASTER_PORT" "$ALLUXIO_WORKER_PORT"
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    if [ "$version" = "latest" ]; then
        echo "latest version, fetching latest version from DockerHub master branch"
        local version
        version="$(dockerhub_latest_version alluxio)"
        echo "expecting version '$version'"
    fi
    hr
    echo "waiting on Alluxio Master to give Alluxio time to properly initialize:"
    # defined in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    RETRY_INTERVAL=2 retry "$startupwait" ./check_alluxio_master_version.py -v -e "$version" -t 2
    hr
    echo "expect Alluxio Worker to also be up by this point:"
    RETRY_INTERVAL=2 retry 10 ./check_alluxio_worker_version.py -v -e "$version" -t 2
    hr
    run ./check_alluxio_master_version.py -v -e "$version"

    run_fail 2 ./check_alluxio_master_version.py -v -e "fail-version"

    run_conn_refused ./check_alluxio_master_version.py -v -e "$version"

    run ./check_alluxio_worker_version.py -v -e "$version"

    run_fail 2 ./check_alluxio_worker_version.py -v -e "fail-version"

    run_conn_refused ./check_alluxio_worker_version.py -v -e "$version"

    run ./check_alluxio_master.py -v

    run_conn_refused ./check_alluxio_master.py -v

    run ./check_alluxio_worker.py -v

    run_conn_refused ./check_alluxio_worker.py -v

    run ./check_alluxio_running_workers.py -v -w 1

    run_fail 1 ./check_alluxio_running_workers.py -v -w 2

    run_fail 2 ./check_alluxio_running_workers.py -v -w 3 -c 2

    run_conn_refused ./check_alluxio_running_workers.py -v -w 1

    run ./check_alluxio_dead_workers.py -v

    run_conn_refused ./check_alluxio_dead_workers.py -v

    run_fail 3 ./check_alluxio_worker_heartbeat.py -l

    set +e
    node="$(./check_alluxio_worker_heartbeat.py -l | tail -n1)"
    set -e
    if [ -z "$node" ]; then
        echo "FAILED to find Alluxio worker node"
        exit 1
    fi
    run ./check_alluxio_worker_heartbeat.py --node "$node"

    run_conn_refused ./check_alluxio_worker_heartbeat.py --node "$node"

    if [ -n "${KEEPDOCKER:-}" ]; then
        echo
        # defined and tracked in bash-tools/lib/utils.sh
        # shellcheck disable=SC2154
        echo "Completed $run_count Alluxio tests"
        return
    fi
    # there is a bug in Alluxio 1.1 + 1.2 properties support that prevents adding the config for reducing the worker detection timeout to 5 mins
    # there is a bug in Aluxio 1.3 - 1.5 that it does not respect the worker timeout setting
    if is_CI || ! [[ "$version" =~ ^1\.[1-5]$ ]]; then
    echo "Now killing Alluxio worker for dead workers test:"
    set +e
    echo docker exec -ti "$DOCKER_CONTAINER" pkill -9 -f WORKER_LOGGER
    # this doesn't find it, bug, probably too far along the cmd line
    #docker exec -ti "$DOCKER_CONTAINER" pkill -9 -f alluxio.worker.AlluxioWorker
    # latches on to WORKER_LOGGER earlier in cmd line, works - do not try using just "worker" as that will match and kill the tail that keeps the container up
    docker exec -ti "$DOCKER_CONTAINER" pkill -9 -f WORKER_LOGGER
    set -e
    hr
    echo "Now waiting for dead worker to be detected by master:"
    # takes 300 secs to detect by default, but docker image config sets this down to a more reasonable 10 secs like Tachyon used to do
    retry 310 ! ./check_alluxio_dead_workers.py -v
    hr
    run_fail 1 ./check_alluxio_dead_workers.py -v

    run_fail 2 ./check_alluxio_dead_workers.py -v -c 0

    run_fail 1 ./check_alluxio_running_workers.py -v -w 1 -c 0

    run_fail 2 ./check_alluxio_running_workers.py -v -w 1

    run_fail 1 ./check_alluxio_worker_heartbeat.py --node "$node" -w 1 -c 500

    run_fail 2 ./check_alluxio_worker_heartbeat.py --node "$node" -w 1 -c 1

    fi
    # defined and tracked in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "Completed $run_count Alluxio tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    echo
}

run_test_versions Alluxio

if is_CI; then
    docker_image_cleanup
    echo
fi
