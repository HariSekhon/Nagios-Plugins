#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-12-08 11:44:27 +0000 (Thu, 08 Dec 2016)
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

section "A t t i v i o"

export ATTIVIO_AIE_PORT="${ATTIVIO_AIE_PORT:-17000}"
export ATTIVIO_AIE_PERFMON_PORT="${ATTIVIO_AIE_PERFMON_PORT:-16960}"

trap_debug_env attivio

echo "running connection refused tests first:"
echo
run_conn_refused ./check_attivio_aie_ingest_session_count.py -v

run_conn_refused ./check_attivio_aie_license_expiry.py -v

run_conn_refused ./check_attivio_aie_system_health.py -v

run_conn_refused ./check_attivio_aie_version.py -v

run_conn_refused ./check_attivio_aie_metrics.py -m "fake" -v

echo

if [ -z "${ATTIVIO_AIE_HOST:-}" ]; then
    echo "WARNING: \$ATTIVIO_AIE_HOST not set, skipping real Attivio AIE checks"
else
    if when_ports_available 5 "$ATTIVIO_AIE_HOST" "$ATTIVIO_AIE_PORT"; then
        echo "WARNING: Attivio AIE host $ATTIVIO_AIE_HOST:$ATTIVIO_AIE_PORT not up, skipping Attivio AIE checks"
    else
        run ./check_attivio_aie_ingest_session_count.py -v

        run ./check_attivio_aie_license_expiry.py -v

        run ./check_attivio_aie_system_health.py -v

        run ./check_attivio_aie_version.py -v

        run_fail 2 ./check_attivio_aie_version.py -v -e 'fail-version'
    fi
fi

if [ -z "${ATTIVIO_AIE_PERFMON_HOST:-}" ]; then
    echo "WARNING: \$ATTIVIO_AIE_PERFMON_HOST not set, skipping real Attivio AIE PerfMon metric checks"
else
    if when_ports_available "$ATTIVIO_AIE_PERFMON_HOST" "$ATTIVIO_AIE_PERFMON_PORT"; then
        echo "./check_attivio_aie_metrics.py -H $ATTIVIO_AIE_PERFMON_HOST -P $ATTIVIO_AIE_PERFMON_PORT -l |"
        ./check_attivio_aie_metrics.py -H "$ATTIVIO_AIE_PERFMON_HOST" -P "$ATTIVIO_AIE_PERFMON_PORT" -l |
        tail -n +3 |
        while read -r metric; do
            run ./check_attivio_aie_metrics.py -H "$ATTIVIO_AIE_PERFMON_HOST" -P "$ATTIVIO_AIE_PERFMON_PORT" -m "$metric" -v
        done
    else
        echo "WARNING: Attivio AIE PerfMon host $ATTIVIO_AIE_PERFMON_HOST:$ATTIVIO_AIE_PERFMON_PORT not up, skipping Attivio AIE PerfMon checks"
    fi
fi
echo
# defined and tracked in bash-tools/lib/utils.sh
# shellcheck disable=SC2154
echo "Completed $run_count Attivio tests"
echo
echo "All Attivio tests completed successfully"
untrap
echo
echo
