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

echo "
# ============================================================================ #
#                             C S V   W r a p p e r
# ============================================================================ #
"

# Try to make these local tests with no dependencies for simplicity

./csv_wrapper.py echo 'test message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1000' | tee /dev/stderr | grep -q '^OK,'
hr
./csv_wrapper.py --shell --result 0 test 'message | perf1=10s;1;2 perf2=5%;80;90;0;100' perf3=1000 | tee /dev/stderr | grep -q '^OK,'
hr
./csv_wrapper.py --result 0 test 'message | perf1=10s;1;2 perf2=5%;80;90;0;100' perf3=1000 --shell | tee /dev/stderr | grep -q '^OK,'
hr
./csv_wrapper.py --result 1 'test 1 message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1000' | tee /dev/stderr | grep -q '^WARNING,'
hr
./csv_wrapper.py --result 2 'test 2 message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1000' | tee /dev/stderr | grep -q '^CRITICAL,'
hr
./csv_wrapper.py --result 3 'test 3 message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1000' | tee /dev/stderr | grep -q '^UNKNOWN,'
hr
./csv_wrapper.py --result 4 'test 4 message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1000' | tee /dev/stderr | grep -q '^DEPENDENT,'
hr
./csv_wrapper.py --shell "echo 'test message | perf1=10s;1;2 perf2=5%;80;90;0;100 perf3=1000'" | tee /dev/stderr | grep -q '^OK,'
hr
./csv_wrapper.py $perl -T ./check_disk_write.pl -d .
hr
./csv_wrapper.py $perl -T ./check_git_branch_checkout.pl -d . -b "$(git branch | awk '/^*/{print $2}')"
hr
echo "Testing failure detection of wrong git branch (perl)"
./csv_wrapper.py $perl -T ./check_git_branch_checkout.pl -d . -b nonexistentbranch | tee /dev/stderr | grep -q '^CRITICAL,'
hr
echo "Testing failure detection of wrong git branch (python)"
./geneos_wrapper.py ./check_git_branch_checkout.py -d . -b nonexistentbranch | tee /dev/stderr | grep -q '^CRITICAL,'
hr
echo test > test.txt
./csv_wrapper.py $perl -T ./check_file_md5.pl -f test.txt -v -c 'd8e8fca2dc0f896fd7cb4cb0031ba249'
hr
./csv_wrapper.py $perl -T ./check_timezone.pl -T "$(readlink /etc/localtime | sed 's/.*zoneinfo\///')" -A "$(date +%Z)" -T "$(readlink /etc/localtime)"
hr
echo "Testing induced failures"
hr
# should return zero exit code regardless but raise non-OK statuses in STATUS field
./csv_wrapper.py --shell exit 0 | tee /dev/stderr | grep -q "^OK,"
hr
./csv_wrapper.py --shell exit 1 | tee /dev/stderr | grep -q "^WARNING,"
hr
./csv_wrapper.py --shell exit 2 | tee /dev/stderr | grep -q "^CRITICAL,"
hr
./csv_wrapper.py --shell exit 3 | tee /dev/stderr | grep -q "^UNKNOWN,"
hr
./csv_wrapper.py nonexistentcommand arg1 arg2 | tee /dev/stderr | grep -q "^UNKNOWN,"
hr
./csv_wrapper.py --shell nonexistentcommand arg1 arg2 | tee /dev/stderr | grep -q "^UNKNOWN,"
hr
./csv_wrapper.py $perl -T check_disk_write.pl --help | tee /dev/stderr | grep -q "^UNKNOWN,"
hr
echo "Success!"
echo; echo
