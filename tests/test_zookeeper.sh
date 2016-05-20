#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-11-11 19:49:15 +0000 (Wed, 11 Nov 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help improve or steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

set -eu
[ -n "${DEBUG:-}" ] && set -x
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

. ./tests/utils.sh

echo "
# ============================================================================ #
#                           Z o o K e e p e r
# ============================================================================ #
"

ZOOKEEPER_HOST="${DOCKER_HOST:-${ZOOKEEPER_HOST:-${HOST:-localhost}}}"
ZOOKEEPER_HOST="${ZOOKEEPER_HOST##*/}"
ZOOKEEPER_HOST="${ZOOKEEPER_HOST%%:*}"
export ZOOKEEPER_HOST

export DOCKER_IMAGE="harisekhon/zookeeper"
export DOCKER_IMAGE2="harisekhon/nagios-plugins"
export DOCKER_CONTAINER="nagios-plugins-zookeeper-test"
export DOCKER_CONTAINER2="nagios-plugins-test"

export MNTDIR="/pl"

docker_exec(){
    docker exec -ti "$DOCKER_CONTAINER2" $MNTDIR/$@
}

startupwait=10

echo "Setting up ZooKeeper test container"
launch_container "$DOCKER_IMAGE" "$DOCKER_CONTAINER" 2181 3181 4181
docker cp "$DOCKER_CONTAINER":/zookeeper/conf/zoo.cfg .
hr
echo "Setting up nagios-plugins test container with zkperl library"
DOCKER_OPTS="--link $DOCKER_CONTAINER:zookeeper -v $PWD:$MNTDIR"
DOCKER_CMD="tail -f /dev/null"
launch_container "$DOCKER_IMAGE2" "$DOCKER_CONTAINER2"
docker cp zoo.cfg "$DOCKER_CONTAINER2":"$MNTDIR/"
hr
$perl -T $I_lib ./check_zookeeper.pl -s -w 10 -c 20 -v
hr
docker_exec check_zookeeper_config.pl -H zookeeper -P 2181 -C "$MNTDIR/zoo.cfg" -v
hr
docker_exec check_zookeeper_child_znodes.pl -H zookeeper -P 2181 -z / --no-ephemeral-check -v
hr
docker_exec check_zookeeper_znode.pl -H zookeeper -P 2181 -z / -v -n --child-znodes
hr

delete_container "$DOCKER_CONTAINER2"
delete_container "$DOCKER_CONTAINER"
