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

run_grep '^0 ' ./check_mk_wrapper.py --name 'basic test' echo 'test message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1000'

run_grep '^0' ./check_mk_wrapper.py -n 'basic test result' --shell --result 0 test 'message | perf1=10s;1;2 perf2=5%;80;90;0;100' perf3=1000

run_grep '^0 ' ./check_mk_wrapper.py -n 'basic test result trailing args' --result 0 test 'message | perf1=10s;1;2 perf2=5%;80;90;0;100' perf3=1000 --shell

run_grep '^1 ' ./check_mk_wrapper.py -n 'basic test result 1' --result 1 'test 1 message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1000'

run_grep '^2 ' ./check_mk_wrapper.py -n 'basic test result 2' --result 2 'test 2 message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1000'

run_grep '^3 ' ./check_mk_wrapper.py -n 'basic test result 3' --result 3 'test 3 message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1000'

run_grep '^4 ' ./check_mk_wrapper.py -n 'basic test result 4' --result 4 'test 4 message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1000'

run_grep '^0 ' ./check_mk_wrapper.py -n 'basic shell test' --shell "echo 'test message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1000'"

run ./check_mk_wrapper.py $perl -T ./check_disk_write.pl -d .

run ./check_mk_wrapper.py $perl -T ./check_git_branch_checkout.pl -d . -b "$(git branch | awk '/^\*/{print $2}')"

echo "testing stripping of numbered Python interpreter:"
if which python2.7 &>/dev/null; then
    python=python2.7
elif which python2.6 &>/dev/null; then
    python=python2.6
else
    python=python
fi
run_grep '^0 check_git_branch_checkout.py' ./check_mk_wrapper.py $python ./check_git_branch_checkout.py -d . -b "$(git branch | awk '/^\*/{print $2}')"

echo "Testing failure detection of wrong git branch (perl):"
run_grep '^2 check_git_branch_checkout.pl ' ./check_mk_wrapper.py $perl -T ./check_git_branch_checkout.pl -d . -b nonexistentbranch

echo "Testing failure detection of wrong git branch (python):"
run_grep '^2 check_git_branch_checkout.py ' ./check_mk_wrapper.py python ./check_git_branch_checkout.py -d . -b nonexistentbranch

tmpfile="$(mktemp /tmp/check_mk_wrapper.txt.XXXXXX)"
echo test > "$tmpfile"
run ./check_mk_wrapper.py $perl -T ./check_file_md5.pl -f "$tmpfile" -v -c 'd8e8fca2dc0f896fd7cb4cb0031ba249'
rm -f "$tmpfile"

run ./check_mk_wrapper.py $perl -T ./check_timezone.pl -T "$(readlink /etc/localtime | sed 's/.*zoneinfo\///')" -A "$(date +%Z)" -T "$(readlink /etc/localtime)"

echo "Testing induced failures:"
echo
# should return zero exit code regardless but raise non-OK statuses in STATUS field
run_grep '^0 ' ./check_mk_wrapper.py --shell exit 0

run_grep '^1 ' ./check_mk_wrapper.py --shell exit 1

run_grep '^2 ' ./check_mk_wrapper.py --shell exit 2

run_grep '^3 ' ./check_mk_wrapper.py --shell exit 3

run_grep '^3 ' ./check_mk_wrapper.py --shell exit 5

run_grep '^3 ' ./check_mk_wrapper.py nonexistentcommand arg1 arg2

run_grep '^3 ' ./check_mk_wrapper.py --shell nonexistentcommand arg1 arg2

run_grep '^3 ' ./check_mk_wrapper.py $perl -T check_disk_write.pl --help

echo "Completed $run_count Check_MK wrapper tests"
echo
echo "All Check_MK wrapper tests passed succesfully"
echo
echo
