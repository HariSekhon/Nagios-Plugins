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
#                                   N e o 4 J
# ============================================================================ #
"

export NEO4J_HOST="${NEO4J_HOST:-localhost}"

echo "creating test Neo4J node"
neo4j-shell -host $NEO4J_HOST -c 'CREATE (p:Person { name: "Hari Sekhon" })'
echo done
hr
# NEO4J_HOST obtained via .travis.yml
perl -T $I_lib ./check_neo4j_readonly.pl -v
hr
perl -T $I_lib ./check_neo4j_remote_shell_enabled.pl -v
hr
perl -T $I_lib ./check_neo4j_stats.pl -v
hr
perl -T $I_lib ./check_neo4j_stats.pl -s NumberOfNodeIdsInUse -c 1:1 -v
hr
# Neo4J on Travis doesn't seem to return anything resulting in "'attributes' field not returned by Neo4J" error
#perl -T $I_lib ./check_neo4j_store_sizes.pl -vvv
#hr
perl -T $I_lib ./check_neo4j_version.pl -v

echo; echo
