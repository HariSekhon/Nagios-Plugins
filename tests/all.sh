#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-11-05 23:29:15 +0000 (Thu, 05 Nov 2015)
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
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "
# ========================== #
# Running Nagios Plugins ALL
# ========================== #
"

cd "$srcdir/..";

. tests/utils.sh

. tests/excluded.sh

# would switch this to perl_syntax.sh from bash-tools but need to tie in exclusions first
#tests/syntax.sh

. bash-tools/all.sh

is_travis || time tests/help.sh
#time tests/help.sh

for script in $(find tests -name 'test*.sh'); do
    if is_CI; then
        [ $(($RANDOM % 3)) = 0 ] || continue
        time $script || break
    else
        time $script
    fi
done

echo "Done"
