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

section "R e d i s"

export REDIS_VERSIONS="${@:-${REDIS_VERSIONS:-latest 2.6 2.8 3.0-alpine 3.2-alpine 4.0-alpine}}"

REDIS_HOST="${DOCKER_HOST:-${REDIS_HOST:-${HOST:-localhost}}}"
REDIS_HOST="${REDIS_HOST##*/}"
REDIS_HOST="${REDIS_HOST%%:*}"
export REDIS_HOST

export REDIS_PORT_DEFAULT="6379"

#export REDIS_PASSWORD="testpass123"
unset REDIS_PASSWORD
unset PASSWORD

export DOCKER_IMAGE="redis"

startupwait 5

check_docker_available

trap_debug_env redis

# TODO: redis authenticated container testing
test_redis(){
    local version="$1"
    section2 "Setting up Redis $version test container"
    if is_CI || [ -n "${DOCKER_PULL:-}" ]; then
        VERSION="$version" docker-compose pull $docker_compose_quiet
    fi
    VERSION="$version" docker-compose up -d
    echo "getting Redis dynamic port mapping:"
    docker_compose_port Redis
    hr
    when_ports_available "$REDIS_HOST" "$REDIS_PORT"
    hr
    echo "creating test Redis key-value"
    #echo set myKey hari | redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT"
    docker exec -i "$DOCKER_CONTAINER" sh <<EOF
        echo set myKey hari | redis-cli
EOF
    echo done
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    local version="${version%%-*}"
    if [ "$version" = "latest" ]; then
        local version=".*"
    fi
    run $perl -T ./check_redis_version.pl -v # -e "$version"  TODO: change to regex and enable this with .* for latest
    hr
    run_fail 2 $perl -T ./check_redis_version.pl -v -e 'fail-version'
    hr
    run_conn_refused $perl -T ./check_redis_version.pl -v
    hr
    # REDIS_HOST obtained via .travis.yml
    run $perl -T ./check_redis_clients.pl -v
    hr
    run_conn_refused $perl -T ./check_redis_clients.pl -v
    hr
    # there is no redis.conf in the Docker container :-/
    #docker cp "$DOCKER_CONTAINER":/etc/redis.conf /tmp/redis.conf
    # doesn't match
    #wget -O /tmp/redis.conf https://raw.githubusercontent.com/antirez/redis/3.0/redis.conf
    > /tmp/.check_redis_config.conf
    #$perl -T ./check_redis_config.pl -H $REDIS_HOST -C /tmp/.check_redis_config.conf --no-warn-extra -v | grep -v -e '^debug:' | sed 's/.*extra config found on running server://;s/=/ /g' | tr ',' '\n' | grep -v requirepass | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tee /tmp/.check_redis_config.conf
    run++
    echo "$perl -T ./check_redis_config.pl -H $REDIS_HOST -C /tmp/.check_redis_config.conf --no-warn-extra -v | grep -v -e '^debug:' | sed 's/.*extra config found on running server://;s/=/ /g' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tee /tmp/.check_redis_config.conf"
    $perl -T ./check_redis_config.pl -H $REDIS_HOST -C /tmp/.check_redis_config.conf --no-warn-extra -v | grep -v -e '^debug:' | sed 's/.*extra config found on running server://;s/=/ /g' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tee /tmp/.check_redis_config.conf
    run $perl -T ./check_redis_config.pl -H $REDIS_HOST -C /tmp/.check_redis_config.conf --no-warn-extra -vv
    hr
    run_conn_refused $perl -T ./check_redis_config.pl -H $REDIS_HOST -C /tmp/.check_redis_config.conf
    hr
    [ -z "${NODELETE:-1}" ] && rm -v /tmp/.check_redis_config.conf
    hr
    run $perl -T ./check_redis_key.pl -k myKey -e hari -v
    hr
    run_conn_refused $perl -T ./check_redis_key.pl -k myKey -e hari -v
    hr
    run $perl -T ./check_redis_publish_subscribe.pl -v
    hr
    run_conn_refused $perl -T ./check_redis_publish_subscribe.pl -v
    hr
    run $perl -T ./check_redis_stats.pl -v
    hr
    run_conn_refused $perl -T ./check_redis_stats.pl -v
    hr
    run $perl -T ./check_redis_stats.pl -s connected_clients -c 1:1 -v
    hr
    run_conn_refused $perl -T ./check_redis_stats.pl -s connected_clients -c 1:1 -v
    hr
    run $perl -T ./check_redis_write.pl -v
    hr
    run_conn_refused $perl -T ./check_redis_write.pl -v
    hr
    echo "checking for no code failure masking root cause in catch quit handler"
    ERRCODE=2 run_grep 'Connection refused' $perl -T ./check_redis_stats.pl -P 9999 -s connected_clients -c 1:1 -v
    hr
    echo "Completed $run_count Redis tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    hr
    echo
}

run_test_versions Redis
