#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-12-05 19:15:47 +0000 (Wed, 05 Dec 2018)
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

# shellcheck disable=SC1090
. "$srcdir/utils.sh"

section "G r a f a n a"

export GRAFANA_VERSIONS="${*:-${GRAFANA_VERSIONS:-latest}}"

GRAFANA_HOST="${DOCKER_HOST:-${GRAFANA_HOST:-${HOST:-localhost}}}"
GRAFANA_HOST="${GRAFANA_HOST##*/}"
GRAFANA_HOST="${GRAFANA_HOST%%:*}"
export GRAFANA_HOST
export GRAFANA_PORT_DEFAULT=3000
export HAPROXY_PORT_DEFAULT=3000

check_docker_available

trap_debug_env grafana

# waits 30 secs just for HBase to come up
startupwait 60

test_grafana(){
    local version="$1"
    section2 "Setting up Grafana $version test container"
    docker_compose_pull
    VERSION="$version" docker-compose up -d --remove-orphans
    hr
    echo "getting Grafana dynamic port mappings:"
    docker_compose_port "Grafana"
    DOCKER_SERVICE=grafana-haproxy docker_compose_port HAProxy
    hr
    # shellcheck disable=SC2153
    when_ports_available "$GRAFANA_HOST" "$GRAFANA_PORT" "$HAPROXY_PORT"
    hr
    when_url_content "http://$GRAFANA_HOST:$GRAFANA_PORT" "Grafana"
    hr
    echo "checking HAProxy Grafana:"
    when_url_content "http://$GRAFANA_HOST:$HAPROXY_PORT" "Grafana"
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    hr
    grafana_tests
    echo
    section2 "Running Grafana HAProxy tests"
    GRAFANA_PORT="$HAPROXY_PORT" \
    grafana_tests

    # defined and tracked in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "Completed $run_count Grafana tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    echo
}

grafana_tests(){
    expected_version="$version"
    if [ "$version" = "latest" ]; then
        expected_version=".*"
    fi
    run ./check_grafana_health.py

    run_conn_refused ./check_grafana_health.py

    run ./check_grafana_version.py -v -e "$expected_version"

    run_fail 2 ./check_grafana_version.py -v -e "fail-version"

    run_conn_refused ./check_grafana_version.py -v -e "$expected_version"

}

run_test_versions "Grafana"

if is_CI; then
    docker_image_cleanup
    echo
fi
