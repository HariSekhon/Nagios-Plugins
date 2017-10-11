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

export NEO4J_VERSIONS="${@:-${NEO4J_VERSIONS:-latest 2.3 3.0 3.1 3.2}}"

NEO4J_HOST="${DOCKER_HOST:-${NEO4J_HOST:-${HOST:-localhost}}}"
NEO4J_HOST="${NEO4J_HOST##*/}"
NEO4J_HOST="${NEO4J_HOST%%:*}"
export NEO4J_HOST

export NEO4J_USERNAME="${NEO4J_USERNAME:-${NEO4J_USERNAME:-neo4j}}"
export NEO4J_PASSWORD="${NEO4J_PASSWORD:-${NEO4J_PASSWORD:-testpw}}"

export NEO4J_PORT_DEFAULT=7474
export NEO4J_HTTP_PORT_DEFAULT=7473
export NEO4J_BOLT_PORT_DEFAULT=7687

check_docker_available

trap_debug_env neo4j

startupwait 20

neo4j_setup(){
    echo "getting Neo4J dynammic port mappings:"
    printf "Neo4J HTTP port => "
    export NEO4J_PORT="`docker-compose port "$DOCKER_SERVICE" "$NEO4J_PORT_DEFAULT" | sed 's/.*://'`"
    echo "$NEO4J_PORT"
    printf "Neo4J HTTPS port => "
    export NEO4J_HTTPS_PORT="`docker-compose port "$DOCKER_SERVICE" "$NEO4J_PORT_DEFAULT" | sed 's/.*://'`"
    echo "$NEO4J_HTTPS_PORT"
    printf "Neo4J Bolt port => "
    export NEO4J_BOLT_PORT="`docker-compose port "$DOCKER_SERVICE" "$NEO4J_PORT_DEFAULT" | sed 's/.*://'`"
    echo "$NEO4J_BOLT_PORT"
    hr
    when_ports_available "$startupwait" "$NEO4J_HOST" "$NEO4J_PORT" "$NEO4J_HTTPS_PORT" "$NEO4J_BOLT_PORT"
    hr
    if [ "${version:0:1}" = "2" ]; then
        :
    else
        when_url_content "$startupwait" "http://$NEO4J_HOST:7687" "not a WebSocket handshake request: missing upgrade"
    fi
    hr
    echo "creating test Neo4J node"
    if [ "${version:0:3}" = "2.3" -o "${version:0:3}" = "3.0" ]; then
        # port 1337 - gets connection refused in newer versions as there is nothing listening on 1337
        docker-compose exec "$DOCKER_SERVICE" /var/lib/neo4j/bin/neo4j-shell -host localhost -c 'CREATE (p:Person { name: "Hari Sekhon" });'
    else
        # connects to 7687
        # needs NEO4J_USERNAME and NEO4J_PASSWORD environment variables for the authenticated service
        docker exec -i -e NEO4J_USERNAME="$NEO4J_USERNAME" -e NEO4J_PASSWORD="$NEO4J_PASSWORD" "nagiosplugins_${DOCKER_SERVICE}_1" /var/lib/neo4j/bin/cypher-shell <<< 'CREATE (p:Person { name: "Hari Sekhon" });'
    fi
    hr
    when_url_content "$startupwait" "http://$NEO4J_HOST:$NEO4J_PORT/browser/" "Neo4j Browser"
}

test_neo4j_noauth(){
    local version="$1"
    section2 "Setting up Neo4J $version test container without auth"
    # otherwise repeated attempts create more nodes and break the NumberOfNodeIdsInUse upper threshold
    docker-compose down &>/dev/null || :
    VERSION="$version" docker-compose pull $docker_compose_quiet
    VERSION="$version" docker-compose up -d
    neo4j_setup
    hr
    if [ "${NOTESTS:-}" ]; then
        exit 0
    fi
    if [ "$version" = "latest" ]; then
        local version=".*"
    fi
    run $perl -T ./check_neo4j_version.pl -v -e "^$version"
    hr
    run $perl -T ./check_neo4j_readonly.pl -v
    # TODO: SSL checks
    #run $perl -T ./check_neo4j_readonly.pl -v -S -P 7473
    hr
    run $perl -T ./check_neo4j_remote_shell_enabled.pl -v
    hr
    run $perl -T ./check_neo4j_stats.pl -v
    hr
    # TODO: why is this zero and not one??
    run $perl -T ./check_neo4j_stats.pl -s NumberOfNodeIdsInUse -c 0:1 -v
    hr
    # Neo4J on Travis doesn't seem to return anything resulting in "'attributes' field not returned by Neo4J" error
    run $perl -T ./check_neo4j_store_sizes.pl -v
    hr
    #delete_container
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    hr
    echo
}

# ============================================================================ #

test_neo4j_auth(){
    local version="$1"
    section2 "Setting up Neo4J $version test container with auth"
    #local DOCKER_OPTS="-e NEO4J_AUTH=$NEO4J_USERNAME/$NEO4J_PASSWORD"
    local startupwait=20
    docker-compose down &>/dev/null || :
    VERSION="$version" docker-compose pull $docker_compose_quiet
    VERSION="$version" NEO4J_AUTH="$NEO4J_USERNAME/$NEO4J_PASSWORD" docker-compose up -d
    neo4j_setup
    hr
    if [ "${NOTESTS:-}" ]; then
        exit 0
    fi
    if [ "$version" = "latest" ]; then
        local version=".*"
    fi
    run $perl -T ./check_neo4j_version.pl -v -e "^$version"
    hr
    run $perl -T ./check_neo4j_readonly.pl -v
    hr
    run $perl -T ./check_neo4j_remote_shell_enabled.pl -v
    hr
    run $perl -T ./check_neo4j_stats.pl -v
    hr
    # TODO: why is this zero and not one??
    run $perl -T ./check_neo4j_stats.pl -s NumberOfNodeIdsInUse -c 0:1 -v
    hr
    # Neo4J on Travis doesn't seem to return anything resulting in "'attributes' field not returned by Neo4J" error
    run $perl -T ./check_neo4j_store_sizes.pl -v
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    hr
    echo
}

test_neo4j(){
    local version="$1"
    test_neo4j_noauth "$version"
    test_neo4j_auth   "$version"
    echo "Completed $run_count Neo4J tests"
}

run_test_versions Neo4J
