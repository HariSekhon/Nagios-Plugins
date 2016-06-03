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

H2O_HOST="${DOCKER_HOST:-${H2O_HOST:-${HOST:-localhost}}}"
H2O_HOST="${H2O_HOST##*/}"
H2O_HOST="${H2O_HOST%%:*}"
export H2O_HOST
echo "using docker address '$H2O_HOST'"
export H2O_PORT="${H2O_PORT:-54321}"

export DOCKER_IMAGE="harisekhon/h2o"
export DOCKER_CONTAINER="nagios-plugins-h2o-test"

export H2O_VERSIONS="${1:-2.6}"

startupwait=10

test_h2o(){
    local version="$1"
    hr
    echo "Setting up H2O $version test container"
    hr
    launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $H2O_PORT

    hr
    $perl -T $I_lib ./check_h2o_cluster.pl
    hr
    $perl -T $I_lib ./check_h2o_jobs.pl
    hr
    $perl -T $I_lib ./check_h2o_node_health.pl
    hr
    $perl -T $I_lib ./check_h2o_node_stats.pl
    hr
    $perl -T $I_lib ./check_h2o_nodes_last_contact.pl
    hr
    delete_container
}

for version in $H2O_VERSIONS; do
    test_h2o $version
done
