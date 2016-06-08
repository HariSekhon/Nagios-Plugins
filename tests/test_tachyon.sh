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
#                               T a c h y o n
# ============================================================================ #
"

# Tachyon 0.7 doesn't always start up properly, but has passed all the plugin tests
#export TACHYON_VERSIONS="${@:-latest 0.7 0.8}"
export TACHYON_VERSIONS="${@:-latest 0.8}"

TACHYON_HOST="${DOCKER_HOST:-${TACHYON_HOST:-${HOST:-localhost}}}"
TACHYON_HOST="${TACHYON_HOST##*/}"
TACHYON_HOST="${TACHYON_HOST%%:*}"
export TACHYON_HOST

export TACHYON_MASTER_PORT="${TACHYON_MASTER_PORT:-19999}"
export TACHYON_WORKER_PORT="${TACHYON_WORKER_PORT:-30000}"

export DOCKER_IMAGE="harisekhon/tachyon"
export DOCKER_CONTAINER="nagios-plugins-tachyon-test"

startupwait=10

test_tachyon(){
    local version="$1"
    travis_sample || continue
    hr
    echo "Setting up Tachyon $version test container"
    hr
    launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $TACHYON_MASTER_PORT $TACHYON_WORKER_PORT

    if [ "$version" = "latest" ]; then
        local version=".*"
    fi
    hr
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
    delete_container
    echo
}

for version in $TACHYON_VERSIONS; do
    test_tachyon $version
done
