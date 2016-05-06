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

export DOCKER_CONTAINER="nagios-plugins-h2o"

if ! is_docker_available; then
    echo 'WARNING: Docker not found, skipping h2o checks!!!'
    exit 0
fi

startupwait=10
is_travis && let startupwait+=20

hr
echo "Setting up H2O test container"
hr
# reuse container it's faster
#docker rm -f "$DOCKER_CONTAINER" &>/dev/null
#sleep 1
if ! is_docker_container_running "$DOCKER_CONTAINER"; then
    docker rm -f "$DOCKER_CONTAINER" &>/dev/null || :
    echo "Starting Docker H2O test container"
    # need tty for sudo which h2o-start.sh local uses while ssh'ing localhost
    docker run -d -t --name "$DOCKER_CONTAINER" -p $H2O_PORT:$H2O_PORT harisekhon/h2o
    echo "waiting $startupwait seconds for H2O to start up..."
    sleep $startupwait
else
    echo "Docker H2O test container already running"
fi

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
echo
if [ -z "${NODELETE:-}" ]; then
    echo -n "Deleting container "
    docker rm -f "$DOCKER_CONTAINER"
fi
echo; echo
