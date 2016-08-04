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

# TODO: update plugins for > 0.24
export MESOS_VERSIONS="${@:-${MESOS_VERSIONS:-latest 0.23 0.24}}"

MESOS_HOST="${DOCKER_HOST:-${MESOS_HOST:-${HOST:-localhost}}}"
MESOS_HOST="${MESOS_HOST##*/}"
MESOS_HOST="${MESOS_HOST%%:*}"
export MESOS_HOST

export MESOS_MASTER_PORT="${MESOS_MASTER_PORT:-5050}"
export MESOS_WORKER_PORT="${MESOS_WORKER_PORT:-5051}"
export MESOS_MASTER="$MESOS_HOST:$MESOS_MASTER_PORT"

export DOCKER_IMAGE="harisekhon/mesos"
export DOCKER_CONTAINER="nagios-plugins-mesos-test"

startupwait=20

if ! is_docker_available; then
    echo 'WARNING: Docker not found, skipping Mesos checks!!!'
    exit 0
fi

test_mesos_version(){
    local version="${1:-latest}"
    hr
    echo "Setting up Mesos $version test container"
    hr
    launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $MESOS_MASTER_PORT $MESOS_WORKER_PORT
    if [ -n "${NOTESTS:-}" ]; then
        return 0
    fi
    hr
    $perl -T ./check_mesos_activated_slaves.pl -v
    hr
    #$perl -T ./check_mesos_chronos_jobs.pl -v
    hr
    $perl -T ./check_mesos_deactivated_slaves.pl -v
    hr
    $perl -T ./check_mesos_master_health.pl -v
    hr
    $perl -T ./check_mesos_master_state.pl -v
    hr
    $perl -T ./check_mesos_metrics.pl -P 5050 -v
    hr
    $perl -T ./check_mesos_metrics.pl -P 5051 -v
    hr
    $perl -T ./check_mesos_master_metrics.pl -v
    hr
    set +e
    slave="$(./check_mesos_slave.py -l | awk '/=/{print $1; exit}')"
    set -e
    echo "checking for mesos slave '$slave'"
    ./check_mesos_slave.py -v -s "$slave"
    hr
    $perl -T ./check_mesos_slave_metrics.pl -v
    hr
    # Not implemented yet
    #$perl -T ./check_mesos_registered_framework.py -v
    hr
    # Not implemented yet
    #$perl -T ./check_mesos_slave_container_statistics.pl -v
    hr
    $perl -T ./check_mesos_slave_state.pl -v
    hr
    delete_container
}

for version in $(ci_sample $MESOS_VERSIONS); do
    test_mesos_version "$version"
done
