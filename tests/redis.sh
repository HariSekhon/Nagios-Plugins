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
#                                   R e d i s
# ============================================================================ #
"

export REDIS_HOST="${REDIS_HOST:-localhost}"

echo "creating test Redis key-value"
echo set myKey hari | redis-cli -h "$REDIS_HOST"
echo done
hr
# REDIS_HOST obtained via .travis.yml
perl -T $I_lib ./check_redis_clients.pl -v
hr
perl -T $I_lib ./check_redis_config.pl --no-warn-extra -v
hr
perl -T $I_lib ./check_redis_key.pl -k myKey -e hari -v
hr
perl -T $I_lib ./check_redis_publish_subscribe.pl -v
hr
perl -T $I_lib ./check_redis_stats.pl -v
hr
perl -T $I_lib ./check_redis_stats.pl -s connected_clients -c 1:1 -v
hr
perl -T $I_lib ./check_redis_version.pl -v
hr
perl -T $I_lib ./check_redis_write.pl -v

echo; echo
