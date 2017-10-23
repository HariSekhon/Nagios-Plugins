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

#export PRESTO_TERADATA_VERSIONS="latest 0.152 0.157 0.167 0.179"
export PRESTO_TERADATA_VERSIONS="latest 0.167 0.179"
export PRESTO_VERSIONS="${@:-${PRESTO_VERSIONS:-$PRESTO_TERADATA_VERSIONS}}"

PRESTO_HOST="${DOCKER_HOST:-${PRESTO_HOST:-${HOST:-localhost}}}"
PRESTO_HOST="${PRESTO_HOST##*/}"
PRESTO_HOST="${PRESTO_HOST%%:*}"
export PRESTO_HOST
export PRESTO_WORKER_HOST="$PRESTO_HOST"

export PRESTO_PORT_DEFAULT=8080
export PRESTO_PORT="${PRESTO_PORT:-$PRESTO_PORT_DEFAULT}"
# only for docker change default port
export PRESTO_WORKER_PORT_DEFAULT=8081
export PRESTO_WORKER_PORT="${PRESTO_WORKER_PORT:-$PRESTO_PORT}"

export PRESTO_ENVIRONMENT="${PRESTO_ENVIRONMENT:-development}"

if [ -z "${NODOCKER:-}" ]; then
    check_docker_available
fi

trap_debug_env presto

startupwait 30

presto_worker_tests(){
    if ! [ "$PRESTO_HOST" != "$PRESTO_WORKER_HOST" -o "$PRESTO_PORT" != "$PRESTO_WORKER_PORT" ]; then
        echo "Presto worker is not a separate host, skipping Presto Worker only checks"
        return 0
    fi
    echo "Now starting Presto Worker tests:"
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
    # doesn't show up as registered for a while, so run this test last and iterate for a little while
    max_node_up_wait=20
    echo "allowing to $max_node_up_wait secs for worker to be detected as online by the Presto Coordinator:"
    retry $max_node_up_wait ./check_presto_num_worker_nodes.py -w 1
    run++
    hr
    run_fail 3 ./check_presto_worker_node.py --list-nodes
    hr
    set +o pipefail
    worker_node="$(./check_presto_worker_node.py --list-nodes | tail -n 1)"
    set -o pipefail
    echo "determined presto worker from live running config = '$worker_node'"
    hr
    echo "lastResponseTime field is not immediately initialized in node data on coordinator, retrying for 10 secs to give node lastResponseTime a chance to be populated"
    retry 10 ./check_presto_worker_node.py --node "$worker_node"
    run++
    hr
    # strip https?:// leaving host:port
    worker_node="${worker_node/*\/}"
    run ./check_presto_worker_node.py --node "$worker_node"
    hr
    # strip :port leaving just host
    worker_node="${worker_node%:*}"
    run ./check_presto_worker_node.py --node "$worker_node"
    hr
    run_fail 2 ./check_presto_worker_node.py --node "nonexistentnode2"
    hr
    echo "retrying worker nodes failed as this doesn't settle immediately after node addition:"
    retry 10 ./check_presto_worker_nodes_failed.py
    run++
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
    run ./check_presto_worker_nodes_response_lag.py
    hr
    # will get a 404 Not Found against worker API
    run_fail 2 ./check_presto_worker_nodes_response_lag.py -P "$PRESTO_WORKER_PORT"
    hr
    run ./check_presto_worker_nodes_recent_failure_ratio.py
    hr
    # will get a 404 Not Found against worker API
    run_fail 2 ./check_presto_worker_nodes_recent_failure_ratio.py -P "$PRESTO_WORKER_PORT"
    hr
    run ./check_presto_worker_nodes_recent_failures.py
    hr
    # will get a 404 Not Found against worker API
    run_fail 2 ./check_presto_worker_nodes_recent_failures.py -P "$PRESTO_WORKER_PORT"
}

test_presto2(){
    local version="$1"
    run_count=0
    if [ -z "${NODOCKER:-}" ]; then
        DOCKER_CONTAINER="${DOCKER_CONTAINER:-$DOCKER_CONTAINER}"
        section2 "Setting up Presto $version test container"
        if is_CI; then
            VERSION="$version" docker-compose pull $docker_compose_quiet
        fi
        # reset container as we start a presto worker inside later so we don't want to start successive workers on compounding failed runs
        [ -n "${KEEPDOCKER:-}" ] || VERSION="$version" docker-compose down || :
        VERSION="$version" docker-compose up -d
        echo "getting Presto dynamic port mapping:"
        docker_compose_port PRESTO_PORT "Presto Coordinator"
    fi
    hr
    when_ports_available "$PRESTO_HOST" "$PRESTO_PORT"
    hr
    # endpoint initializes blank, wait until there is some content, eg. nodeId
    # don't just run ./check_presto_state.py
    when_url_content "http://$PRESTO_HOST:$PRESTO_PORT/v1/service/presto/general" nodeId
    hr
    if [ "$version" = "latest" -o "$version" = "NODOCKER" ]; then
        if [ "$teradata_distribution" = 1 ]; then
            echo "latest version, fetching latest version from DockerHub master branch"
            local version="$(dockerhub_latest_version presto)"
        else
            # don't want to have to pull presto versions script from Dockerfiles repo
            local version=".*"
        fi
        echo "expecting version '$version'"
    fi
    hr
    # presto service not found in list of endpoints initially even after it's come up, hence reason for when_url_content test above
    if [ -n "${NODOCKER:-}" ]; then
        # custom compiled presto has a version like 'dc91f48' which results in UNKNOWN: Presto Coordinator version unrecognized 'dc91f48'
        run_fail "0 3" ./check_presto_version.py --expected "$version(-t.\d+.\d+)?"
        hr
        run_fail "2 3" ./check_presto_version.py --expected "fail-version"
    else
        run ./check_presto_version.py --expected "$version(-t.\d+.\d+)?"
        hr
        run_fail 2 ./check_presto_version.py --expected "fail-version"
    fi
    hr
    run_conn_refused ./check_presto_version.py --expected "$version(-t.\d+.\d+)?"
    hr
    run ./check_presto_coordinator.py
    hr
    run_conn_refused ./check_presto_coordinator.py
    hr
    run ./check_presto_environment.py
    hr
    run ./check_presto_environment.py --expected "$PRESTO_ENVIRONMENT"
    hr
    run_conn_refused ./check_presto_environment.py --expected "$PRESTO_ENVIRONMENT"
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
    run_fail "0 1 2" ./check_presto_queries.py
    hr
    run_fail 3 ./check_presto_queries.py --list
    hr
    run ./check_presto_state.py
    hr
    run_conn_refused ./check_presto_state.py
    hr
    run_fail 2 ./check_presto_worker_node.py --node "nonexistentnode"
    hr
    run_fail 1 ./check_presto_worker_nodes_response_lag.py
    hr
    run_conn_refused ./check_presto_worker_nodes_response_lag.py
    hr
    run_fail 1 ./check_presto_worker_nodes_recent_failure_ratio.py
    hr
    run_conn_refused ./check_presto_worker_nodes_recent_failure_ratio.py
    hr
    run_fail 1 ./check_presto_worker_nodes_recent_failures.py
    hr
    run_conn_refused ./check_presto_worker_nodes_recent_failures.py
    hr
    if [ -n "${NODOCKER:-}" ]; then
        presto_worker_tests
        hr
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
    echo
    echo "creating some sample queries to test check_presto_queries.py against:"
    presto <<EOF2
    select 1+1;
    select 2+2;
    select 3+3;
    select failure;
    select failure2;
EOF2
EOF
    hr
    run_fail 3 ./check_presto_queries.py --list
    hr
    run ./check_presto_queries.py --exclude 'failure'
    hr
    run_fail 1 ./check_presto_queries.py
    hr
    run_fail 2 ./check_presto_queries.py -c 1
    hr
    run ./check_presto_queries.py --include 'select 1\+1'
    hr
    run_fail 1 ./check_presto_queries.py --include 'failure'
    hr
    run_fail 2 ./check_presto_queries.py --include 'failure' -c 1
    hr
    run_fail 1 ./check_presto_queries.py --include 'nonexistentquery'
    hr
    echo "getting Presto Worker dynamic port mapping:"
    docker_compose_port "Presto Worker"
    hr
    presto_worker_tests
    hr
    echo "finding presto docker container IP for specific node registered checks:"
    # hostname command not installed
    #hostname="$(docker exec -i "$DOCKER_CONTAINER" hostname -f)"
    # registering IP not hostname
    #hostname="$(docker exec -i "$DOCKER_CONTAINER" tail -n1 /etc/hosts | awk '{print $2}')"
    ip="$(docker exec -i "$DOCKER_CONTAINER" tail -n1 /etc/hosts | awk '{print $1}')"
    echo "determined presto container IP = '$ip'"
    hr
    echo "lastResponseTime field is not immediately initialized in node data on coordinator, retrying for 10 secs to give node lastResponseTime a chance to be populated"
    retry 10 ./check_presto_worker_node.py --node "http://$ip:$PRESTO_WORKER_PORT_DEFAULT"
    run++
    hr
    run ./check_presto_worker_node.py --node "$ip:$PRESTO_WORKER_PORT_DEFAULT"
    hr
    run ./check_presto_worker_node.py --node "$ip"
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
        if ./check_presto_worker_nodes_failed.py | tee /dev/stderr | grep -q -e 'WARNING: Presto SQL - 1 worker node failed' -e "500 Internal Server Error"; then
            break
        fi
        if [ $SECONDS -gt $max_detect_secs ]; then
            echo
            echo "FAILED: Presto worker did not detect worker failure after $max_detect_secs secs!"
            exit 1
        fi
        echo "waited $SECONDS secs, will try again until Presto coordinator detects worker failure..."
        # sleeping can miss API might change and hit 500 Internal Server Error bug as it only very briefly returns 1 failed node
        # sometimes misses the state change before the API breaks
        # do not enable
        #sleep 0.5
    done
    set -o pipefail
    # subsequent queries to the API expose a bug in the Presto API returning 500 Internal Server Error
    hr
    # XXX: this still passes as worker is still found, only response time lag and recent failures / recent failure ratios will reliably detect worker failure, not drop in the number of nodes
    run_fail "0 2" ./check_presto_num_worker_nodes.py -w 1
    hr
    run_fail 2 ./check_presto_worker_node.py --node "http://$ip:$PRESTO_WORKER_PORT_DEFAULT"
    hr
    run_fail 2 ./check_presto_worker_node.py --node "$ip:$PRESTO_WORKER_PORT_DEFAULT"
    hr
    run_fail 2 ./check_presto_worker_node.py --node "$ip"
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
    [ -z "${KEEPDOCKER:-}" ] || exit 0
    [ -n "${NODOCKER:-}" ] ||
    docker-compose down
    hr
    echo
}

if [ -n "${NODOCKER:-}" ]; then
    PRESTO_VERSIONS="NODOCKER"
fi

test_presto(){
    local version="$1"
    teradata_distribution=0
    for teradata_version in $PRESTO_TERADATA_VERSIONS; do
        if [ "$version" = "$teradata_version" ]; then
            teradata_distribution=1
            break
        fi
    done
    if [ "$teradata_distribution" = "1" ]; then
        echo "Testing Teradata's Presto distribution version:  '$version'"
        COMPOSE_FILE="$srcdir/docker/presto-docker-compose.yml" test_presto2 "$1"
        # must call this manually here as we're sneaking in an extra batch of tests that run_test_versions is generally not aware of
        let total_run_count+=$run_count
        # reset this so it can be used in test_presto to detect now testing Facebook
        teradata_distribution=0
    fi
    if [ -n "${NODOCKER:-}" ]; then
        echo "Testing External Presto:"
    else
        echo "Testing Facebook's Presto release version:  '$version'"
    fi
    COMPOSE_FILE="$srcdir/docker/presto-dev-docker-compose.yml" test_presto2 "$1"
}

run_test_versions Presto
