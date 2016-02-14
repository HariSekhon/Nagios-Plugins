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

export ZOOKEEPER_HOST="${ZOOKEEPER_HOST:-${HOST:-localhost}}"

# XXX: make sure to keep this aligned with Makefile to pull down correct zookeeper version
#ZOOKEEPER_VERSION=3.4.6
#zookeeper="zookeeper-$ZOOKEEPER_VERSION"
#TAR="$zookeeper.tgz"

#if ! [ -e "$TAR" ]; then
#    echo "fetching zookeeper tarball '$TAR'"
#    wget "http://www.us.apache.org/dist/zookeeper/zookeeper-$zookeeper_VERSION/$TAR"
#    echo
#fi

#if ! [ -d "$zookeeper" ]; then
#    echo "unpacking zookeeper"
#    tar zxf "$TAR"
#    echo
#fi

#if [ -n "$zookeeper_built" -a -z "$(netstat -an | grep [:.]2181)" ]; then
#    cp -vf "$zookeeper/conf/zoo_sample.cfg" "$zookeeper/conf/zoo.cfg"
#
#    "$zookeeper/bin/zkServer.sh" start &
#    sleep 10
#fi

export DOCKER_IMAGE="harisekhon/zookeeper"
export DOCKER_IMAGE2="harisekhon/nagios-plugins"
export DOCKER_CONTAINER="nagios-plugins-zookeeper"
export DOCKER_CONTAINER2="nagios-plugins"
export MNTDIR="/nagios-plugins-tmp"

if ! is_docker_available; then
    echo 'WARNING: Docker not found, skipping ZooKeeper checks!!!'
    exit 0
fi

docker_run_test(){
    docker exec -ti "$DOCKER_CONTAINER2" $MNTDIR/$@
}

echo "Setting up test ZooKeeper container"
docker rm -f "$DOCKER_CONTAINER" &>/dev/null || :
docker rm -f "$DOCKER_CONTAINER2" &>/dev/null || :
echo "Starting Docker ZooKeeper test container"
docker run -d --name "$DOCKER_CONTAINER" -p 2181:2181 -p 3181:3181 -p 4181:4181 "$DOCKER_IMAGE"
docker cp "$DOCKER_CONTAINER":/zookeeper/conf/zoo.cfg .
hr
echo "Setting up test nagios-plugins container with zkperl library"
docker run -d --name "$DOCKER_CONTAINER2" --link "$DOCKER_CONTAINER:zookeeper" -v "$PWD":"$MNTDIR" "$DOCKER_IMAGE2" tail -f /dev/null
docker cp zoo.cfg "$DOCKER_CONTAINER2":"$MNTDIR/"
hr
echo "Sleeping for 5 secs to allow ZooKeeper time to start up"
sleep 5
hr
$perl -T $I_lib ./check_zookeeper.pl -s -w 10 -c 20 -v
hr
docker_run_test check_zookeeper_config.pl -H zookeeper -P 2181 -C "$MNTDIR/zoo.cfg" -v
hr
docker_run_test check_zookeeper_child_znodes.pl -H zookeeper -P 2181 -z / --no-ephemeral-check -v
hr
docker_run_test check_zookeeper_znode.pl -H zookeeper -P 2181 -z / -v -n --child-znodes
hr

#echo
#hr
#$perl -T $I_lib ./check_zookeeper.pl -s -w 10 -c 20 -v
#hr
#$perl -T $I_lib ./check_zookeeper_config.pl -C "$zookeeper/conf/zoo.cfg" -v
#hr
#if [ -n "$zookeeper_built" ]; then
#    $perl -T $I_lib ./check_zookeeper_child_znodes.pl -z / --no-ephemeral-check -v
#    hr
#    $perl -T $I_lib ./check_zookeeper_znode.pl -z / -v -n --child-znodes
#    hr
#fi

echo
echo -n "Deleting container "
docker rm -f "$DOCKER_CONTAINER"
echo -n "Deleting container "
docker rm -f "$DOCKER_CONTAINER2"
echo; echo
