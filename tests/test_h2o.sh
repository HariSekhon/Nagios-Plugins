#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-02-10 23:18:47 +0000 (Wed, 10 Feb 2016)
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

section "0 x d a t a   H 2 O"

# TODO: updates for H2O 3.x required
export H2O_VERSIONS="${@:-${H2O_VERSIONS:-2.6 2}}"

H2O_HOST="${DOCKER_HOST:-${H2O_HOST:-${HOST:-localhost}}}"
H2O_HOST="${H2O_HOST##*/}"
H2O_HOST="${H2O_HOST%%:*}"
export H2O_HOST
echo "using docker address '$H2O_HOST'"
export H2O_PORT_DEFAULT="${H2O_PORT:-54321}"

check_docker_available

trap_debug_env h2o

startupwait 10

test_h2o(){
    local version="$1"
    hr
    section2 "Setting up H2O $version test container"
    hr
    #launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $H2O_PORT
    VERSION="$version" docker-compose up -d
    export H2O_PORT="`docker-compose port "$DOCKER_SERVICE" "$H2O_PORT_DEFAULT" | sed 's/.*://'`"
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    when_ports_available $startupwait $H2O_HOST $H2O_PORT
    hr
    when_url_content "$startupwait" "http://$H2O_HOST:$H2O_PORT/" "0xdata"
    hr
    echo "$perl -T ./check_h2o_cluster.pl"
    $perl -T ./check_h2o_cluster.pl
    hr
    echo "$perl -T ./check_h2o_jobs.pl"
    $perl -T ./check_h2o_jobs.pl
    hr
    echo "$perl -T ./check_h2o_node_health.pl"
    $perl -T ./check_h2o_node_health.pl
    hr
    echo "$perl -T ./check_h2o_node_stats.pl"
    $perl -T ./check_h2o_node_stats.pl
    hr
    echo "$perl -T ./check_h2o_nodes_last_contact.pl"
    $perl -T ./check_h2o_nodes_last_contact.pl
    hr
    #delete_container
    docker-compose down
}

run_test_versions H2O
