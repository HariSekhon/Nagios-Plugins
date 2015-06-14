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
#                               M e m c a c h e d
# ============================================================================ #
"

export MEMCACHED_HOST="${MEMCACHED_HOST:-localhost}"

echo "creating test Memcached key-value"
echo -ne "add myKey 0 100 4\r\nhari\r\n" | nc $MEMCACHED_HOST 11211
echo done
hr
# MEMCACHED_HOST obtained via .travis.yml
perl -T $I_lib ./check_memcached_write.pl -v
hr
perl -T $I_lib ./check_memcached_key.pl -k myKey -e hari -v
hr
perl -T $I_lib ./check_memcached_stats.pl -w 15 -c 20 -v

echo; echo
