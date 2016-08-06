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

export DOCKER_IMAGE="mongo"
export DOCKER_CONTAINER="nagios-plugins-mongo-test"

export MONGO_PORTS="27017 28017"

docker rm -f "$DOCKER_CONTAINER-auth" &>/dev/null || :

startupwait 5

echo "Setting up MongoDB test container"
DOCKER_CMD="--rest"
launch_container "$DOCKER_IMAGE" "$DOCKER_CONTAINER" $MONGO_PORTS
when_ports_available $startupwait $MONDODB_HOST $MONGO_PORTS
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
delete_container
hr

# ============================================================================ #

# XXX: New for MongoDB 3.0 - done to test API authentication changes in 1.x driver

export MONGODB_USERNAME="nagios"
export MONGODB_PASSWORD="testpw"

echo "Setting up MongoDB authenticated test container"
DOCKER_CMD="mongod --auth --rest"
launch_container "$DOCKER_IMAGE" "$DOCKER_CONTAINER-auth" $MONGO_PORTS
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
delete_container "$DOCKER_CONTAINER-auth"
