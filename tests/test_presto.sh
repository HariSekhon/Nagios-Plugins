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

export PRESTO_VERSIONS="${@:-${PRESTO_VERSIONS:-latest 0.152 0.157 0.167 0.179}}"

PRESTO_HOST="${DOCKER_HOST:-${PRESTO_HOST:-${HOST:-localhost}}}"
PRESTO_HOST="${PRESTO_HOST##*/}"
PRESTO_HOST="${PRESTO_HOST%%:*}"
export PRESTO_HOST

export PRESTO_PORT_DEFAULT="${PRESTO_PORT:-8080}"

check_docker_available

trap_debug_env presto

startupwait 10

test_presto(){
    local version="$1"
    echo "Setting up Presto $version test container"
    #launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $PRESTO_PORT
    VERSION="$version" docker-compose up -d
    export PRESTO_PORT="`docker-compose port "$DOCKER_SERVICE" "$PRESTO_PORT_DEFAULT" | sed 's/.*://'`"
    when_ports_available "$startupwait" "$PRESTO_HOST" "$PRESTO_PORT"
    #echo "sleeping for 5 secs to give API time to initialize properly"
    #sleep 5
    echo "giving Presto up to 20 secs for service to come up:"
    for x in {1..20}; do
        # endpoint initializes blank, wait until there is some content, eg. nodeId
        echo "trying http://$PRESTO_HOST:$PRESTO_PORT/v1/service/presto/general"
        curl -s "http://$PRESTO_HOST:$PRESTO_PORT/v1/service/presto/general" | grep -q nodeId && break
        #echo "./check_presto_state.py"
        #./check_presto_state.py && break
        sleep 1
    done
    if [ "$version" = "latest" ]; then
        version=".*"
    fi
    hr
    # presto service not found in list of endpoints initially even after it's come up
    echo "./check_presto_version.py --expected \"$version(-t.\d+.\d+)?\""
    ./check_presto_version.py --expected "$version(-t.\d+.\d+)?"
    hr
    echo "./check_presto_coordinator.py"
    ./check_presto_coordinator.py
    hr
    echo "./check_presto_environment.py --expected development"
    ./check_presto_environment.py --expected development
    hr
    echo "./check_presto_nodes_failed.py"
    ./check_presto_nodes_failed.py
    hr
    echo "./check_presto_num_queries.py"
    ./check_presto_num_queries.py
    hr
    echo "./check_presto_state.py"
    ./check_presto_state.py
    hr
    #delete_container
    docker-compose down
    hr
    echo
}

if [ -z "${1:-}" ]; then
    echo "Testing Facebook's latest presto release before Teradata's distribution:"
    COMPOSE_FILE="$srcdir/docker/presto-dev-docker-compose.yml" test_presto latest
fi

run_test_versions presto
