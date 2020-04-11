#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-11-11 19:49:15 +0000 (Wed, 11 Nov 2015)
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

section "Z o o K e e p e r"

export ZOOKEEPER_VERSIONS="${*:-${ZOOKEEPER_VERSIONS:-3.3 3.4 latest}}"

ZOOKEEPER_HOST="${DOCKER_HOST:-${ZOOKEEPER_HOST:-${HOST:-localhost}}}"
ZOOKEEPER_HOST="${ZOOKEEPER_HOST##*/}"
ZOOKEEPER_HOST="${ZOOKEEPER_HOST%%:*}"
export ZOOKEEPER_HOST
export ZOOKEEPER_PORT_DEFAULT=2181
export HAPROXY_PORT_DEFAULT=2181
#export ZOOKEEPER_PORTS="$ZOOKEEPER_PORT_DEFAULT 3181 4181"

export DOCKER_MOUNT_DIR="/pl"

check_docker_available

trap_debug_env zookeeper

startupwait 10

test_zookeeper(){
    local version="$1"
    section2 "Setting up ZooKeeper $version test container"
    docker_compose_pull
    VERSION="$version" docker-compose up -d --remove-orphans
    hr
    echo "getting ZooKeeper dynammic port mapping:"
    docker_compose_port "ZooKeeper"
    DOCKER_SERVICE=zookeeper-haproxy docker_compose_port HAProxy
    hr
    # shellcheck disable=SC2153
    when_ports_available "$ZOOKEEPER_HOST" "$ZOOKEEPER_PORT" "$HAPROXY_PORT"
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    expected_version="$version"
    if [ "$expected_version" = "latest" ]; then
        echo "latest version, fetching latest version from DockerHub master branch"
        local expected_version
        expected_version="$(dockerhub_latest_version zookeeper-dev)"
        echo "expecting version '$expected_version'"
    fi
    hr

    run ./check_zookeeper_version.py -e "$expected_version"

    run_fail 2 ./check_zookeeper_version.py -e "fail-version"

    run_conn_refused ./check_zookeeper_version.py -e "$expected_version"

    zookeeper_tests

    docker_exec check_zookeeper_child_znodes.pl -H localhost -z / --no-ephemeral-check -v

    echo "checking connection refused:"
    ERRCODE=2 docker_exec check_zookeeper_child_znodes.pl -H localhost -z / --no-ephemeral-check -v -P "$wrong_port"

    docker_exec check_zookeeper_znode.pl -H localhost -z / -v -n --child-znodes

    echo "checking connection refused:"
    ERRCODE=2 docker_exec check_zookeeper_znode.pl -H localhost -z / -v -n --child-znodes -P "$wrong_port"
    echo
    section2 "Now checking HAProxy ZooKeeper checks:"
    ZOOKEEPER_PORT="$HAPROXY_PORT" \
    zookeeper_tests

    # defined and tracked in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "Completed $run_count ZooKeeper tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
}

zookeeper_tests(){
    if [ "${version:0:3}" = "3.3" ]; then
        # $perl defined in bash-tools/lib/perl.sh (imported by utils.sh)
        # shellcheck disable=SC2154
        run_fail 3 "$perl" -T ./check_zookeeper.pl -s -w 50 -c 100 -v
    else
        run "$perl" -T ./check_zookeeper.pl -s -w 50 -c 100 -v
    fi

    run_conn_refused "$perl" -T ./check_zookeeper.pl -s -w 50 -c 100 -v

    docker_exec check_zookeeper_config.pl -H localhost -C "/zookeeper/conf/zoo.cfg" -v

    echo "checking connection refused:"
    ERRCODE=2 docker_exec check_zookeeper_config.pl -H localhost -C "/zookeeper/conf/zoo.cfg" -v -P "$wrong_port"
}

run_test_versions ZooKeeper

if is_CI; then
    docker_image_cleanup
    echo
fi
