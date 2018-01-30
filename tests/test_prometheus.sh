#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-01-30 10:42:54 +0000 (Tue, 30 Jan 2018)
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

section "P r o m e t h e u s"

export PROMETHEUS_VERSIONS="${@:-${PROMETHEUS_VERSIONS:-latest v1.0.0 v1.1.3 v1.2.3 v1.3.1 v1.4.0 v1.5.3 v1.6.3 v1.7.2 v1.8.2 v2.1.0}}"
# 0.9.0 does not have node_exporter_build_info
# 0.10.0 tag is broken with a Go error: https://github.com/prometheus/node_exporter/issues/804
export NODE_EXPORTER_VERSIONS="${NODE_EXPORTER_VERSIONS:-latest 0.12.0 v0.13.0 v0.14.0 v0.15.2}}"

PROMETHEUS_HOST="${DOCKER_HOST:-${PROMETHEUS_HOST:-${HOST:-localhost}}}"
PROMETHEUS_HOST="${PROMETHEUS_HOST##*/}"
PROMETHEUS_HOST="${PROMETHEUS_HOST%%:*}"
export PROMETHEUS_HOST
export PROMETHEUS_COLLECTD_HOST="$PROMETHEUS_HOST"
export PROMETHEUS_NODE_EXPORTER_HOST="$PROMETHEUS_HOST"
export PROMETHEUS_PORT_DEFAULT=9090
export HAPROXY_PORT_DEFAULT=9090
export COLLECTD_PORT_DEFAULT=9103
export NODE_EXPORTER_PORT_DEFAULT=9100

check_docker_available

trap_debug_env prometheus

test_prometheus(){
    local version="$1"
    section2 "Setting up Prometheus $version test container"
    docker_compose_pull
    local export NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-$(bash-tools/random_select.sh $NODE_EXPORTER_VERSIONS)}"
    VERSION="$version" docker-compose up -d
    hr
    echo "getting Prometheus dynamic port mappings:"
    docker_compose_port "Prometheus"
    DOCKER_SERVICE=prometheus-haproxy docker_compose_port HAProxy
    DOCKER_SERVICE=prometheus-collectd docker_compose_port Collectd
    DOCKER_SERVICE=prometheus-node-exporter docker_compose_port "Node Exporter"
    hr
    when_ports_available "$PROMETHEUS_HOST" "$PROMETHEUS_PORT" "$HAPROXY_PORT" "$COLLECTD_PORT" "$NODE_EXPORTER_PORT"
    hr
    when_url_content "http://$PROMETHEUS_HOST:$PROMETHEUS_PORT/graph" "Prometheus"
    hr
    echo "checking Prometheus Collectd:"
    when_url_content "http://$PROMETHEUS_HOST:$COLLECTD_PORT/metrics" "collectd/write_prometheus"
    hr
    echo "checking Prometheus Node Exporter:"
    when_url_content "http://$PROMETHEUS_HOST:$NODE_EXPORTER_PORT/metrics" "^node_exporter_build_info"
    hr
    echo "checking HAProxy Prometheus:"
    when_url_content "http://$PROMETHEUS_HOST:$HAPROXY_PORT/graph" "Prometheus"
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    hr

    run ./check_prometheus_collectd.py

    run_conn_refused ./check_prometheus_collectd.py

    # ============================================================================ #

    run ./check_prometheus_collectd_version.py -v -e '5.8'

    run_fail 2 ./check_prometheus_collectd_version.py -v -e 'fail-version'

    run_conn_refused ./check_prometheus_collectd_version.py

    # ============================================================================ #

    expected_node_exporter_version="${NODE_EXPORTER_VERSION#v}"
    if [ "$NODE_EXPORTER_VERSION" = "latest" ]; then
        $expected_node_exporter_version=".*"
    fi
    run ./check_prometheus_node_exporter_version.py -v -e "$expected_node_exporter_version"

    run_fail 2 ./check_prometheus_node_exporter_version.py -v -e 'fail-version'

    run_conn_refused ./check_prometheus_node_exporter_version.py

    # ============================================================================ #

    prometheus_tests
    echo
    section2 "Running Prometheus HAProxy tests"
    PROMETHEUS_PORT="$HAPROXY_PORT" \
    prometheus_tests

    echo "Completed $run_count Prometheus tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    echo
}

prometheus_tests(){
    expected_version="${version#v}"
    if [ "$version" = "latest" ]; then
        expected_version=".*"
    fi
    run ./check_prometheus_version.py -v -e "$expected_version"

    run_fail 2 ./check_prometheus_version.py -v -e "fail-version"

    run_conn_refused ./check_prometheus_version.py -v -e "$expected_version"
}

run_test_versions "Prometheus"
