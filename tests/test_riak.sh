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

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

. ./tests/utils.sh

section "R I A K"

export RIAK_VERSIONS="${@:-${RIAK_VERSIONS:-latest 1.4 2.0 2.1}}"

# RIAK_HOST no longer obtained via .travis.yml, some of these require local riak-admin tool so only makes more sense to run all tests locally
RIAK_HOST="${DOCKER_HOST:-${RIAK_HOST:-${HOST:-localhost}}}"
RIAK_HOST="${RIAK_HOST##*/}"
RIAK_HOST="${RIAK_HOST%%:*}"
export RIAK_HOST
export RIAK_PORT_DEFAULT=8098

export DOCKER_IMAGE="harisekhon/riak-dev"
export DOCKER_CONTAINER="nagios-plugins-riak-test"

export MNTDIR="/pl"

check_docker_available

trap_debug_env riak

docker_exec(){
    run docker-compose exec --user riak "$DOCKER_SERVICE" $MNTDIR/$@
}

startupwait 20

test_riak(){
    local version="$1"
    section2 "Setting up Riak $version test container"
    #DOCKER_OPTS="-v $srcdir/..:$MNTDIR"
    #launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $RIAK_PORT
    VERSION="$version" docker-compose up -d
    export RIAK_PORT="`docker-compose port "$DOCKER_SERVICE" "$RIAK_PORT_DEFAULT" | sed 's/.*://'`"
    when_ports_available "$startupwait" "$RIAK_HOST" "$RIAK_PORT"
    echo "sleeping for 5 secs to allow process to settle"
    sleep 5
    # Riak 2.x
    #echo "creating myBucket with n_val setting of 1 (to avoid warnings in riak-admin)"
    #docker exec -ti -u riak "$DOCKER_CONTAINER" riak-admin bucket-type create myBucket '{"props":{"n_val":1}}' || :
    #docker exec -ti -u riak "$DOCKER_CONTAINER" riak-admin bucket-type activate myBucket
    #docker exec -ti -u riak "$DOCKER_CONTAINER" riak-admin bucket-type update myBucket '{"props":{"n_val":1}}'
    echo "creating test Riak document"
    # don't use new bucket types yet
    #curl -XPUT localhost:8098/types/myType/buckets/myBucket/keys/myKey -d 'hari'
    curl -XPUT "$RIAK_HOST:$RIAK_PORT/buckets/myBucket/keys/myKey" -d 'hari'
    echo "done"
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    hr
    # riak-admin doesn't work in Dockerized environments, fails trying to stat '/proc/sys/net/core/wmem_default'
    #docker_exec check_riak_diag.pl --ignore-warnings -v
    # must attempt to check this locally if available - but may get "CRITICAL: 'riak-admin diag' returned 1 -  Node is not running!"
    if which riak-admin; then
        echo "$perl -T check_riak_diag.pl --ignore-warnings -v || :"
        $perl -T check_riak_diag.pl --ignore-warnings -v || :
    fi
    hr
    run $perl -T check_riak_key.pl -b myBucket -k myKey -e hari -v
    hr
    docker_exec check_riak_member_status.pl -v
    hr
    docker_exec check_riak_ringready.pl -v
    hr
    run $perl -T check_riak_stats.pl --all -v
    hr
    run $perl -T check_riak_stats.pl -s ring_num_partitions -c 64:64 -v
    hr
    if [ "${version:0:1}" != 1 ]; then
        run $perl -T check_riak_stats.pl -s disk.0.size -c 1024: -v
    fi
    hr
    run $perl -T check_riak_write.pl -v
    hr
    docker_exec check_riak_write_local.pl -v
    hr
    run $perl -T check_riak_version.pl -v
    hr
    echo "Completed $run_count Riak tests"
    hr
    echo
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    echo
    hr
    echo; echo
}

run_test_versions Riak


# ============================================================================ #
#                                     E N D
# ============================================================================ #
exit 0
# ============================================================================ #
# Old Travis checks not used any more

echo "creating myBucket with n_val setting of 1 (to avoid warnings in riak-admin)"
$sudo riak-admin bucket-type create myBucket '{"props":{"n_val":1}}' || :
$sudo riak-admin bucket-type activate myBucket
$sudo riak-admin bucket-type update myBucket '{"props":{"n_val":1}}'
echo "creating test Riak document"
# don't use new bucket types yet
#curl -XPUT localhost:$RIAK_PORT/types/myType/buckets/myBucket/keys/myKey -d 'hari'
curl -XPUT $RIAK_HOST:$RIAK_PORT/buckets/myBucket/keys/myKey -d 'hari'
echo "done"
hr
# needs sudo - uses wrong version of perl if not explicit path with sudo
$sudo $perl -T ./check_riak_diag.pl --ignore-warnings -v
hr
$perl -T ./check_riak_key.pl -b myBucket -k myKey -e hari -v
hr
$sudo $perl -T ./check_riak_member_status.pl -v
hr
# needs sudo - riak must be started as root in Travis
$sudo $perl -T ./check_riak_ringready.pl -v
hr
$perl -T ./check_riak_stats.pl --all -v
hr
$perl -T ./check_riak_stats.pl -s ring_num_partitions -c 64:64 -v
hr
$perl -T ./check_riak_stats.pl -s disk.0.size -c 1024: -v
hr
$perl -T ./check_riak_write.pl -v
hr
# needs sudo - riak must be started as root in Travis
$sudo $perl -T ./check_riak_write_local.pl -v
hr
$perl -T ./check_riak_version.pl

echo; echo
