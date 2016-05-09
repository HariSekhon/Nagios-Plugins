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
srcdir2="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir2/..";

. ./tests/utils.sh

# because including bash-tools/util.sh resets the srcdir
srcdir="$srcdir2"

echo "
# ============================================================================ #
#                                   N g i n x
# ============================================================================ #
"

NGINX_HOST="${DOCKER_HOST:-${NGINX_HOST:-${HOST:-localhost}}}"
NGINX_HOST="${NGINX_HOST##*/}"
NGINX_HOST="${NGINX_HOST%%:*}"
export NGINX_HOST

export DOCKER_IMAGE="nginx"
export DOCKER_CONTAINER="nagios-plugins-nginx"

if ! is_docker_available; then
    echo 'WARNING: Docker not found, skipping Nginx checks!!!'
    exit 0
fi

startupwait=1
is_travis && let startupwait+=4

echo "Setting up Nginx test container"
if ! is_docker_container_running "$DOCKER_CONTAINER"; then
    docker rm -f "$DOCKER_CONTAINER" &>/dev/null || :
    echo "Starting Docker Nginx test container"
    docker create --name "$DOCKER_CONTAINER" -p 80:80 nginx
    docker cp "$srcdir/conf/nginx/conf.d/default.conf" "$DOCKER_CONTAINER":/etc/nginx/conf.d/default.conf
    docker start "$DOCKER_CONTAINER"
    echo "waiting $startupwait seconds for Nginx to start up"
    sleep $startupwait
else
    echo "Docker Nginx test container already running"
fi

hr
$perl -T $I_lib ./check_nginx_stats.pl -H "$NGINX_HOST" -u /status
hr
delete_container
