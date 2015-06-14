#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-05-25 01:38:24 +0100 (Mon, 25 May 2015)
#
#  https://github.com/harisekhon
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help improve or steer this or other code I publish
#
#  http://www.linkedin.com/in/harisekhon
#

set -eu
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

. tests/travis.sh

echo "
# ============================================================================ #
#                                   R I A K
# ============================================================================ #
"

# RIAK_HOST no longer obtained via .travis.yml, some of these require local riak-admin tool so only makes more sense to run all tests locally
export RIAK_HOST="localhost"

echo "creating myBucket with n_val setting of 1 (to avoid warnings in riak-admin)"
$sudo riak-admin bucket-type create myBucket '{"props":{"n_val":1}}' || :
$sudo riak-admin bucket-type activate myBucket
$sudo riak-admin bucket-type update myBucket '{"props":{"n_val":1}}'
echo "creating test Riak document"
# don't use new bucket types yet
#curl -XPUT localhost:8098/types/myType/buckets/myBucket/keys/myKey -d 'hari'
curl -XPUT $RIAK_HOST:8098/buckets/myBucket/keys/myKey -d 'hari'
echo "done"
hr
# needs sudo - uses wrong version of perl if not explicit path with sudo
$sudo $perl -T $I_lib ./check_riak_diag.pl --ignore-warnings -v
hr
perl -T $I_lib ./check_riak_key.pl -b myBucket -k myKey -e hari -v
hr
$sudo $perl -T $I_lib ./check_riak_member_status.pl -v
hr
# needs sudo - riak must be started as root in Travis
$sudo $perl -T $I_lib ./check_riak_ringready.pl -v
hr
perl -T $I_lib ./check_riak_stats.pl --all -v
hr
perl -T $I_lib ./check_riak_stats.pl -s ring_num_partitions -c 64:64 -v
hr
perl -T $I_lib ./check_riak_stats.pl -s disk.0.size -c 1024: -v
hr
# needs sudo - riak must be started as root in Travis
$sudo $perl -T $I_lib ./check_riak_write_local.pl -v
hr
perl -T $I_lib ./check_riak_write.pl -v
hr
perl -T $I_lib ./check_riak_version.pl

echo; echo
