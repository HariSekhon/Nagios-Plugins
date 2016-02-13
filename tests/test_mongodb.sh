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
#                                M o n g o D B
# ============================================================================ #
"

export MONGODB_HOST="${MONGODB_HOST:-localhost}"

export DOCKER_CONTAINER="nagios-plugins-mongo"

if ! is_docker_available; then
    echo 'WARNING: Docker not found, skipping Memcached checks!!!'
    exit 0
fi

echo "Setting up test MongoDB container"
if ! docker ps | tee /dev/stderr | grep -q "[[:space:]]$DOCKER_CONTAINER$"; then
    echo "Starting Docker MongoDB test container"
    docker run -d --name "$DOCKER_CONTAINER" -p 27017:27017 mongo
    sleep 1
else
    echo "Docker MongoDB test container already running"
fi

hr
# not part of a replica set so this fails
#$perl -T $I_lib ./check_mongodb_master.pl
#hr
#$perl -T $I_lib ./check_mongodb_master_rest.pl
#hr
# Type::Tiny::XS currently doesn't build on Perl 5.8 due to a bug
if [ "$PERL_MAJOR_VERSION" != "5.8" ]; then
    $perl -T $I_lib ./check_mongodb_write.pl -v
fi
hr
echo
echo -n "Deleting container "
docker rm -f "$DOCKER_CONTAINER"
echo; echo
