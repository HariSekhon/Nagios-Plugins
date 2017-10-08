#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-12-14 00:39:35 +0000 (Wed, 14 Dec 2016)
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

section "C h e c k   M K   W r a p p e r"

# Try to make these local tests with no dependencies for simplicity

run ./check_mk_wrapper.py --name 'basic test' echo 'test message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1000' | tee /dev/stderr | grep -q '^0 '
hr
run ./check_mk_wrapper.py -n 'basic test result' --shell --result 0 test 'message | perf1=10s;1;2 perf2=5%;80;90;0;100' perf3=1000 | tee /dev/stderr | grep -q '^0 '
hr
run ./check_mk_wrapper.py -n 'basic test result trailing args' --result 0 test 'message | perf1=10s;1;2 perf2=5%;80;90;0;100' perf3=1000 --shell | tee /dev/stderr | grep -q '^0 '
hr
run ./check_mk_wrapper.py -n 'basic test result 1' --result 1 'test 1 message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1000' | tee /dev/stderr | grep -q '^1 '
hr
run ./check_mk_wrapper.py -n 'basic test result 2' --result 2 'test 2 message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1000' | tee /dev/stderr | grep -q '^2 '
hr
run ./check_mk_wrapper.py -n 'basic test result 3' --result 3 'test 3 message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1000' | tee /dev/stderr | grep -q '^3 '
hr
run ./check_mk_wrapper.py -n 'basic test result 4' --result 4 'test 4 message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1000' | tee /dev/stderr | grep -q '^4 '
hr
run ./check_mk_wrapper.py -n 'basic shell test' --shell "echo 'test message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1000'" | tee /dev/stderr | grep -q '^0 '
hr
run ./check_mk_wrapper.py $perl -T ./check_disk_write.pl -d .
hr
run ./check_mk_wrapper.py $perl -T ./check_git_branch_checkout.pl -d . -b "$(git branch | awk '/^\*/{print $2}')"
hr
echo "testing stripping of numbered Python interpreter"
if which python2.7 &>/dev/null; then
    python=python2.7
elif which python2.6 &>/dev/null; then
    python=python2.6
else
    python=python
fi
run ./check_mk_wrapper.py $python ./check_git_branch_checkout.py -d . -b "$(git branch | awk '/^\*/{print $2}')" | tee /dev/stderr | grep -q '^0 check_git_branch_checkout.py'
hr
echo "Testing failure detection of wrong git branch (perl)"
run ./check_mk_wrapper.py $perl -T ./check_git_branch_checkout.pl -d . -b nonexistentbranch | tee /dev/stderr | grep -q '^2 check_git_branch_checkout.pl '
hr
echo "Testing failure detection of wrong git branch (python)"
run ./check_mk_wrapper.py python ./check_git_branch_checkout.py -d . -b nonexistentbranch | tee /dev/stderr | grep -q '^2 check_git_branch_checkout.py '
hr
echo test > test.txt
run ./check_mk_wrapper.py $perl -T ./check_file_md5.pl -f test.txt -v -c 'd8e8fca2dc0f896fd7cb4cb0031ba249'
hr
run ./check_mk_wrapper.py $perl -T ./check_timezone.pl -T "$(readlink /etc/localtime | sed 's/.*zoneinfo\///')" -A "$(date +%Z)" -T "$(readlink /etc/localtime)"
hr
echo "Testing induced failures"
hr
# should return zero exit code regardless but raise non-OK statuses in STATUS field
run ./check_mk_wrapper.py --shell exit 0 | tee /dev/stderr | grep -q '^0 '
hr
run ./check_mk_wrapper.py --shell exit 1 | tee /dev/stderr | grep -q '^1 '
hr
run ./check_mk_wrapper.py --shell exit 2 | tee /dev/stderr | grep -q '^2 '
hr
run ./check_mk_wrapper.py --shell exit 3 | tee /dev/stderr | grep -q '^3 '
hr
run ./check_mk_wrapper.py --shell exit 5 | tee /dev/stderr | grep -q '^3 '
hr
run ./check_mk_wrapper.py nonexistentcommand arg1 arg2 | tee /dev/stderr | grep -q '^3 '
hr
run ./check_mk_wrapper.py --shell nonexistentcommand arg1 arg2 | tee /dev/stderr | grep -q '^3 '
hr
run ./check_mk_wrapper.py $perl -T check_disk_write.pl --help | tee /dev/stderr | grep -q '^3 '
hr
echo "Completed $run_count Check_MK wrapper tests"
echo
echo "All Check_MK wrapper tests passed succesfully"
echo
echo
