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

echo "
# ============================================================================ #
#                                   S p a r k
# ============================================================================ #
"

export SPARK_VERSIONS="${@:-${SPARK_VERSIONS:-latest 1.3 1.4 1.5 1.6}}"

SPARK_HOST="${DOCKER_HOST:-${SPARK_HOST:-${HOST:-localhost}}}"
SPARK_HOST="${SPARK_HOST##*/}"
SPARK_HOST="${SPARK_HOST%%:*}"
export SPARK_HOST
export SPARK_MASTER_PORT="${SPARK_MASTER_PORT:-8080}"
export SPARK_WORKER_PORT="${SPARK_WORKER_PORT:-8081}"

export DOCKER_IMAGE="harisekhon/spark"
export DOCKER_CONTAINER="nagios-plugins-spark-test"

startupwait 15

check_docker_available

test_spark(){
    local version="$1"
    hr
    echo "Setting up Spark $version test container"
    hr
    #launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $SPARK_MASTER_PORT $SPARK_WORKER_PORT
    docker-compose down &>/dev/null
    VERSION="$version" docker-compose up -d
    spark_master_port="`docker-compose port "$DOCKER_SERVICE" "$SPARK_MASTER_PORT" | sed 's/.*://'`"
    spark_worker_port="`docker-compose port "$DOCKER_SERVICE" "$SPARK_WORKER_PORT" | sed 's/.*://'`"
    local SPARK_MASTER_PORT="$spark_master_port"
    local SPARK_WORKER_PORT="$spark_worker_port"
    when_ports_available $startupwait $SPARK_HOST $SPARK_MASTER_PORT $SPARK_WORKER_PORT
    if [ -n "${NOTESTS:-}" ]; then
        return 0
    fi
    if [ "$version" = "latest" ]; then
        local version=".*"
    fi
    hr
    ./check_spark_master_version.py -e "$version"
    hr
    ./check_spark_worker_version.py -e "$version"
    hr
    $perl -T ./check_spark_cluster.pl -c 1: -v
    hr
    $perl -T ./check_spark_cluster_dead_workers.pl -w 1 -c 1 -v
    hr
    $perl -T ./check_spark_cluster_memory.pl -w 80 -c 90 -v
    hr
    $perl -T ./check_spark_worker.pl -w 80 -c 90 -v
    hr
    #delete_container
    docker-compose down
    hr
    echo
}

for version in $SPARK_VERSIONS; do
    test_spark $version
done
