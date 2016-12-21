#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-12-18 16:55:07 +0000 (Sun, 18 Dec 2016)
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

echo "
# ============================================================================ #
#                                R a b b i t M Q
# ============================================================================ #
"

export RABBITMQ_VERSIONS="${@:-${RABBITMQ_VERSIONS:-latest 3.4 3.5 3.6}}"

RABBITMQ_HOST="${DOCKER_HOST:-${RABBITMQ_HOST:-${HOST:-localhost}}}"
RABBITMQ_HOST="${RABBITMQ_HOST##*/}"
RABBITMQ_HOST="${RABBITMQ_HOST%%:*}"
export RABBITMQ_HOST

#export RABBITMQ_PORT="${RABBITMQ_PORT:-5672}"
#export RABBITMQ_HTTP_PORT="${RABBITMQ_HTTP_PORT:-15672}"
export RABBITMQ_PORT=5672
export RABBITMQ_HTTP_PORT=15672

# used by docker-compose config
export RABBITMQ_DEFAULT_VHOST="nagios-plugins"
export RABBITMQ_DEFAULT_USER="rabbituser"
export RABBITMQ_DEFAULT_PASS="rabbitpw"
# used by plugins
export RABBITMQ_VHOST="$RABBITMQ_DEFAULT_VHOST"
export RABBITMQ_USER="$RABBITMQ_DEFAULT_USER"
export RABBITMQ_PASSWORD="$RABBITMQ_DEFAULT_PASS"

export TEST_VHOSTS="$RABBITMQ_VHOST / /test test2"

check_docker_available

# needs to be longer than 10 to allow RabbitMQ to settle so topic creation works
startupwait 20

test_rabbitmq(){
    local version="$1"
    echo "Setting up RabbitMQ $version test containers"
    hr
    #local DOCKER_OPTS=""
    #launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $RABBITMQ_PORT
    local VERSION="$version-management"
    VERSION="${VERSION#latest-}"
    VERSION="$VERSION" docker-compose up -d
    rabbitmq_port="`docker-compose port "$DOCKER_SERVICE" "$RABBITMQ_PORT" | sed 's/.*://'`"
    rabbitmq_http_port="`docker-compose port "$DOCKER_SERVICE" "$RABBITMQ_HTTP_PORT" | sed 's/.*://'`"
    local RABBITMQ_PORT="$rabbitmq_port"
    local RABBITMQ_HTTP_PORT="$rabbitmq_http_port"
    echo "RabbitMQ Port = $RABBITMQ_PORT"
    echo "RabbitMQ HTTP Port = $RABBITMQ_HTTP_PORT"
    when_ports_available "$startupwait" "$RABBITMQ_HOST" "$RABBITMQ_PORT" "$RABBITMQ_HTTP_PORT"
    # echo sleeping 30 secs
    #sleep 30
    hr
    docker-compose exec "$DOCKER_SERVICE" bash <<-EOF
        # RabbitMQ 3.4 docker image doesn't auto-create the mgmt user or vhost based on the env vars like 3.6 :-/
        rabbitmqctl add_user "$RABBITMQ_USER" "$RABBITMQ_PASSWORD"
        rabbitmqctl set_user_tags "$RABBITMQ_USER" management

        for x in $TEST_VHOSTS vhost_with_tracing; do
            rabbitmqctl add_vhost \$x
            rabbitmqctl set_permissions -p \$x "$RABBITMQ_USER" '.*' '.*' '.*'
        done

        rabbitmqctl trace_on -p vhost_with_tracing

        exit
EOF
    if [ -n "${NOTESTS:-}" ]; then
        return 0
    fi
    version="${version%management}"
    version="${version%-}"
    if [ -z "$version" -o "$version" = "latest" ]; then
        local version=".*"
    fi
    hr
    ./check_rabbitmq_version.py -P "$RABBITMQ_HTTP_PORT" -e "$version"
    hr
    echo "check auth failure for version check"
    set +e
    ./check_rabbitmq_version.py -P "$RABBITMQ_HTTP_PORT" -u wronguser -e "$version"
    check_exit_code 2
    set -e
    hr
    ./check_rabbitmq.py -v
    hr
    set +e
    echo "checking auth failure for message pub-sub"
    ./check_rabbitmq.py -u wronguser -p wrongpassword -v
    check_exit_code 2
    hr
    echo "checking message pub-sub against non-existent vhost"
    ./check_rabbitmq.py -v -O "nonexistentvhost"
    check_exit_code 2
    set -e

    local RABBITMQ_PORT="$RABBITMQ_HTTP_PORT"
    hr
    for x in $TEST_VHOSTS; do
        ./check_rabbitmq_aliveness.py -O "$x"
        hr
        ./check_rabbitmq_vhost_exists.py -O "$x" --no-tracing
        hr
    done
    set +e
    echo "checking non-existent vhost raises aliveness critical for object not found:"
    ./check_rabbitmq_aliveness.py -O "nonexistentvhost"
    check_exit_code 2
    hr
    echo "checking non-existent vhost raises critical:"
    ./check_rabbitmq_vhost_exists.py -O "nonexistentvhost"
    check_exit_code 2
    echo "and with tracing:"
    ./check_rabbitmq_vhost_exists.py -O "nonexistentvhost" --no-tracing
    check_exit_code 2
    hr
    echo "checking vhost with tracing is still ok:"
    ./check_rabbitmq_vhost_exists.py -O "vhost_with_tracing"
    check_exit_code 0
    echo "checking vhost with tracing raises warning when using --no-tracing:"
    ./check_rabbitmq_vhost_exists.py -O "vhost_with_tracing" --no-tracing
    check_exit_code 1
    set -e
    hr
    # 3.5+ only
    if [ "$version" = "latest" ] ||
        [ ${version:0:1} -gt 3 ] ||
        [ ${version:0:1} -eq 3 -a ${version:2:1} -ge 5 ]; then
        # 3.6+ only
        if [ ${version:0:1} -lt 4 -a ${version:2:1} -ge 6 ]; then
            ./check_rabbitmq_healthchecks.py
            hr
        fi
        ./check_rabbitmq_stats_db_event_queue.py
        hr
        echo "check auth failure for stats db event queue check"
        set +e
        ./check_rabbitmq_stats_db_event_queue.py -u wronguser
        check_exit_code 2
        set -e
        hr
    fi
    #delete_container
    docker-compose down
    echo
}

for version in $(ci_sample $RABBITMQ_VERSIONS); do
    test_rabbitmq $version
done
