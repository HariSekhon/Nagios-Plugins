#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-10-29 11:36:58 +0100 (Sun, 29 Oct 2017)
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

section "C o u c h D B"

# 1.6 and 2.1 were getting the following error, seem to be behaving now:
# ERROR: Get https://registry-1.docker.io/v2/: dial tcp: lookup registry-1.docker.io on 194.239.134.83:53: server misbehaving
export COUCHDB_VERSIONS="${@:-${COUCHDB_VERSIONS:-latest 1.6 2.1}}"

COUCHDB_HOST="${DOCKER_HOST:-${COUCHDB_HOST:-${HOST:-localhost}}}"
COUCHDB_HOST="${COUCHDB_HOST##*/}"
COUCHDB_HOST="${COUCHDB_HOST%%:*}"
export COUCHDB_HOST

export COUCHDB_PORT_DEFAULT=5984

export COUCHDB_TEST_DB="nagios-plugins"

export COUCHDB_USER="${COUCHDB_USER:-admin}"
export COUCHDB_PASSWORD="${COUCHDB_PASSWORD:-password}"

startupwait 10

check_docker_available

trap_debug_env couchdb

docker_exec(){
    run docker-compose exec "$DOCKER_SERVICE" "$MNTDIR/$@"
}

test_couchdb(){
    local version="$1"
    section2 "Setting up CouchDB $version test container"
    if is_CI; then
        VERSION="$version" docker-compose pull $docker_compose_quiet
    fi
    VERSION="$version" docker-compose up -d
    echo "getting CouchDB dynamic port mapping:"
    docker_compose_port "CouchDB"
    hr
    when_ports_available "$COUCHDB_HOST" "$COUCHDB_PORT"
    hr
    when_url_content "http://$COUCHDB_HOST:$COUCHDB_PORT/" "couchdb"
    hr
    # this only seems to work in 2.x, not 1.6
    if [ "${version:0:1}" != 1 ]; then
        retry 10 ./check_couchdb_status.py
    fi
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    hr
    echo "Setting up nagios-plugins database:"
    curl -s -u "$COUCHDB_USER:$COUCHDB_PASSWORD" -X PUT -H 'content-type: application/json' "$COUCHDB_HOST:$COUCHDB_PORT/$COUCHDB_TEST_DB" | tee /dev/stderr | grep --color -e '{"ok":true}' -e 'already exists'
    # TODO: run curl call to set up DB
    hr
    if [ "$version" = "latest" ]; then
        version=".*"
    fi
    run ./check_couchdb_version.py -e "$version"
    hr
    run_fail 2 ./check_couchdb_version.py -e "fail-version"
    hr
    run_conn_refused ./check_couchdb_version.py -e "$version"
    hr
    # this only seems to work in 2.x, not 1.6
    if [ "${version:0:1}" != 1 ]; then
        run ./check_couchdb_status.py
    fi
    hr
    run_conn_refused ./check_couchdb_status.py
    hr
    run_fail 3 ./check_couchdb_database_exists.py --list
    hr
    run_fail 3 ./check_couchdb_database_stats.py --list
    hr
    run ./check_couchdb_database_exists.py --database "$COUCHDB_TEST_DB"
    hr
    run_fail 2 ./check_couchdb_database_exists.py --database "nonexistentdatabase"
    hr
    run_conn_refused ./check_couchdb_database_exists.py --database "$COUCHDB_TEST_DB"
    hr
    run ./check_couchdb_database_stats.py --database "$COUCHDB_TEST_DB"
    hr
    run_fail 2 ./check_couchdb_database_stats.py --database "nonexistentdatabase"
    hr
    run_conn_refused ./check_couchdb_database_stats.py --database "$COUCHDB_TEST_DB"
    hr
    # race condition, misses
    #echo "trigger compaction and check stat for compaction=1:"
    #curl -s -u "$COUCHDB_USER:$COUCHDB_PASSWORD" -X POST -H 'content-type: application/json' "$COUCHDB_HOST:$COUCHDB_PORT/$COUCHDB_TEST_DB/_compact" | tee /dev/stderr | grep '{"ok":true}'
    #sleep 1
    #run_grep 'compact_running=1' ./check_couchdb_database_stats.py --database "$COUCHDB_TEST_DB"
    hr
    echo "Completed $run_count CouchDB tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    echo
}

run_test_versions CouchDB
