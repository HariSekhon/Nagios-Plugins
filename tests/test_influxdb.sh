#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-01-19 18:05:53 +0000 (Fri, 19 Jan 2018)
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

section "I n f l u x D B"

# there is no alpine version of 0.12
export INFLUXDB_VERSIONS="${*:-${INFLUXDB_VERSIONS:-0.12 0.13-alpine 1.0-alpine 1.1-alpine 1.2-alpine 1.3-alpine 1.4-alpine 1.5-alpine alpine}}"

INFLUXDB_HOST="${DOCKER_HOST:-${INFLUXDB_HOST:-${HOST:-localhost}}}"
INFLUXDB_HOST="${INFLUXDB_HOST##*/}"
INFLUXDB_HOST="${INFLUXDB_HOST%%:*}"
export INFLUXDB_HOST
export INFLUXDB_PORT_DEFAULT=8086
export HAPROXY_PORT_DEFAULT=8086

check_docker_available

trap_debug_env influxdb

test_influxdb(){
    local version="$1"
    section2 "Setting up InfluxDB $version test container"
    docker_compose_pull
    VERSION="$version" docker-compose up -d --remove-orphans
    hr
    echo "getting InfluxDB dynamic port mappings:"
    docker_compose_port "InfluxDB"
    DOCKER_SERVICE=influxdb-haproxy docker_compose_port HAProxy
    hr
    # shellcheck disable=SC2153
    when_ports_available "$INFLUXDB_HOST" "$INFLUXDB_PORT" "$HAPROXY_PORT"
    hr
    when_url_content "http://$INFLUXDB_HOST:$INFLUXDB_PORT/query?q=show%20databases" "results"
    hr
    echo "checking HAProxy InfluxDB:"
    when_url_content "http://$INFLUXDB_HOST:$HAPROXY_PORT/query?q=show%20databases" "results"
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    hr
    influxdb_tests
    echo
    section2 "Running InfluxDB HAProxy tests"
    INFLUXDB_PORT="$HAPROXY_PORT" \
    influxdb_tests

    # defined and tracked in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "Completed $run_count InfluxDB tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    echo
}

influxdb_tests(){
    expected_version="${version%-alpine}"
    if [ "$version" = "latest" ] || [ "$version" = "alpine" ]; then
        expected_version=".*"
    fi
    build=""
    if [[ "$version" = "latest" || "$version" = "alpine" ]]; then # || "${version:0:3}" -ge 1.4 ]]; then
        build="--build OSS"
    fi
    # want splitting
    # shellcheck disable=SC2086
    run ./check_influxdb_version.py -v -e "$expected_version" $build

    # want splitting
    # shellcheck disable=SC2086
    run_fail 2 ./check_influxdb_version.py -v -e "fail-version" $build

    # want splitting
    # shellcheck disable=SC2086
    run_conn_refused ./check_influxdb_version.py -v -e "$expected_version" $build

    run ./check_influxdb_api_ping.py

    run_conn_refused ./check_influxdb_api_ping.py
}

run_test_versions "InfluxDB"

if is_CI; then
    docker_image_cleanup
    echo
fi
