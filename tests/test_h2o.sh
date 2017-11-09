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
export H2O_PORT_DEFAULT=54321

check_docker_available

trap_debug_env h2o

startupwait 20

test_h2o(){
    local version="$1"
    section2 "Setting up H2O $version test container"
    if is_CI || [ -n "${DOCKER_PULL:-}" ]; then
        VERSION="$version" docker-compose pull $docker_compose_quiet
    fi
    VERSION="$version" docker-compose up -d
    hr
    echo "getting H2O dynamic port mapping:"
    docker_compose_port "H2O"
    hr
    when_ports_available "$H2O_HOST" "$H2O_PORT"
    hr
    # 2.x h2o, 3.x H2O Flow
    when_url_content "http://$H2O_HOST:$H2O_PORT/" "h2o|H2O"
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    docker_compose_version_test h2o "$version"
    hr

    run $perl -T ./check_h2o_cluster.pl

    run $perl -T ./check_h2o_jobs.pl

    run $perl -T ./check_h2o_node_health.pl

    run $perl -T ./check_h2o_node_stats.pl

    run $perl -T ./check_h2o_nodes_last_contact.pl

    run_conn_refused $perl -T ./check_h2o_cluster.pl

    run_conn_refused $perl -T ./check_h2o_jobs.pl

    run_conn_refused $perl -T ./check_h2o_node_health.pl

    run_conn_refused $perl -T ./check_h2o_node_stats.pl

    run_conn_refused $perl -T ./check_h2o_nodes_last_contact.pl

    echo "Completed $run_count H2O tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
}

run_test_versions H2O
