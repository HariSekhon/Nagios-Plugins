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
#                                M o n g o D B
# ============================================================================ #
"

export MONGODB_HOST="${MONGODB_HOST:-localhost}"

# not part of a replica set so this fails
#perl -T $I_lib ./check_mongodb_master.pl
#hr
#perl -T $I_lib ./check_mongodb_master_rest.pl
#hr
# Type::Tiny::XS currently doesn't build on Perl 5.8 due to a bug
if [ "$TRAVIS_PERL_VERSION" != "5.8" ]; then
    perl -T $I_lib ./check_mongodb_write.pl -v
fi

echo; echo
