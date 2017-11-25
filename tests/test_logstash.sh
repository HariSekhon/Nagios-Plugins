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
# Rest API 5.x onwards
export LOGSTASH_VERSIONS="${@:-${LOGSTASH_VERSIONS:-latest 5.0 5.1 5.2 5.3 5.4 5.5 5.6 6.0.0}}"

LOGSTASH_HOST="${DOCKER_HOST:-${LOGSTASH_HOST:-${HOST:-localhost}}}"
LOGSTASH_HOST="${LOGSTASH_HOST##*/}"
LOGSTASH_HOST="${LOGSTASH_HOST%%:*}"
export LOGSTASH_HOST
export LOGSTASH_PORT_DEFAULT=9600

check_docker_available

trap_debug_env logstash

startupwait 70

test_logstash(){
    local version="$1"
    section2 "Setting up Logstash $version test container"
    # TODO: change latest if Elastic.co finally support 'latest' tag, otherwise it points to 5.x on dockerhub
    if ! [ "$version" = "latest" -o "${version:0:1}" = 5 ]; then
        local export COMPOSE_FILE="$srcdir/docker/$DOCKER_SERVICE-elastic.co-docker-compose.yml"
    fi
    docker_compose_pull
    docker-compose down || :
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
    local expected_version="$version"
    if [ "$version" = "latest" ]; then
        local expected_version=".*"
    fi

    run ./check_logstash_version.py --expected "$expected_version"

    run ./check_logstash_version.py -v --expected "$expected_version"

    run_fail 2 ./check_logstash_version.py -v --expected "fail-version"

    run_conn_refused ./check_logstash_version.py -v --expected "$expected_version"

    # ============================================================================ #

    echo "checking will alert warning on logstash recently started:"
    run_fail 1 ./check_logstash_status.py

    run_fail 1 ./check_logstash_status.py -v

    retry 5 ./check_logstash_status.py -w 1

    run ./check_logstash_status.py -w 1

    run ./check_logstash_status.py -v -w 1

    run_conn_refused ./check_logstash_status.py -v

    # ============================================================================ #
    # API changed between Logstash 5 and 6
    local logstash_5=""
    # TODO: re-enable on latest if Elastic.co finally support 'latest' tag, otherwise it points to 5.x on dockerhub
    if [ "$version" = "latest" -o "${version:0:1}" = 5 ]; then
        logstash_5="--logstash-5"
    fi

    local pipeline="main"
    echo "waiting 30 secs for pipeline API endpoint to come up:"
    retry 40 ./check_logstash_pipeline.py $logstash_5
    hr

    run_fail 3 ./check_logstash_pipeline.py -l $logstash_5

    run ./check_logstash_pipeline.py -v $logstash_5

    run ./check_logstash_pipeline.py -v --pipeline "$pipeline" $logstash_5

    run ./check_logstash_pipeline.py -v --pipeline "$pipeline" --workers 8 $logstash_5

    run_fail 1 ./check_logstash_pipeline.py -v --pipeline "$pipeline" --workers 99 $logstash_5

    # TODO: re-enable on latest if Elastic.co finally support 'latest' tag, otherwise it points to 5.x on dockerhub
    if [ "$version" = "latest" -o "${version:0:1}" = 5 ]; then
        run_usage ./check_logstash_pipeline.py -v --pipeline "$pipeline" --dead-letter-queue-enabled $logstash_5

        run_usage ./check_logstash_pipeline.py -v --pipeline "nonexistent_pipeline" $logstash_5
    else
        run_fail 1 ./check_logstash_pipeline.py -v --pipeline "$pipeline" --dead-letter-queue-enabled

        run_fail 2 ./check_logstash_pipeline.py -v --pipeline "nonexistent_pipeline"
    fi

    run_conn_refused ./check_logstash_pipeline.py -v

    run_conn_refused ./check_logstash_pipeline.py -v --pipeline "$pipeline"

    echo "Completed $run_count Logstash tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
}

run_test_versions Logstash
