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

. "$srcdir/utils.sh"

section "S p a r k"

export SPARK_VERSIONS="${@:-${SPARK_VERSIONS:-latest 1.3 1.4 1.5 1.6}}"

SPARK_HOST="${DOCKER_HOST:-${SPARK_HOST:-${HOST:-localhost}}}"
SPARK_HOST="${SPARK_HOST##*/}"
SPARK_HOST="${SPARK_HOST%%:*}"
export SPARK_HOST
export SPARK_MASTER_PORT_DEFAULT="${SPARK_MASTER_PORT:-8080}"
export SPARK_WORKER_PORT_DEFAULT="${SPARK_WORKER_PORT:-8081}"

export DOCKER_IMAGE="harisekhon/spark"
export DOCKER_CONTAINER="nagios-plugins-spark-test"

startupwait 15

check_docker_available

trap_debug_env spark

test_spark(){
    local version="$1"
    hr
    section2 "Setting up Spark $version test container"
    hr
    #launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $SPARK_MASTER_PORT $SPARK_WORKER_PORT
    docker-compose down &>/dev/null
    VERSION="$version" docker-compose up -d
    export SPARK_MASTER_PORT="`docker-compose port "$DOCKER_SERVICE" "$SPARK_MASTER_PORT_DEFAULT" | sed 's/.*://'`"
    export SPARK_WORKER_PORT="`docker-compose port "$DOCKER_SERVICE" "$SPARK_WORKER_PORT_DEFAULT" | sed 's/.*://'`"
    when_ports_available $startupwait $SPARK_HOST $SPARK_MASTER_PORT $SPARK_WORKER_PORT
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    if [ "$version" = "latest" ]; then
        local version=".*"
    fi
    hr
    echo "./check_spark_master_version.py -e '$version'"
    ./check_spark_master_version.py -e "$version"
    hr
    echo "./check_spark_worker_version.py -e '$version'"
    ./check_spark_worker_version.py -e "$version"
    hr
    echo "trying check_spark_cluster.pl up to 10 times to give cluster worker a chance to initialize:"
    set +e
    for x in {1..10}; do
        echo -n "$x: "
        $perl -T ./check_spark_cluster.pl -c 1: -v && break
        sleep 1
    done
    set -e
    hr
    echo "$perl -T ./check_spark_cluster.pl -c 1: -v"
    $perl -T ./check_spark_cluster.pl -c 1: -v
    hr
    echo "$perl -T ./check_spark_cluster_dead_workers.pl -w 1 -c 1 -v"
    $perl -T ./check_spark_cluster_dead_workers.pl -w 1 -c 1 -v
    hr
    echo "$perl -T ./check_spark_cluster_memory.pl -w 80 -c 90 -v"
    $perl -T ./check_spark_cluster_memory.pl -w 80 -c 90 -v
    hr
    echo "$perl -T ./check_spark_worker.pl -w 80 -c 90 -v"
    $perl -T ./check_spark_worker.pl -w 80 -c 90 -v
    hr
    #delete_container
    docker-compose down
    hr
    echo
}

run_test_versions Spark
