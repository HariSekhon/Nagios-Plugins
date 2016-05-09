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

TACHYON_HOST="${DOCKER_HOST:-${TACHYON_HOST:-${HOST:-localhost}}}"
TACHYON_HOST="${TACHYON_HOST##*/}"
TACHYON_HOST="${TACHYON_HOST%%:*}"
export TACHYON_HOST

export TACHYON_MASTER_PORT="${TACHYON_MASTER_PORT:-19999}"
export TACHYON_WORKER_PORT="${TACHYON_WORKER_PORT:-30000}"

export DOCKER_IMAGE="harisekhon/tachyon"
export DOCKER_CONTAINER="nagios-plugins-tachyon-test"

startupwait=10

hr
echo "Setting up Tachyon test container"
hr
launch_container "$DOCKER_IMAGE" "$DOCKER_CONTAINER" $TACHYON_MASTER_PORT $TACHYON_WORKER_PORT

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
