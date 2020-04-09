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

# shellcheck disable=SC1090
. "$srcdir/utils.sh"

section "A t l a s"

export SANDBOX_CLUSTER="Sandbox"
#export ATLAS_HOST="${ATLAS_HOST:-localhost}"
export ATLAS_PORT="${ATLAS_PORT:-21000}"
export ATLAS_USER="${ATLAS_USER:-holger_gov}"
export ATLAS_PASSWORD="${ATLAS_PASSWORD:-holger_gov}"

# TODO: switch to dockerized test

trap_debug_env atlas

echo "checking connection refused tests first:"
echo
run_conn_refused ./check_atlas_version.py

run_conn_refused ./check_atlas_version.py -e '0\.'

run_conn_refused ./check_atlas_status.py -A

run_conn_refused ./check_atlas_entity.py -l

run_conn_refused ./check_atlas_entity.py -E Sales -T DB

run_conn_refused ./check_atlas_entity.py -I "1"

echo

if [ -z "${ATLAS_HOST:-}" ]; then
    echo "WARNING: \$ATLAS_HOST not set, skipping real Atlas checks"
else
    if ! when_ports_available 5 "$ATLAS_HOST" "$ATLAS_PORT"; then
        echo "WARNING: Atlas host $ATLAS_HOST:$ATLAS_PORT not up, skipping Atlas checks"
        echo
        echo
        untrap
        exit 0
    fi
    hr
    if ! when_url_content 5 "$ATLAS_HOST:$ATLAS_PORT" atlas; then
        echo "WARNING: Atlas host $ATLAS_HOST:$ATLAS_PORT content not found, skipping Atlas checks"
        echo
        echo
        untrap
        exit 0
    fi
    hr
    # Sandbox often has some broken stuff, we're testing the code works, not the cluster
    #[ "$ATLAS_CLUSTER" = "$SANDBOX_CLUSTER" ] && set +e
    #echo "testing Atlas server $ATLAS_HOST"
    hr
    run ./check_atlas_version.py

    run ./check_atlas_version.py -e '0\.'

    run_fail 2 ./check_atlas_version.py -e 'fail-version'

    run ./check_atlas_status.py -A

    run_fail 3 ./check_atlas_entity.py -l

    run ./check_atlas_entity.py -E Sales -T DB

    set +o pipefail
    id="$(./check_atlas_entity.py -l | tail -n 1 | awk '{print $1}')"
    set -o pipefail
    echo "got Atlas ID = $id"
    hr
    run ./check_atlas_entity.py -I "$id"
fi
echo
# defined and tracked in bash-tools/lib/utils.sh
# shellcheck disable=SC2154
echo "Completed $run_count Apache Atlas tests"
echo
echo "All Apache Atlas tests completed successfully"
untrap
echo
echo
