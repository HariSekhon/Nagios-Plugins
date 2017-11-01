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

. "$srcdir/utils.sh"

section "C o n s u l"

export CONSUL_VERSIONS="${@:-${CONSUL_VERSIONS:-latest 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9}}"

CONSUL_HOST="${DOCKER_HOST:-${CONSUL_HOST:-${HOST:-localhost}}}"
CONSUL_HOST="${CONSUL_HOST##*/}"
CONSUL_HOST="${CONSUL_HOST%%:*}"
export CONSUL_HOST

export CONSUL_PORT_DEFAULT=8500

export DOCKER_IMAGE="harisekhon/consul"

export MNTDIR="/pl"

startupwait 10

check_docker_available

trap_debug_env consul

docker_exec(){
    run docker-compose exec "$DOCKER_SERVICE" "$MNTDIR/$@"
}

test_consul(){
    local version="$1"
    section2 "Setting up Consul $version test container"
    if is_CI; then
        VERSION="$version" docker-compose pull $docker_compose_quiet
    fi
    VERSION="$version" docker-compose up -d
    echo "getting Consul dynamic port mapping:"
    docker_compose_port "Consul"
    hr
    when_ports_available "$CONSUL_HOST" "$CONSUL_PORT"
    hr
    # older versions say Consul Agent
    # newer versions say Consul by Hashicorp
    when_url_content "http://$CONSUL_HOST:$CONSUL_PORT/" "Consul (Agent|by HashiCorp)"
    hr
    echo "waiting for leader election to avoid write key failure:"
    # typically takes ~ 7 secs
    retry 15 ./check_consul_leader_elected.py
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    hr
    local testkey="nagios/consul/testkey1"
    echo "Writing random value to test key $testkey"
    local random_val=$RANDOM
    curl -X PUT -d "$random_val" "http://$CONSUL_HOST:$CONSUL_PORT/v1/kv/$testkey"
    echo
    hr
    local expected_version="$version"
    if [ "$version" = "latest" ]; then
        echo "latest version, fetching latest version from DockerHub master branch"
        local expected_version="$(dockerhub_latest_version consul)"
        echo "expecting version '$expected_version'"
    fi
    set +e
    found_version=$(docker-compose exec "$DOCKER_SERVICE" consul version | tr -d '\r' | head -n1 | tee /dev/stderr | sed 's/.*v//')
    set -e
    if [[ "$found_version" != $expected_version* ]]; then
        echo "Docker container version does not match expected version! (found '$found_version', expected '$expected_version')"
        exit 1
    fi
    hr
    echo "Consul version $found_version"
    hr
    run ./check_consul_leader_elected.py
    hr
    run_conn_refused ./check_consul_leader_elected.py
    hr
    run ./check_consul_peer_count.py
    hr
    run_conn_refused ./check_consul_peer_count.py
    hr
    run ./check_consul_key.py -k /nagios/consul/testkey1 -r "^$random_val$" -v
    hr
    run_conn_refused ./check_consul_key.py -k /nagios/consul/testkey1 -r "^$random_val$" -v
    hr
    echo "writing deterministic test key to check thresholds"
    curl -X PUT -d "5" "http://$CONSUL_HOST:$CONSUL_PORT/v1/kv/$testkey"
    echo
    hr
    run ./check_consul_key.py -k /nagios/consul/testkey1 -r '^\d$' -w 5 -v
    hr
    run ./check_consul_key.py -k /nagios/consul/testkey1 -r '^\d$' -c 5 -v
    hr
    run ./check_consul_key.py -k /nagios/consul/testkey1 -r '^\d$' -w 5 -c 5 -v
    hr
    echo "checking threshold failures are caught correctly"
    hr
    set +o pipefail
    echo "./check_consul_key.py -k /nagios/consul/testkey1 -r '^\d$' -w 4 -c 5 -v | tee /dev/stderr | grep --color=yes ^WARNING"
    run_grep '^WARNING' ./check_consul_key.py -k /nagios/consul/testkey1 -r '^\d$' -w 4 -c 5 -v
    hr
    run_grep '^CRITICAL' ./check_consul_key.py -k /nagios/consul/testkey1 -r '^\d$' -w 4 -c 4 -v
    set -o pipefail
    hr
    run ./check_consul_write.py -v
    hr
    run_conn_refused ./check_consul_write.py -v
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    echo

    hr
    section2 "Setting up Consul-dev $version test container"
    hr
    #local DOCKER_OPTS="-v $srcdir/..:$MNTDIR"
    #local DOCKER_CMD=""
    local DOCKER_SERVICE="$DOCKER_SERVICE-dev"
    local COMPOSE_FILE="$srcdir/docker/$DOCKER_SERVICE-docker-compose.yml"
    VERSION="$version" docker-compose up -d
    export CONSUL_PORT="`docker-compose port "$DOCKER_SERVICE" "$CONSUL_PORT_DEFAULT" | sed 's/.*://'`"
    hr
    #docker exec -i "$DOCKER_CONTAINER-dev" "$MNTDIR/check_consul_version.py" -e "$expected_version"
    docker_exec "check_consul_version.py" -e "$expected_version"
    hr
    ERRCODE=2 docker_exec "check_consul_version.py" -e "fail-version"
    hr
    echo "Completed $run_count Consul tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    echo
}

run_test_versions Consul
