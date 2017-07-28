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
export MESOS_VERSIONS="${@:-${MESOS_VERSIONS:-${VERSIONS:-latest 0.23 0.24}}}"

MESOS_HOST="${DOCKER_HOST:-${MESOS_HOST:-${HOST:-localhost}}}"
MESOS_HOST="${MESOS_HOST##*/}"
MESOS_HOST="${MESOS_HOST%%:*}"
export MESOS_HOST

export MESOS_MASTER_PORT="${MESOS_MASTER_PORT:-5050}"
export MESOS_WORKER_PORT="${MESOS_WORKER_PORT:-5051}"
export MESOS_MASTER="$MESOS_HOST:$MESOS_MASTER_PORT"

startupwait 20

check_docker_available

test_mesos_version(){
    local version="${1:-latest}"
    hr
    echo "Setting up Mesos $version test container"
    hr
    #launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $MESOS_MASTER_PORT $MESOS_WORKER_PORT
    VERSION="$version" docker-compose up -d
    mesos_master_port="`docker-compose port "$DOCKER_SERVICE" "$MESOS_MASTER_PORT" | sed 's/.*://'`"
    mesos_worker_port="`docker-compose port "$DOCKER_SERVICE" "$MESOS_WORKER_PORT" | sed 's/.*://'`"
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    when_ports_available "$startupwait" "$MESOS_HOST" "$mesos_master_port" "$mesos_worker_port"
    hr
    $perl -T ./check_mesos_activated_slaves.pl -P "$mesos_master_port" -v
    hr
    #$perl -T ./check_mesos_chronos_jobs.pl -P "$cronos_port" -v
    hr
    $perl -T ./check_mesos_deactivated_slaves.pl -P "$mesos_master_port" -v
    hr
    $perl -T ./check_mesos_master_health.pl -P "$mesos_master_port" -v
    hr
    $perl -T ./check_mesos_master_state.pl -P "$mesos_master_port" -v
    hr
    $perl -T ./check_mesos_metrics.pl -P "$mesos_master_port" -v
    hr
    $perl -T ./check_mesos_metrics.pl -P "$mesos_worker_port" -v
    hr
    $perl -T ./check_mesos_master_metrics.pl -P "$mesos_master_port" -v
    hr
    set +e
    slave="$(./check_mesos_slave.py -P "$mesos_master_port" -l | awk '/=/{print $1; exit}')"
    set -e
    echo "checking for mesos slave '$slave'"
    ./check_mesos_slave.py -P "$mesos_master_port" -v -s "$slave"
    hr
    $perl -T ./check_mesos_slave_metrics.pl -P "$mesos_worker_port" -v
    hr
    # Not implemented yet
    #$perl -T ./check_mesos_registered_framework.py -v
    hr
    # Not implemented yet
    #$perl -T ./check_mesos_slave_container_statistics.pl -v
    hr
    $perl -T ./check_mesos_slave_state.pl -P "$mesos_worker_port" -v
    hr
    #delete_container
    docker-compose down
}

for version in $(ci_sample $MESOS_VERSIONS); do
    test_mesos_version "$version"
done
