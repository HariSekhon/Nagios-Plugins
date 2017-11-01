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

section "T a c h y o n"

export TACHYON_VERSIONS="${@:-${TACHYON_VERSIONS:-latest 0.7 0.8}}"

TACHYON_HOST="${DOCKER_HOST:-${TACHYON_HOST:-${HOST:-localhost}}}"
TACHYON_HOST="${TACHYON_HOST##*/}"
TACHYON_HOST="${TACHYON_HOST%%:*}"
export TACHYON_HOST

export TACHYON_MASTER_PORT_DEFAULT=19999
export TACHYON_WORKER_PORT_DEFAULT=30000

startupwait 15

check_docker_available

trap_debug_env tachyon

test_tachyon(){
    local version="$1"
    section2 "Setting up Tachyon $version test container"
    if is_CI; then
        VERSION="$version" docker-compose pull $docker_compose_quiet
    fi
    if [ -z "${KEEPDOCKER:-}" ]; then
        docker-compose down || :
    fi
    VERSION="$version" docker-compose up -d
    echo "getting Tachyon dynamic port mappings:"
    docker_compose_port "Tachyon Master"
    docker_compose_port "Tachyon Worker"
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    when_ports_available "$TACHYON_HOST" "$TACHYON_MASTER_PORT" "$TACHYON_WORKER_PORT"
    if [ "$version" = "latest" ]; then
        echo "latest version, fetching latest version from DockerHub master branch"
        local version="$(dockerhub_latest_version tachyon)"
        echo "expecting version '$version'"
    fi
    hr
    echo "waiting on Tachyon Master to give Tachyon time to properly initialize:"
    RETRY_INTERVAL=2 retry "$startupwait" ./check_tachyon_master_version.py -v -e "$version" -t 2
    hr
    echo "expect Tachyon Worker to also be up by this point:"
    RETRY_INTERVAL=2 retry 10 ./check_tachyon_worker_version.py -v -e "$version" -t 2
    hr
    run ./check_tachyon_master_version.py -v -e "$version"
    hr
    run_fail 2 ./check_tachyon_master_version.py -v -e "fail-version"
    hr
    run ./check_tachyon_worker_version.py -v -e "$version"
    hr
    run_fail 2 ./check_tachyon_worker_version.py -v -e "fail-version"
    hr
    run ./check_tachyon_master.py -v
    hr
    #docker exec -ti "$DOCKER_CONTAINER" ps -ef
    run ./check_tachyon_worker.py -v
    hr
    run ./check_tachyon_running_workers.py -v -w 1
    hr
    run ./check_tachyon_dead_workers.py -v
    hr
    run_conn_refused ./check_tachyon_master_version.py -v -e "$version"
    hr
    run_conn_refused ./check_tachyon_worker_version.py -v -e "$version"
    hr
    run_conn_refused ./check_tachyon_master.py -v
    hr
    run_conn_refused ./check_tachyon_worker.py -v
    hr
    run ./check_tachyon_running_workers.py -v -w 1
    hr
    run_fail 1 ./check_tachyon_running_workers.py -v -w 2
    hr
    run_fail 2 ./check_tachyon_running_workers.py -v -w 3 -c 2
    hr
    run_conn_refused ./check_tachyon_running_workers.py -v -w 1
    hr
    run_conn_refused ./check_tachyon_dead_workers.py -v
    hr
    if [ -n "${KEEPDOCKER:-}" ]; then
        echo
        echo "Completed $run_count Tachyon tests"
        return
    fi
    if [ "$version" = "0.7" ]; then
        echo "Skipping Tachyon worker failure detection due to bug in Tachyon < 8.0:"
        echo
        echo "https://tachyon.atlassian.net/browse/ALLUXIO-1130"
        echo
    else
        echo "Now killing Tachyon worker for dead workers test:"
        set +e
        echo docker exec -ti "$DOCKER_CONTAINER" pkill -9 -f WORKER_LOGGER
        # latches on to WORKER_LOGGER earlier in cmd line, works - do not try using just "worker" as that will match and kill the tail that keeps the container up
        docker exec -ti "$DOCKER_CONTAINER" pkill -9 -f WORKER_LOGGER
        set -e
        hr
        echo "Now waiting for dead worker to be detected by master:"
        echo "(detects heartbeat lag / expired after 10 secs)"
        retry 20 ! ./check_tachyon_dead_workers.py -v
        hr
        run_fail 1 ./check_tachyon_dead_workers.py -v
        hr
        run_fail 2 ./check_tachyon_dead_workers.py -v -c 0
        hr
        run_fail 1 ./check_tachyon_running_workers.py -v -w 1 -c 0
        hr
        run_fail 2 ./check_tachyon_running_workers.py -v -w 1
    fi
    hr
    echo "Completed $run_count Tachyon tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    echo
}

run_test_versions Tachyon
