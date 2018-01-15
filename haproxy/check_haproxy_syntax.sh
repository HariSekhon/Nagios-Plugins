#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-01-15 17:56:39 +0000 (Mon, 15 Jan 2018)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

haproxy_srcdir="$srcdir"

. "$srcdir/../bash-tools/utils.sh"

section "HAProxy Configs"

echo "Testing all HAProxy configs under $haproxy_srcdir for correctness:"
echo
echo "(requires HAProxy 1.7+ to be able to skip any unresolvable DNS entries)"
echo

trap "pkill -9 -P $$; exit 1" $TRAP_SIGNALS

test_haproxy_conf(){
    local cfg="$1"
    local str=$(printf "%-${maxwidth}s " "$cfg:")
    if haproxy -c -f 10-global.cfg -f 20-defaults.cfg -f 30-stats.cfg -f "$cfg" &>/dev/null; then
        echo "$str OK"
    else
        echo "$str FAILED"
        echo
        echo "Error:"
        echo
        untrap
        # kill remaining child procs
        pkill -9 -P $$ || :
        haproxy -c -f 10-global.cfg -f 21-defaults.cfg -f 30-stats.cfg -f "$cfg"
        exit 1
    fi
}

if which haproxy &>/dev/null; then
    cd "$haproxy_srcdir"
    echo
    maxwidth=0
    for cfg in [a-z]*.cfg; do
        if [ "${#cfg}" -gt $maxwidth ]; then
            maxwidth="${#cfg}"
        fi
    done
    let maxwidth+=1
    for cfg in [a-z]*.cfg; do
        # slow due to all the DNS lookup failures for alternative haproxy services DNS names so aggressively parallelizing
        test_haproxy_conf "$cfg" &
    done
    wait
fi
untrap
