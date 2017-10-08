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

section "A p a c h e   M e s o s"

# TODO: update plugins for > 0.24
export MESOS_VERSIONS="${@:-${MESOS_VERSIONS:-${VERSIONS:-latest 0.23 0.24}}}"

MESOS_HOST="${DOCKER_HOST:-${MESOS_HOST:-${HOST:-localhost}}}"
MESOS_HOST="${MESOS_HOST##*/}"
MESOS_HOST="${MESOS_HOST%%:*}"
export MESOS_HOST

export MESOS_MASTER_PORT_DEFAULT=5050
export MESOS_WORKER_PORT_DEFAULT=5051
export MESOS_MASTER="$MESOS_HOST:$MESOS_MASTER_PORT_DEFAULT"

startupwait 30

check_docker_available

trap_debug_env mesos

test_mesos(){
    local version="${1:-latest}"
    hr
    section2 "Setting up Mesos $version test container"
    hr
    #launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $MESOS_MASTER_PORT $MESOS_WORKER_PORT
    VERSION="$version" docker-compose up -d
    export MESOS_MASTER_PORT="`docker-compose port "$DOCKER_SERVICE" "$MESOS_MASTER_PORT_DEFAULT" | sed 's/.*://'`"
    export MESOS_WORKER_PORT="`docker-compose port "$DOCKER_SERVICE" "$MESOS_WORKER_PORT_DEFAULT" | sed 's/.*://'`"
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    when_ports_available "$startupwait" "$MESOS_HOST" "$MESOS_MASTER_PORT" "$MESOS_WORKER_PORT"
    hr
    run $perl -T ./check_mesos_activated_slaves.pl -P "$MESOS_MASTER_PORT" -v
    hr
    #run $perl -T ./check_mesos_chronos_jobs.pl -P "$cronos_port" -v
    hr
    run $perl -T ./check_mesos_deactivated_slaves.pl -v
    hr
    run $perl -T ./check_mesos_master_health.pl -v
    hr
    run $perl -T ./check_mesos_master_state.pl -v
    hr
    run $perl -T ./check_mesos_metrics.pl -P "$MESOS_MASTER_PORT" -v
    hr
    run $perl -T ./check_mesos_metrics.pl -P "$MESOS_WORKER_PORT" -v
    hr
    run $perl -T ./check_mesos_master_metrics.pl -v
    hr
    set +e
    slave="$(./check_mesos_slave.py -l | awk '/=/{print $1; exit}')"
    set -e
    echo "checking for mesos slave '$slave'"
    run ./check_mesos_slave.py -v -s "$slave"
    hr
    run $perl -T ./check_mesos_slave_metrics.pl  -v
    hr
    # Not implemented yet
    #run $perl -T ./check_mesos_registered_framework.py -v
    hr
    # Not implemented yet
    #run $perl -T ./check_mesos_slave_container_statistics.pl -v
    hr
    run $perl -T ./check_mesos_slave_state.pl -v
    hr
    echo "Completed $run_count Mesos tests"
    #delete_container
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
}

run_test_versions Mesos
