#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-01-26 23:36:03 +0000 (Tue, 26 Jan 2016)
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
#                            A p a c h e   D r i l l
# ============================================================================ #
"

APACHE_DRILL_HOST="${DOCKER_HOST:-${APACHE_DRILL_HOST:-${HOST:-localhost}}}"
APACHE_DRILL_HOST="${APACHE_DRILL_HOST##*/}"
APACHE_DRILL_HOST="${APACHE_DRILL_HOST%%:*}"
export APACHE_DRILL_HOST
echo "using docker address '$APACHE_DRILL_HOST'"
export APACHE_DRILL_PORT="${APACHE_DRILL_PORT:-8047}"
#export DRILL_HEAP="900M"
#export DRILL_HOME="/apache-drill"

export DOCKER_IMAGE="harisekhon/zookeeper"
export DOCKER_IMAGE2="harisekhon/apache-drill"
export DOCKER_CONTAINER="nagios-plugins-zookeeper"
export DOCKER_CONTAINER2="nagios-plugins-drill"

if ! is_docker_available; then
    echo 'WARNING: Docker unavailable, skipping drill checks!!!'
    exit 0
fi

#[ -n "${DEBUG:-1}" ] && DOCKER_DEBUG="-ai" || DOCKER_DEBUG=""

startupwait=30
[ -n "${TRAVIS:-}" ] && let startupwait+=20

echo "Setting up apache drill test container"
hr
# reuse container it's faster
#docker rm -f "$DOCKER_CONTAINER" &>/dev/null
#sleep 1
if ! docker ps | tee /dev/stderr | grep -q "[[:space:]]$DOCKER_CONTAINER$"; then
    docker rm -f "$DOCKER_CONTAINER" &>/dev/null || :
    docker rm -f "$DOCKER_CONTAINER2" &>/dev/null || :
    echo "Starting Docker ZooKeeper test container"
    docker run -d --name "$DOCKER_CONTAINER" -p 2181:2181 -p 3181:3181 -p 4181:4181 "$DOCKER_IMAGE"
    sleep 1
    hr

    ## working default 900M put in container itself now
    #
    #echo "Creating Docker apache-drill test container"
    #docker create --name "$DOCKER_CONTAINER" -p $APACHE_DRILL_PORT:$APACHE_DRILL_PORT harisekhon/apache-drill
    #echo "setting heap to $DRILL_HEAP"
    # more efficient but can't do this because the container isn't started yet
    #docker exec /usr/bin/perl -pi -e "s/^DRILL_HEAP=\"4G\"/DRILL_HEAP=\"$DRILL_HEAP\"/" "$DRILL_HOME/conf/drill-env.sh"
    # more portable
    #docker cp "$DOCKER_CONTAINER:$DRILL_HOME/conf/drill-env.sh" /tmp/
    #perl -pi -e "s/^DRILL_HEAP=\"4G\"/DRILL_HEAP=\"$DRILL_HEAP\"/" /tmp/drill-env.sh
    #docker cp /tmp/drill-env.sh "$DOCKER_CONTAINER:$DRILL_HOME/conf/drill-env.sh"
    #rm /tmp/drill-env.sh
    echo "Starting Docker Apache Drill test container"
    #docker start $DOCKER_DEBUG "$DOCKER_CONTAINER"
    #docker run -d --name "$DOCKER_CONTAINER" -p $APACHE_DRILL_PORT:$APACHE_DRILL_PORT harisekhon/apache-drill supervisord -n
    docker run -d --name "$DOCKER_CONTAINER2" --link "$DOCKER_CONTAINER:zookeeper" -p $APACHE_DRILL_PORT:$APACHE_DRILL_PORT "$DOCKER_IMAGE2" supervisord -n
    echo "waiting $startupwait seconds for drill to start up"
    sleep $startupwait
else
    echo "Docker apache-drill test container already running"
fi

hr
./check_apache_drill_status.py -v
hr
$perl -T $I_lib ./check_apache_drill_metrics.pl -v
hr
echo
echo -n "Deleting container "
docker rm -f "$DOCKER_CONTAINER"
echo -n "Deleting container "
docker rm -f "$DOCKER_CONTAINER2"
echo; echo
