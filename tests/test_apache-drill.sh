#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-01-26 23:36:03 +0000 (Tue, 26 Jan 2016)
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

section "A p a c h e   D r i l l"

export APACHE_DRILL_VERSIONS="${@:-${APACHE_DRILL_VERSIONS:-latest 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 1.10 1.11}}"

APACHE_DRILL_HOST="${DOCKER_HOST:-${APACHE_DRILL_HOST:-${HOST:-localhost}}}"
APACHE_DRILL_HOST="${APACHE_DRILL_HOST##*/}"
APACHE_DRILL_HOST="${APACHE_DRILL_HOST%%:*}"
export APACHE_DRILL_HOST
export APACHE_DRILL_PORT_DEFAULT=8047
export HAPROXY_PORT_DEFAULT=8047

export DOCKER_CONTAINER="nagios-plugins-apache-drill"

check_docker_available

trap_debug_env apache_drill

test_apache_drill(){
    local version="$1"
    section2 "Setting up Apache Drill $version test container"
    docker_compose_pull
    VERSION="$version" docker-compose up -d
    hr
    echo "getting Apache Drill dynamic port mappings:"
    docker_compose_port "Apache Drill"
    DOCKER_SERVICE=haproxy docker_compose_port HAProxy
    hr
    when_ports_available "$APACHE_DRILL_HOST" "$APACHE_DRILL_PORT" "$HAPROXY_PORT"
    hr
    when_url_content "http://$APACHE_DRILL_HOST:$APACHE_DRILL_PORT/status" "Running"
    hr
    echo "checking HAProxy Apache Drill port:"
    when_url_content "http://$APACHE_DRILL_HOST:$HAPROXY_PORT/status" "Running"
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    docker_compose_version_test apache-drill "$version"
    hr
    test_drill
    echo
    hr
    echo "Running HAProxy tests"
    hr
    test_drill
    echo
    section2 "Running Drill HAProxy test"
    APACHE_DRILL_PORT="$HAPROXY_PORT" \
    test_drill

    echo "Completed $run_count Apache Drill tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    echo
}

test_drill(){
    #run ./check_apache_drill_version.py -v -e "$version"

    #run_fail 2 ./check_apache_drill_version.py -v -e "fail-version"

    run ./check_apache_drill_status.py -v

    run_conn_refused ./check_apache_drill_status.py -v

    run $perl -T ./check_apache_drill_metrics.pl -v

    run_conn_refused $perl -T ./check_apache_drill_metrics.pl -v

    # check container query capability is working
    #
    # Apache Drill 1.10 onwards requires JDK not JRE:
    #
    # https://github.com/HariSekhon/Dockerfiles/pull/15
    #
    # looks like the Apache Drill /status API doesn't reflect the break either, raised in:
    #
    # https://issues.apache.org/jira/browse/DRILL-5990
    #
    #docker_exec sqlline -u jdbc:drill:zk=zookeeper <<< "select * from sys.options limit 1;"
    # more reliable for some versions of drill eg. 0.7
    docker_exec sqlline -u jdbc:drill:zk=zookeeper -f /dev/stdin <<< "select * from sys.options limit 1;"

}

startupwait 50

run_test_versions "Apache Drill"
