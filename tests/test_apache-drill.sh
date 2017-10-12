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
    VERSION="$version" docker-compose pull $docker_compose_quiet
    VERSION="$version" docker-compose up -d
    echo "getting Apache Drill dynamic port mappings:"
    printf "Apache Drill port => "
    export APACHE_DRILL_PORT="`docker-compose port "$DOCKER_SERVICE" "$APACHE_DRILL_PORT_DEFAULT" | sed 's/.*://'`"
    echo "$APACHE_DRILL_PORT"
    hr
    when_ports_available "$startupwait" "$APACHE_DRILL_HOST" "$APACHE_DRILL_PORT"
    hr
    when_url_content "$startupwait" "http://$APACHE_DRILL_HOST:$APACHE_DRILL_PORT/status" "Running"
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    if [ "$version" = "latest" ]; then
        local version="*"
    fi
    set +e
    #found_version="$(docker exec  "$DOCKER_CONTAINER" ls / | grep apache-drill | tee /dev/stderr | tail -n1 | sed 's/-[[:digit:]]*//')"
    #env | grep -i -e docker -e compose
    found_version="$(docker-compose exec "$DOCKER_SERVICE" ls / -1 --color=no | grep --color=no apache-drill | tee /dev/stderr | tail -n 1 | sed 's/apache-drill-//')"
    set -e
    if [[ "$found_version" != $version* ]]; then
        echo "Docker container version does not match expected version! (found '$found_version', expected '$version')"
        exit 1
    fi
    hr
    echo "found Apache Drill version $found_version"
    hr
    #run ./check_apache_drill_version.py -v -e "$version"
    hr
    run ./check_apache_drill_status.py -v
    hr
    echo "checking connection refused:"
    run_fail 2 ./check_apache_drill_status.py -v -P 804
    hr
    run $perl -T ./check_apache_drill_metrics.pl -v
    hr
    echo "checking connection refused:"
    run_fail 2 $perl -T ./check_apache_drill_metrics.pl -v -P 804
    hr
    echo "Completed $run_count Apache Drill tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    echo
}

startupwait 50

run_test_versions "Apache Drill"
