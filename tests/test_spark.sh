#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-02-10 23:18:47 +0000 (Wed, 10 Feb 2016)
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

srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/.."

# shellcheck disable=SC1090
. "$srcdir/utils.sh"

section "S p a r k"

export SPARK_VERSIONS="${*:-${SPARK_VERSIONS:-1.3 1.4 1.5 1.6 latest}}"

SPARK_HOST="${DOCKER_HOST:-${SPARK_HOST:-${HOST:-localhost}}}"
SPARK_HOST="${SPARK_HOST##*/}"
SPARK_HOST="${SPARK_HOST%%:*}"
export SPARK_HOST
export SPARK_MASTER_PORT_DEFAULT=8080
export SPARK_WORKER_PORT_DEFAULT=8081

export DOCKER_IMAGE="harisekhon/spark"
export DOCKER_CONTAINER="nagios-plugins-spark-test"

startupwait 15

check_docker_available

trap_debug_env spark

test_spark(){
    local version="$1"
    section2 "Setting up Spark $version test container"
    docker-compose down &>/dev/null
    docker_compose_pull
    if [ -z "${KEEPDOCKER:-}" ]; then
        docker-compose down || :
    fi
    VERSION="$version" docker-compose up -d --remove-orphans
    hr
    echo "getting Spark dynamic port mappings:"
    printf "Spark Master Port => "
    SPARK_MASTER_PORT="$(docker-compose port "$DOCKER_SERVICE" "$SPARK_MASTER_PORT_DEFAULT" | sed 's/.*://')"
    export SPARK_MASTER_PORT
    echo "$SPARK_MASTER_PORT"
    printf "Spark Worker Port => "
    SPARK_WORKER_PORT="$(docker-compose port "$DOCKER_SERVICE" "$SPARK_WORKER_PORT_DEFAULT" | sed 's/.*://')"
    export SPARK_WORKER_PORT
    echo "$SPARK_WORKER_PORT"
    hr
    when_ports_available "$SPARK_HOST" "$SPARK_MASTER_PORT" "$SPARK_WORKER_PORT"
    hr
    when_url_content "http://$SPARK_HOST:$SPARK_MASTER_PORT" "Spark Master"
    hr
    when_url_content "http://$SPARK_HOST:$SPARK_WORKER_PORT" "Spark Worker"
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    if [ "$version" = "latest" ]; then
        echo "latest version, fetching latest version from DockerHub master branch"
        local version
        version="$(dockerhub_latest_version spark)"
        echo "expecting version '$version'"
    fi
    hr
    run ./check_spark_master_version.py -e "$version"

    run_fail 2 ./check_spark_master_version.py -e "fail-version"

    run_conn_refused ./check_spark_master_version.py -e "$version"

    run ./check_spark_worker_version.py -e "$version"

    run_fail 2 ./check_spark_worker_version.py -e "fail-version"

    run_conn_refused ./check_spark_worker_version.py -e "$version"

    # defined in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "trying check_spark_cluster.pl for up to $startupwait secs to give cluster worker a chance to initialize:"
    retry "$startupwait" ./check_spark_cluster.pl -c 1: -v
    hr

    # $perl defined in bash-tools/lib/perl.sh (imported by utils.sh)
    # shellcheck disable=SC2154
    run "$perl" -T ./check_spark_cluster.pl -c 1: -v

    run_conn_refused "$perl" -T ./check_spark_cluster.pl -c 1: -v

    run "$perl" -T ./check_spark_cluster_dead_workers.pl -w 0 -c 1 -v

    run_conn_refused "$perl" -T ./check_spark_cluster_dead_workers.pl -w 1 -c 1 -v

    run "$perl" -T ./check_spark_cluster_memory.pl -w 80 -c 90 -v

    run_conn_refused "$perl" -T ./check_spark_cluster_memory.pl -w 80 -c 90 -v

    run "$perl" -T ./check_spark_worker.pl -w 80 -c 90 -v

    run_conn_refused "$perl" -T ./check_spark_worker.pl -w 80 -c 90 -v

    if [ -n "${KEEPDOCKER:-}" ]; then
        echo
        # defined and tracked in bash-tools/lib/utils.sh
        # shellcheck disable=SC2154
        echo "Completed $run_count Spark tests"
        return
    fi
    echo "Now killing Spark Worker to check for worker failure detection:"
    docker exec "$DOCKER_CONTAINER" pkill -9 -f org.apache.spark.deploy.worker.Worker
    hr
    echo "Now waiting for Spark Worker failure to be detected:"
    retry 10 ! "$perl" -T ./check_spark_cluster_dead_workers.pl
    run++
    hr
    # defined and tracked in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "Completed $run_count Spark tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    hr
    echo
}

run_test_versions Spark

if is_CI; then
    docker_image_cleanup
    echo
fi
