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

# shellcheck disable=SC1090
. "$srcdir/utils.sh"

section "C S V   A d a p t e r"

# Try to make these local tests with no dependencies for simplicity

run_grep '^OK,test message,10,5,1001$' ./adapter_csv.py echo 'test message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1001'

run_grep '^OK,test message,10,5,1002$' ./adapter_csv.py --shell --result 0 test 'message | perf1=10s;1;2 perf2=5%;80;90;0;100' perf3=1002

run_grep '^OK,test message,10,5,1003$' ./adapter_csv.py --result 0 test 'message | perf1=10s;1;2 perf2=5%;80;90;0;100' perf3=1003 --shell

run_grep '^WARNING,test 1 message,10,5,1004$' ./adapter_csv.py --result 1 'test 1 message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1004'

run_grep '^CRITICAL,test 2 message,10,5,1005$' ./adapter_csv.py --result 2 'test 2 message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1005'

run_grep '^UNKNOWN,test 3 message,10,5,1006$' ./adapter_csv.py --result 3 'test 3 message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1006'

run_grep '^DEPENDENT,test 4 message,10,5,1007$' ./adapter_csv.py --result 4 'test 4 message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1007'

run_grep '^OK,test message,10,5,1008$' ./adapter_csv.py --shell "echo 'test message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1008'"

# $perl defined in bash-tools/lib/perl.sh (imported by utils.sh)
# shellcheck disable=SC2154
run ./adapter_csv.py "$perl" -T ./check_disk_write.pl -d .

# copied from tests/test_git.sh
if is_CI; then
    echo '> git branch'
    git --no-pager branch
    echo
fi
current_branch="$(git branch | grep '^\*' | sed 's/^*[[:space:]]*//;s/[()]//g')"

run ./adapter_csv.py "$perl" -T ./check_git_checkout_branch.pl -d . -b "$current_branch"

echo "Testing failure detection of wrong git branch (perl)"
run_grep '^CRITICAL,' ./adapter_csv.py "$perl" -T ./check_git_checkout_branch.pl -d . -b nonexistentbranch

echo "Testing failure detection of wrong git branch (python)"
run_grep '^CRITICAL', ./adapter_csv.py ./check_git_checkout_branch.py -d . -b nonexistentbranch

tmpfile="$(mktemp /tmp/adapter_csv.txt.XXXXXX)"
echo test > "$tmpfile"
run ./adapter_csv.py "$perl" -T ./check_file_md5.pl -f "$tmpfile" -v -c 'd8e8fca2dc0f896fd7cb4cb0031ba249'
rm -vf "$tmpfile"
hr
run ./adapter_csv.py "$perl" -T ./check_timezone.pl -T "$(readlink /etc/localtime | sed 's/.*zoneinfo\///')" -A "$(date +%Z)" -T "$(readlink /etc/localtime)"

echo "Testing induced failures:"
echo
# should return zero exit code regardless but raise non-OK statuses in STATUS field
run_grep '^OK,<no output>$' ./adapter_csv.py --shell exit 0

run_grep '^WARNING,<no output>$' ./adapter_csv.py --shell exit 1

run_grep '^CRITICAL,<no output>$' ./adapter_csv.py --shell exit 2

run_grep '^UNKNOWN,<no output>$' ./adapter_csv.py --shell exit 3

run_grep '^UNKNOWN,<no output>$' ./adapter_csv.py --shell exit 5

run_grep '^UNKNOWN,' ./adapter_csv.py nonexistentcommand arg1 arg2

run_grep '^UNKNOWN,' ./adapter_csv.py --shell nonexistentcommand arg1 arg2

run_grep '^UNKNOWN,usage: check_disk_write.pl ' ./adapter_csv.py "$perl" -T check_disk_write.pl --help

# defined and tracked in bash-tools/lib/utils.sh
# shellcheck disable=SC2154
echo "Completed $run_count CSV adapter tests"
echo
echo "All CSV adapter tests completed successfully"
echo
echo
