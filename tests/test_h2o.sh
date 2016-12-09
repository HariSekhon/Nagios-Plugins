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

echo "
# ============================================================================ #
#                            0 x d a t a   H 2 O
# ============================================================================ #
"

# TODO: updates for H2O 3.x
export H2O_VERSIONS="${@:-${H2O_VERSIONS:-latest 2.6 2}}"

H2O_HOST="${DOCKER_HOST:-${H2O_HOST:-${HOST:-localhost}}}"
H2O_HOST="${H2O_HOST##*/}"
H2O_HOST="${H2O_HOST%%:*}"
export H2O_HOST
echo "using docker address '$H2O_HOST'"
export H2O_PORT="${H2O_PORT:-54321}"

export DOCKER_IMAGE="harisekhon/h2o"

export SERVICE="${0#*test_}"
export SERVICE="${SERVICE%.sh}"
export DOCKER_CONTAINER="nagios-plugins-$SERVICE-test"
export COMPOSE_PROJECT_NAME="$DOCKER_CONTAINER"
export COMPOSE_FILE="$srcdir/docker/$SERVICE-docker-compose.yml"

check_docker_available

startupwait 10

test_h2o(){
    local version="$1"
    hr
    echo "Setting up H2O $version test container"
    hr
    #launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $H2O_PORT
    VERSION="$version" docker-compose up -d
    h2o_port="`docker-compose port "$SERVICE" "$H2O_PORT" | sed 's/.*://'`"
    if [ -n "${NOTESTS:-}" ]; then
        return 0
    fi
    when_ports_available $startupwait $H2O_HOST $H2O_PORT
    hr
    $perl -T ./check_h2o_cluster.pl -P "$h2o_port"
    hr
    $perl -T ./check_h2o_jobs.pl -P "$h2o_port"
    hr
    $perl -T ./check_h2o_node_health.pl -P "$h2o_port"
    hr
    $perl -T ./check_h2o_node_stats.pl -P "$h2o_port"
    hr
    $perl -T ./check_h2o_nodes_last_contact.pl -P "$h2o_port"
    hr
    #delete_container
    docker-compose down
}

for version in $(ci_sample $H2O_VERSIONS); do
    test_h2o $version
done
