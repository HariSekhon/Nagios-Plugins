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

# TODO: docker images for 0.25 and 0.26 need fixes
export MESOS_VERSIONS="${@:-${MESOS_VERSIONS:-${VERSIONS:-latest 0.23 0.24 0.27 0.28}}}"

MESOS_HOST="${DOCKER_HOST:-${MESOS_HOST:-${HOST:-localhost}}}"
MESOS_HOST="${MESOS_HOST##*/}"
MESOS_HOST="${MESOS_HOST%%:*}"
export MESOS_HOST

export MESOS_MASTER_PORT_DEFAULT=5050
export MESOS_SLAVE_PORT_DEFAULT=5051
export MESOS_MASTER="$MESOS_HOST:$MESOS_MASTER_PORT_DEFAULT"

startupwait 30

check_docker_available

trap_debug_env mesos

test_mesos(){
    local version="${1:-latest}"
    section2 "Setting up Mesos $version test container"
    if is_CI || [ -n "${DOCKER_PULL:-}" ]; then
        VERSION="$version" docker-compose pull $docker_compose_quiet
    fi
    VERSION="$version" docker-compose up -d
    echo "getting Mesos dynamic port mappings:"
    docker_compose_port "Mesos Master"
    docker_compose_port "Mesos Slave"
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    when_ports_available "$MESOS_HOST" "$MESOS_MASTER_PORT" "$MESOS_SLAVE_PORT"
    hr
    # could use state.json here but Slave doesn't have this so it's better differentiation
    when_url_content "http://$MESOS_HOST:$MESOS_MASTER_PORT/" master
    hr
    when_url_content "http://$MESOS_HOST:$MESOS_SLAVE_PORT/state.json" slave
    hr
    if [ "$version" = "latest" ]; then
        echo "latest version, fetching latest version from DockerHub master branch"
        local version="$(dockerhub_latest_version mesos)"
        echo "expecting version '$version'"
    fi
    hr
    found_version="$(docker-compose exec "$DOCKER_SERVICE" dpkg -l mesos | tail -n 1 | tr -d '\r' | awk '{print $3; exit}' | sed 's/-.*//')"
    echo "found Mesos version '$found_version'"
    hr
    if [[ "$found_version" =~ $version* ]]; then
        echo "$name docker version matches expected (found '$found_version', expected '$version')"
    else
        echo "Docker container version does not match expected version! (found '$found_version', expected '$version')"
        exit 1
    fi
    hr
    run $perl -T ./check_mesos_activated_slaves.pl -P "$MESOS_MASTER_PORT" -v
    hr
    run_conn_refused $perl -T ./check_mesos_activated_slaves.pl -v
    hr
    #run $perl -T ./check_mesos_chronos_jobs.pl -P "$cronos_port" -v
    hr
    run $perl -T ./check_mesos_deactivated_slaves.pl -v
    hr
    run_conn_refused $perl -T ./check_mesos_deactivated_slaves.pl -v
    hr
    run $perl -T ./check_mesos_master_health.pl -v
    hr
    run_conn_refused $perl -T ./check_mesos_master_health.pl -v
    hr
    run $perl -T ./check_mesos_master_state.pl -v
    hr
    run_conn_refused $perl -T ./check_mesos_master_state.pl -v
    hr
    # must specify ports here as calling generic base plugin
    echo "checking master metrics:"
    run $perl -T ./check_mesos_metrics.pl -P "$MESOS_MASTER_PORT" -v
    hr
    run_conn_refused $perl -T ./check_mesos_metrics.pl -v
    hr
    echo "checking SLAVE metrics:"
    run $perl -T ./check_mesos_metrics.pl -P "$MESOS_SLAVE_PORT" -v
    hr
    run $perl -T ./check_mesos_master_metrics.pl -v
    hr
    run_conn_refused $perl -T ./check_mesos_master_metrics.pl -v
    hr
    run $perl -T ./check_mesos_slave_metrics.pl  -v
    hr
    run_conn_refused $perl -T ./check_mesos_slave_metrics.pl  -v
    hr
    set +e
    slave="$(./check_mesos_slave.py -l | awk '/=/{print $1; exit}')"
    set -e
    echo "checking for Mesos Slave '$slave' via Mesos Master API:"
    run ./check_mesos_slave.py -v -s "$slave" -P "$MESOS_MASTER_PORT"
    hr
    run_conn_refused ./check_mesos_slave.py -v -s "$slave"
    hr
    # Not implemented yet
    #run $perl -T ./check_mesos_registered_framework.py -v
    hr
    # Not implemented yet
    #run $perl -T ./check_mesos_slave_container_statistics.pl -v
    hr
    run $perl -T ./check_mesos_slave_state.pl -v -P "$MESOS_SLAVE_PORT"
    hr
    run_conn_refused $perl -T ./check_mesos_slave_state.pl -v
    hr
    echo "Completed $run_count Mesos tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
}

run_test_versions Mesos
