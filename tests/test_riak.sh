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
    run docker-compose exec --user riak "$DOCKER_SERVICE" "$MNTDIR/$@"
}

startupwait 20

test_riak(){
    local version="$1"
    section2 "Setting up Riak $version test container"
    if is_CI; then
        VERSION="$version" docker-compose pull $docker_compose_quiet
    fi
    VERSION="$version" docker-compose up -d
    echo "getting Riak dynamic port mapping:"
    echo "Riak HTTP port => "
    export RIAK_PORT="`docker-compose port "$DOCKER_SERVICE" "$RIAK_PORT_DEFAULT" | sed 's/.*://'`"
    echo "$RIAK_PORT"
    hr
    when_ports_available "$RIAK_HOST" "$RIAK_PORT"
    hr
    when_url_content "http://$RIAK_HOST:$RIAK_PORT/ping" OK
    hr
    echo "waiting for up to $startupwait secs for Riak to come fully up:"
    SECONDS=0
    count=1
    while true; do
        echo -n "try $count:  "
        if $perl -T check_riak_write.pl -v; then
            break
        fi
        if ! [ $SECONDS -le $startupwait ]; then
            echo "FAIL: Riak not ready after $startupwait secs"
            exit 1
        fi
        let count+=1
        sleep 1
    done
    hr
    # Riak 2.x
    #echo "creating myBucket with n_val setting of 1 (to avoid warnings in riak-admin)"
    #docker exec -ti -u riak "$DOCKER_CONTAINER" riak-admin bucket-type create myBucket '{"props":{"n_val":1}}' || :
    #docker exec -ti -u riak "$DOCKER_CONTAINER" riak-admin bucket-type activate myBucket
    #docker exec -ti -u riak "$DOCKER_CONTAINER" riak-admin bucket-type update myBucket '{"props":{"n_val":1}}'
    echo "creating test Riak document"
    # don't use new bucket types yet
    #curl -XPUT localhost:8098/types/myType/buckets/myBucket/keys/myKey -d 'hari'
    # This doesn't fail, returns
    #
    # Error:
    # all_nodes_down
    #
    # relying on check_riak_write.pl iterating test above to latch until Riak is ready so this will succeed
    curl -XPUT "$RIAK_HOST:$RIAK_PORT/buckets/myBucket/keys/myKey" -d 'hari'
    echo "done"
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    run $perl -T check_riak_version.pl -v -e "$version"
    hr
    run_fail 2 $perl -T check_riak_version.pl -v -e 'fail-version'
    hr
    run_conn_refused $perl -T check_riak_version.pl -v
    hr
    hr
    run $perl -T check_riak_api_ping.pl
    hr
    run_conn_refused $perl -T check_riak_api_ping.pl
    hr
    # riak-admin doesn't work in Dockerized environments, fails trying to stat '/proc/sys/net/core/wmem_default'
    #docker_exec check_riak_diag.pl --ignore-warnings -v
    # must attempt to check this locally if available - but may get "CRITICAL: 'riak-admin diag' returned 1 -  Node is not running!"
    if which riak-admin; then
        run_fail "0 2" $perl -T check_riak_diag.pl --ignore-warnings -v
    else
        echo "WARNING: riak-admin not available locally, skipping test of check_riak_diag.pl as it doesn't work in dockerized environments (fails to stat  '/proc/sys/net/core/wmem_default')"
    fi
    hr
    run $perl -T check_riak_key.pl -b myBucket -k myKey -e hari -v
    hr
    run_conn_refused $perl -T check_riak_key.pl -b myBucket -k myKey -e hari -v
    hr
    docker_exec check_riak_member_status.pl -v
    hr
    docker_exec check_riak_ringready.pl -v
    hr
    run $perl -T check_riak_stats.pl --all -v
    hr
    run_conn_refused $perl -T check_riak_stats.pl --all -v
    hr
    run $perl -T check_riak_stats.pl -s ring_num_partitions -c 64:64 -v
    hr
    if [ "${version:0:1}" != 1 ]; then
        run $perl -T check_riak_stats.pl -s disk.0.size -c 1024: -v
    fi
    hr
    run $perl -T check_riak_write.pl -v
    hr
    run_conn_refused $perl -T check_riak_write.pl -v
    hr
    docker_exec check_riak_write_local.pl -v
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
