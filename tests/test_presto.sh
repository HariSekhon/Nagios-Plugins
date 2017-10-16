#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-09-22 17:01:38 +0200 (Fri, 22 Sep 2017)
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
srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$srcdir/..";

. ./tests/utils.sh

section "P r e s t o   S Q L"

export PRESTO_TERADATA_VERSIONS="latest 0.152 0.157 0.167 0.179"
export PRESTO_VERSIONS="${@:-${PRESTO_VERSIONS:-$PRESTO_TERADATA_VERSIONS}}"

PRESTO_HOST="${DOCKER_HOST:-${PRESTO_HOST:-${HOST:-localhost}}}"
PRESTO_HOST="${PRESTO_HOST##*/}"
PRESTO_HOST="${PRESTO_HOST%%:*}"
export PRESTO_HOST

export PRESTO_PORT_DEFAULT=8080
export PRESTO_PORT="$PRESTO_PORT_DEFAULT"
export PRESTO_WORKER_PORT_DEFAULT=8081
export PRESTO_WORKER_PORT="$PRESTO_WORKER_PORT_DEFAULT"

check_docker_available

trap_debug_env presto

startupwait 30

test_presto(){
    local version="$1"
    run_count=0
    DOCKER_CONTAINER="${DOCKER_CONTAINER:-nagiosplugins_${DOCKER_SERVICE}_1}"
    if [ -z "${NODOCKER:-}" ]; then
        section2 "Setting up Presto $version test container"
        if is_CI; then
            VERSION="$version" docker-compose pull $docker_compose_quiet
        fi
        # reset container as we start a presto worker inside later so we don't want to start successive workers on compounding failed runs
        VERSION="$version" docker-compose down || :
        VERSION="$version" docker-compose up -d
        echo "getting Presto dynamic port mapping:"
        printf "Presto Coordinator port => "
        export PRESTO_PORT="`docker-compose port "$DOCKER_SERVICE" "$PRESTO_PORT_DEFAULT" | sed 's/.*://'`"
        echo "$PRESTO_PORT"
        hr
        when_ports_available "$PRESTO_HOST" "$PRESTO_PORT"
        hr
        # endpoint initializes blank, wait until there is some content, eg. nodeId
        # don't just run ./check_presto_state.py
        when_url_content "http://$PRESTO_HOST:$PRESTO_PORT/v1/service/presto/general" nodeId
        hr
    fi
    if [ "$version" = "latest" ]; then
        version=".*"
    fi
    hr
    # presto service not found in list of endpoints initially even after it's come up
    run ./check_presto_version.py --expected "$version(-t.\d+.\d+)?"
    hr
    run_fail 2 ./check_presto_version.py --expected "fail-version"
    hr
    run_conn_refused ./check_presto_version.py --expected "$version(-t.\d+.\d+)?"
    hr
    run ./check_presto_coordinator.py
    hr
    run_conn_refused ./check_presto_coordinator.py
    hr
    run ./check_presto_environment.py
    hr
    run ./check_presto_environment.py --expected development
    hr
    run_conn_refused ./check_presto_environment.py --expected development
    hr
    run ./check_presto_worker_nodes_failed.py
    hr
    run_conn_refused ./check_presto_worker_nodes_failed.py
    hr
    run ./check_presto_num_queries.py
    hr
    run_conn_refused ./check_presto_num_queries.py
    hr
    run_fail 2 ./check_presto_num_worker_nodes.py -w 1
    hr
    run_conn_refused ./check_presto_num_worker_nodes.py -w 1
    hr
    run ./check_presto_state.py
    hr
    run_conn_refused ./check_presto_state.py
    hr
    run ./check_presto_worker_nodes_response_lag.py
    hr
    run_conn_refused ./check_presto_worker_nodes_response_lag.py
    hr
    run ./check_presto_worker_nodes_recent_failure_ratio.py
    hr
    run_conn_refused ./check_presto_worker_nodes_recent_failure_ratio.py
    hr
    run ./check_presto_worker_nodes_recent_failures.py
    hr
    run_conn_refused ./check_presto_worker_nodes_recent_failures.py
    hr
    if [ -n "${NODOCKER:-}" ]; then
        echo "External Presto, skipping worker setup + teardown checks..."
        echo
        echo "Completed $run_count Presto tests"
        return 0
    fi
    # Starting process in the same container for convenience, short lived only for tests so doesn't need separate container
    echo "Now reconfiguring to run additional Presto worker:"
    docker exec -i "$DOCKER_CONTAINER" bash <<EOF
    # set -x
    set -euo pipefail
    if [ -d /etc/presto ]; then
        echo "detected Teradata distribution path"
        BIN_DIR=/usr/lib/presto/bin
        CONF_DIR=/etc/presto
    elif [ -d /presto/ ]; then
        echo "detected Facebook distribution path"
        BIN_DIR=/presto/bin
        CONF_DIR=/presto/etc
    else
        echo "FAILED to detect Presto paths!"
        exit 1
    fi
    for x in node config; do
        cp -vf "\$CONF_DIR"/"\$x".properties{,.worker}
    done
    sed -i 's/node.id=.*/node.id=2/' "\$CONF_DIR"/node.properties.worker
    sed -i 's/coordinator=true/coordinator=false/' "\$CONF_DIR"/config.properties.worker
    sed -i 's/http-server.http.port=8080/http-server.http.port=8081/' "\$CONF_DIR"/config.properties.worker
    "\$BIN_DIR"/launcher --config="\$CONF_DIR"/config.properties.worker --node-config "\$CONF_DIR"/node.properties.worker --pid-file /var/run/worker-launcher.pid start
EOF
    hr
    echo "getting Presto Worker dynamic port mapping:"
    printf "Presto Worker port => "
    export PRESTO_WORKER_PORT="`docker-compose port "$DOCKER_SERVICE" "$PRESTO_WORKER_PORT_DEFAULT" | sed 's/.*://'`"
    echo "$PRESTO_WORKER_PORT"
    hr
    when_url_content "http://$PRESTO_HOST:$PRESTO_WORKER_PORT/v1/service/general/presto" environment # or "services" which is blank on worker
    hr
    # this info is not available via the Presto worker API
    run_fail 3 ./check_presto_version.py --expected "$version(-t.\d+.\d+)?" -P "$PRESTO_WORKER_PORT"
    hr
    run_fail 2 ./check_presto_coordinator.py -P "$PRESTO_WORKER_PORT"
    hr
    run ./check_presto_environment.py -P "$PRESTO_WORKER_PORT"
    hr
    run ./check_presto_environment.py --expected development -P "$PRESTO_WORKER_PORT"
    hr
    run ./check_presto_state.py -P "$PRESTO_WORKER_PORT"
    hr
    # will get a 404 Not Found against worker API
    run_fail 2 ./check_presto_worker_nodes_failed.py -P "$PRESTO_WORKER_PORT"
    hr
    # will get a 404 Not Found against worker API
    run_fail 2 ./check_presto_num_queries.py -P "$PRESTO_WORKER_PORT"
    hr
    # will get a 404 Not Found against worker API
    run_fail 2 ./check_presto_num_worker_nodes.py -w 1 -P "$PRESTO_WORKER_PORT"
    hr
    # will get a 404 Not Found against worker API
    run_fail 2 ./check_presto_worker_nodes_response_lag.py -P "$PRESTO_WORKER_PORT"
    hr
    # will get a 404 Not Found against worker API
    run_fail 2 ./check_presto_worker_nodes_recent_failure_ratio.py -P "$PRESTO_WORKER_PORT"
    hr
    # will get a 404 Not Found against worker API
    run_fail 2 ./check_presto_worker_nodes_recent_failures.py -P "$PRESTO_WORKER_PORT"
    hr
    echo "Now killing Presto Worker:"
    # Presto Worker runs the same com.facebook.presto.server.PrestoServer class with a different node id
    # worker doesn't show up as a failed node in coorindator API if we send a polite kill signal, must kill -9 worker
    docker exec -i "$DOCKER_CONTAINER" /usr/bin/pkill -9 -f -- -Dnode.id=2
    # This doesn't work because the port still responds as open, even when the mapped port is down
    # must be a result of docker networking
    #when_ports_down 20  "$PRESTO_HOST" "$PRESTO_WORKER_PORT"
    SECONDS=0
    max_kill_time=20
    while docker exec "$DOCKER_CONTAINER" ps -ef | grep -q -- -Dnode.id=2; do
        if [ $SECONDS -gt $max_kill_time ]; then
            echo "Presto Worker process did not go down after $max_kill_time secs!"
            exit 1
        fi
        echo "waiting for Presto Worker process to go down"
        sleep 1
    done
    hr
    run_fail 2 ./check_presto_state.py -P "$PRESTO_WORKER_PORT"
    hr
    echo "re-running failed worker node check against the coordinator API to detect failure of the worker we just killed:"
    # usually detects in around 5-10 secs
    max_detect_secs=60
    set +o pipefail
    SECONDS=0
    while true; do
        # can't just test status code as gets 500 Internal Server Error within a few secs
        if ./check_presto_worker_nodes_failed.py | tee /dev/stderr | grep -q 'WARNING: Presto SQL 1 worker node failed'; then
            break
        fi
        if [ $SECONDS -gt $max_detect_secs ]; then
            echo
            echo "FAILED: Presto worker did not detect worker failure after $max_detect_secs secs!"
            exit 1
        fi
        echo "waited $SECONDS secs, will try again until Presto coordinator detects worker failure..."
        # sleeping is risky - API might change and hit 500 Internal Server Error bug as it only very briefly returns 1 failed node which we're relying on to to break this loop (will otherwise be caught by timeout and failed)
        # sometimes misses the state change before the API breaks, do not enable
        #sleep 0.5
    done
    set -o pipefail
    # subsequent queries to the API expose a bug in the Presto API returning 500 Internal Server Error
    hr
    # XXX: must permit error state 2 on checks below to pass 500 Internal Server Error caused by Presto Bug
    run_fail "1 2" ./check_presto_worker_nodes_failed.py
    hr
    run_fail "0 2" ./check_presto_worker_nodes_response_lag.py --max-age 1
    hr
    run_fail "1 2" ./check_presto_worker_nodes_recent_failure_ratio.py
    hr
    run_fail "1 2" ./check_presto_worker_nodes_recent_failures.py
    hr
    echo "Completed $run_count Presto tests"
    hr
    [ -n "${KEEPDOCKER:-}" -o -n "${NODOCKER:-}" ] ||
    docker-compose down
    hr
    echo
}

if [ -n "${@:-}" ]; then
    for version in "$@"; do
        teradata_distribution=0
        if [ "$version" = "latest" ]; then
            echo "Testing Facebook's latest presto release before Teradata's latest distribution:"
            COMPOSE_FILE="$srcdir/docker/presto-dev-docker-compose.yml" test_presto latest
            # must call this manually as not using standard run_test_versions() function here which normally adds this
            let total_run_count+=$run_count
            echo
            hr
            teradata_distribution=1
        else
            for teradata_version in $PRESTO_TERADATA_VERSIONS; do
                if [ "$version" = "$teradata_version" ]; then
                    teradata_distribution=1
                    break
                fi
            done
        fi
        if [ "$teradata_distribution" = "1" ]; then
            echo "Testing Teradata's Presto distribution '$version':"
            COMPOSE_FILE="$srcdir/docker/presto-docker-compose.yml" test_presto "$1"
        else
            echo "Testing Facebook's Presto release '$version':"
            COMPOSE_FILE="$srcdir/docker/presto-dev-docker-compose.yml" test_presto "$1"
        fi
        # must call this manually as not using standard run_test_versions() function here which normally adds this
        let total_run_count+=$run_count
    done
    untrap
    echo "All Presto tests succeeded for versions: $@"
    echo
    echo "Total Tests run: $total_run_count"
else
    echo "Testing Facebook's latest presto release before Teradata distribution:"
    COMPOSE_FILE="$srcdir/docker/presto-dev-docker-compose.yml" test_presto latest
    echo
    hr
    echo
    echo "Now testing Teradata's distribution:"
    COMPOSE_FILE="$srcdir/docker/presto-docker-compose.yml" run_test_versions presto
fi
