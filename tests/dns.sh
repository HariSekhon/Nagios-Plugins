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
#                                   D N S
# ============================================================================ #
"

perl -T $I_lib ./check_dns.pl -s 4.2.2.1,4.2.2.2,4.2.2.3,4.2.2.4 -r google.com -q MX
hr
perl -T $I_lib ./check_dns.pl -s a.resolvers.level3.net,b.resolvers.level3.net,c.resolvers.level3.net,d.resolvers.level3.net -r google.com -q MX
hr
perl -T $I_lib ./check_dns.pl -s a.resolvers.level3.net,b.resolvers.level3.net,c.resolvers.level3.net,d.resolvers.level3.net -r google.com

echo; echo
