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

section "R a b b i t M Q"

export RABBITMQ_VERSIONS="${@:-${RABBITMQ_VERSIONS:-latest 3.4 3.5 3.6}}"

RABBITMQ_HOST="${DOCKER_HOST:-${RABBITMQ_HOST:-${HOST:-localhost}}}"
RABBITMQ_HOST="${RABBITMQ_HOST##*/}"
RABBITMQ_HOST="${RABBITMQ_HOST%%:*}"
export RABBITMQ_HOST

#export RABBITMQ_PORT="${RABBITMQ_PORT:-5672}"
#export RABBITMQ_HTTP_PORT="${RABBITMQ_HTTP_PORT:-15672}"
export RABBITMQ_PORT_DEFAULT=5672
export RABBITMQ_HTTP_PORT_DEFAULT=15672

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

trap_debug_env rabbitmq

# needs to be longer to allow RabbitMQ Cluster to settle
startupwait 40

test_rabbitmq(){
    local version="$1"
    section2 "Setting up RabbitMQ $version test containers"
    local VERSION="$version"
    VERSION="${VERSION#latest-}"
    # if one container is already still up it'll result in inconsistent state error when the other tries to join cluster, causing rabbit2 joining node container to crash
    # so shut down any already existing containers for safety
    #docker-compose down
    VERSION="$version" docker-compose pull $docker_compose_quiet
    VERSION="$VERSION" docker-compose up -d
    local DOCKER_SERVICE="rabbit1"
    local DOCKER_SERVICE2="rabbit2"
    echo "getting RabbitMQ dynamic port mappings:"
    printf "RabbitMQ node 1 port => "
    export RABBITMQ_PORT="`docker-compose port "$DOCKER_SERVICE" "$RABBITMQ_PORT_DEFAULT" | sed 's/.*://'`"
    echo "$RABBITMQ_PORT"
    printf "RabbitMQ node 2 port => "
    export RABBITMQ_PORT2="`docker-compose port "$DOCKER_SERVICE2" "$RABBITMQ_PORT_DEFAULT" | sed 's/.*://'`"
    echo "$RABBITMQ_PORT2"
    printf "RabbitMQ node 1 HTTP port => "
    export RABBITMQ_HTTP_PORT="`docker-compose port "$DOCKER_SERVICE" "$RABBITMQ_HTTP_PORT_DEFAULT" | sed 's/.*://'`"
    echo "$RABBITMQ_HTTP_PORT"
    printf "RabbitMQ node 2 HTTP port => "
    export RABBITMQ_HTTP_PORT2="`docker-compose port "$DOCKER_SERVICE2" "$RABBITMQ_HTTP_PORT_DEFAULT" | sed 's/.*://'`"
    echo "$RABBITMQ_HTTP_PORT2"
    hr
    when_ports_available "$startupwait" "$RABBITMQ_HOST" "$RABBITMQ_PORT" "$RABBITMQ_HTTP_PORT" "$RABBITMQ_PORT2" "$RABBITMQ_HTTP_PORT2"
    hr
    echo "setting up RabbitMQ environment"
    docker exec -i "nagiosplugins_${DOCKER_SERVICE}_1" bash <<EOF
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
    hr
    rabbitmqadmin="tests/bin/rabbitmqadmin"
    if [ -x "$rabbitmqadmin" ]; then
        echo "$rabbitmqadmin found"
    else
        mkdir -vp "$(dirname "$rabbitmqadmin")"
        echo "downloading rabbitmqadmin from RabbitMQ instance"
        wget -O "$rabbitmqadmin" "http://$RABBITMQ_HOST:$RABBITMQ_HTTP_PORT/cli/rabbitmqadmin"
        chmod +x "$rabbitmqadmin"
    fi
    hr
    rabbitmqadmin="$rabbitmqadmin -H $RABBITMQ_HOST -P $RABBITMQ_HTTP_PORT -u $RABBITMQ_USER -p $RABBITMQ_PASSWORD --vhost $RABBITMQ_VHOST"
    echo "Declaring exchanges, queues and bindings"
    $rabbitmqadmin declare exchange name=exchange1 type=topic durable=true
    $rabbitmqadmin declare exchange name=exchange2 type=fanout durable=false
    $rabbitmqadmin declare queue name=queue1 durable=true
    $rabbitmqadmin declare queue name=queue2 durable=false
    $rabbitmqadmin declare binding source="exchange1" destination_type="queue" destination="queue1" routing_key=""
    $rabbitmqadmin declare binding source="exchange2" destination_type="queue" destination="queue2" routing_key=""
    hr
    echo "Setting up HA on queue2"
    $rabbitmqadmin declare policy name='ha-two' pattern='^queue2$' definition='{"ha-mode":"exactly", "ha-params":2, "ha-sync-mode":"automatic"}'
    docker exec -i "nagiosplugins_${DOCKER_SERVICE}_1" bash <<EOF
        rabbitmqctl set_policy ha-two "^queue2$"  '{"ha-mode":"exactly", "ha-params":2, "ha-sync-mode":"automatic"}'

        exit
EOF
    hr
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
    run ./check_rabbitmq_version.py -P "$RABBITMQ_HTTP_PORT" --expected "$expected_version"
    hr
    run_conn_refused ./check_rabbitmq_version.py --expected "$expected_version"
    hr
    echo "check auth failure for version check:"
    run_fail 2 ./check_rabbitmq_version.py -P "$RABBITMQ_HTTP_PORT" -u wronguser --expected "$expected_version"
    hr
    run ./check_rabbitmq.py -v
    hr
    run_conn_refused ./check_rabbitmq.py -v
    hr
    echo "and via non-durable queue2:"
    run ./check_rabbitmq.py -v --queue queue2 --non-durable
    hr
    echo "checking auth failure for message pub-sub:"
    run_fail 2 ./check_rabbitmq.py -u wronguser -p wrongpassword -v
    hr
    echo "checking message pub-sub against non-existent vhost:"
    run_fail 2 ./check_rabbitmq.py -v --vhost "nonexistentvhost"
    hr
    echo "checking mandatory flag publish failure:"
    run_fail 2 ./check_rabbitmq.py -v --routing-key nonexistentroutingkey
    hr
    echo "checking message never received (pub-sub against wrong queue that won't receive the message):"
    run_fail 2 ./check_rabbitmq.py -v --queue queue1 --routing-key queue2
    hr
    echo "checking exchange1 precondition failure for type topic vs default direct:"
    run_fail 2 ./check_rabbitmq.py -v --exchange exchange1
    hr
    echo "checking queue2 precondition failure for durable vs non-durable:"
    run_fail 2 ./check_rabbitmq.py -v --queue queue2
    hr

    local RABBITMQ_PORT="$RABBITMQ_HTTP_PORT"
    # ============================================================================ #
    hr
    run ./check_rabbitmq_auth.py
    hr
    run_conn_refused ./check_rabbitmq_auth.py
    hr
    run ./check_rabbitmq_auth.py --tag 'admin.*'
    hr
    echo "checking auth failure:"
    run_fail 2 ./check_rabbitmq_auth.py -u 'wronguser'
    hr
    echo "checking auth failure with differing tag:"
    run_fail 2 ./check_rabbitmq_auth.py --tag 'monitoring'
    hr
    # ============================================================================ #
    hr
    run ./check_rabbitmq_cluster_name.py
    hr
    run_conn_refused ./check_rabbitmq_cluster_name.py
    hr
    run ./check_rabbitmq_cluster_name.py -e 'rabbit@rabb.t\d'
    hr
    run ./check_rabbitmq_cluster_name.py -e 'rabbit@rabb.t\d' -P "$RABBITMQ_HTTP_PORT2"
    hr
    echo "checking cluster name regex failure:"
    run_fail 2 ./check_rabbitmq_cluster_name.py --expected 'wrongclustername'
    hr
    # ============================================================================ #
    hr
    for x in $TEST_VHOSTS; do
        run ./check_rabbitmq_aliveness.py --vhost "$x"
        hr
        run ./check_rabbitmq_vhost.py --vhost "$x" --no-tracing
        hr
        run ./check_rabbitmq_exchange.py --vhost "$x" --exchange amq.direct         --type direct   --durable true
        hr
        run ./check_rabbitmq_exchange.py --vhost "$x" --exchange amq.fanout         --type fanout   --durable true
        hr
        run ./check_rabbitmq_exchange.py --vhost "$x" --exchange amq.headers        --type headers  --durable true
        hr
        run ./check_rabbitmq_exchange.py --vhost "$x" --exchange amq.match          --type headers  --durable true
        hr
        run ./check_rabbitmq_exchange.py --vhost "$x" --exchange amq.rabbitmq.trace --type topic    --durable true
        hr
        run ./check_rabbitmq_exchange.py --vhost "$x" --exchange amq.topic          --type topic    --durable true
        hr
    done
    # ============================================================================ #
    hr
    set +e
    echo "check raises critical for non-existent vhost object not found:"
    run_fail 2 ./check_rabbitmq_aliveness.py --vhost "nonexistentvhost"
    hr
    run_conn_refused ./check_rabbitmq_aliveness.py --vhost "/"
    hr
    # ============================================================================ #
    hr
    run_fail 3 ./check_rabbitmq_vhost.py --list-vhosts
    hr
    run_conn_refused ./check_rabbitmq_vhost.py --list-vhosts
    hr
    echo "check raises critical for non-existent vhost:"
    run_fail 2 ./check_rabbitmq_vhost.py --vhost 'nonexistentvhost'
    hr
    echo "and with tracing:"
    run_fail 2 ./check_rabbitmq_vhost.py --vhost 'nonexistentvhost' --no-tracing
    hr
    echo "checking vhost with tracing is still ok:"
    run ./check_rabbitmq_vhost.py --vhost 'vhost_with_tracing'
    hr
    echo "checking vhost with tracing raises warning when using --no-tracing:"
    run_fail 1 ./check_rabbitmq_vhost.py --vhost 'vhost_with_tracing' --no-tracing
    hr
    # ============================================================================ #
    hr
    run_fail 3 ./check_rabbitmq_exchange.py --list-exchanges
    hr
    run_conn_refused ./check_rabbitmq_exchange.py --list-exchanges
    hr
    run ./check_rabbitmq_exchange.py --exchange exchange1 -v --type topic
    hr
    echo "check non-existent vhost raises critical:"
    run_fail 2 ./check_rabbitmq_exchange.py --vhost 'nonexistentvhost' --exchange amq.direct
    hr
    echo "check non-existent exchange raises critical:"
    run_fail 2 ./check_rabbitmq_exchange.py --exchange 'nonexistentexchange'
    hr
    # ============================================================================ #
    hr
    run_fail 3 ./check_rabbitmq_queue.py --list-queues
    hr
    run_conn_refused ./check_rabbitmq_queue.py --list-queues
    hr
    run ./check_rabbitmq_queue.py --queue queue1 --durable true
    hr
    echo "with non-durable queue:"
    run ./check_rabbitmq_queue.py --queue queue2 --durable false
    hr
    echo "with non-durable queue where durable queue is found:"
    run_fail 2 ./check_rabbitmq_queue.py --queue queue1 --durable false
    hr
    echo "with durable queue where non-durable queue is found:"
    run_fail 2 ./check_rabbitmq_queue.py --queue queue2 --durable true
    hr
    docker exec -i "nagiosplugins_${DOCKER_SERVICE}_1" bash <<EOF
        rabbitmqctl sync_queue -p "$RABBITMQ_VHOST" queue2

        exit
EOF
    hr
    # ============================================================================ #
    hr
    run_conn_refused ./check_rabbitmq_healthchecks.py
    hr
    run_conn_refused ./check_rabbitmq_stats_db_event_queue.py
    hr
    # 3.5+ only
    echo "version: $version"
    hr
    if [ "$version" = "latest" ] ||
        [ ${version:0:1} -gt 3 ] ||
        [ ${version:0:1} -eq 3 -a ${version:2:1} -ge 5 ]; then
        # 3.6+ only
        if [ "$version" = "latest" ] ||
            [ ${version:0:1} -gt 3 ] ||
            [ ${version:0:1} -eq 3 -a ${version:2:1} -ge 6 ]; then
            echo "(RabbitMQ 3.6+ only):"
            run ./check_rabbitmq_healthchecks.py
            hr
        fi
        hr
        echo "(RabbitMQ 3.5+ only):"
        run ./check_rabbitmq_stats_db_event_queue.py
        hr
        echo "check auth failure for stats db event queue check"
        run_fail 2 ./check_rabbitmq_stats_db_event_queue.py -u wronguser
        hr
        echo
        echo "Tests completed successfully for RabbitMQ version $version"
        echo
        hr
    fi
    echo "Completed $run_count RabbitMQ tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    echo
}

run_test_versions RabbitMQ
