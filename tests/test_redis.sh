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

section "R e d i s"

export REDIS_VERSIONS="${*:-${REDIS_VERSIONS:-2.6 2.8 3.0-alpine 3.2-alpine 4.0-alpine latest}}"

REDIS_HOST="${DOCKER_HOST:-${REDIS_HOST:-${HOST:-localhost}}}"
REDIS_HOST="${REDIS_HOST##*/}"
REDIS_HOST="${REDIS_HOST%%:*}"
export REDIS_HOST

export REDIS_PORT_DEFAULT=6379
export HAPROXY_PORT_DEFAULT=6379

#export REDIS_PASSWORD="testpass123"
unset REDIS_PASSWORD
unset PASSWORD

startupwait 5

check_docker_available

trap_debug_env redis

# TODO: redis authenticated container testing
test_redis(){
    local version="$1"
    section2 "Setting up Redis $version test container"
    docker_compose_pull
    VERSION="$version" docker-compose up -d --remove-orphans
    hr
    echo "getting Redis dynamic port mapping:"
    docker_compose_port Redis
    DOCKER_SERVICE=redis-haproxy docker_compose_port HAProxy
    hr
    # shellcheck disable=SC2153
    when_ports_available "$REDIS_HOST" "$REDIS_PORT" "$HAPROXY_PORT"
    hr
    if [ -z "${NOSETUP:-}" ]; then
        echo "creating test Redis key-value"
        #echo set myKey hari | redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT"
        docker exec -i "$DOCKER_CONTAINER" sh <<EOF
            echo set myKey hari | redis-cli
EOF
        echo "Done"
        hr
    fi
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    local expected_version
    export expected_version="${version%%-*}"
    if [ "$version" = "latest" ]; then
        local version=".*"
    fi

    redis_tests

    redis_test_conn_refused

    echo
    section2 "HAProxy Redis tests:"
    echo

    REDIS_PORT="$HAPROXY_PORT" \
    redis_tests

    [ -z "${NODELETE:-}" ] && rm -v /tmp/.check_redis_config.conf

    # defined and tracked in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "Completed $run_count Redis tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    hr
    echo
}

redis_tests(){
    # $perl defined in bash-tools/lib/perl.sh (imported by utils.sh)
    # shellcheck disable=SC2154
    run "$perl" -T ./check_redis_version.pl -v # -e "$version"  TODO: change to regex and enable this with .* for latest

    run_fail 2 "$perl" -T ./check_redis_version.pl -v -e 'fail-version'

    # there is no redis.conf in the Docker container :-/
    #docker cp "$DOCKER_CONTAINER":/etc/redis.conf /tmp/redis.conf
    # doesn't match
    #wget -O /tmp/redis.conf https://raw.githubusercontent.com/antirez/redis/3.0/redis.conf
    echo > /tmp/.check_redis_config.conf
    #$perl -T ./check_redis_config.pl -H $REDIS_HOST -C /tmp/.check_redis_config.conf --no-warn-extra -v | grep -v -e '^debug:' | sed 's/.*extra config found on running server://;s/=/ /g' | tr ',' '\n' | grep -v requirepass | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tee /tmp/.check_redis_config.conf
    run++
    # shellcheck disable=SC2028
    echo "$perl -T ./check_redis_config.pl -H $REDIS_HOST -C /tmp/.check_redis_config.conf --no-warn-extra -v | grep -v -e '^debug:' | sed 's/.*extra config found on running server://;s/=/ /g' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tee /tmp/.check_redis_config.conf"
    "$perl" -T ./check_redis_config.pl -H "$REDIS_HOST" -C /tmp/.check_redis_config.conf --no-warn-extra -v | grep -v -e '^debug:' | sed 's/.*extra config found on running server://;s/=/ /g' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tee /tmp/.check_redis_config.conf
    run "$perl" -T ./check_redis_config.pl -H "$REDIS_HOST" -C /tmp/.check_redis_config.conf --no-warn-extra -vv

    run "$perl" -T ./check_redis_clients.pl -v

    run "$perl" -T ./check_redis_stats.pl -v

    run "$perl" -T ./check_redis_key.pl -k myKey -e hari -v

    run "$perl" -T ./check_redis_publish_subscribe.pl -v

    run "$perl" -T ./check_redis_stats.pl -s connected_clients -c 1:1 -v

    run "$perl" -T ./check_redis_write.pl -v

    echo "checking for no code failure masking root cause in catch quit handler"
    ERRCODE=2 run_grep 'Connection refused' "$perl" -T ./check_redis_stats.pl -P 9999 -s connected_clients -c 1:1 -v
}

redis_test_conn_refused(){
    run_conn_refused "$perl" -T ./check_redis_version.pl -v
    run_conn_refused "$perl" -T ./check_redis_config.pl -H "$REDIS_HOST" -C /tmp/.check_redis_config.conf
    run_conn_refused "$perl" -T ./check_redis_clients.pl -v
    run_conn_refused "$perl" -T ./check_redis_stats.pl -v
    run_conn_refused "$perl" -T ./check_redis_key.pl -k myKey -e hari -v
    run_conn_refused "$perl" -T ./check_redis_publish_subscribe.pl -v
    run_conn_refused "$perl" -T ./check_redis_stats.pl -s connected_clients -c 1:1 -v
    run_conn_refused "$perl" -T ./check_redis_write.pl -v
}

run_test_versions Redis

if is_CI; then
    docker_image_cleanup
    echo
fi
