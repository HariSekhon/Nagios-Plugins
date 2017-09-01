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
srcdir2="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir2/..";

. ./tests/utils.sh

srcdir="$srcdir2"

#[ `uname -s` = "Linux" ] || exit 0

section "DockerHub Plugins"

# test one of the more stable automated builds
./check_dockerhub_repo_build_status.py -r harisekhon/apache-drill
hr
./check_dockerhub_repo_build_status.py -r harisekhon/apache-drill -v
hr
# intentionally broken repo created specifically for this test
set +e
./check_dockerhub_repo_build_status.py -r harisekhon/ci_intentionally_broken_test_do_not_use -v
check_exit_code 2
set -e
echo
echo
