#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-01-26 23:36:03 +0000 (Tue, 26 Jan 2016)
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

srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/.."

. "$srcdir/utils.sh"

section "A p a c h e   D r i l l"

export APACHE_DRILL_VERSIONS="${@:-${APACHE_DRILL_VERSIONS:-latest 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 1.10}}"

APACHE_DRILL_HOST="${DOCKER_HOST:-${APACHE_DRILL_HOST:-${HOST:-localhost}}}"
APACHE_DRILL_HOST="${APACHE_DRILL_HOST##*/}"
APACHE_DRILL_HOST="${APACHE_DRILL_HOST%%:*}"
export APACHE_DRILL_HOST
export APACHE_DRILL_PORT_DEFAULT=8047

export DOCKER_CONTAINER="nagios-plugins-apache-drill"

check_docker_available

trap_debug_env apache_drill

test_apache_drill(){
    local version="$1"
    section2 "Setting up Apache Drill $version test container"
    if is_CI || [ -n "${DOCKER_PULL:-}" ]; then
        VERSION="$version" docker-compose pull $docker_compose_quiet
    fi
    VERSION="$version" docker-compose up -d
    hr
    echo "getting Apache Drill dynamic port mappings:"
    docker_compose_port "Apache Drill"
    hr
    when_ports_available "$APACHE_DRILL_HOST" "$APACHE_DRILL_PORT"
    hr
    when_url_content "http://$APACHE_DRILL_HOST:$APACHE_DRILL_PORT/status" "Running"
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    docker_compose_version_test apache-drill "$version"
    hr
    #run ./check_apache_drill_version.py -v -e "$version"

    #run_fail 2 ./check_apache_drill_version.py -v -e "fail-version"

    run ./check_apache_drill_status.py -v

    run_conn_refused ./check_apache_drill_status.py -v

    run $perl -T ./check_apache_drill_metrics.pl -v

    run_conn_refused $perl -T ./check_apache_drill_metrics.pl -v

    echo "Completed $run_count Apache Drill tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    echo
}

startupwait 50

run_test_versions "Apache Drill"
