#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-05-06 12:12:15 +0100 (Fri, 06 May 2016)
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
#                                    M a p R
# ============================================================================ #
"

if [ -z "$MAPR_HOST" ]; then
    echo "WARNING: MapR host not detected, skipping MapR checks"
    exit 0
fi

if ! which nc &>/dev/null && nc -iv "$MAPR_HOST" 8083; then
    echo "WARNING: MapR host 8083 not up, skipping MapR checks"
    exit 0
fi

hr
# TODO: add checks
#$perl -T $I_lib 
#hr
#$perl -T $I_lib 
hr
echo; echo
