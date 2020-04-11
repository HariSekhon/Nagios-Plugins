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

# shellcheck disable=SC1090
. "$srcdir/utils.sh"

section "R I A K"

export RIAK_VERSIONS="${*:-${RIAK_VERSIONS:-1.4 2.0 2.1 latest}}"

# RIAK_HOST no longer obtained via .travis.yml, some of these require local riak-admin tool so only makes more sense to run all tests locally
RIAK_HOST="${DOCKER_HOST:-${RIAK_HOST:-${HOST:-localhost}}}"
RIAK_HOST="${RIAK_HOST##*/}"
RIAK_HOST="${RIAK_HOST%%:*}"
export RIAK_HOST
export RIAK_PORT_DEFAULT=8098
export HAPROXY_PORT_DEFAULT=8098

export DOCKER_IMAGE="harisekhon/riak-dev"
export DOCKER_CONTAINER="nagios-plugins-riak-test"

export DOCKER_MOUNT_DIR="/pl"

check_docker_available

trap_debug_env riak

# picked up by docker_exec
export DOCKER_USER=riak

startupwait 20

test_riak(){
    local version="$1"
    section2 "Setting up Riak $version test container"
    docker_compose_pull
    VERSION="$version" docker-compose up -d --remove-orphans
    hr
    echo "getting Riak dynamic port mapping:"
    docker_compose_port Riak
    DOCKER_SERVICE=riak-haproxy docker_compose_port HAProxy
    hr
    # shellcheck disable=SC2153
    when_ports_available "$RIAK_HOST" "$RIAK_PORT" "$HAPROXY_PORT"
    hr
    when_url_content "http://$RIAK_HOST:$RIAK_PORT/ping" OK
    hr
    echo "checking HAProxy Riak:"
    when_url_content "http://$RIAK_HOST:$HAPROXY_PORT/ping" OK
    hr
    # defined in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "waiting for up to $startupwait secs for Riak to come fully up:"
    # $perl defined in bash-tools/lib/perl.sh (imported by utils.sh)
    # shellcheck disable=SC2154
    retry "$startupwait" "$perl" -T check_riak_write.pl -v
    hr
    if [ -z "${NOSETUP:-}" ]; then
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
        hr
    fi
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    if [ "$version" = "latest" ]; then
        echo "latest version, fetching latest version from DockerHub master branch"
        local version
        version="$(dockerhub_latest_version riak-dev)"
        echo "expecting version '$version'"
        # TODO: fix and remove
        version=".*"
    fi
    hr

    riak_tests

    echo
    section2 "HAProxy Riak tests:"
    echo

    RIAK_PORT="$HAPROXY_PORT" \
    riak_tests

    # defined and tracked in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "Completed $run_count Riak tests"
    hr
    echo
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    echo
    hr
    echo; echo
}

riak_tests(){
    run "$perl" -T check_riak_version.pl -v -e "$version"

    run_fail 2 "$perl" -T check_riak_version.pl -v -e 'fail-version'

    run_conn_refused "$perl" -T check_riak_version.pl -v

    run "$perl" -T check_riak_api_ping.pl

    run_conn_refused "$perl" -T check_riak_api_ping.pl

    # riak-admin doesn't work in Dockerized environments, fails trying to stat '/proc/sys/net/core/wmem_default'
    #docker_exec check_riak_diag.pl --ignore-warnings -v
    # must attempt to check this locally if available - but may get "CRITICAL: 'riak-admin diag' returned 1 -  Node is not running!"
    if type -P riak-admin; then
        run_fail "0 2" "$perl" -T check_riak_diag.pl --ignore-warnings -v
    else
        echo "WARNING: riak-admin not available locally, skipping test of check_riak_diag.pl as it doesn't work in dockerized environments (fails to stat  '/proc/sys/net/core/wmem_default')"
        hr
    fi

    run "$perl" -T check_riak_key.pl -b myBucket -k myKey -e hari -v

    run_conn_refused "$perl" -T check_riak_key.pl -b myBucket -k myKey -e hari -v

    docker_exec check_riak_member_status.pl -v

    docker_exec check_riak_ringready.pl -v

    run "$perl" -T check_riak_stats.pl --all -v

    run_conn_refused "$perl" -T check_riak_stats.pl --all -v

    run "$perl" -T check_riak_stats.pl -s ring_num_partitions -c 64:64 -v

    if [ "${version:0:1}" != 1 ]; then
        run "$perl" -T check_riak_stats.pl -s disk.0.size -c 1024: -v
    fi

    run "$perl" -T check_riak_write.pl -v

    run_conn_refused "$perl" -T check_riak_write.pl -v

    docker_exec check_riak_write_local.pl -v
}

run_test_versions Riak

if is_CI; then
    docker_image_cleanup
    echo
fi
