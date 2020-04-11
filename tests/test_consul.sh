#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-01-26 23:36:03 +0000 (Tue, 26 Jan 2016)
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

section "C o n s u l"

export CONSUL_VERSIONS="${*:-${CONSUL_VERSIONS:-0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 latest}}"

CONSUL_HOST="${DOCKER_HOST:-${CONSUL_HOST:-${HOST:-localhost}}}"
CONSUL_HOST="${CONSUL_HOST##*/}"
CONSUL_HOST="${CONSUL_HOST%%:*}"
export CONSUL_HOST

export CONSUL_PORT_DEFAULT=8500
export HAPROXY_PORT_DEFAULT=8500

export DOCKER_IMAGE="harisekhon/consul"

# used by docker_compose_exec
export DOCKER_MOUNT_DIR="/pl"

startupwait 10

check_docker_available

trap_debug_env consul

test_consul(){
    local version="$1"
    section2 "Setting up Consul $version test container"
    docker_compose_pull
    VERSION="$version" docker-compose up -d --remove-orphans
    hr
    echo "getting Consul dynamic port mapping:"
    docker_compose_port "Consul"
    DOCKER_SERVICE=consul-haproxy docker_compose_port HAProxy
    hr
    # shellcheck disable=SC2153
    when_ports_available "$CONSUL_HOST" "$CONSUL_PORT" "$HAPROXY_PORT"
    hr
    # older versions say Consul Agent
    # newer versions say Consul by Hashicorp
    when_url_content "http://$CONSUL_HOST:$CONSUL_PORT/" "Consul (Agent|by HashiCorp)"
    hr
    echo "checking HAProxy Consul:"
    when_url_content "http://$CONSUL_HOST:$HAPROXY_PORT/" "Consul (Agent|by HashiCorp)"
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    expected_version="$version"
    if [ "$version" = "latest" ]; then
        echo "latest version, fetching latest version from DockerHub master branch"
        local expected_version
        expected_version="$(dockerhub_latest_version consul)"
        echo "expecting version '$expected_version'"
    fi

    consul_tests

    echo

    section2 "Running HAProxy tests"

    CONSUL_PORT="$HAPROXY_PORT" \
    consul_tests

    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    hr

    consul_dev_tests

    hr
    # defined and tracked in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "Completed $run_count Consul tests"
    hr
    echo
}

consul_tests(){
    echo "waiting for leader election to avoid write key failure:"
    # typically takes ~ 7 secs
    retry 15 ./check_consul_leader_elected.py
    hr
    local testkey="nagios/consul/testkey1"
    echo "Writing random value to test key $testkey"
    local random_val=$RANDOM
    curl -X PUT -d "$random_val" "http://$CONSUL_HOST:$CONSUL_PORT/v1/kv/$testkey"
    echo
    hr
    set +e
    found_version=$(docker-compose exec "$DOCKER_SERVICE" consul version | tr -d '\r' | head -n1 | tee /dev/stderr | sed 's/.*v//')
    set -e
    if ! [[ "$found_version" =~ ^$expected_version.*$ ]]; then
        echo "Docker container version does not match expected version! (found '$found_version', expected '$expected_version')"
        exit 1
    fi
    hr
    echo "Consul version $found_version"
    hr
    run ./check_consul_leader_elected.py

    run_conn_refused ./check_consul_leader_elected.py

    run ./check_consul_peer_count.py

    run_conn_refused ./check_consul_peer_count.py

    run ./check_consul_key.py -k "$testkey" -r "^$random_val$" -v

    run_conn_refused ./check_consul_key.py -k "$testkey" -r "^$random_val$" -v

    echo "writing deterministic test key to check thresholds"
    curl -X PUT -d "5" "http://$CONSUL_HOST:$CONSUL_PORT/v1/kv/$testkey"
    echo
    hr
    run ./check_consul_key.py -k "$testkey" -r '^\d$' -w 5 -v

    run ./check_consul_key.py -k "$testkey" -r '^\d$' -c 5 -v

    run ./check_consul_key.py -k "$testkey" -r '^\d$' -w 5 -c 5 -v

    echo "checking threshold failures are caught correctly:"

    ERRCODE=1 run_grep '^WARNING' ./check_consul_key.py -k "$testkey" -r '^\d$' -w 4 -c 5 -v

    ERRCODE=2 run_grep '^CRITICAL' ./check_consul_key.py -k "$testkey" -r '^\d$' -w 4 -c 4 -v

    local leader_lock="nagios/consul/leader"
    echo "checking key doesn't exist:"
    run_fail 2 ./check_consul_service_leader_elected.py -k "nonexistent"

    echo "checking regular key doesn't have a leader lock:"
    run_fail 2 ./check_consul_service_leader_elected.py -k "$testkey"

    echo "creating session:"
    local session
    session="$(curl -s -X PUT -d '{"Name": "nagios"}' "http://$CONSUL_HOST:$CONSUL_PORT/v1/session/create" | awk -F'"' '/ID/{print $4}')"
    echo
    echo "deleting last session lock if it exists:"
    set +o pipefail
    old_session="$(curl -s "http://$CONSUL_HOST:$CONSUL_PORT/v1/kv/$leader_lock" | python -mjson.tool | awk -F'"' '/Session/ {print $4}')"
    set -o pipefail
    curl -X PUT -d '<body>' "http://$CONSUL_HOST:$CONSUL_PORT/v1/kv/$leader_lock?release=$old_session" || :
    echo
    echo
    echo "creating leader key $leader_lock:"
    local result
    result="$(curl -s -X PUT -d '<body>' "http://$CONSUL_HOST:$CONSUL_PORT/v1/kv/$leader_lock?acquire=$session")"
    if [ "$result" != "true" ]; then
        echo "Failed to acquire leader lock!"
        echo
        echo "$result"
        exit 1
    fi
    echo
    hr
    if ! [[ "$version" =~ ^0.[12]$ ]]; then
        echo "checking leader lock is now there:"
        run ./check_consul_service_leader_elected.py -k "$leader_lock"

        echo "checking leader lock is now and expected server matches regex:"
        run ./check_consul_service_leader_elected.py -k "$leader_lock" -r '^[A-Za-z0-9]+$'
    fi

    echo "checking leader lock exists but doesn't contain the expected server name"
    run_fail 2 ./check_consul_service_leader_elected.py -k "$leader_lock" -r 'wronghost'

    echo "releasing leader lock:"
    local result
    result="$(curl -s -X PUT -d '<body>' "http://$CONSUL_HOST:$CONSUL_PORT/v1/kv/$leader_lock?release=$session")"
    if [ "$result" != "true" ]; then
        echo "Failed to release leader lock!"
        exit 1
    fi

    echo "checking key no longer has a leader lock:"
    run_fail 2 ./check_consul_service_leader_elected.py -k "$testkey"

    run_conn_refused ./check_consul_service_leader_elected.py -k "$leader_lock"

    run ./check_consul_write.py -v

    run_conn_refused ./check_consul_write.py -v
}

consul_dev_tests(){
    section2 "Setting up Consul-dev $version test container"
    local DOCKER_SERVICE="$DOCKER_SERVICE-dev"
    export COMPOSE_FILE="$srcdir/docker/$DOCKER_SERVICE-docker-compose.yml"
    if is_CI || [ -n "${DOCKER_PULL:-}" ]; then
        # $docker_compose_quiet defined in bash-tools/lib/docker.sh
        # $docker_compose_quiet shouldn't be quoted as this will pass a blank arg rather than no arg
        # shellcheck disable=SC2154,SC2086
        VERSION="$version" docker-compose pull $docker_compose_quiet
    fi
    VERSION="$version" docker-compose up -d --remove-orphans
    hr
    #export CONSUL_PORT="`docker-compose port "$DOCKER_SERVICE" "$CONSUL_PORT_DEFAULT" | sed 's/.*://'`"
    docker_compose_port "Consul"
    hr
    #docker exec -i "$DOCKER_CONTAINER-dev" "$DOCKER_MOUNT_DIR/check_consul_version.py" -e "$expected_version"
    docker_compose_exec "check_consul_version.py" -e "$expected_version"

    ERRCODE=2 docker_compose_exec "check_consul_version.py" -e "fail-version"
    echo
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
}

run_test_versions Consul

if is_CI; then
    docker_image_cleanup
    echo
fi
