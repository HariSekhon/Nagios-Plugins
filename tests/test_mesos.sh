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
#                            A p a c h e   M e s o s
# ============================================================================ #
"

MESOS_HOST="${DOCKER_HOST:-${MESOS_HOST:-${HOST:-localhost}}}"
MESOS_HOST="${MESOS_HOST##*/}"
MESOS_HOST="${MESOS_HOST%%:*}"
export MESOS_HOST
echo "using docker address '$MESOS_HOST'"
export MESOS_MASTER_PORT="${MESOS_MASTER_PORT:-5050}"
export MESOS_WORKER_PORT="${MESOS_WORKER_PORT:-5051}"
export MESOS_MASTER="$MESOS_HOST:$MESOS_MASTER_PORT"

export DOCKER_CONTAINER="nagios-plugins-mesos"

if ! which docker &>/dev/null; then
    echo 'WARNING: Docker not found, skipping mesos checks!!!'
    exit 0
fi

startupwait=10
[ -n "${TRAVIS:-}" ] && let startupwait+=20

hr
echo "Setting up test Mesos container"
hr
# reuse container it's faster
#docker rm -f "$DOCKER_CONTAINER" &>/dev/null
#sleep 1
if ! docker ps | tee /dev/stderr | grep -q "[[:space:]]$DOCKER_CONTAINER$"; then
    docker rm -f "$DOCKER_CONTAINER" &>/dev/null || :
    echo "Starting Docker Mesos test container"
    # need tty for sudo which mesos-start.sh local uses while ssh'ing localhost
    docker run -d -t --name "$DOCKER_CONTAINER" -p $MESOS_MASTER_PORT:$MESOS_MASTER_PORT -p $MESOS_WORKER_PORT:$MESOS_WORKER_PORT harisekhon/mesos
    echo "waiting $startupwait seconds for Mesos Master + Worker to become responsive..."
    sleep $startupwait
else
    echo "Docker Mesos test container already running"
fi

hr
$perl -T $I_lib ./check_mesos_activated_slaves.pl -v
hr
#$perl -T $I_lib ./check_mesos_chronos_jobs.pl -v
hr
$perl -T $I_lib ./check_mesos_deactivated_slaves.pl -v
hr
$perl -T $I_lib ./check_mesos_master_health.pl -v
hr
$perl -T $I_lib ./check_mesos_master_state.pl -v
hr
$perl -T $I_lib ./check_mesos_metrics.pl -P 5050 -v
hr
$perl -T $I_lib ./check_mesos_metrics.pl -P 5051 -v
hr
$perl -T $I_lib ./check_mesos_master_metrics.pl -v
hr
slave="$(./check_mesos_slave.py -l | awk '/=/{print $1; exit}')"
./check_mesos_slave.py -v -s "$slave"
hr
$perl -T $I_lib ./check_mesos_slave_metrics.pl -v
hr
# Not implemented yet
#$perl -T $I_lib ./check_mesos_registered_framework.py -v
hr
# Not implemented yet
#$perl -T $I_lib ./check_mesos_slave_container_statistics.pl -v
hr
$perl -T $I_lib ./check_mesos_slave_state.pl -v
hr
echo
echo -n "Deleting container "
docker rm -f "$DOCKER_CONTAINER"
echo; echo
