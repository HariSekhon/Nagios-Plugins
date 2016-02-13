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
#  http://www.linkedin.com/in/harisekhon
#

set -eu
[ -n "${DEBUG:-}" ] && set -x
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

. ./tests/utils.sh

echo "
# ============================================================================ #
#                                   R e d i s
# ============================================================================ #
"

export REDIS_HOST="${REDIS_HOST:-localhost}"
#export REDIS_PASSWORD="testpass123"
unset REDIS_PASSWORD
unset PASSWORD

export DOCKER_CONTAINER="nagios-plugins-redis"

if ! is_docker_available; then
    echo 'WARNING: Docker not found, skipping Redis checks!!!'
    exit 0
fi

echo "Setting up test Redis container"
if ! docker ps | tee /dev/stderr | grep -q "[[:space:]]$DOCKER_CONTAINER$"; then
    docker rm -f "$DOCKER_CONTAINER" &>/dev/null || :
    echo "Starting Docker Redis test container"
    docker run -d --name "$DOCKER_CONTAINER" -p 6379:6379 redis ########--requirepass "$REDIS_PASSWORD"
    sleep 1
else
    echo "Docker Redis test container already running"
fi

echo "creating test Redis key-value"
echo set myKey hari | redis-cli -h "$REDIS_HOST"
echo done
hr
# REDIS_HOST obtained via .travis.yml
$perl -T $I_lib ./check_redis_clients.pl -v
hr
# there is no redis.conf in the Docker container :-/
#docker cp "$DOCKER_CONTAINER":/etc/redis.conf /tmp/redis.conf
# doesn't match
#wget -O /tmp/redis.conf https://raw.githubusercontent.com/antirez/redis/3.0/redis.conf
> /tmp/.check_redis_config.conf
$perl -T $I_lib ./check_redis_config.pl -H $REDIS_HOST -C /tmp/.check_redis_config.conf --no-warn-extra -v | sed 's/.*extra config found on running server://;s/=/ /g' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | egrep -v -e "^requirepass|bind|logfile|masterauth|notify-keyspace-events|slaveof|unixsocket$" | tee /tmp/.check_redis_config.conf
$perl -T $I_lib ./check_redis_config.pl -H $REDIS_HOST -C /tmp/.check_redis_config.conf --no-warn-extra -v
rm /tmp/.check_redis_config.conf
hr
$perl -T $I_lib ./check_redis_key.pl -k myKey -e hari -v
hr
$perl -T $I_lib ./check_redis_publish_subscribe.pl -v
hr
$perl -T $I_lib ./check_redis_stats.pl -v
hr
$perl -T $I_lib ./check_redis_stats.pl -s connected_clients -c 1:1 -v
hr
$perl -T $I_lib ./check_redis_version.pl -v
hr
$perl -T $I_lib ./check_redis_write.pl -v
hr
echo "checking for no code failure masking root cause in catch quit handler"
$perl -T $I_lib ./check_redis_stats.pl -P 9999 -s connected_clients -c 1:1 -v | tee /dev/stderr | grep -v ' line '
hr
echo
echo -n "Deleting container "
docker rm -f "$DOCKER_CONTAINER"
echo; echo
