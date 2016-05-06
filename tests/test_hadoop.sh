#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-05-06 12:12:15 +0100 (Fri, 06 May 2016)
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
#                                  H a d o o p
# ============================================================================ #
"

HADOOP_HOST="${DOCKER_HOST:-${HADOOP_HOST:-${HOST:-localhost}}}"
HADOOP_HOST="${HADOOP_HOST##*/}"
HADOOP_HOST="${HADOOP_HOST%%:*}"
export HADOOP_HOST
echo "using docker address '$HADOOP_HOST'"

export DOCKER_CONTAINER="nagios-plugins-hadoop"

if ! is_docker_available; then
    echo 'WARNING: Docker not found, skipping Hadoop checks!!!'
    exit 0
fi

startupwait=30
is_travis && let startupwait+=20

hr
echo "Setting up Hadoop test container"
hr
# reuse container it's faster
#docker rm -f "$DOCKER_CONTAINER" &>/dev/null
#sleep 1
if ! is_docker_container_running "$DOCKER_CONTAINER"; then
    docker rm -f "$DOCKER_CONTAINER" &>/dev/null || :
    echo "Starting Docker Hadoop test container"
    # need tty for sudo which hadoop-start.sh local uses while ssh'ing localhost
    docker run -d -t --name "$DOCKER_CONTAINER" \
        -p 8032:8032 \
        -p 8088:8088 \
        -p 9000:9000 \
        -p 10020:10020 \
        -p 19888:19888 \
        -p 50010:50010 \
        -p 50020:50020 \
        -p 50070:50070 \
        -p 50075:50075 \
        -p 50090:50090 \
        harisekhon/hadoop-dev
    echo "waiting $startupwait seconds for Hadoop to start up..."
    sleep $startupwait
else
    echo "Docker Hadoop test container already running"
fi

hr
# TODO: add checks
#$perl -T $I_lib 
#hr
#$perl -T $I_lib 
hr
if is_zookeeper_built; then
    #$perl -T $I_lib 
    :
else
    echo "ZooKeeper not built - skipping ZooKeeper checks"
fi
hr
echo
if [ -z "${NODELETE:-}" ]; then
    echo -n "Deleting container "
    docker rm -f "$DOCKER_CONTAINER"
fi
echo; echo
