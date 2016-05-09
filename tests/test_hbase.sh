#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-05-06 12:12:15 +0100 (Fri, 06 May 2016)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback
#
#  https://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x

srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/.."

. "$srcdir/utils.sh"

echo "
# ============================================================================ #
#                                   H B a s e
# ============================================================================ #
"

HBASE_HOST="${DOCKER_HOST:-${HBASE_HOST:-${HOST:-localhost}}}"
HBASE_HOST="${HBASE_HOST##*/}"
HBASE_HOST="${HBASE_HOST%%:*}"
export HBASE_HOST

export DOCKER_IMAGE="harisekhon/hbase-dev"
export DOCKER_CONTAINER="nagios-plugins-hbase"

startupwait=45

hr
echo "Setting up HBase test container"
hr
launch_container "$DOCKER_IMAGE" "$DOCKER_CONTAINER" 2181 8080 8085 9090 9095 16000 16010 16201 16301

# set up test table
# needs to pick up JAVA_HOME from shell
#docker exec -i "$DOCKER_CONTAINER" /bin/bash <<EOF
#/hbase/bin/hbase shell <<EOF2
#list
#EOF2
#EOF

hr
# TODO: add $HOST env support
$perl -T $I_lib ./check_hbase_regionservers.pl -H $HBASE_HOST -P 8080
hr
# TODO: enable no tables CRITICAL check, then create table then re-check
$perl -T $I_lib ./check_hbase_tables.pl || :
$perl -T $I_lib ./check_hbase_tables_thrift.pl || :
# XXX: needs updates
#$perl -T $I_lib ./check_hbase_tables_stargate.pl
#$perl -T $I_lib ./check_hbase_tables_jsp.pl
#hr
#$perl -T $I_lib 
#hr
#$perl -T $I_lib 
hr
if is_zookeeper_built; then
    $perl -T $I_lib ./check_hbase_unassigned_regions_znode.pl
    hr
else
    echo "ZooKeeper not built - skipping ZooKeeper checks"
fi

delete_container
hr
