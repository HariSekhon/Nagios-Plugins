#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-02-23 18:40:33 +0000 (Fri, 23 Feb 2018)
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

section "R a n c h e r"

export RANCHER_VERSIONS="${*:-${RANCHER_VERSIONS:-v1.0.2 v1.1.4 v1.2.4 v1.3.5 v1.4.3 v1.5.9 v1.6.14 stable latest}}"

RANCHER_HOST="${DOCKER_HOST:-${RANCHER_HOST:-${HOST:-localhost}}}"
RANCHER_HOST="${RANCHER_HOST##*/}"
RANCHER_HOST="${RANCHER_HOST%%:*}"
export RANCHER_HOST
export RANCHER_PORT_DEFAULT=8080
export HAPROXY_PORT_DEFAULT=8080

check_docker_available

# takes a while to bootstrap rancher-server + embedded mysql db
startupwait 120

trap_debug_env rancher

test_rancher(){
    local version="$1"
    section2 "Setting up Rancher $version test container"
    docker_compose_pull
    VERSION="$version" docker-compose up -d --remove-orphans
    hr
    echo "getting Rancher dynamic port mapping:"
    docker_compose_port "Rancher"
    DOCKER_SERVICE=rancher-haproxy docker_compose_port HAProxy
    hr
    # shellcheck disable=SC2153
    when_ports_available "$RANCHER_HOST" "$RANCHER_PORT" "$HAPROXY_PORT"
    hr
    when_url_content "http://$RANCHER_HOST:$RANCHER_PORT/ping" "pong"
    hr
    echo "checking HAProxy Rancher:"
    when_url_content "http://$RANCHER_HOST:$HAPROXY_PORT/ping" "pong"
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    hr
    if [ "$version" = "latest" ]; then
        local version=".*"
    fi
    rancher_tests
    echo
    section2 "Running HAProxy + Authentication tests"
    RANCHER_PORT="$HAPROXY_PORT" \
    rancher_tests

    # defined and tracked in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "Completed $run_count Rancher tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
}

rancher_tests(){
    run ./check_rancher_api_ping.py

    run_conn_refused ./check_rancher_api_ping.py
}

run_test_versions Rancher

if is_CI; then
    docker_image_cleanup
    echo
fi
