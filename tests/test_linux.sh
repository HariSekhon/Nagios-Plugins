#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-10-07 13:41:58 +0100 (Wed, 07 Oct 2015)
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

[ `uname -s` = "Linux" ] || exit 0

echo "
# ============================================================================ #
#                                   L i n u x
# ============================================================================ #
"

$perl -T $I_lib ./check_linux_timezone.pl -T UTC -Z /usr/share/zoneinfo/UTC -A UTC
hr
if [ -x /usr/bin/yum ]; then
    $perl -T $I_lib ./check_yum.pl
    $perl -T $I_lib ./check_yum.pl --all-updates || :
    hr
    ./check_yum.py
    ./check_yum.py --all-updates || :
    hr
fi

echo; echo
