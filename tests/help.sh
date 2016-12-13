#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-05-25 01:38:24 +0100 (Mon, 25 May 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help improve or steer this or other code I publish
#
#  http://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir_nagios_plugins_help="$srcdir"
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

. ./tests/utils.sh

section "Testing --help for all programs"

test_help(){
    local prog="$1"
    optional_cmd=""
    if [[ $prog =~ .*\.pl$ ]]; then
        optional_cmd="$perl -T"
    fi
    echo "$optional_cmd $prog --help"
    set +e
    $optional_cmd $prog --help # >/dev/null
    status=$?
    set -e
    [[ "$prog" = *.py ]] && [ $status = 0 ] && { echo "allowing python program $prog to have exit code zero instead of 3"; return 0; }
    # quick hack for older programs
#    [ "$prog" = "check_dhcpd_leases.py" -o \
#      "$prog" = "check_linux_ram.py"    -o \
#      "$prog" = "check_logserver.py"    -o \
#      "$prog" = "check_syslog_mysql.py" -o \
#      "$prog" = "check_yum.py" ] && [ $status = 0 ] && { echo "allowing $prog to have zero exit code"; continue; }
    [ $status = 3 ] || { echo "status code for $prog --help was $status not expected 3"; exit 1; }
}

# Capturing and uploading logs when run in Travis CI as jobs to fail once they exceed the 4MB log length limit

log=/dev/stdout

if is_CI; then
    # running out of space on device on Travis CI
    #log=`mktemp /tmp/log.XXXXXX`
    log=/dev/null
fi

upload_logs(){
    return 0
    if is_CI; then
        echo "uploading logs:"
        curl -sT "$log" transfer.sh || :
        curl -sT "$log" chunk.io || :
    fi
}

trap upload_logs $TRAP_SIGNALS

for x in $(echo *.pl *.py *.rb */*.pl */*.py */*.rb 2>/dev/null); do
    isExcluded "$x" && continue
    echo "$x:"
    test_help "$x" 2>&1 >> "$log"
    hr
done

untrap

upload_logs

echo "All Perl / Python / Ruby programs found exited with expected code 3 for --help"

srcdir="$srcdir_nagios_plugins_help"
