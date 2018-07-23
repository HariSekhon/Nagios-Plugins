#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-06-22 09:51:51 +0100 (Wed, 22 Jun 2016)
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

section "C S V   W r a p p e r"

# Try to make these local tests with no dependencies for simplicity

run_grep '^OK,' ./csv_wrapper.py echo 'test message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1000'

run_grep '^OK,' ./csv_wrapper.py --shell --result 0 test 'message | perf1=10s;1;2 perf2=5%;80;90;0;100' perf3=1000

run_grep '^OK,' ./csv_wrapper.py --result 0 test 'message | perf1=10s;1;2 perf2=5%;80;90;0;100' perf3=1000 --shell

run_grep '^WARNING,' ./csv_wrapper.py --result 1 'test 1 message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1000'

run_grep '^CRITICAL,' ./csv_wrapper.py --result 2 'test 2 message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1000'

run_grep '^UNKNOWN,' ./csv_wrapper.py --result 3 'test 3 message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1000'

run_grep '^DEPENDENT' ./csv_wrapper.py --result 4 'test 4 message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1000'

run_grep '^OK,' ./csv_wrapper.py --shell "echo 'test message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1000'"

run ./csv_wrapper.py $perl -T ./check_disk_write.pl -d .

run ./csv_wrapper.py $perl -T ./check_git_checkout_branch.pl -d . -b "$(git branch | awk '/^*/{print $2}')"

echo "Testing failure detection of wrong git branch (perl)"
run_grep '^CRITICAL,' ./csv_wrapper.py $perl -T ./check_git_checkout_branch.pl -d . -b nonexistentbranch

echo "Testing failure detection of wrong git branch (python)"
run_grep '^CRITICAL', ./geneos_wrapper.py ./check_git_checkout_branch.py -d . -b nonexistentbranch

tmpfile="$(mktemp /tmp/csv_wrapper.txt.XXXXXX)"
echo test > "$tmpfile"
run ./csv_wrapper.py $perl -T ./check_file_md5.pl -f "$tmpfile" -v -c 'd8e8fca2dc0f896fd7cb4cb0031ba249'
rm -vf "$tmpfile"
hr
run ./csv_wrapper.py $perl -T ./check_timezone.pl -T "$(readlink /etc/localtime | sed 's/.*zoneinfo\///')" -A "$(date +%Z)" -T "$(readlink /etc/localtime)"

echo "Testing induced failures:"
echo
# should return zero exit code regardless but raise non-OK statuses in STATUS field
run_grep '^OK,' ./csv_wrapper.py --shell exit 0

run_grep '^WARNING,' ./csv_wrapper.py --shell exit 1

run_grep '^CRITICAL,' ./csv_wrapper.py --shell exit 2

run_grep '^UNKNOWN,' ./csv_wrapper.py --shell exit 3

run_grep '^UNKNOWN,' ./csv_wrapper.py --shell exit 5

run_grep '^UNKNOWN,' ./csv_wrapper.py nonexistentcommand arg1 arg2

run_grep '^UNKNOWN,' ./csv_wrapper.py --shell nonexistentcommand arg1 arg2

run_grep '^UNKNOWN,' ./csv_wrapper.py $perl -T check_disk_write.pl --help

echo "Completed $run_count CSV wrapper tests"
echo
echo "All CSV wrapper tests completed successfully"
echo
echo
