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
srcdir_nagios_plugins_all="${srcdir:-}"
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

. tests/utils.sh
. bash-tools/docker.sh

section "Running Nagios Plugins ALL"

declare_if_inside_docker

nagios_plugins_start_time="$(start_timer)"

. tests/excluded.sh

. bash-tools/all.sh

#is_travis ||
time tests/help.sh

# try to minimize time by skipping this as Travis CI is killing the build during testing after 50 mins
#is_travis ||
tests/test_docker.sh

tests_run=""
failed_tests=""

for script in $(find tests -name 'test*.sh'); do
    if [ -n "${NOTESTS:-}" -a "$script" = "run_tests.sh" ]; then
        echo "NOTESTS env var specified, skipping dockerized tests"
        continue
    fi
    if is_CI; then
        [ $(($RANDOM % 3)) = 0 ] || continue
        tests_run="$tests_run
$script"
        declare_if_inside_docker
        time $script ||
        failed_tests="$failed_tests
$script"
    else
        declare_if_inside_docker
        time $script
    fi
done

if is_CI; then
    echo
    echo "Tests Run:
$tests_run"
fi

if [ -n "$failed_tests" ]; then
    echo
    echo "WARNING: the following tests failed:
$failed_tests"
fi

srcdir="$srcdir_nagios_plugins_all"

time_taken "$nagios_plugins_start_time" "Nagios Plugins All Tested Completed in"
section "Nagios Plugins Tests Successful"
