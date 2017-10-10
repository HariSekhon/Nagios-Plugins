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
    section2 "Setting up Mesos $version test container"
    VERSION="$version" docker-compose up -d
    echo "getting Mesos dynamic port mappings"
    printf "getting Mesos Master port => "
    export MESOS_MASTER_PORT="`docker-compose port "$DOCKER_SERVICE" "$MESOS_MASTER_PORT_DEFAULT" | sed 's/.*://'`"
    echo "$MESOS_MASTER_PORT"
    printf "getting Mesos Worker port => "
    export MESOS_WORKER_PORT="`docker-compose port "$DOCKER_SERVICE" "$MESOS_WORKER_PORT_DEFAULT" | sed 's/.*://'`"
    echo "$MESOS_WORKER_PORT"
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    when_ports_available "$startupwait" "$MESOS_HOST" "$MESOS_MASTER_PORT" "$MESOS_WORKER_PORT"
    hr
    # could use state.json here but Slave doesn't have this so it's better differentiation
    when_url_content "$startupwait" "http://$MESOS_HOST:$MESOS_MASTER_PORT/" master
    hr
    when_url_content "$startupwait" "http://$MESOS_HOST:$MESOS_WORKER_PORT/state.json" slave
    hr
    run_fail "0 2" $perl -T ./check_mesos_activated_slaves.pl -P "$MESOS_MASTER_PORT" -v
    hr
    #run $perl -T ./check_mesos_chronos_jobs.pl -P "$cronos_port" -v
    hr
    run $perl -T ./check_mesos_deactivated_slaves.pl -v
    hr
    run $perl -T ./check_mesos_master_health.pl -v
    hr
    run $perl -T ./check_mesos_master_state.pl -v -P "$MESOS_MASTER_PORT"
    hr
    echo "checking master metrics:"
    run $perl -T ./check_mesos_metrics.pl -P "$MESOS_MASTER_PORT" -v
    hr
    echo "checking worker metrics:"
    run $perl -T ./check_mesos_metrics.pl -P "$MESOS_WORKER_PORT" -v
    hr
    run $perl -T ./check_mesos_master_metrics.pl -v -P "$MESOS_MASTER_PORT"
    hr
    run $perl -T ./check_mesos_slave_metrics.pl  -v -P "$MESOS_WORKER_PORT"
    hr
    set +e
    slave="$(./check_mesos_slave.py -l | awk '/=/{print $1; exit}')"
    set -e
    echo "checking for Mesos Slave '$slave' via Mesos Master API"
    run ./check_mesos_slave.py -v -s "$slave" -P "$MESOS_MASTER_PORT"
    hr
    # Not implemented yet
    #run $perl -T ./check_mesos_registered_framework.py -v
    hr
    # Not implemented yet
    #run $perl -T ./check_mesos_slave_container_statistics.pl -v
    hr
    run $perl -T ./check_mesos_slave_state.pl -v -P "$MESOS_WORKER_PORT"
    hr
    echo "Completed $run_count Mesos tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
}

run_test_versions Mesos
