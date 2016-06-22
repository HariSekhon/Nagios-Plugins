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

echo "
# ============================================================================ #
#                                   N e o 4 J
# ============================================================================ #
"

export NEO4J_VERSIONS="${@:-latest 2.3 3.0}"

NEO4J_HOST="${DOCKER_HOST:-${NEO4J_HOST:-${HOST:-localhost}}}"
NEO4J_HOST="${NEO4J_HOST##*/}"
NEO4J_HOST="${NEO4J_HOST%%:*}"
export NEO4J_HOST

export NEO4J_USERNAME="${NEO4J_USERNAME:-${NEO4J_USERNAME:-neo4j}}"
export NEO4J_PASSWORD="${NEO4J_PASSWORD:-${NEO4J_PASSWORD:-testpw}}"

export NEO4J_PORTS="7473 7474"

export DOCKER_IMAGE="neo4j"
export DOCKER_CONTAINER="nagios-plugins-neo4j-test"

if ! is_docker_available; then
    echo 'WARNING: Docker not found, skipping Neo4j checks!!!'
    exit 0
fi

test_neo4j(){
    local version="$1"
    local startupwait=10
    echo "Setting up Neo4J $version test container without authentication"
    delete_container "$DOCKER_CONTAINER-auth" &>/dev/null || :
    local DOCKER_OPTS="-e NEO4J_AUTH=none"
    launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $NEO4J_PORTS
    echo "creating test Neo4J node"
    docker exec "$DOCKER_CONTAINER" /var/lib/neo4j/bin/neo4j-shell -host localhost -c 'CREATE (p:Person { name: "Hari Sekhon" });'
    if [ "${NOTESTS:-}" ]; then
        return 0
    fi
    if [ "$version" = "latest" ]; then
        local version=".*"
    fi
    hr
    $perl -T $I_lib ./check_neo4j_version.pl -v -e "^$version"
    hr
    $perl -T $I_lib ./check_neo4j_readonly.pl -v
    # TODO: SSL checks
    #$perl -T $I_lib ./check_neo4j_readonly.pl -v -S -P 7473
    hr
    $perl -T $I_lib ./check_neo4j_remote_shell_enabled.pl -v
    hr
    $perl -T $I_lib ./check_neo4j_stats.pl -v
    hr
    # TODO: why is this zero and not one??
    $perl -T $I_lib ./check_neo4j_stats.pl -s NumberOfNodeIdsInUse -c 0:1 -v
    hr
    # Neo4J on Travis doesn't seem to return anything resulting in "'attributes' field not returned by Neo4J" error
    $perl -T $I_lib ./check_neo4j_store_sizes.pl -v
    hr
    delete_container
    hr
    echo
}

# ============================================================================ #

test_neo4j_auth(){
    local version="$1"
    echo "Setting up Neo4J $version test container with authentication"
    local DOCKER_OPTS="-e NEO4J_AUTH=$NEO4J_USERNAME/$NEO4J_PASSWORD"
    delete_container "$DOCKER_CONTAINER" &>/dev/null || :
    local startupwait=20
    launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER-auth" $NEO4J_PORTS
    echo "creating test Neo4J node"
    docker exec "$DOCKER_CONTAINER-auth" /var/lib/neo4j/bin/neo4j-shell -host localhost -c 'CREATE (p:Person { name: "Hari Sekhon" });'
    if [ "${NOTESTS:-}" ]; then
        return 0
    fi
    if [ "$version" = "latest" ]; then
        local version=".*"
    fi
    hr
    $perl -T $I_lib ./check_neo4j_version.pl -v -e "^$version"
    hr
    $perl -T $I_lib ./check_neo4j_readonly.pl -v
    hr
    $perl -T $I_lib ./check_neo4j_remote_shell_enabled.pl -v
    hr
    $perl -T $I_lib ./check_neo4j_stats.pl -v
    hr
    # TODO: why is this zero and not one??
    $perl -T $I_lib ./check_neo4j_stats.pl -s NumberOfNodeIdsInUse -c 0:1 -v
    hr
    # Neo4J on Travis doesn't seem to return anything resulting in "'attributes' field not returned by Neo4J" error
    $perl -T $I_lib ./check_neo4j_store_sizes.pl -v
    hr
    delete_container "$DOCKER_CONTAINER-auth"
    hr
    echo
}

for version in $(ci_sample $NEO4J_VERSIONS); do
    test_neo4j $version
    test_neo4j_auth $version
done
