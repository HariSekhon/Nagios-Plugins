#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-05-25 01:38:24 +0100 (Mon, 25 May 2015)
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
#                               M e m c a c h e d
# ============================================================================ #
"

MEMCACHED_HOST="${DOCKER_HOST:-${MEMCACHED_HOST:-${HOST:-localhost}}}"
MEMCACHED_HOST="${MEMCACHED_HOST##*/}"
MEMCACHED_HOST="${MEMCACHED_HOST%%:*}"
export MEMCACHED_HOST
echo "using docker address '$MEMCACHED_HOST'"

export DOCKER_CONTAINER="nagios-plugins-memcached"

if ! is_docker_available; then
    echo 'WARNING: Docker not found, skipping Memcached checks!!!'
    exit 0
fi

startupwait=1
[ -n "${TRAVIS:-}" ] && let startupwait+=4

echo "Setting up test Memcached container"
if ! docker ps | tee /dev/stderr | grep -q "[[:space:]]$DOCKER_CONTAINER$"; then
    docker rm -f "$DOCKER_CONTAINER" &>/dev/null || :
    echo "Starting Docker Memcached test container"
    docker run -d --name "$DOCKER_CONTAINER" -p 11211:11211 memcached
    echo "waiting $startupwait second for Memcached to start up"
    sleep $startupwait
else
    echo "Docker Memcached test container already running"
fi

echo "creating test Memcached key-value"
echo -ne "add myKey 0 100 4\r\nhari\r\n" | nc $MEMCACHED_HOST 11211
echo done
hr
# MEMCACHED_HOST obtained via .travis.yml
$perl -T $I_lib ./check_memcached_write.pl -v
hr
$perl -T $I_lib ./check_memcached_key.pl -k myKey -e hari -v
hr
$perl -T $I_lib ./check_memcached_stats.pl -w 15 -c 20 -v
hr
echo
echo -n "Deleting container "
docker rm -f "$DOCKER_CONTAINER"
echo; echo
