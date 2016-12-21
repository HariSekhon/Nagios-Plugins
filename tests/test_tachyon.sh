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
srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$srcdir/.."

. "$srcdir/utils.sh"

echo "
# ============================================================================ #
#                                 T a c h y o n
# ============================================================================ #
"

# Tachyon 0.7 doesn't always start up properly, but has passed all the plugin tests
#export TACHYON_VERSIONS="${@:-${TACHYON_VERSIONS:-latest 0.7 0.8}}"
export TACHYON_VERSIONS="${@:-${TACHYON_VERSIONS:-latest 0.8}}"

TACHYON_HOST="${DOCKER_HOST:-${TACHYON_HOST:-${HOST:-localhost}}}"
TACHYON_HOST="${TACHYON_HOST##*/}"
TACHYON_HOST="${TACHYON_HOST%%:*}"
export TACHYON_HOST

export TACHYON_MASTER_PORT="${TACHYON_MASTER_PORT:-19999}"
export TACHYON_WORKER_PORT="${TACHYON_WORKER_PORT:-30000}"

startupwait 15

check_docker_available

test_tachyon(){
    local version="$1"
    hr
    echo "Setting up Tachyon $version test container"
    hr
    #launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $TACHYON_MASTER_PORT $TACHYON_WORKER_PORT
    VERSION="$version" docker-compose up -d
    tachyon_master_port="`docker-compose port "$DOCKER_SERVICE" "$TACHYON_MASTER_PORT" | sed 's/.*://'`"
    tachyon_worker_port="`docker-compose port "$DOCKER_SERVICE" "$TACHYON_WORKER_PORT" | sed 's/.*://'`"
    local TACHYON_MASTER_PORT="$tachyon_master_port"
    local TACHYON_WORKER_PORT="$tachyon_worker_port"
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    when_ports_available "$startupwait" "$TACHYON_HOST" "$TACHYON_MASTER_PORT" "$TACHYON_WORKER_PORT"
    if [ "$version" = "latest" ]; then
        local version=".*"
    fi
    hr
    echo "retrying for $startupwait secs to give Tachyon time to initialize"
    for x in `seq $startupwait`; do
        ./check_tachyon_master_version.py -v -e "$version" && break
        sleep 1
    done
    ./check_tachyon_master_version.py -v -e "$version"
    hr
    ./check_tachyon_worker_version.py -v -e "$version"
    hr
    ./check_tachyon_master.py -v
    hr
    #docker exec -ti "$DOCKER_CONTAINER" ps -ef
    ./check_tachyon_worker.py -v
    hr
    ./check_tachyon_running_workers.py -v
    hr
    ./check_tachyon_dead_workers.py -v
    hr
    #delete_container
    docker-compose down
    echo
}

for version in $(ci_sample $TACHYON_VERSIONS); do
    test_tachyon $version
done
