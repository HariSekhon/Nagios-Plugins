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

. "$srcdir/utils.sh"

is_travis && exit 0

section "A t t i v i o"

export ATTIVIO_AIE_PORT="${ATTIVIO_AIE_PORT:-17000}"
export ATTIVIO_AIE_PERFMON_PORT="${ATTIVIO_AIE_PERFMON_PORT:-16960}"

trap_debug_env attivio

if [ -n "${ATTIVIO_AIE_HOST:-}" ]; then
    if which nc &>/dev/null && ! echo | nc -w 1 "$ATTIVIO_AIE_HOST" "$ATTIVIO_AIE_PORT"; then
        echo "WARNING: Attivio AIE host $ATTIVIO_AIE_HOST:$ATTIVIO_AIE_PORT not up, skipping Attivio AIE checks"
    else
        echo "./check_attivio_aie_ingest_session_count.py -v"
        ./check_attivio_aie_ingest_session_count.py -v
        hr
        echo "./check_attivio_aie_license_expiry.py -v"
        ./check_attivio_aie_license_expiry.py -v
        hr
        echo "./check_attivio_aie_system_health.py -v"
        ./check_attivio_aie_system_health.py -v
        hr
        echo "./check_attivio_aie_version.py -v"
        ./check_attivio_aie_version.py -v
        hr
    fi
else
    echo "WARNING: \$ATTIVIO_AIE_HOST not set, skipping Attivio AIE checks"
fi

if [ -n "${ATTIVIO_AIE_PERFMON_HOST:-}" ]; then
    if which nc &>/dev/null && ! echo | nc -w 1 "$ATTIVIO_AIE_PERFMON_HOST" "$ATTIVIO_AIE_PERFMON_PORT"; then
        echo "WARNING: Attivio AIE PerfMon host $ATTIVIO_AIE_PERFMON_HOST:$ATTIVIO_AIE_PERFMON_PORT not up, skipping Attivio AIE PerfMon checks"
    else
        echo "./check_attivio_aie_metrics.py -H "$ATTIVIO_AIE_PERFMON_HOST" -P "$ATTIVIO_AIE_PERFMON_PORT" -l |"
        ./check_attivio_aie_metrics.py -H "$ATTIVIO_AIE_PERFMON_HOST" -P "$ATTIVIO_AIE_PERFMON_PORT" -l |
        tail -n +3 |
        while read metric; do
            echo "./check_attivio_aie_metrics.py -H "$ATTIVIO_AIE_PERFMON_HOST" -P "$ATTIVIO_AIE_PERFMON_PORT" -m "$metric" -v"
            ./check_attivio_aie_metrics.py -H "$ATTIVIO_AIE_PERFMON_HOST" -P "$ATTIVIO_AIE_PERFMON_PORT" -m "$metric" -v
            hr
        done
    fi
else
    echo "WARNING: \$ATTIVIO_AIE_PERFMON_HOST not set, skipping Attivio AIE PerfMon metric checks"
fi
echo
echo "All Attivio tests completed successfully"
untrap
echo
echo
