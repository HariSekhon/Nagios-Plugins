#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-06-29 15:18:14 +0200 (Thu, 29 Jun 2017)
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

is_travis && exit 0

section "A t l a s"

export SANDBOX_CLUSTER="Sandbox"
export ATLAS_HOST="${ATLAS_HOST:-localhost}"
export ATLAS_PORT="${ATLAS_PORT:-21000}"
export ATLAS_USER="${ATLAS_USER:-holger_gov}"
export ATLAS_PASSWORD="${ATLAS_PASSWORD:-holger_gov}"

# TODO: switch to dockerized test

if [ -z "${ATLAS_HOST:-}" ]; then
    echo "WARNING: \$ATLAS_HOST not set, skipping Atlas checks"
    exit 0
fi

trap_debug_env atlas

if ! which nc &>/dev/null; then
    # Don't run in docker containers
    echo "nc command not found, cannot check Atlas availability, skipping checks"
    exit 0
fi
if ! echo | nc -G 1 "$ATLAS_HOST" $ATLAS_PORT; then
    echo "WARNING: Atlas host $ATLAS_HOST:$ATLAS_PORT not up, skipping Atlas checks"
    exit 0
fi

#if which curl &>/dev/null && ! curl -sL "$ATLAS_HOST:$ATLAS_PORT" | grep -qi atlas; then
#    echo "WARNING: Atlas host $ATLAS_HOST:$ATLAS_PORT did not contain atlas in html, may be some other service bound to the port, skipping..."
#    exit 0
#fi

# Sandbox often has some broken stuff, we're testing the code works, not the cluster
#[ "$ATLAS_CLUSTER" = "$SANDBOX_CLUSTER" ] && set +e
#echo "testing Atlas server $ATLAS_HOST"
hr
./check_atlas_version.py
hr
./check_atlas_version.py -e '0\.'
hr
./check_atlas_status.py -A
hr
set +e
./check_atlas_entity.py -l
check_exit_code 3
set -e
hr
./check_atlas_entity.py -E Sales -T DB
hr
set +o pipefail
id="$(./check_atlas_entity.py -l | tail -n 1 | awk '{print $1}')"
set -o pipefail
./check_atlas_entity.py -I "$id"
hr
echo
echo "All Atlas tests completed successfully"
untrap
echo
echo
