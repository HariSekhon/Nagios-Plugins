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

# shellcheck disable=SC1090
. "$srcdir/utils.sh"

section "N e o 4 J"

export NEO4J_VERSIONS="${*:-${NEO4J_VERSIONS:-2.3 3.0 3.1 3.2 latest}}"

NEO4J_HOST="${DOCKER_HOST:-${NEO4J_HOST:-${HOST:-localhost}}}"
NEO4J_HOST="${NEO4J_HOST##*/}"
NEO4J_HOST="${NEO4J_HOST%%:*}"
export NEO4J_HOST

export NEO4J_USERNAME="${NEO4J_USERNAME:-${NEO4J_USERNAME:-neo4j}}"
export NEO4J_PASSWORD="${NEO4J_PASSWORD:-${NEO4J_PASSWORD:-testpw}}"

export NEO4J_PORT_DEFAULT=7474
export NEO4J_HTTPS_PORT_DEFAULT=7473
export NEO4J_BOLT_PORT_DEFAULT=7687

check_docker_available

trap_debug_env neo4j

startupwait 30

test_neo4j_main(){
    local version="$1"
    if [ -n "${NEO4J_AUTH:-}" ]; then
        local auth_msg="with auth"
    else
        local auth_msg="without auth"
    fi
    section2 "Setting up Neo4J $version test container $auth_msg"
    # otherwise repeated attempts create more nodes and break the NumberOfNodeIdsInUse upper threshold
    docker-compose down &>/dev/null || :
    docker_compose_pull
    VERSION="$version" docker-compose up -d --remove-orphans
    hr
    echo "getting Neo4J dynammic port mappings:"
    docker_compose_port NEO4J_PORT "Neo4J HTTP"
    docker_compose_port NEO4J_HTTPS_PORT "Neo4J HTTPS"
    docker_compose_port "Neo4J Bolt"
    hr
    # shellcheck disable=SC2153
    when_ports_available "$NEO4J_HOST" "$NEO4J_PORT" "$NEO4J_HTTPS_PORT" "$NEO4J_BOLT_PORT"
    hr
    when_url_content "http://$NEO4J_HOST:$NEO4J_PORT/browser/" "Neo4j Browser"
    hr
    if [ "${version:0:1}" = "2" ]; then
        :
    else
        when_url_content "http://$NEO4J_HOST:7687" "not a WebSocket handshake request: missing upgrade"
    fi
    hr
    if [ -z "${NOSETUP:-}" ]; then
        echo "creating test Neo4J node"
        if [ "${version:0:3}" = "2.3" ] || [ "${version:0:3}" = "3.0" ]; then
            # port 1337 - gets connection refused in newer versions as there is nothing listening on 1337
            docker-compose exec "$DOCKER_SERVICE" /var/lib/neo4j/bin/neo4j-shell -host localhost -c 'CREATE (p:Person { name: "Hari Sekhon" });'
        else
            # connects to 7687
            # needs NEO4J_USERNAME and NEO4J_PASSWORD environment variables for the authenticated service
            local auth_env=""
            if [ -n "${NEO4J_AUTH:-}" ]; then
                # API 1.25+
                auth_env="-e NEO4J_USERNAME=$NEO4J_USERNAME -e NEO4J_PASSWORD=$NEO4J_PASSWORD"
            fi
            # want splitting
            # shellcheck disable=SC2086
            docker exec -i $auth_env "$DOCKER_CONTAINER" /var/lib/neo4j/bin/cypher-shell <<< 'CREATE (p:Person { name: "Hari Sekhon" });'
        fi
        hr
    fi
    if [ "${NOTESTS:-}" ]; then
        exit 0
    fi
    if [ "$version" = "latest" ]; then
        local version=".*"
    fi
    # $perl defined in bash-tools/lib/perl.sh (imported by utils.sh)
    # shellcheck disable=SC2154
    run "$perl" -T ./check_neo4j_version.pl -v -e "^$version"

    run_fail 2 "$perl" -T ./check_neo4j_version.pl -v -e 'fail-version'

    run "$perl" -T ./check_neo4j_readonly.pl -v

    # TODO: SSL checks
    #run "$perl" -T ./check_neo4j_readonly.pl -v -S -P 7473

    run "$perl" -T ./check_neo4j_remote_shell_enabled.pl -v

    run "$perl" -T ./check_neo4j_stats.pl -v

    run "$perl" -T ./check_neo4j_stats.pl -s NumberOfNodeIdsInUse -c 1:20 -v

    # Neo4J on Travis doesn't seem to return anything resulting in "'attributes' field not returned by Neo4J" error
    run "$perl" -T ./check_neo4j_store_sizes.pl -v

    run_conn_refused "$perl" -T ./check_neo4j_version.pl -v -e "^$version"

    run_conn_refused "$perl" -T ./check_neo4j_readonly.pl -v

    run_conn_refused "$perl" -T ./check_neo4j_remote_shell_enabled.pl -v

    run_conn_refused "$perl" -T ./check_neo4j_stats.pl -v

    run_conn_refused "$perl" -T ./check_neo4j_stats.pl -s NumberOfNodeIdsInUse -c 0:1 -v

    run_conn_refused "$perl" -T ./check_neo4j_store_sizes.pl -v

    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    hr
    echo
}

# ============================================================================ #

test_neo4j(){
    local version="$1"
    test_neo4j_main "$version"
    NEO4J_AUTH="$NEO4J_USERNAME/$NEO4J_PASSWORD" \
        test_neo4j_main "$version"
    # defined and tracked in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "Completed $run_count Neo4J tests"
}

run_test_versions Neo4J

if is_CI; then
    docker_image_cleanup
    echo
fi
