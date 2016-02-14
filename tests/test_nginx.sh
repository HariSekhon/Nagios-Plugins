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
#                                   N g i n x
# ============================================================================ #
"

export NGINX_HOST="${NGINX_HOST:-${HOST:-localhost}}"

export DOCKER_CONTAINER="nagios-plugins-nginx"

if ! is_docker_available; then
    echo 'WARNING: Docker not found, skipping Nginx checks!!!'
    exit 0
fi

echo "Setting up test Nginx container"
if ! docker ps | tee /dev/stderr | grep -q "[[:space:]]$DOCKER_CONTAINER$"; then
    docker rm -f "$DOCKER_CONTAINER" &>/dev/null || :
    echo "Starting Docker Nginx test container"
    docker create --name "$DOCKER_CONTAINER" -p 80:80 nginx
    docker cp "$srcdir/conf/nginx/conf.d/default.conf" "$DOCKER_CONTAINER":/etc/nginx/conf.d/default.conf
    docker start "$DOCKER_CONTAINER"
    echo "waiting 1 second for Nginx to start up"
    sleep 1
else
    echo "Docker Nginx test container already running"
fi

hr
$perl -T $I_lib ./check_nginx_stats.pl -H "$NGINX_HOST" -u /status
hr
echo
echo -n "Deleting container "
docker rm -f "$DOCKER_CONTAINER"
echo; echo
