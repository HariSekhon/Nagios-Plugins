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

total=$(grep -EHn \
      -e '^[[:space:]]*run(_grep|_fail)?[[:space:]]' \
      -e '^[[:space:]]*run\+\+[[:space:]]*$' \
      -e '^[[:space:]]*docker_exec[[:space:]]' \
      "${@:-tests/test_*.sh}" |
      grep -Ev 'run[[:space:]]+docker(-compose)?[[:space:]]+exec' |
      tee /dev/stderr |
      wc -l)

echo
echo "Total Tests: $total"
echo
