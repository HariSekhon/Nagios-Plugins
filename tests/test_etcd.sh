#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-03-17 14:43:37 +0000 (Sat, 17 Mar 2018)
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
srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$srcdir/.."

# shellcheck disable=SC1090
. "$srcdir/utils.sh"

section "E t c d"

export ETCD_VERSIONS="${*:-${ETCD_VERSIONS:-v2.0.13 v2.1.3 v2.2.5 v2.3.8 v3.0 latest}}"

ETCD_HOST="${DOCKER_HOST:-${ETCD_HOST:-${HOST:-localhost}}}"
ETCD_HOST="${ETCD_HOST##*/}"
ETCD_HOST="${ETCD_HOST%%:*}"
export ETCD_HOST

export ETCD_PORT_DEFAULT=2379
export HAPROXY_PORT_DEFAULT=2379

startupwait 10

check_docker_available

trap_debug_env etcd

test_etcd(){
    local version="$1"
    section2 "Setting up Etcd $version test container"
    docker_compose_pull
    if [ "${version:0:3}" = "v2." ]; then
        VERSION="$version" docker-compose -f "$srcdir/docker/etcd2-docker-compose.yml" up -d --remove-orphans
    else
        VERSION="$version" docker-compose up -d --remove-orphans
    fi
    hr
    echo "getting Etcd dynamic port mapping:"
    DOCKER_SERVICE=etcd1 docker_compose_port "Etcd" "Etcd1"
    DOCKER_SERVICE=etcd-haproxy docker_compose_port HAProxy
    hr
    # shellcheck disable=SC2153
    when_ports_available "$ETCD_HOST" "$ETCD_PORT" "$HAPROXY_PORT"
    hr
    # Etcd 2.x /version:
    #
    # etcd 2.0.13
    #
    # Etcd 3.x /version:
    #
    # {"etcdserver":"3.3.2","etcdcluster":"3.3.0"}
    #
    when_url_content "http://$ETCD_HOST:$ETCD_PORT/version" "etcd"
    hr
    echo "checking HAProxy Etcd:"
    when_url_content "http://$ETCD_HOST:$HAPROXY_PORT/version" "etcd"
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    local expected_version="${version#v}"
    if [ "$version" = "latest" ]; then
        local expected_version=".*"
    fi

    etcd_tests

    echo

    section2 "Running HAProxy tests"

    ETCD_PORT="$HAPROXY_PORT" \
    etcd_tests

    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    hr

    hr
    # defined and tracked in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "Completed $run_count Etcd tests"
    hr
    echo
}

etcd_tests(){
    run ./check_etcd_version.py -v --expected "$expected_version"

    run_fail 2 ./check_etcd_version.py -v --expected "fail-version"

    run_conn_refused ./check_etcd_version.py -v --expected "$expected_version"
}

run_test_versions Etcd

if is_CI; then
    docker_image_cleanup
    echo
fi
