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

srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# needs to be longer to allow RabbitMQ Cluster to settle
startupwait 40

test_rabbitmq(){
    local version="$1"
    echo "Setting up RabbitMQ $version test containers"
    hr
    #local DOCKER_OPTS=""
    #launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $RABBITMQ_PORT
    local VERSION="$version"
    VERSION="${VERSION#latest-}"
    # if one container is already still up it'll result in inconsistent state error when the other tries to join cluster, causing rabbit2 joining node container to crash
    # so shut down any already existing containers for safety
    #docker-compose down
    VERSION="$VERSION" docker-compose up -d
    local DOCKER_SERVICE="rabbit1"
    local DOCKER_SERVICE2="rabbit2"
    rabbitmq_port="`docker-compose port "$DOCKER_SERVICE" "$RABBITMQ_PORT" | sed 's/.*://'`"
    rabbitmq_port2="`docker-compose port "$DOCKER_SERVICE2" "$RABBITMQ_PORT" | sed 's/.*://'`"
    rabbitmq_http_port="`docker-compose port "$DOCKER_SERVICE" "$RABBITMQ_HTTP_PORT" | sed 's/.*://'`"
    rabbitmq_http_port2="`docker-compose port "$DOCKER_SERVICE2" "$RABBITMQ_HTTP_PORT" | sed 's/.*://'`"
    local RABBITMQ_PORT="$rabbitmq_port"
    local RABBITMQ_PORT2="$rabbitmq_port2"
    local RABBITMQ_HTTP_PORT="$rabbitmq_http_port"
    local RABBITMQ_HTTP_PORT2="$rabbitmq_http_port2"
    echo "Rabbit1 Port = $RABBITMQ_PORT"
    echo "Rabbit2 Port = $RABBITMQ_PORT2"
    echo "Rabbit1 HTTP Port = $RABBITMQ_HTTP_PORT"
    echo "Rabbit2 HTTP Port = $RABBITMQ_HTTP_PORT2"
    when_ports_available "$startupwait" "$RABBITMQ_HOST" "$RABBITMQ_PORT" "$RABBITMQ_HTTP_PORT" "$RABBITMQ_PORT2" "$RABBITMQ_HTTP_PORT2"
    hr
    docker-compose exec "$DOCKER_SERVICE" bash <<-EOF
        # RabbitMQ 3.4 docker image doesn't auto-create the mgmt user or vhost based on the env vars like 3.6 :-/
        rabbitmqctl add_user "$RABBITMQ_USER" "$RABBITMQ_PASSWORD"
        rabbitmqctl set_user_tags "$RABBITMQ_USER" administrator

        for x in $TEST_VHOSTS vhost_with_tracing; do
            rabbitmqctl add_vhost \$x
            rabbitmqctl set_permissions -p \$x "$RABBITMQ_USER" '.*' '.*' '.*'
        done

        rabbitmqctl trace_on -p vhost_with_tracing

        exit
EOF
    rabbitmqadmin="tests/bin/rabbitmqadmin"
    if ! [ -x "$rabbitmqadmin" ]; then
        mkdir -p "$(dirname "$rabbitmqadmin")"
        wget -O "$rabbitmqadmin" "http://$RABBITMQ_HOST:$RABBITMQ_HTTP_PORT/cli/rabbitmqadmin"
        chmod +x "$rabbitmqadmin"
    fi
    rabbitmqadmin="$rabbitmqadmin -H $RABBITMQ_HOST -P $RABBITMQ_HTTP_PORT -u $RABBITMQ_USER -p $RABBITMQ_PASSWORD --vhost $RABBITMQ_VHOST"
    echo "Declaring exchanges, queues and bindings"
    $rabbitmqadmin declare exchange name=exchange1 type=topic durable=true
    $rabbitmqadmin declare exchange name=exchange2 type=fanout durable=false
    $rabbitmqadmin declare queue name=queue1 durable=true
    $rabbitmqadmin declare queue name=queue2 durable=false
    $rabbitmqadmin declare binding source="exchange1" destination_type="queue" destination="queue1" routing_key=""
    $rabbitmqadmin declare binding source="exchange2" destination_type="queue" destination="queue2" routing_key=""
    echo Done
    echo "Setting up HA on queue2"
    $rabbitmqadmin declare policy name='ha-two' pattern='^queue2$' definition='{"ha-mode":"exactly", "ha-params":2, "ha-sync-mode":"automatic"}'
    docker-compose exec "$DOCKER_SERVICE" bash <<-EOF
        rabbitmqctl set_policy ha-two "^queue2$"  '{"ha-mode":"exactly", "ha-params":2, "ha-sync-mode":"automatic"}'

        exit
EOF
    echo "Done"
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    version="${version%management}"
    version="${version%-}"
    local expected_version="$version"
    if [ -z "$expected_version" -o "$expected_version" = "latest" ]; then
        local expected_version=".*"
    fi
    hr
    ./check_rabbitmq_version.py -P "$RABBITMQ_HTTP_PORT" --expected "$expected_version"
    hr
    echo "check auth failure for version check:"
    set +e
    ./check_rabbitmq_version.py -P "$RABBITMQ_HTTP_PORT" -u wronguser --expected "$expected_version"
    check_exit_code 2
    set -e
    hr
    ./check_rabbitmq.py -v
    hr
    echo "and via non-durable queue2:"
    ./check_rabbitmq.py -v --queue queue2 --non-durable
    hr
    set +e
    echo "checking auth failure for message pub-sub:"
    ./check_rabbitmq.py -u wronguser -p wrongpassword -v
    check_exit_code 2
    hr
    echo "checking message pub-sub against non-existent vhost:"
    ./check_rabbitmq.py -v --vhost "nonexistentvhost"
    check_exit_code 2
    hr
    echo "checking mandatory flag publish failure:"
    ./check_rabbitmq.py -v --routing-key nonexistentroutingkey
    check_exit_code 2
    hr
    echo "checking message never received (pub-sub against wrong queue that won't receive the message):"
    ./check_rabbitmq.py -v --queue queue1 --routing-key queue2
    check_exit_code 2
    hr
    echo "checking exchange1 precondition failure for type topic vs direct:"
    ./check_rabbitmq.py -v --exchange exchange1
    check_exit_code 2
    hr
    echo "checking queue2 precondition failure for durable vs non-durable:"
    ./check_rabbitmq.py -v --queue queue2
    check_exit_code 2
    hr
    set -e

    local RABBITMQ_PORT="$RABBITMQ_HTTP_PORT"
    # ============================================================================ #
    hr
    echo "check_rabbitmq_auth.py:"
    ./check_rabbitmq_auth.py
    hr
    ./check_rabbitmq_auth.py --tag 'admin.*'
    hr
    set +e
    echo "checking auth failure:"
    ./check_rabbitmq_auth.py -u 'wronguser'
    check_exit_code 2
    hr
    echo "checking auth failure with differing tag:"
    ./check_rabbitmq_auth.py --tag 'monitoring'
    check_exit_code 2
    set -e
    hr
    # ============================================================================ #
    hr
    ./check_rabbitmq_cluster_name.py
    hr
    ./check_rabbitmq_cluster_name.py -e 'rabbit@rabb.t\d'
    hr
    ./check_rabbitmq_cluster_name.py -e 'rabbit@rabb.t\d' -P "$RABBITMQ_HTTP_PORT2"
    hr
    set +e
    echo "checking cluster name regex failure:"
    ./check_rabbitmq_cluster_name.py --expected 'wrongclustername'
    check_exit_code 2
    hr
    set -e
    # ============================================================================ #
    hr
    for x in $TEST_VHOSTS; do
        ./check_rabbitmq_aliveness.py --vhost "$x"
        hr
        ./check_rabbitmq_vhost.py --vhost "$x" --no-tracing
        hr
        ./check_rabbitmq_exchange.py --vhost "$x" --exchange amq.direct         --type direct   --durable true
        ./check_rabbitmq_exchange.py --vhost "$x" --exchange amq.fanout         --type fanout   --durable true
        ./check_rabbitmq_exchange.py --vhost "$x" --exchange amq.headers        --type headers  --durable true
        ./check_rabbitmq_exchange.py --vhost "$x" --exchange amq.match          --type headers  --durable true
        ./check_rabbitmq_exchange.py --vhost "$x" --exchange amq.rabbitmq.trace --type topic    --durable true
        ./check_rabbitmq_exchange.py --vhost "$x" --exchange amq.topic          --type topic    --durable true
        hr
    done
    # ============================================================================ #
    hr
    set +e
    echo "check_rabbitmq_aliveness raises critical for non-existent vhost object not found:"
    ./check_rabbitmq_aliveness.py --vhost "nonexistentvhost"
    check_exit_code 2
    set -e
    hr
    # ============================================================================ #
    hr
    echo "check_rabbitmq_exchange:"
    set +e
    ./check_rabbitmq_vhost.py --list-vhosts
    check_exit_code 3
    hr
    echo "check_rabbitmq_vhost.py raises critical for non-existent vhost:"
    ./check_rabbitmq_vhost.py --vhost "nonexistentvhost"
    check_exit_code 2
    hr
    echo "and with tracing:"
    ./check_rabbitmq_vhost.py --vhost "nonexistentvhost" --no-tracing
    check_exit_code 2
    hr
    echo "checking vhost with tracing is still ok:"
    ./check_rabbitmq_vhost.py --vhost "vhost_with_tracing"
    check_exit_code 0
    hr
    echo "checking vhost with tracing raises warning when using --no-tracing:"
    ./check_rabbitmq_vhost.py --vhost "vhost_with_tracing" --no-tracing
    check_exit_code 1
    set -e
    hr
    # ============================================================================ #
    hr
    echo "check_rabbitmq_exchange:"
    set +e
    ./check_rabbitmq_exchange.py --list-exchanges
    check_exit_code 3
    hr
    ./check_rabbitmq_exchange.py --exchange exchange1 -v
    check_exit_code 0
    hr
    echo "checking check_rabbitmq_exchange.py non-existent vhost raises critical:"
    ./check_rabbitmq_exchange.py --vhost "nonexistentvhost" --exchange amq.direct
    check_exit_code 2
    hr
    echo "checking check_rabbitmq_exchange.py non-existent exchange raises critical:"
    ./check_rabbitmq_exchange.py --exchange "nonexistentexchange"
    check_exit_code 2
    set -e
    hr
    # ============================================================================ #
    hr
    echo "check_rabbitmq_queue.py:"
    set +e
    ./check_rabbitmq_queue.py --list-queues
    check_exit_code 3
    set -e
    hr
    ./check_rabbitmq_queue.py --queue queue1 --durable true
    hr
    echo "with non-durable queue:"
    ./check_rabbitmq_queue.py --queue queue2 --durable false
    hr
    set +e
    echo "with non-durable queue where durable queue is found:"
    ./check_rabbitmq_queue.py --queue queue1 --durable false
    check_exit_code 2
    hr
    echo "with durable queue where non-durable queue is found:"
    ./check_rabbitmq_queue.py --queue queue2 --durable true
    check_exit_code 2
    set -e
    docker-compose exec "$DOCKER_SERVICE" bash <<-EOF
        rabbitmqctl sync_queue -p "$RABBITMQ_VHOST" queue2

        exit
EOF
    hr
    # ============================================================================ #
    hr
    # 3.5+ only
    echo $version
    if [ "$version" = "latest" ] ||
        [ ${version:0:1} -gt 3 ] ||
        [ ${version:0:1} -eq 3 -a ${version:2:1} -ge 5 ]; then
        # 3.6+ only
        if [ "$version" = "latest" ] ||
            [ ${version:0:1} -gt 3 ] ||
            [ ${version:0:1} -eq 3 -a ${version:2:1} -ge 6 ]; then
            echo "check_rabbitmq_healthchecks.py (RabbitMQ 3.6+ only):"
            ./check_rabbitmq_healthchecks.py
            hr
        fi
        hr
        echo "check_rabbitmq_stats_db_event_queue.py (RabbitMQ 3.5+ only):"
        ./check_rabbitmq_stats_db_event_queue.py
        hr
        echo "check auth failure for stats db event queue check"
        set +e
        ./check_rabbitmq_stats_db_event_queue.py -u wronguser
        check_exit_code 2
        set -e
        hr
        echo
        echo "Tests completed successfully for RabbitMQ version $version"
        echo
        hr
    fi
    #delete_container
    [ -z "${NODELETE:-}" ] &&
        docker-compose down
    echo
}

for version in $(ci_sample $RABBITMQ_VERSIONS); do
    test_rabbitmq $version
done
