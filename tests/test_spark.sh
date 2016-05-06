#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-02-10 23:18:47 +0000 (Wed, 10 Feb 2016)
#
#  https://github.com/harisekhon
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

SPARK_HOST="${DOCKER_HOST:-${SPARK_HOST:-${HOST:-localhost}}}"
SPARK_HOST="${SPARK_HOST##*/}"
SPARK_HOST="${SPARK_HOST%%:*}"
export SPARK_HOST
echo "using docker address '$SPARK_HOST'"
export SPARK_MASTER_PORT="${SPARK_MASTER_PORT:-8080}"
export SPARK_WORKER_PORT="${SPARK_WORKER_PORT:-8081}"

export DOCKER_CONTAINER="nagios-plugins-spark"

if ! is_docker_available; then
    echo 'WARNING: Docker not found, skipping spark checks!!!'
    exit 0
fi

startupwait=10
is_travis && let startupwait+=20

hr
echo "Setting up Spark test container"
hr
# reuse container it's faster
#docker rm -f "$DOCKER_CONTAINER" &>/dev/null
#sleep 1
if ! docker ps | tee /dev/stderr | grep -q "[[:space:]]$DOCKER_CONTAINER$"; then
    docker rm -f "$DOCKER_CONTAINER" &>/dev/null || :
    echo "Starting Docker Spark test container"
    # need tty for sudo which spark-start.sh local uses while ssh'ing localhost
    docker run -d -t --name "$DOCKER_CONTAINER" -p $SPARK_MASTER_PORT:$SPARK_MASTER_PORT -p $SPARK_WORKER_PORT:$SPARK_WORKER_PORT harisekhon/spark
    echo "waiting $startupwait seconds for Spark Master + Worker to become responsive..."
    sleep $startupwait
else
    echo "Docker Spark test container already running"
fi

hr
$perl -T $I_lib ./check_spark_cluster.pl -c 1: -v
hr
$perl -T $I_lib ./check_spark_cluster_dead_workers.pl -w 1 -c 1 -v
hr
$perl -T $I_lib ./check_spark_cluster_memory.pl -w 80 -c 90 -v
hr
$perl -T $I_lib ./check_spark_worker.pl -w 80 -c 90 -v
hr
echo
echo -n "Deleting container "
docker rm -f "$DOCKER_CONTAINER"
echo; echo
