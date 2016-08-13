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

set -eu
[ -n "${DEBUG:-}" ] && set -x
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

. ./tests/utils.sh

for x in $(echo *.pl *.py *.rb */*.pl */*.py */*.rb 2>/dev/null); do
    isExcluded "$x" && continue
    optional_cmd=""
    if [[ $x =~ .*\.pl$ ]]; then
        optional_cmd="$perl -T"
    fi
    echo $optional_cmd ./$x --help
    set +e
    $optional_cmd ./$x --help # >/dev/null
    status=$?
    set -e
    [[ "$x" = *.py ]] && [ $status = 0 ] && { echo "allowing python program $x to have exit code zero instead of 3"; continue; }
    # quick hack for older programs
#    [ "$x" = "check_dhcpd_leases.py" -o \
#      "$x" = "check_linux_ram.py"    -o \
#      "$x" = "check_logserver.py"    -o \
#      "$x" = "check_syslog_mysql.py" -o \
#      "$x" = "check_yum.py" ] && [ $status = 0 ] && { echo "allowing $x to have zero exit code"; continue; }
    [ $status = 3 ] || { echo "status code for $x --help was $status not expected 3"; exit 1; }
    echo "================================================================================"
done
echo "All Perl / Python / Ruby programs found exited with expected code 3 for --help"
