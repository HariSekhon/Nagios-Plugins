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

# shellcheck disable=SC1091
. tests/utils.sh
# shellcheck disable=SC1091
. bash-tools/lib/docker.sh

section "Running Nagios Plugins ALL"

# Breaks on CentOS Docker without this, although works on Debian, Ubuntu and Alpine without
export LINES="${LINES:-25}"
export COLUMNS="${COLUMNS:-80}"

declare_if_inside_docker

nagios_plugins_start_time="$(start_timer)"

# shellcheck disable=SC1091
. tests/excluded.sh

# must be included so that local exclude function can take precedence
# shellcheck disable=SC1091
. bash-tools/check_all.sh

#is_travis ||
time tests/help.sh

if is_buildkite; then
    exit 0
fi

# try to minimize time by skipping this as Travis CI is killing the build during testing after 50 mins
#is_travis ||
tests/test_docker.sh

tests_run=""
tests_succeeded=""
tests_failed=""

SECONDS=0

# time limited CI builds
is_CI_limited(){
    if is_CI &&
       ! is_azure_devops &&
       ! is_github_action &&
       ! is_buildkite; then
        return 0
    fi
    return 1
}

if is_CI_limited; then
    #if is_CI && [ $((RANDOM % 2)) = 0 ]; then
    #    echo "Reversing test script list to give more likely coverage to scripts at the end of the list within the limited build time limits"
    #    test_scripts="$(tail -r <<< "$test_scripts")"
    #fi

    # better than above
    # randomize and take top 5 results since we need to limit runtime
    # more important than deterministic ordering and better than random ordered skips
    test_scripts="$(find tests -name 'test*.sh' | perl -MList::Util=shuffle -e 'print shuffle<STDIN>' | head -n 5)"
else
    test_scripts="$(find tests -name 'test*.sh' | sort)"
fi

for script in $test_scripts; do
    if [ -n "${NOTESTS:-}" ] && [ "$script" = "run_tests.sh" ]; then
        echo "NOTESTS env var specified, skipping dockerized tests"
        continue
    fi
    if is_CI; then
    #if is_CI && [ $((RANDOM % 2)) = 0 ]; then
        # limiting test scripts above now due to too many builds and cumulative run times causing failures
        #[ $((RANDOM % 4)) = 0 ] || continue
        max_mins=50
        if is_travis && [ $SECONDS -gt $((max_mins*60)) ]; then
            echo "Build has been running for longer than $max_mins minutes and is inside Travis CI, skipping rest of test_*.sh scripts"
            break
        fi
        tests_run="$tests_run
$script"
        declare_if_inside_docker
        if time "$script" "${VERSION:-}"; then
            tests_succeeded="$tests_succeeded
$script"
        else
            tests_failed="$tests_failed
$script"
        fi
    else
        declare_if_inside_docker
        time "$script" "${VERSION:-}"
    fi
done

if is_CI; then
    echo
    echo "Tests Run:
$tests_run"
    echo
    echo "Tests Succeeded:
$tests_succeeded"
    echo
fi

if [ -n "$tests_failed" ]; then
    echo
    echo "WARNING:

Tests Failed:
$tests_failed"
fi

srcdir="$srcdir_nagios_plugins_all"

time_taken "$nagios_plugins_start_time" "Nagios Plugins All Tested Completed in"
section "Nagios Plugins Tests Successful"
