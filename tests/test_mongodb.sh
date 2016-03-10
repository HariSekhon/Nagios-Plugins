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
#                                M o n g o D B
# ============================================================================ #
"

MONGODB_HOST="${DOCKER_HOST:-${MONGODB_HOST:-${HOST:-localhost}}}"
MONGODB_HOST="${MONGODB_HOST##*/}"
MONGODB_HOST="${MONGODB_HOST%%:*}"
export MONGODB_HOST
echo "using docker address '$MONGODB_HOST'"

export DOCKER_CONTAINER="nagios-plugins-mongo"

if ! is_docker_available; then
    echo 'WARNING: Docker not found, skipping Memcached checks!!!'
    exit 0
fi

startupwait=5
[ -n "${TRAVIS:-}" ] && let startupwait+=20

echo "Setting up test MongoDB container"
if ! is_docker_container_running "$DOCKER_CONTAINER"; then
    docker rm -f "$DOCKER_CONTAINER" &>/dev/null || :
    docker rm -f "$DOCKER_CONTAINER-auth" &>/dev/null || :
    echo "Starting Docker MongoDB test container"
    docker run -d --name "$DOCKER_CONTAINER" -p 27017:27017 -p 28017:28017 mongo --rest
    echo "waiting $startupwait seconds for mongod to start up"
    sleep $startupwait
else
    echo "Docker MongoDB test container already running"
fi

# not part of a replica set so this returns CRITICAL
# TODO: more specific CLI runs to valid critical and output
hr
$perl -T $I_lib ./check_mongodb_master.pl || :
hr
$perl -T $I_lib ./check_mongodb_master_rest.pl
hr
# Type::Tiny::XS currently doesn't build on Perl 5.8 due to a bug
if [ "$PERL_MAJOR_VERSION" != "5.8" ]; then
    $perl -T $I_lib ./check_mongodb_write.pl -v
fi
hr
echo
echo -n "Deleting container "
docker rm -f "$DOCKER_CONTAINER"
echo
hr

# ============================================================================ #

# XXX: New for MongoDB 3.0 - done to test API authentication changes in 1.x driver :-(

export MONGODB_USERNAME="nagios"
export MONGODB_PASSWORD="testpw"

echo "Setting up test MongoDB authenticated container"
if ! docker ps | tee /dev/stderr | grep -q "[[:space:]]$DOCKER_CONTAINER-auth$"; then
    docker rm -f "$DOCKER_CONTAINER" &>/dev/null || :
    docker rm -f "$DOCKER_CONTAINER-auth" &>/dev/null || :
    echo "Starting Docker MongoDB authenticated test container"
    docker run -d --name "$DOCKER_CONTAINER-auth" -p 27017:27017 -p 28017:28017 mongo mongod --auth --rest
    echo "waiting 5 seconds for mongod to start up"
    sleep 5
    echo "setting up test user"
    docker exec -i "$DOCKER_CONTAINER-auth" mongo --host localhost <<EOF
    use admin
    db.createUser({"user":"$MONGODB_USERNAME", "pwd":"$MONGODB_PASSWORD", "roles":[{role:"root", db:"admin"}]})
EOF
    #db.createUser({"user":"$MONGODB_USERNAME", "pwd":"$MONGODB_PASSWORD", "roles":[{role:"userAdminAnyDatabase", db:"admin"},{role:"readWriteAnyDatabase", db:"admin"}]})
    echo "testing test user authentication works in mongo shell before attempting plugin"
    # mongo client may not be installed and also make sure we are using the same version client from within the container to minimize incompatibilities
    docker exec -i "$DOCKER_CONTAINER-auth" mongo -u "$MONGODB_USERNAME" -p "$MONGODB_PASSWORD" --authenticationDatabase admin <<EOF # doesn't work without giving the authenticationDatabase
    use nagios
    db.nagioscoll.insert({'test':'test'})
EOF
else
    echo "Docker MongoDB authenticated test container already running"
fi
hr
# not part of a replica set so this returns CRITICAL
# TODO: more specific CLI runs to valid critical and output
hr
$perl -T $I_lib ./check_mongodb_master.pl || :
hr
# TODO: Fails - authentication not supported, basic auth doesn't seem to work
$perl -T $I_lib ./check_mongodb_master_rest.pl -v || :
hr
# Type::Tiny::XS currently doesn't build on Perl 5.8 due to a bug
if [ "$PERL_MAJOR_VERSION" != "5.8" ]; then
    $perl -T $I_lib ./check_mongodb_write.pl -v
fi
hr
echo
if [ -z "${NODELETE:-}" ]; then
    echo -n "Deleting container "
    docker rm -f "$DOCKER_CONTAINER"
fi
echo; echo
