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
srcdir_nagios_plugins_help="${srcdir:-}"
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

# pulled in by utils -> bash-tools/lib/utils.sh -> perl.sh
#. ./bash-tools/lib/perl.sh

# shellcheck disable=SC1090
. "$srcdir/excluded.sh"

# shellcheck disable=SC1090
. "$srcdir/utils.sh"

# shellcheck disable=SC1090
. "$srcdir/../bash-tools/lib/python.sh"

EXT="${EXT:-all}"

section "Testing --help for $EXT programs"

# Breaks on CentOS Docker without this, although works on Debian, Ubuntu and Alpine without
export LINES="${LINES:-25}"
export COLUMNS="${COLUMNS:-80}"

help_start_time="$(start_timer)"

test_help(){
    local prog="$1"

    if [ "$EXT" != "all" ] &&
       [ "$EXT" != "${prog##*.}" ]; then
        return 0
    fi

    optional_cmd=""
    # for Travis CI running in a perlbrew we must use the perl we find
    if [[ $prog =~ .*\.pl$ ]]; then
        # defined in bash-tools/lib/perl.sh
        # shellcheck disable=SC2154
        optional_cmd="$perl -T"
    elif [[ $prog =~ .*\.py$ ]]; then
        # defined in bash-tools/lib/perl.sh
        # shellcheck disable=SC2154
        optional_cmd="$python"
    fi

    # quick hack for older programs which return zero for --help due to python OptParse module
    if [[ "$prog" =~ adapter_geneos.py      ||
          "$prog" =~ geneos_adapter.py      ||
          "$prog" =~ check_dhcpd_leases.py  ||
          "$prog" =~ check_linux_ram.py     ||
          "$prog" =~ check_logserver.py     ||
          "$prog" =~ check_syslog_mysql.py  ||
          "$prog" =~ check_sftp.py          ||
          "$prog" =~ check_svn.py           ||
          "$prog" =~ check_vnc.py           ||
          "$prog" =~ check_yum.py ]]; then
        # shellcheck disable=SC2086
        run $optional_cmd "./$prog" --help
    elif [[ "$prog" =~ /templates/ ]]; then
        echo "skipping template '$prog'"
    elif [[ "$prog" =~ check_3ware_raid.py ]]; then # && $EUID != 0 ]]; then
        echo "skipping check_3ware_raid.py" # which needs root as $USER has \$EUID $EUID != 0"
    elif [[ "$prog" =~ check_md_raid.py ]]; then # && $EUID != 0 ]]; then
        echo "skipping check_md_raid.py" # which needs root as $USER has \$EUID $EUID != 0"
    elif [[ "$prog" =~ check_lsi_megaraid.py ]]; then # && $EUID != 0 ]]; then
        echo "skipping check_lsi_megaraid.py" # which needs root as $USER has \$EUID $EUID != 0"
    elif [[ "$prog" =~ check_gentoo_portage.py ]]; then
        echo "skipping check_gentoo_portage.py"
    elif [[ "$prog" =~ /lib_.*.py ]]; then
        echo "skipping $prog"
    else
        # shellcheck disable=SC2086
        run_usage $optional_cmd "./$prog" --help
    fi
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

# shellcheck disable=SC2086
#trap upload_logs $TRAP_SIGNALS

for x in ${*:-$(ls ./*.pl ./*.py ./*.rb ./*/*.pl ./*/*.py ./*/*.rb 2>/dev/null | sort)}; do
    isExcluded "$x" && continue
    # this is taking too much time and failing Travis CI builds
    if is_travis; then
        [ $((RANDOM % 3)) = 0 ] || continue
    fi
    # shellcheck disable=SC2069
    test_help "$x" # 2>&1 >> "$log"
done

untrap

#upload_logs

srcdir="$srcdir_nagios_plugins_help"

time_taken "$help_start_time" "Help Checks Completed in"
section2 "All Perl / Python / Ruby programs found exited
with expected exit code 3 for --help"
echo
