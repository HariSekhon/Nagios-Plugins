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

echo "
# ============================================================================ #
#                                  Z a l o n i
# ============================================================================ #
"

export ZALONI_BEDROCK_PORT="${ZALONI_BEDROCK_PORT:-8080}"

if [ -n "${ZALONI_BEDROCK_HOST:-}" ]; then
    if which nc &>/dev/null && ! echo | nc -w 1 "$ZALONI_BEDROCK_HOST" "$ZALONI_BEDROCK_PORT"; then
        echo "WARNING: Zaloni Bedrock host $ZALONI_BEDROCK_HOST:$ZALONI_BEDROCK_PORT not up, skipping Zaloni checks"
    else
        set +e
        ./check_zaloni_bedrock_ingestion.py -l
        check_exit_code 3
        set -e
        hr
        ./check_zaloni_bedrock_ingestion.py -v -r 600 -a 1440
        hr

        ./check_zaloni_bedrock_workflow.py -l |
        tail -n +6 |
        sed 's/.*[[:space:]]\{4\}\([[:digit:]]\+\)[[:space:]]\{4\}.*/\1/' |
        while read workflow_id; do
            ./check_zaloni_bedrock_workflow.py -I "$workflow_id" -v
            hr
        done

        ./check_zaloni_bedrock_workflow.py -l |
        tail -n +6 |
        sed 's/[[:space:]]\{4\}[[:digit:]]\+[[:space:]]\{4\}.*//' |
        while read workflow_name; do
            ./check_zaloni_bedrock_workflow.py -N "$workflow_name" -v
            hr
        done
    fi
else
    echo "WARNING: \$ZALONI_BEDROCK_HOST not set, skipping Zaloni checks"
fi

echo
echo
