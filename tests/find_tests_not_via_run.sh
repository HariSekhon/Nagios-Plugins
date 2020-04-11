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

# shellcheck disable=SC2016
grep -Hn 'check_' tests/test_*.sh |
sed 's/#.*// ; s/[[:space:]]>[[:space:]].*//' |
# could put these all in one big alternation regex but separately is easier to maintain
grep -Ev -e '\.sh:[[:digit:]]+:[[:space:]]*$' \
         -e '\.sh:[[:digit:]]+:([[:space:]]*|.*=")run(_grep|_fail)?[[:space:]]' \
         -e '\.sh:[[:digit:]]+:[[:space:]]*docker_exec[[:space:]]' \
         -e '\.sh:[[:digit:]]+:[[:space:]]*check_docker_available' \
         -e '\.sh:[[:digit:]]+:[[:space:]]*check_exit_code[[:space:]]' \
         -e '[[:space:]]+(&&|\|\|)[[:space:]]+break' \
         -e '[[:space:]]\|([[:space:]]|"?$)' \
         -e 'for x in ' \
         -e 'echo "WARNING:' \
         -e '=`\$check_whois'
         # this fails to find tests which are using subshells to determine args like check_timezone.pl
         #-e '\$\('
