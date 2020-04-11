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

# shellcheck disable=SC1090
. "$srcdir/utils.sh"

section "L o g s t a s h"

# Logstash 6.0+ only available on new docker.elastic.co which uses full sub-version x.y.z and does not have x.y tags
# Rest API 5.x onwards
export LOGSTASH_VERSIONS="${*:-${LOGSTASH_VERSIONS:-5.0 5.1 5.2 5.3 5.4 5.5 5.6 6.0.1 6.1.1 latest}}"

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
    if ! [ "$version" = "latest" ] || [ "${version:0:1}" = 5 ]; then
        local export COMPOSE_FILE="$srcdir/docker/$DOCKER_SERVICE-elastic.co-docker-compose.yml"
    fi
    docker_compose_pull
    # force restarting the container so the uptime so the check_logstash_status.py checks get the right success and failure results for the amount of uptime
    [ -n "${NODOCKER:-}" ] || docker-compose stop || :
    VERSION="$version" docker-compose up -d --remove-orphans
    hr
    echo "getting Logstash dynamic port mapping:"
    docker_compose_port "Logstash"
    hr
    # shellcheck disable=SC2153
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

    echo "waiting for Logstash JVM uptime to come online:"
    retry 40 ./check_logstash_status.py -w 1

    run ./check_logstash_status.py -w 1

    echo "checking will alert warning on logstash recently started:"
    run_fail 1 ./check_logstash_status.py

    run_fail 1 ./check_logstash_status.py -v

    run_conn_refused ./check_logstash_status.py -v

    # ============================================================================ #
    # API changed between Logstash 5 and 6
    local logstash_5=""
    # TODO: re-enable on latest if Elastic.co finally support 'latest' tag, otherwise it points to 5.x on dockerhub
    if [ "$version" = "latest" ] || [ "${version:0:1}" = 5 ]; then
        logstash_5="--logstash-5"
    fi
    # ============================================================================ #
    echo "waiting for pipeline(s) to come online:"
    retry 20 ./check_logstash_pipelines.py $logstash_5
    hr

    run_fail 3 ./check_logstash_pipelines.py -l $logstash_5

    run ./check_logstash_pipelines.py -v $logstash_5

    # Logstash 6 has 2 pipelines by default - 'main' and '.monitoring-logstash'
    run_fail 1 ./check_logstash_pipelines.py -v $logstash_5 -w 3

    run_fail 2 ./check_logstash_pipelines.py -v $logstash_5 -c 3

    run_conn_refused ./check_logstash_pipelines.py -v $logstash_5

    # ============================================================================ #
    local pipeline="main"
    echo "waiting for pipeline API endpoint to come online:"
    retry 20 ./check_logstash_pipeline.py $logstash_5
    hr

    run_fail 3 ./check_logstash_pipeline.py -l $logstash_5

    run ./check_logstash_pipeline.py -v $logstash_5

    run ./check_logstash_pipeline.py -v --pipeline "$pipeline" $logstash_5

    run ./check_logstash_pipeline.py -v --pipeline "$pipeline" -w 2:8 $logstash_5

    run_fail 1 ./check_logstash_pipeline.py -v --pipeline "$pipeline" -w 99 $logstash_5

    # TODO: re-enable on latest if Elastic.co finally support 'latest' tag, otherwise it points to 5.x on dockerhub
    if [ "$version" = "latest" ] || [ "${version:0:1}" = 5 ]; then
        run_usage ./check_logstash_pipeline.py -v --pipeline "$pipeline" --dead-letter-queue-enabled $logstash_5

        run_usage ./check_logstash_pipeline.py -v --pipeline "nonexistent_pipeline" $logstash_5
    else
        run_fail 1 ./check_logstash_pipeline.py -v --pipeline "$pipeline" --dead-letter-queue-enabled

        run_fail 2 ./check_logstash_pipeline.py -v --pipeline "nonexistent_pipeline"
    fi

    run_conn_refused ./check_logstash_pipeline.py -v

    run_conn_refused ./check_logstash_pipeline.py -v --pipeline "$pipeline"

    # ============================================================================ #

    run_fail 3 ./check_logstash_plugins.py -l

    run ./check_logstash_plugins.py -v

    run_fail 1 ./check_logstash_plugins.py -w 10

    run_fail 2 ./check_logstash_plugins.py -c 20

    run_conn_refused ./check_logstash_plugins.py

    # ============================================================================ #

    echo "waiting for Logstash::Runner cpu percentage to come down to normal:"
    retry 80 ./check_logstash_hot_threads.py

    run ./check_logstash_hot_threads.py

    run ./check_logstash_hot_threads.py -v

    echo "setting warning threshold low to test warning scenario for top hot thread:"
    run_fail 1 ./check_logstash_hot_threads.py -w 0.1 -c 100

    echo "setting critical threshold low to test critical scenario for top hot thread:"
    run_fail 2 ./check_logstash_hot_threads.py -c 0.1

    echo "setting warning threshold high to test ok scenario:"
    run ./check_logstash_hot_threads.py --top-3 -w 90

    run ./check_logstash_hot_threads.py --top-3 -w 90 -v

    echo "setting warning threshold low to test warning failure:"
    run_fail 1 ./check_logstash_hot_threads.py --top-3 -w 0.1

    echo "setting critical threshold low to test critical failure:"
    run_fail 2 ./check_logstash_hot_threads.py --top-3 -c 0.1

    run_conn_refused ./check_logstash_hot_threads.py -v

    # defined and tracked in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "Completed $run_count Logstash tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
}

run_test_versions Logstash

if is_CI; then
    docker_image_cleanup
    echo
fi
