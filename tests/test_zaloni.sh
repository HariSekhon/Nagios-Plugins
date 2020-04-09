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

is_travis && exit 0

section "Z a l o n i"

export ZALONI_BEDROCK_PORT="${ZALONI_BEDROCK_PORT:-8080}"

if [ -z "${ZALONI_BEDROCK_PASSWORD:-}" ]; then
    echo "WARNING: ZALONI_BEDROCK_PASSWORD not defined, defaulting to 'test'"
    export ZALONI_BEDROCK_PASSWORD=test
    echo
fi

trap_debug_env Zaloni

echo "running conection refused checks first:"
echo
run_conn_refused ./check_zaloni_bedrock_ingestion.py -l

run_conn_refused ./check_zaloni_bedrock_workflow.py --all -v --min-runtime 0


if [ -z "${ZALONI_BEDROCK_HOST:-}" ]; then
    echo "WARNING: \$ZALONI_BEDROCK_HOST not set, skipping real Zaloni checks"
else
    if type -P nc &>/dev/null && ! echo | nc -w 1 "$ZALONI_BEDROCK_HOST" "$ZALONI_BEDROCK_PORT"; then
        echo "WARNING: Zaloni Bedrock host $ZALONI_BEDROCK_HOST:$ZALONI_BEDROCK_PORT not up, skipping Zaloni checks"
    else
        run_fail 3 ./check_zaloni_bedrock_ingestion.py -l

        run_fail "0 2" ./check_zaloni_bedrock_ingestion.py -v -r 600 -a 1440

        set +o pipefail
        ./check_zaloni_bedrock_workflow.py -l |
        tail -n +6 |
        sed 's/.*[[:space:]]\{4\}\([[:digit:]]\+\)[[:space:]]\{4\}.*/\1/' |
        while read -r workflow_id; do
            # TODO: fix - won't increment due to subshell
            run_fail "0 2" ./check_zaloni_bedrock_workflow.py -I "$workflow_id" -v --min-runtime 0
        done

        ./check_zaloni_bedrock_workflow.py -l |
        tail -n +6 |
        sed 's/[[:space:]]\{4\}[[:digit:]]\+[[:space:]]\{4\}.*//' |
        while read -r workflow_name; do
            # TODO: fix - won't increment due to subshell
            run_fail "0 2" ./check_zaloni_bedrock_workflow.py -N "$workflow_name" -v --min-runtime 0
        done

        run_fail "0 2" ./check_zaloni_bedrock_workflow.py --all -v --min-runtime 0

    fi
fi
echo
# defined and tracked in bash-tools/lib/utils.sh
# shellcheck disable=SC2154
echo "Completed $run_count Zaloni tests"
echo
echo "All Zaloni tests passed successfully"
untrap
echo
echo
