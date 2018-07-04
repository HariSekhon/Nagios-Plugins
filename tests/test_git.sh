#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-10-07 13:41:58 +0100 (Wed, 07 Oct 2015)
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

section "G i t"

# ============================================================================ #
current_branch="$(git branch | grep '^\*' | sed 's/^*[[:space:]]*//;s/[()]//g')"

run $perl -T ./check_git_checkout_branch.pl -d . -b "$current_branch"

# Travis CI runs in a detached head which throws CriticalError
if is_travis; then
    ERRCODE=2 run_grep "CRITICAL: HEAD is a detached symbolic reference as it points to '[a-z0-9]+'" ./check_git_checkout_branch.py -d . -b "$current_branch"
else
    run ./check_git_checkout_branch.py -d . -b "$current_branch"
fi

# because we test before pushing upstream, this will often fail
run_fail "0 2" ./check_git_checkout_up_to_date.py --directory . --no-fetch

# might fail to fetch if we are offline, could timeout too
run_fail "0 2 3" ./check_git_checkout_up_to_date.py -d . -t 30

run_fail 2 ./check_git_checkout_up_to_date.py -d . -r nonexistent

# ============================================================================ #
echo "Testing failure detection of wrong git branch:"
run_fail 2 $perl -T ./check_git_checkout_branch.pl -d . -b nonexistentbranch

# in Travis this will result in CRITICAL: HEAD is a detached symbolic reference as it points to '<hashref>' but will still pass with the right exit code
run_fail 2          ./check_git_checkout_branch.py -d . -b nonexistentbranch

# ============================================================================ #
echo "checking directory not defined results in usage error:"
run_usage $perl -T ./check_git_checkout_branch.pl -b "$current_branch"

run_usage          ./check_git_checkout_branch.py -b "$current_branch"

run_usage ./check_git_checkout_dirty.py

run_usage ./check_git_checkout_up_to_date.py

# ============================================================================ #
echo "setting up git root in /tmp for git checks:"
GIT_TMP="$(mktemp -d /tmp/git.XXXXXX)"
GIT_TMP2="$GIT_TMP-clone"
trap "rm -vfr $GIT_TMP $GIT_TMP2" EXIT

pushd "$GIT_TMP"
echo "initializing test repo:"
git init
echo "cloning test repo:"
git clone "$GIT_TMP" "$GIT_TMP2"
popd
hr

run ./check_git_checkout_branch.py -d "$GIT_TMP" -b "$current_branch"

run ./check_git_checkout_dirty.py -d "$GIT_TMP"

echo "will fail because there is no first HEAD commit:"
run_fail 2 ./check_git_checkout_up_to_date.py -d "$GIT_TMP2"

run ./check_git_uncommitted_changes.py -d "$GIT_TMP"

gitfile="myfile"
touch "$GIT_TMP/$gitfile"

run ./check_git_checkout_branch.py -d "$GIT_TMP" -b "$current_branch"

echo "check_git_checkout_dirty.py doesn't count untracked files:"
run ./check_git_checkout_dirty.py -d "$GIT_TMP"

run_fail 2 ./check_git_uncommitted_changes.py -d "$GIT_TMP"

run_fail 2 ./check_git_uncommitted_changes.py -d "$GIT_TMP" -v

pushd "$GIT_TMP"
git add "$gitfile"
popd
hr

run ./check_git_checkout_branch.py -d "$GIT_TMP" -b master

run_fail 2 ./check_git_checkout_dirty.py -d "$GIT_TMP"

echo "will still fail because there is no HEAD revision nor in clone:"
run_fail 2 ./check_git_checkout_up_to_date.py -d "$GIT_TMP2"

run_fail 2 ./check_git_uncommitted_changes.py -d "$GIT_TMP"

run_fail 2 ./check_git_uncommitted_changes.py -d "$GIT_TMP" -v

echo "committing git file $gitfile:"
pushd "$GIT_TMP"
git commit -m "added $gitfile"
popd
hr
echo "now checking for no untracked changes:"

run ./check_git_checkout_dirty.py -d "$GIT_TMP"

run ./check_git_uncommitted_changes.py -d "$GIT_TMP"

run_fail 2 ./check_git_checkout_up_to_date.py -d "$GIT_TMP2"

pushd "$GIT_TMP2"
git pull
popd

run ./check_git_checkout_up_to_date.py -d "$GIT_TMP2"

echo "modifying committed file:"
echo test >> "$GIT_TMP/$gitfile"
hr

run_fail 2 ./check_git_checkout_dirty.py -d "$GIT_TMP"

run_fail 2 ./check_git_uncommitted_changes.py -d "$GIT_TMP"

pushd "$GIT_TMP"
git ci -m "modified file" "$gitfile"
popd
hr

run_fail 2 ./check_git_checkout_up_to_date.py -d "$GIT_TMP2"

echo "updating cloned repo:"
pushd "$GIT_TMP2"
git pull
popd
hr

run ./check_git_checkout_up_to_date.py -d "$GIT_TMP2"



rm -fr "$GIT_TMP" "$GIT_TMP2"
trap '' EXIT

# ============================================================================ #

echo "Completed $run_count Git tests"
echo
echo "All Git tests passed successfully"
echo
echo
