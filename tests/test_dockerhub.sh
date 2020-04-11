#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-09-01 00:04:33 +0200 (Fri, 01 Sep 2017)
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

# shellcheck disable=SC1090
. "$srcdir/utils.sh"

srcdir="$srcdir"

#[ `uname -s` = "Linux" ] || exit 0

section "D o c k e r H u b "

# test one of the more stable automated builds, but not one with too many tags as a Dockerfiles push all will result in > 10 queued builds
#echo "testing repo expected to have successful build:"
#run ./check_dockerhub_repo_build_status.py -r harisekhon/zookeeper
echo "DockerHub has space failures all the time, must allow for broken build:"
run_fail "0 2" ./check_dockerhub_repo_build_status.py -r harisekhon/zookeeper

echo "testing repo with extended output information:"
#run ./check_dockerhub_repo_build_status.py -r harisekhon/zookeeper -v
run_fail "0 2" ./check_dockerhub_repo_build_status.py -r harisekhon/zookeeper -v

echo "testing detection of failing repo build:"
# intentionally broken repo created specifically for this test
run_fail 2 ./check_dockerhub_repo_build_status.py -r harisekhon/ci_intentionally_broken_test_do_not_use -v

echo
# defined and tracked in bash-tools/lib/utils.sh
# shellcheck disable=SC2154
echo "Completed $run_count DockerHub tests"
echo
echo "DockerHub tests completed successfully"
echo
echo
