#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-08-15 23:35:27 +0100 (Wed, 15 Aug 2018)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback
#
#  https://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$srcdir/.."

# shellcheck disable=SC1090
. "$srcdir/utils.sh"

section "N i f i"

export NIFI_VERSIONS="${*:-${NIFI_VERSIONS:-0.5 0.6 0.7 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 latest}}"

NIFI_HOST="${DOCKER_HOST:-${NIFI_HOST:-${HOST:-localhost}}}"
NIFI_HOST="${NIFI_HOST##*/}"
NIFI_HOST="${NIFI_HOST%%:*}"
export NIFI_HOST

export NIFI_PORT_DEFAULT=8080

startupwait 60

check_docker_available

trap_debug_env nifi

test_nifi(){
    local version="$1"
    section2 "Setting up Nifi $version test container"
    docker_compose_pull
    VERSION="$version" docker-compose up -d --remove-orphans
    hr
    echo "getting Nifi dynamic port mapping:"
    docker_compose_port "Nifi"
    hr
    # ============================================================================ #
    # shellcheck disable=SC2153
    when_ports_available "$NIFI_HOST" "$NIFI_PORT"
    hr
    when_url_content "http://$NIFI_HOST:$NIFI_PORT/nifi/" "nifi"
    hr
    # ============================================================================ #
    if [ "${version:0:1}" != 1 ]; then
        retry 10 ./check_nifi_status.py
    fi
    hr
    # ============================================================================ #
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    if [ "$version" = "latest" ]; then
        version=".*"
    fi
    run ./check_nifi_version.py -e "$version"

    run_fail 2 ./check_nifi_version.py -e "fail-version"

    run_conn_refused ./check_nifi_version.py -e "$version"

    # ============================================================================ #

    run ./check_nifi_java_gc.py

    run_fail 1 ./check_nifi_java_gc.py -w 1

    run_fail 2 ./check_nifi_java_gc.py -c 1

    run_conn_refused ./check_nifi_java_gc.py

    # ============================================================================ #

    run ./check_nifi_processor_load_average.py

    run_fail 1 ./check_nifi_processor_load_average.py -w 0.01

    run_fail 2 ./check_nifi_processor_load_average.py -c 0.01

    run_conn_refused ./check_nifi_processor_load_average.py

    # defined and tracked in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "Completed $run_count Nifi tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    echo
}

run_test_versions Nifi

if is_CI; then
    docker_image_cleanup
    echo
fi
