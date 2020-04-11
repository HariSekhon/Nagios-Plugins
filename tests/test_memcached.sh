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
srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$srcdir/..";

# shellcheck disable=SC1090
. "$srcdir/utils.sh"

section "M e m c a c h e d"

if is_CI; then
    echo "Skipping Memcached checks as they sometimes hang in CI"
    exit 0
fi

export MEMCACHED_VERSIONS="${*:-${MEMCACHED_VERSIONS:-1.4 1.5 latest}}"

MEMCACHED_HOST="${DOCKER_HOST:-${MEMCACHED_HOST:-${HOST:-localhost}}}"
MEMCACHED_HOST="${MEMCACHED_HOST##*/}"
MEMCACHED_HOST="${MEMCACHED_HOST%%:*}"
export MEMCACHED_HOST

export MEMCACHED_PORT_DEFAULT=11211

check_docker_available

trap_debug_env memcached

startupwait 1

test_memcached(){
    local version="$1"
    section2 "Setting up Memcached $version test container"
    docker_compose_pull
    VERSION="$version" docker-compose up -d --remove-orphans
    hr
    echo "getting Memcached dynamic port mapping:"
    docker_compose_port Memcached
    hr
    # inferred and defined by docker_compose_post
    # shellcheck disable=SC2153
    when_ports_available "$MEMCACHED_HOST" "$MEMCACHED_PORT"
    hr
    echo "creating test Memcached key-value"
    # shellcheck disable=SC1117
    echo -ne "add myKey 0 100 4\r\nhari\r\n" |
    # function wrapper defined in bash-tools/lib/utils.sh to call gtimeout on Mac
    if type timeout &>/dev/null; then
        # -k=60 gives 'Abort trap 6' error on Mac
        timeout -k 60 10 nc -v "$MEMCACHED_HOST" "$MEMCACHED_PORT"
    else
        nc -v "$MEMCACHED_HOST" "$MEMCACHED_PORT"
    fi
    echo "Done"
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    hr
    if [ "$version" = "latest" ]; then
        version=".*"
    fi
    echo "expecting version '$version'"
    hr
    # --version doesn't work in older versions eg. 1.4
    set +e
    found_version="$(docker-compose exec "$DOCKER_SERVICE" /usr/local/bin/memcached -V | tr -d '\r' | awk '{print $2}')"
    set -e
    if [ -z "$found_version" ]; then
        echo "FAILED to find memcached version"
    fi
    echo "found Memcached version '$found_version'"
    hr
    if [[ "$found_version" =~ $version ]]; then
        echo "Memcached docker container version matches expected (found '$found_version', expected '$version')"
    else
        echo "Memcached docker container version does not match expected version! (found '$found_version', expected '$version')"
        exit 1
    fi
    hr
    # MEMCACHED_HOST obtained via .travis.yml
    # $perl defined in bash-tools/lib/perl.sh (imported by utils.sh)
    # shellcheck disable=SC2154
    run "$perl" -T ./check_memcached_write.pl -v

    run_conn_refused "$perl" -T ./check_memcached_write.pl -v

    run "$perl" -T ./check_memcached_key.pl -k myKey -e hari -v

    run_conn_refused "$perl" -T ./check_memcached_key.pl -k myKey -e hari -v

    run "$perl" -T ./check_memcached_stats.pl -w 15 -c 20 -v

    run_conn_refused "$perl" -T ./check_memcached_stats.pl -w 15 -c 20 -v

    # defined and incremented in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "Completed $run_count Memcached tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    hr
    echo
}

run_test_versions Memcached

if is_CI; then
    docker_image_cleanup
    echo
fi
