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

section "N e o 4 J"

export NEO4J_VERSIONS="${@:-${NEO4J_VERSIONS:-latest 2.3 3.0}}"

NEO4J_HOST="${DOCKER_HOST:-${NEO4J_HOST:-${HOST:-localhost}}}"
NEO4J_HOST="${NEO4J_HOST##*/}"
NEO4J_HOST="${NEO4J_HOST%%:*}"
export NEO4J_HOST

export NEO4J_USERNAME="${NEO4J_USERNAME:-${NEO4J_USERNAME:-neo4j}}"
export NEO4J_PASSWORD="${NEO4J_PASSWORD:-${NEO4J_PASSWORD:-testpw}}"

export NEO4J_PORT_DEFAULT="7474"
export NEO4J_PORTS_DEFAULT="$NEO4J_PORT_DEFAULT 7473"

check_docker_available

trap_debug_env neo4j

startupwait 10

test_neo4j_noauth(){
    local version="$1"
    echo "Setting up Neo4J $version test container without authentication"
    #local DOCKER_OPTS="-e NEO4J_AUTH=none"
    #launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $NEO4J_PORTS
    # otherwise repeated attempts create more nodes and break the NumberOfNodeIdsInUse upper threshold
    docker-compose down &>/dev/null || :
    VERSION="$version" docker-compose up -d
    export NEO4J_PORT="`docker-compose port "$DOCKER_SERVICE" "$NEO4J_PORT_DEFAULT" | sed 's/.*://'`"
    export NEO4J_PORTS=`{ for x in $NEO4J_PORTS_DEFAULT; do docker-compose port "$DOCKER_SERVICE" "$x"; done; } | sed 's/.*://'`
    when_ports_available $startupwait $NEO4J_HOST $NEO4J_PORTS
    echo "creating test Neo4J node"
    docker-compose exec "$DOCKER_SERVICE" /var/lib/neo4j/bin/neo4j-shell -host localhost -c 'CREATE (p:Person { name: "Hari Sekhon" });'
    if [ "${NOTESTS:-}" ]; then
        exit 0
    fi
    if [ "$version" = "latest" ]; then
        local version=".*"
    fi
    hr
    $perl -T ./check_neo4j_version.pl -v -e "^$version"
    hr
    $perl -T ./check_neo4j_readonly.pl -v
    # TODO: SSL checks
    #$perl -T ./check_neo4j_readonly.pl -v -S -P 7473
    hr
    $perl -T ./check_neo4j_remote_shell_enabled.pl -v
    hr
    $perl -T ./check_neo4j_stats.pl -v
    hr
    # TODO: why is this zero and not one??
    $perl -T ./check_neo4j_stats.pl -s NumberOfNodeIdsInUse -c 0:1 -v
    hr
    # Neo4J on Travis doesn't seem to return anything resulting in "'attributes' field not returned by Neo4J" error
    $perl -T ./check_neo4j_store_sizes.pl -v
    hr
    #delete_container
    docker-compose down
    hr
    echo
}

# ============================================================================ #

test_neo4j_auth(){
    local version="$1"
    echo "Setting up Neo4J $version test container with authentication"
    #local DOCKER_OPTS="-e NEO4J_AUTH=$NEO4J_USERNAME/$NEO4J_PASSWORD"
    local startupwait=20
    #launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER-auth" $NEO4J_PORTS
    docker-compose down &>/dev/null || :
    VERSION="$version" NEO4J_AUTH="$NEO4J_USERNAME/$NEO4J_PASSWORD" docker-compose up -d
    neo4j_port="`docker-compose port "$DOCKER_SERVICE" "$NEO4J_PORT" | sed 's/.*://'`"
    local NEO4J_PORT="$neo4j_port"
    neo4j_ports=`{ for x in $NEO4J_PORTS; do docker-compose port "$DOCKER_SERVICE" "$x"; done; } | sed 's/.*://'`
    when_ports_available $startupwait $NEO4J_HOST $neo4j_ports
    echo "creating test Neo4J node"
    docker-compose exec "$DOCKER_SERVICE" /var/lib/neo4j/bin/neo4j-shell -host localhost -c 'CREATE (p:Person { name: "Hari Sekhon" });'
    if [ "${NOTESTS:-}" ]; then
        exit 0
    fi
    if [ "$version" = "latest" ]; then
        local version=".*"
    fi
    hr
    echo "$perl -T ./check_neo4j_version.pl -v -e '^$version'"
    $perl -T ./check_neo4j_version.pl -v -e "^$version"
    hr
    echo "$perl -T ./check_neo4j_readonly.pl -v"
    $perl -T ./check_neo4j_readonly.pl -v
    hr
    echo "$perl -T ./check_neo4j_remote_shell_enabled.pl -v"
    $perl -T ./check_neo4j_remote_shell_enabled.pl -v
    hr
    echo "$perl -T ./check_neo4j_stats.pl -v"
    $perl -T ./check_neo4j_stats.pl -v
    hr
    # TODO: why is this zero and not one??
    echo "$perl -T ./check_neo4j_stats.pl -s NumberOfNodeIdsInUse -c 0:1 -v"
    $perl -T ./check_neo4j_stats.pl -s NumberOfNodeIdsInUse -c 0:1 -v
    hr
    # Neo4J on Travis doesn't seem to return anything resulting in "'attributes' field not returned by Neo4J" error
    echo "$perl -T ./check_neo4j_store_sizes.pl -v"
    $perl -T ./check_neo4j_store_sizes.pl -v
    hr
    #delete_container "$DOCKER_CONTAINER-auth"
    docker-compose down
    hr
    echo
}

test_neo4j(){
    local version="$1"
    test_neo4j_noauth "$version"
    test_neo4j_auth   "$version"
}

run_test_versions Neo4J
