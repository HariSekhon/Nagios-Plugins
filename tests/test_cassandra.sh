#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-05-25 01:38:24 +0100 (Mon, 25 May 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help improve or steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

. ./tests/utils.sh

section "C a s s a n d r a"

export CASSANDRA_VERSIONS="${@:-${CASANDRA_VERSIONS:-latest 1.2 2.0 2.1 2.2 3.0 3.5 3.6 3.7 3.9 3.10 3.11}}"

CASSANDRA_HOST="${DOCKER_HOST:-${CASSANDRA_HOST:-${HOST:-localhost}}}"
CASSANDRA_HOST="${CASSANDRA_HOST##*/}"
CASSANDRA_HOST="${CASSANDRA_HOST%%:*}"
export CASSANDRA_HOST
export CASSANDRA_PORT_DEFAULT=9042
export CASSANDRA_JMX_PORT_DEFAULT=7199

export MNTDIR="/pl"

startupwait 10

check_docker_available

trap_debug_env cassandra

docker_exec(){
    #docker exec -ti "$DOCKER_CONTAINER" $MNTDIR/$@
    run docker-compose exec "$DOCKER_SERVICE" "$MNTDIR/$@"
}

test_cassandra(){
    local version="$1"
    section2 "Setting up Cassandra $version test container"
    VERSION="$version" docker-compose pull $docker_compose_quiet
    VERSION="$version" docker-compose up -d
    echo "getting Cassandra dynamic port mappings:"
    printf "Cassandra CQL port => "
    export CASSANDRA_PORT="`docker-compose port "$DOCKER_SERVICE" "$CASSANDRA_PORT_DEFAULT" | sed 's/.*://'`"
    echo "$CASSANDRA_PORT"
    printf "Cassandra JMX port => "
    export CASSANDRA_JMX_PORT="`docker-compose port "$DOCKER_SERVICE" "$CASSANDRA_JMX_PORT_DEFAULT" | sed 's/.*://'`"
    echo "$CASSANDRA_JMX_PORT"
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    when_ports_available "$startupwait" "$CASSANDRA_HOST" "$CASSANDRA_PORT" "$CASSANDRA_JMX_PORT"
    if [ "$version" = "latest" ]; then
        local version=".*"
    fi
    hr
    # doesn't always fail reliably as Cassandra 1.2 comes up faster than later versions
    #set +e
    #echo "checking nodetool failure after initial startup:"
    #docker_exec check_cassandra_balance.pl
    #check_exit_code 2
    #set -e
    #hr
    echo "trying up to 20 times for nodetool status to succeed"
    for x in {1..20}; do
        docker-compose exec "$DOCKER_SERVICE" nodetool status && break
        echo "===="
        sleep 1
    done
    hr
    docker_exec check_cassandra_version_nodetool.py -e "$version"
    hr
    FAIL=2 docker_exec check_cassandra_version_nodetool.py -e "fail-version"
    hr
    # Dockerized Cassandra doesn't seem able to detect it's own token % - even when container has been running for a long time
    # TODO: add more specific command testing here to only except that scenario
    docker_exec check_cassandra_balance.pl
    hr
    docker_exec check_cassandra_balance.pl -v
    hr
    docker_exec check_cassandra_balance.pl --nodetool /cassandra/bin/nodetool -v
    hr
    echo "checking connection refused:"
    FAIL=2 docker_exec check_cassandra_balance.pl -v -P 719
    hr
    docker_exec check_cassandra_heap.pl -w 70 -c 90 -v
    hr
    docker_exec check_cassandra_heap.pl --nodetool /cassandra/bin/nodetool -w 70 -c 90 -v
    hr
    echo "checking connection refused:"
    FAIL=2 docker_exec check_cassandra_heap.pl -w 70 -c 90 -v -P 719
    hr
    docker_exec check_cassandra_netstats.pl -v
    hr
    docker_exec check_cassandra_netstats.pl --nodetool /cassandra/bin/nodetool -v
    hr
    echo "checking connection refused:"
    FAIL=2 docker_exec check_cassandra_netstats.pl -v -P 719
    hr
    docker_exec check_cassandra_nodes.pl -v
    hr
    docker_exec check_cassandra_nodes.pl --nodetool /cassandra/bin/nodetool -v
    hr
    echo "checking connection refused:"
    FAIL=2 docker_exec check_cassandra_nodes.pl -v -P 719
    hr
    docker_exec check_cassandra_tpstats.pl -v
    hr
    docker_exec check_cassandra_tpstats.pl --nodetool /cassandra/bin/nodetool -v
    hr
    echo "checking connection refused:"
    FAIL=2 docker_exec check_cassandra_tpstats.pl -P 719
    hr
    echo "Completed $run_count Cassandra tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    hr
    echo
    echo
}

run_test_versions Cassandra
