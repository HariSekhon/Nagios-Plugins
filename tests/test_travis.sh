#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-08-22 16:17:31 +0100 (Mon, 22 Aug 2016)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help improve or steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

. ./tests/utils.sh

section "T r a v i s   C I"

# this repo should always be working
./check_travis_ci_last_build.py -r HariSekhon/bash-tools
hr
set +e
./check_travis_ci_last_build.py -r HariSekhon/nagios-plugins
check_exit_code 0 2
hr
echo "check warning threshold to induce failure as builds should always take longer than 10 secs"
./check_travis_ci_last_build.py -r HariSekhon/nagios-plugins -v -w 10
check_exit_code 1 2
hr
echo "check critical threshold to induce failure as builds should always take longer than 10 secs"
./check_travis_ci_last_build.py -r HariSekhon/nagios-plugins -v -c 10
check_exit_code 2
hr
./check_travis_ci_last_build.py -r HariSekhon/tools
check_exit_code 0 2
hr
./check_travis_ci_last_build.py -r HariSekhon/spotify-tools
check_exit_code 0 2
hr
./check_travis_ci_last_build.py -r HariSekhon/pytools
check_exit_code 0 2
hr
./check_travis_ci_last_build.py -r HariSekhon/pylib
check_exit_code 0 2
hr
./check_travis_ci_last_build.py -r HariSekhon/lib
check_exit_code 0 2
hr
./check_travis_ci_last_build.py -r HariSekhon/lib-java
check_exit_code 0 2
hr
./check_travis_ci_last_build.py -r HariSekhon/nagios-plugin-kafka
check_exit_code 0 2
hr
./check_travis_ci_last_build.py -r HariSekhon/spark-apps
check_exit_code 0 2
hr
echo "checking no builds returned"
./check_travis_ci_last_build.py -r harisekhon/nagios-plugins -v
check_exit_code 3
hr
echo "checking wrong repo name/format"
./check_travis_ci_last_build.py -r test -v
check_exit_code 3
hr
./check_travis_ci_last_build.py -r harisekhon/ -v
check_exit_code 3
hr
./check_travis_ci_last_build.py -r /nagios-plugins -v
check_exit_code 3
hr
echo "checking nonexistent repo"
./check_travis_ci_last_build.py -r nonexistent/repo -v
check_exit_code 3
hr
echo
echo "All Travis CI tests passed successfully"
echo
echo
