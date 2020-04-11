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
srcdir_nagios_plugins_syntax="${srcdir:-}"
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

# shellcheck disable=SC1090
. "$srcdir/utils.sh"

section "Perl Syntax Checks"

perl_syntax_start_time="$(start_timer)"

for x in *.pl */*.pl; do
    # this call is expensive, skip it when in CI as using fresh git checkouts
    if ! is_CI; then
        isExcluded "$x" && continue
    fi
    #printf "%-50s" "$x:"
    #$perl -TWc ./$x
    # defined in lib/perl.sh (imported by utils.sh)
    # shellcheck disable=SC2154
    "$perl" -Tc "./$x"
done

srcdir="$srcdir_nagios_plugins_syntax"

time_taken "$perl_syntax_start_time" "Help Checks Completed in $perl_syntax_time_taken secs"
section2 "All Perl programs passed syntax check"
echo
