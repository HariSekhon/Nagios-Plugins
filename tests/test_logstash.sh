#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-11-24 20:47:02 +0100 (Fri, 24 Nov 2017)
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

section "L o g s t a s h"

# Logstash 6.0+ only available on new docker.elastic.co which uses full sub-version x.y.z and does not have x.y tags
export LOGSTASH_VERSIONS="${@:-${LOGSTASH_VERSIONS:-latest 1.3 1.4 1.5 1.6 1.7 2.0 2.1 2.2 2.3 2.4 5.0 5.1 5.2 5.3 5.4 5.5 5.6 6.0.0}}"

LOGSTASH_HOST="${DOCKER_HOST:-${LOGSTASH_HOST:-${HOST:-localhost}}}"
LOGSTASH_HOST="${LOGSTASH_HOST##*/}"
LOGSTASH_HOST="${LOGSTASH_HOST%%:*}"
export LOGSTASH_HOST
export LOGSTASH_PORT_DEFAULT=9600

check_docker_available

trap_debug_env logstash

startupwait 20

test_logstash(){
    local version="$1"
    section2 "Setting up Logstash $version test container"
    # re-enable this when Elastic.co finally support 'latest' tag
    #if [ "$version" = "latest" ] || [ "${version:0:1}" -ge 6 ]; then
    if [ "$version" != "latest" ] && [ "${version:0:1}" -ge 6 ]; then
        local export COMPOSE_FILE="$srcdir/docker/$DOCKER_SERVICE-elastic.co-docker-compose.yml"
    fi
    docker_compose_pull
    VERSION="$version" docker-compose up -d
    hr
    echo "getting Logstash dynamic port mapping:"
    docker_compose_port "Logstash"
    hr
    when_ports_available "$LOGSTASH_HOST" "$LOGSTASH_PORT"
    hr
    when_url_content "http://$LOGSTASH_HOST:$LOGSTASH_PORT" "build_date"
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    hr
    if [ "$version" = "latest" ]; then
        local version=".*"
    fi

    run ./check_logstash_version.py --expected "$version"

    run ./check_logstash_version.py -v --expected "$version"

    run_fail 2 ./check_logstash_version.py -v --expected "fail-version"

    run_conn_refused ./check_logstash_version.py -v --expected "$version"

    echo "Completed $run_count Logstash tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
}

run_test_versions Logstash
