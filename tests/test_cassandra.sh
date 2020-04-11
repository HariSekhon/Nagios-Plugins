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

# shellcheck disable=SC1090
. "$srcdir/utils.sh"

section "C a s s a n d r a"

export CASSANDRA_VERSIONS="${*:-${CASANDRA_VERSIONS:-1.2 2.0 2.1 2.2 3.0 3.5 3.6 3.7 3.9 3.10 3.11 latest}}"

CASSANDRA_HOST="${DOCKER_HOST:-${CASSANDRA_HOST:-${HOST:-localhost}}}"
CASSANDRA_HOST="${CASSANDRA_HOST##*/}"
CASSANDRA_HOST="${CASSANDRA_HOST%%:*}"
export CASSANDRA_HOST
export CASSANDRA_PORT_DEFAULT=9042
export HAPROXY_PORT_DEFAULT=9042
export CASSANDRA_JMX_PORT_DEFAULT=7199

export DOCKER_MOUNT_DIR="/pl"

startupwait 10

check_docker_available

trap_debug_env cassandra

proxy_host="cassandra-proxy"

test_cassandra(){
    local version="$1"
    section2 "Setting up Cassandra $version test container"
    docker_compose_pull
    VERSION="$version" docker-compose up -d --remove-orphans
    hr
    echo "getting Cassandra dynamic port mappings:"
    docker_compose_port CASSANDRA_PORT "Cassandra CQL"
    docker_compose_port "Cassandra JMX"
    DOCKER_SERVICE=cassandra-haproxy docker_compose_port HAPROXY "HAProxy CQL"
    hr
    # shellcheck disable=SC2153
    when_ports_available "$CASSANDRA_HOST" "$CASSANDRA_PORT" "$HAPROXY_PORT" # "$CASSANDRA_JMX_PORT" binds to 127.0.0.1
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    if [ "$version" = "latest" ]; then
        echo "latest version, fetching latest version from DockerHub master branch"
        local version
        version="$(dockerhub_latest_version cassandra-dev)"
        echo "expecting version '$version'"
    fi
    hr
    # doesn't always fail reliably as Cassandra 1.2 comes up faster than later versions
    #set +e
    #echo "checking nodetool failure after initial startup:"
    #docker_exec check_cassandra_balance.pl
    #check_exit_code 2
    #set -e
    #hr
    echo "waiting for nodetool status to succeed:"
    retry 40 docker-compose exec "$DOCKER_SERVICE" nodetool status --host "$proxy_host"
    hr
    docker_exec check_cassandra_version_nodetool.py -e "$version"

    ERRCODE=2 docker_exec check_cassandra_version_nodetool.py -e "fail-version"

    docker_exec check_cassandra_balance.pl

    docker_exec check_cassandra_balance.pl -v

    docker_exec check_cassandra_balance.pl --nodetool /cassandra/bin/nodetool -v --host "$proxy_host"

    echo "checking connection refused:"
    ERRCODE=2 docker_exec check_cassandra_balance.pl -v -P 719

    docker_exec check_cassandra_heap.pl -w 70 -c 90 -v

    docker_exec check_cassandra_heap.pl --nodetool /cassandra/bin/nodetool -w 70 -c 90 -v --host "$proxy_host"

    echo "checking connection refused:"
    ERRCODE=2 docker_exec check_cassandra_heap.pl -w 70 -c 90 -v -P 719

    docker_exec check_cassandra_netstats.pl -v

    docker_exec check_cassandra_netstats.pl --nodetool /cassandra/bin/nodetool -v --host "$proxy_host"

    echo "checking connection refused:"
    ERRCODE=2 docker_exec check_cassandra_netstats.pl -v -P 719

    docker_exec check_cassandra_nodes.pl -v

    docker_exec check_cassandra_nodes.pl --nodetool /cassandra/bin/nodetool -v --host "$proxy_host"

    echo "checking connection refused:"
    ERRCODE=2 docker_exec check_cassandra_nodes.pl -v -P 719

    docker_exec check_cassandra_tpstats.pl -v

    docker_exec check_cassandra_tpstats.pl --nodetool /cassandra/bin/nodetool -v --host "$proxy_host"

    echo "checking connection refused:"
    ERRCODE=2 docker_exec check_cassandra_tpstats.pl -P 719

    # defined and tracked in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "Completed $run_count Cassandra tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    hr
    echo
    echo
}

run_test_versions Cassandra

if is_CI; then
    docker_image_cleanup
    echo
fi
